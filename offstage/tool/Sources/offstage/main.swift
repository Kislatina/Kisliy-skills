import Foundation
import AppKit

let boolFlags: Set<String> = ["all", "all-windows", "abs", "image", "right", "double", "json", "display",
                              "shared-home", "restore-state", "purge", "help", "as-is", "fresh", "raw", "list", "no-hide"]
let multiFlags: Set<String> = ["env", "arg", "open", "mod", "key"]

struct Parsed {
    var positional: [String] = []
    var opts: [String: String] = [:]
    var multi: [String: [String]] = [:]
    var flags: Set<String> = []
}

func parse(_ argv: [String]) -> Parsed {
    var p = Parsed()
    var i = 0
    var stopFlags = false
    while i < argv.count {
        let a = argv[i]
        if a == "--" { stopFlags = true; i += 1; continue }
        if !stopFlags, a.hasPrefix("--"), a.count > 2 {
            var name = String(a.dropFirst(2))
            var inline: String? = nil
            if let eq = name.firstIndex(of: "=") { inline = String(name[name.index(after: eq)...]); name = String(name[..<eq]) }
            if boolFlags.contains(name) { p.flags.insert(name); i += 1; continue }
            let value: String
            if let inline { value = inline } else { i += 1; value = i < argv.count ? argv[i] : "" }
            if multiFlags.contains(name) { p.multi[name, default: []].append(value) } else { p.opts[name] = value }
            i += 1
            continue
        }
        p.positional.append(a)
        i += 1
    }
    return p
}

func usage() -> String {
    """
    offstage — run a macOS app on a hidden virtual display, look at it, drive it.

      offstage up [--size 1280x800] [--scale 2]      start the daemon + virtual display (idempotent)
      offstage down                                   quit every session, drop the display
      offstage status                                 permissions, display, sessions

      offstage launch <App.app> [--id NAME] [--env K=V]... [--arg A]... [--open FILE]...
                      [--home DIR | --shared-home] [--as-is] [--fresh] [--restore-state] [--wait 20] [--settle 0.6]
          --as-is   run the original bundle (shares UserDefaults with the user's copy!)
          --fresh   wipe this session id's saved state (defaults, HOME) before launching
          --no-hide launch visible (some sandboxed apps, e.g. TextEdit, need this); window is
                    yanked to the virtual display on the first frame — a brief flash is possible
      offstage ls
      offstage quit <session> [--purge] | --all

      offstage shot <session> [--label L] [--out file.png] [--scale 1|2] [--window ID]
                    [--display] [--region X Y W H]
      offstage windows <session>
      offstage tree <session> [--depth 14] [--all] [--role AXButton] [--window ID] [--all-windows] [--abs] [--json]
      offstage find <session> --id ID | --title T | --value V | --desc D [--role R] [--nth N] [--path #0.1.2]

      offstage click <session> X Y [--image | --abs] [--right] [--double] [--mod cmd]...
      offstage click <session> --id ID | --title T | --path #0.1.2      (AX-located click)
      offstage press <session> --id ID [--action AXPress]               (AX action, no mouse)
      offstage set   <session> --id ID --value "text"                    (AX value)
      offstage focus <session> --id ID
      offstage type  <session> "text" [--delay 4]
      offstage key   <session> cmd+n [enter ...]   (⌘-chords are pressed via the menu bar; --raw posts the event)
      offstage menu  <session>                     list enabled menu items with shortcuts (--all includes disabled)
      offstage menu  <session> File "New Window"   press a menu item by (trailing) path
      offstage scroll <session> X Y --dx 0 --dy -300
      offstage drag  <session> X Y --to X Y
      offstage resize <session> 1100x720 [--window ID]
      offstage wait  <session> [seconds]
      offstage log   <session> [--last 2m]

    Coordinates: points relative to the main window's top-left by default;
    --image = pixels of the last screenshot of that session; --abs = global points.
    Every command prints one JSON object; "ok": false carries "error".
    """
}

func emit(_ j: JSON, code: Int32 = 0) -> Never {
    print(jsonString(j))
    exit(code)
}

func sizeArg(_ s: String?) -> (Int, Int) {
    guard let s, let x = s.lowercased().firstIndex(of: "x"),
          let w = Int(s[..<x]), let h = Int(s[s.index(after: x)...]) else { return (1280, 800) }
    return (max(640, w), max(400, h))
}

let argv = Array(CommandLine.arguments.dropFirst())
let p = parse(argv)
guard let command = p.positional.first, !p.flags.contains("help"), command != "help" else {
    print(usage()); exit(argv.isEmpty ? 1 : 0)
}
let rest = Array(p.positional.dropFirst())

func req(_ cmd: String, _ extra: JSON = [:]) -> JSON {
    var j: JSON = ["cmd": cmd]
    if let s = rest.first { j["session"] = s }
    for (k, v) in p.opts { j[k] = v }
    for f in p.flags { j[camel(f)] = true }
    for (k, v) in p.multi { j[k] = v }
    for (k, v) in extra { j[k] = v }
    return j
}
/// The daemon has its own cwd; resolve paths on the client side.
func absPath(_ s: String) -> String {
    let e = (s as NSString).expandingTildeInPath
    return e.hasPrefix("/") ? e : FileManager.default.currentDirectoryPath + "/" + e
}
func camel(_ s: String) -> String {
    let parts = s.split(separator: "-").map(String.init)
    return parts.enumerated().map { $0 == 0 ? $1 : $1.capitalized }.joined()
}
/// Commands that need the daemon auto-start it (with default display) so an
/// agent can go straight to `launch` without a separate `up`.
func autoStart() {
    guard !Client.daemonRunning() else { return }
    guard CGPreflightScreenCaptureAccess(), AXIsProcessTrusted() else { return }  // surfaced as a clear error by the command
    _ = try? Client.startDaemon(width: 1280, height: 800, scale: 2)
}
func run(_ r: JSON) -> Never {
    autoStart()
    do {
        let out = try Client.send(r)
        emit(out, code: out.bool("ok") ? 0 : 1)
    } catch { emit(["ok": false, "error": "\(error)"], code: 1) }
}
func needSession() {
    if rest.first == nil { emit(["ok": false, "error": "session id required; `offstage ls` lists them"], code: 1) }
}
func xy(_ from: Int) -> (Double, Double)? {
    guard rest.count > from + 1, let x = Double(rest[from]), let y = Double(rest[from + 1]) else { return nil }
    return (x, y)
}

switch command {
case "serve":
    // Internal: the daemon itself.
    let (w, h) = sizeArg(p.opts["size"])
    let scale = Int(p.opts["scale"] ?? "2") ?? 2
    MainActor.assumeIsolated {
        do {
            let daemon = try Daemon(width: w, height: h, scale: scale)
            let fd = try Sock.listen(at: Paths.socket.path)
            try? String(getpid()).write(to: Paths.pidFile, atomically: true, encoding: .utf8)
            daemon.installGuards()
            serve(daemon: daemon, fd: fd)
            daemon.log("serving on \(Paths.socket.path)")
        } catch {
            FileHandle.standardError.write("offstage serve failed: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }
    RunLoop.main.run()

case "up":
    let (w, h) = sizeArg(p.opts["size"])
    let scale = Int(p.opts["scale"] ?? "2") ?? 2
    if !CGPreflightScreenCaptureAccess() || !AXIsProcessTrusted() {
        emit(["ok": false, "error": "missing permissions for this terminal host",
              "permissions": ["screenRecording": CGPreflightScreenCaptureAccess(), "accessibility": AXIsProcessTrusted()],
              "hint": "System Settings → Privacy & Security → Screen Recording / Accessibility — only the user can grant these; never trigger the prompt yourself"], code: 1)
    }
    do { emit(try Client.startDaemon(width: w, height: h, scale: scale)) }
    catch { emit(["ok": false, "error": "\(error)"], code: 1) }

case "down":
    if !Client.daemonRunning() { emit(["ok": true, "message": "daemon was not running"]) }
    run(["cmd": "down"])

case "status":
    var j = Client.localStatus()
    if j.bool("daemon"), let d = try? Client.send(["cmd": "status"]) { for (k, v) in d { j[k] = v } }
    j["ok"] = true
    emit(j)

case "launch":
    guard let app = rest.first else { emit(["ok": false, "error": "launch needs the .app path"], code: 1) }
    var r = req("launch", ["app": absPath(app)])
    r["session"] = nil
    r["args"] = p.multi["arg"] ?? []
    r["open"] = (p.multi["open"] ?? []).map(absPath)
    if let h = p.opts["home"] { r["home"] = absPath(h) }
    run(r)

case "ls": run(["cmd": "ls"])

case "quit":
    if !p.flags.contains("all") { needSession() }
    run(req("quit"))

case "shot":
    needSession()
    var r = req("shot")
    if let o = p.opts["out"] { r["out"] = absPath(o) }
    if let reg = p.opts["region"] {
        let n = reg.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }
        if n.count == 4 { r["rx"] = n[0]; r["ry"] = n[1]; r["rw"] = n[2]; r["rh"] = n[3] }
    }
    run(r)

case "windows", "tree", "find", "press", "set", "focus":
    needSession()
    run(req(command))

case "click", "scroll", "drag":
    needSession()
    var r = req(command)
    if let (x, y) = xy(1) { r["x"] = x; r["y"] = y }
    r["mods"] = p.multi["mod"] ?? []
    if command == "drag" {
        let n = (p.opts["to"] ?? "").split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }
        if n.count == 2 { r["tx"] = n[0]; r["ty"] = n[1] }
        else if rest.count >= 5, let tx = Double(rest[3]), let ty = Double(rest[4]) { r["tx"] = tx; r["ty"] = ty }
    }
    run(r)

case "type":
    needSession()
    guard rest.count > 1 else { emit(["ok": false, "error": "type needs text"], code: 1) }
    run(req("type", ["text": rest.dropFirst().joined(separator: " ")]))

case "key":
    needSession()
    let chords = Array(rest.dropFirst()) + (p.multi["key"] ?? [])
    run(req("key", ["keys": chords]))

case "menu":
    needSession()
    run(req("menu", ["path": Array(rest.dropFirst())]))

case "resize":
    needSession()
    guard rest.count > 1 else { emit(["ok": false, "error": "resize needs WxH"], code: 1) }
    let (w, h) = sizeArg(rest[1])
    run(req("resize", ["w": w, "h": h]))

case "wait":
    needSession()
    run(req("wait", ["seconds": Double(rest.count > 1 ? rest[1] : "1") ?? 1]))

case "log":
    needSession()
    guard let ls = try? Client.send(["cmd": "ls"]), let sessions = ls["sessions"] as? [JSON],
          let s = sessions.first(where: { ($0["id"] as? String)?.hasPrefix(rest[0]) == true }),
          let pid = s.int("pid") else { emit(["ok": false, "error": "no such session"], code: 1) }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
    task.arguments = ["show", "--predicate", "processID == \(pid)", "--last", p.opts["last"] ?? "2m", "--style", "compact", "--info"]
    let pipe = Pipe(); task.standardOutput = pipe; task.standardError = pipe
    try? task.run(); task.waitUntilExit()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let lines = out.split(separator: "\n").suffix(Int(p.opts["lines"] ?? "200") ?? 200)
    emit(["ok": true, "pid": pid, "lines": lines.count, "log": lines.joined(separator: "\n")])

default:
    emit(["ok": false, "error": "unknown command '\(command)'", "usage": usage()], code: 1)
}
