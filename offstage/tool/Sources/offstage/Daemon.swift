import Foundation
import AppKit
import ApplicationServices

/// The long-lived process: owns the virtual display, the sessions, a focus
/// guard and a window warden, and answers JSON requests on a unix socket.
@MainActor
final class Daemon {
    let display: VirtualDisplay
    private var sessions: [String: Session] = [:]
    private var counter: [String: Int] = [:]
    private var lastUserApp: NSRunningApplication?
    private var logHandle: FileHandle?
    private var shuttingDown = false

    init(width: Int, height: Int, scale: Int) throws {
        display = try VirtualDisplay(width: width, height: height, scale: scale)
        FileManager.default.createFile(atPath: Paths.daemonLog.path, contents: nil)
        logHandle = try? FileHandle(forWritingTo: Paths.daemonLog)
        logHandle?.seekToEndOfFile()
        lastUserApp = NSWorkspace.shared.frontmostApplication
        log("display \(display.id) \(display.bounds) scale \(scale)")
    }

    func log(_ s: String) {
        let line = "\(now()) \(s)\n"
        logHandle?.write(line.data(using: .utf8)!)
    }

    // MARK: guards

    func installGuards() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in self.appActivated(app) }
        }
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.wardenTick() }
        }
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { Task { @MainActor in await self.shutdown(reason: "signal \(sig)") } }
            src.resume()
            signalSources.append(src)
        }
    }
    private var signalSources: [DispatchSourceSignal] = []

    private func isOurs(_ pid: pid_t) -> Bool { sessions.values.contains { $0.pid == pid } }

    /// If one of our apps grabs the foreground, hand it straight back.
    private func appActivated(_ app: NSRunningApplication) {
        if isOurs(app.processIdentifier) {
            log("focus guard: \(app.localizedName ?? "?") stole focus, restoring")
            restoreFocus(from: app)
        } else {
            lastUserApp = app
        }
    }

    private func restoreFocus(from thief: NSRunningApplication) {
        if let prev = lastUserApp, !prev.isTerminated, prev.processIdentifier != thief.processIdentifier {
            prev.activate(options: [.activateIgnoringOtherApps])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == thief.processIdentifier {
                // Hiding the active app makes macOS activate the previous one;
                // unhiding does not activate.
                thief.hide()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { thief.unhide() }
            }
        }
    }

    /// Any window of ours that is not on the virtual display gets moved there.
    /// New windows are born on the screen with the menu bar (the app is never
    /// key), so this is what keeps them off the user's screen.
    private func wardenTick() {
        guard !shuttingDown else { return }
        let vb = display.bounds
        _ = vb
        for s in sessions.values where s.isAlive {
            moveAllWindows(s, tag: "warden")
            // Not during launch: registering an AXObserver on a hidden,
            // still-launching TextEdit kept its document window from ever
            // appearing (observed on macOS 26.5).
            if s.needsObserver && s.launched { let r = s.installObserver(); if r.hasPrefix("ok") { log("observer for \(s.id): \(r)") } }
        }
        // Focus guard fallback for activations the notification missed.
        if let front = NSWorkspace.shared.frontmostApplication, isOurs(front.processIdentifier) {
            restoreFocus(from: front)
        }
    }

    private func placement(for size: CGSize, in vb: CGRect) -> CGPoint {
        // Centre the window on the virtual display, never let it hang off.
        let x = max(vb.minX, min(vb.minX + (vb.width - size.width) / 2, vb.maxX - size.width))
        let y = max(vb.minY, min(vb.minY + (vb.height - size.height) / 2, vb.maxY - size.height))
        return CGPoint(x: x.rounded(), y: y.rounded())
    }

    @discardableResult
    func moveAllWindows(_ s: Session, tag: String = "launch") -> Int {
        let vb = display.bounds
        var moved = 0
        for w in s.windowElements {
            guard let f = AX.frame(w) else { continue }
            if !vb.contains(CGPoint(x: f.midX, y: f.midY)) {
                let p = placement(for: f.size, in: vb)
                if AX.setPosition(w, p) {
                    moved += 1
                    log("\(tag): moved window '\(AX.string(w, kAXTitleAttribute) ?? "")' of \(s.id) from \(f.origin) to \(p)")
                }
            }
        }
        return moved
    }

    // MARK: lifecycle

    func shutdown(reason: String) async {
        guard !shuttingDown else { return }
        shuttingDown = true
        log("shutdown: \(reason)")
        for s in sessions.values { _ = await s.terminate(); s.unregisterClone() }
        try? FileManager.default.removeItem(at: Paths.socket)
        try? FileManager.default.removeItem(at: Paths.pidFile)
        exit(0)
    }

    // MARK: dispatch

    func handle(_ req: JSON) async -> JSON {
        let cmd = req.str("cmd") ?? ""
        do {
            let r = try await dispatch(cmd, req)
            var out = r
            out["ok"] = true
            return out
        } catch {
            log("error in \(cmd): \(error)")
            return ["ok": false, "error": "\(error)", "cmd": cmd]
        }
    }

    private func session(_ req: JSON) throws -> Session {
        guard let id = req.str("session"), !id.isEmpty else {
            throw fail("session id required (see `offstage ls`)")
        }
        if let s = sessions[id] { return s }
        // Allow a unique prefix / app name.
        let matches = sessions.values.filter { $0.id.hasPrefix(id) }
        if matches.count == 1 { return matches[0] }
        throw fail("no session '\(id)'; running: \(sessions.keys.sorted())")
    }

    private func dispatch(_ cmd: String, _ req: JSON) async throws -> JSON {
        switch cmd {
        case "ping", "up":
            return ["display": display.json, "pid": Int(getpid()), "sessions": sessions.count]
        case "status":
            return [
                "display": display.json, "pid": Int(getpid()),
                "permissions": ["screenRecording": CGPreflightScreenCaptureAccess(), "accessibility": AXIsProcessTrusted()],
                "frontmost": NSWorkspace.shared.frontmostApplication?.localizedName ?? "",
                "sessions": sessions.values.sorted { $0.startedAt < $1.startedAt }.map { $0.json(displayBounds: display.bounds) },
                "log": Paths.daemonLog.path,
            ]
        case "down":
            Task { await self.shutdown(reason: "down") }
            return ["message": "shutting down"]
        case "launch": return try await launch(req)
        case "ls":
            return ["sessions": sessions.values.sorted { $0.startedAt < $1.startedAt }.map { $0.json(displayBounds: display.bounds) }]
        case "quit":
            if req.bool("all") {
                var out: [String] = []
                for s in sessions.values { _ = await s.terminate(); s.unregisterClone(); out.append(s.id) }
                sessions.removeAll()
                return ["quit": out]
            }
            let s = try session(req)
            let ok = await s.terminate()
            s.unregisterClone()
            sessions[s.id] = nil
            if req.bool("purge") {
                try? FileManager.default.removeItem(at: s.dir)
                s.wipeDefaults()
            }
            return ["quit": s.id, "terminated": ok]
        case "shot": return try await shot(req)
        case "windows":
            let s = try session(req)
            return ["session": s.id, "windows": s.json(displayBounds: display.bounds)["windows"] ?? []]
        case "tree": return try tree(req)
        case "find": return try find(req)
        case "click": return try await click(req)
        case "type":
            let s = try session(req)
            try ensureAlive(s)
            guard let text = req.str("text") else { throw fail("text required") }
            let wid = try keyWindow(s, req)
            Input(pid: s.pid).type(text, delayMs: req.int("delay") ?? 4, window: wid)
            return ["typed": text.count, "window": wid.map { Int($0) } ?? 0]
        case "key":
            let s = try session(req)
            try ensureAlive(s)
            let chords = req.list("keys")
            guard !chords.isEmpty else { throw fail("key chord required, e.g. cmd+n") }
            let inp = Input(pid: s.pid)
            let wid = try keyWindow(s, req)
            var via: [String] = []
            for c in chords {
                // ⌘-chords: an inactive app's NSMenu never sees them, so press
                // the menu item that owns the shortcut instead.
                if !req.bool("raw"), let item = Menus.item(for: c, in: s.ax) {
                    guard item.enabled else { throw fail("menu item '\(item.path.joined(separator: " › "))' for \(c) is disabled") }
                    let r = AX.press(item.element)
                    via.append("\(c) → menu '\(item.path.joined(separator: " › "))' (\(r == .success ? "ok" : "axError \(r.rawValue)"))")
                } else {
                    try inp.key(c, window: wid)
                    via.append("\(c) → event")
                }
                usleep(40_000)
            }
            return ["keys": chords, "window": wid.map { Int($0) } ?? 0, "via": via]
        case "menu":
            let s = try session(req)
            try ensureAlive(s)
            let path = req.list("path")
            if path.isEmpty || req.bool("list") {
                let items = Menus.items(of: s.ax).filter { $0.enabled || req.bool("all") }
                return ["count": items.count, "items": items.map { $0.json }]
            }
            guard let item = Menus.item(titled: path, in: s.ax) else {
                throw fail("no menu item matching \(path.joined(separator: " › ")); `offstage menu \(s.id)` lists them")
            }
            guard item.enabled else { throw fail("menu item '\(item.path.joined(separator: " › "))' is disabled") }
            let r = AX.press(item.element)
            return ["pressed": r == .success, "axError": r.rawValue, "item": item.json]
        case "scroll":
            let s = try session(req)
            try ensureAlive(s)
            let p = try resolvePoint(s, req)
            let wid = Input(pid: s.pid).scroll(at: p, dx: req.int("dx") ?? 0, dy: req.int("dy") ?? 0)
            return ["at": ["x": Int(p.x), "y": Int(p.y)], "window": wid.map { Int($0) } ?? 0]
        case "drag":
            let s = try session(req)
            try ensureAlive(s)
            let a = try resolvePoint(s, req)
            guard let tx = req.dbl("tx"), let ty = req.dbl("ty") else { throw fail("drag needs target --to X Y") }
            let origin = try coordinateOrigin(s, req)
            let b = CGPoint(x: origin.x + tx, y: origin.y + ty)
            let wid = Input(pid: s.pid).drag(from: a, to: b)
            return ["from": ["x": Int(a.x), "y": Int(a.y)], "to": ["x": Int(b.x), "y": Int(b.y)], "window": wid.map { Int($0) } ?? 0]
        case "resize":
            let s = try session(req)
            try ensureAlive(s)
            guard let w = try targetWindow(s, req) else { throw fail("no window") }
            guard let width = req.dbl("w"), let height = req.dbl("h") else { throw fail("resize needs WxH") }
            let vb = display.bounds
            let size = CGSize(width: min(width, vb.width), height: min(height, vb.height))
            AX.setPosition(w, placement(for: size, in: vb))
            let ok = AX.setSize(w, size)
            AX.setPosition(w, placement(for: AX.frame(w)?.size ?? size, in: vb))
            return ["resized": ok, "frame": rectJSON(AX.frame(w) ?? .zero)]
        case "set":
            let s = try session(req)
            try ensureAlive(s)
            guard let el = try findElement(s, req) else { throw fail("element not found") }
            guard let value = req.str("value") else { throw fail("value required") }
            let r = AX.setValue(el.element, value)
            return ["set": r == .success, "axError": r.rawValue, "element": el.json(relativeTo: nil)]
        case "press":
            let s = try session(req)
            try ensureAlive(s)
            guard let el = try findElement(s, req) else { throw fail("element not found") }
            let action = req.str("action") ?? kAXPressAction
            let r = AX.press(el.element, action)
            return ["pressed": r == .success, "axError": r.rawValue, "action": action,
                    "actions": AX.actions(el.element), "element": el.json(relativeTo: nil)]
        case "focus":
            let s = try session(req)
            try ensureAlive(s)
            guard let el = try findElement(s, req) else { throw fail("element not found") }
            let r = AX.setFocused(el.element)
            return ["focused": r == .success, "axError": r.rawValue]
        case "wait":
            let s = try session(req)
            let secs = req.dbl("seconds") ?? 1
            try await Task.sleep(nanoseconds: UInt64(secs * 1e9))
            return ["waited": secs, "alive": s.isAlive]
        default:
            throw fail("unknown command '\(cmd)'")
        }
    }

    private func ensureAlive(_ s: Session) throws {
        guard s.isAlive else { throw fail("session \(s.id) is not running (pid \(s.pid) gone)") }
    }

    // MARK: launch

    private func launch(_ req: JSON) async throws -> JSON {
        guard let appPath = req.str("app") else { throw fail("app path required") }
        let url = URL(fileURLWithPath: (appPath as NSString).expandingTildeInPath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { throw fail("no such app: \(url.path)") }
        let name = url.deletingPathExtension().lastPathComponent
            .lowercased().replacingOccurrences(of: " ", with: "")
        var id = req.str("id") ?? name
        if sessions[id] != nil {
            let n = (counter[id] ?? 1) + 1
            counter[id] = n
            id = "\(id)-\(n)"
        }
        var env: [String: String] = [:]
        for kv in req.list("env") {
            guard let eq = kv.firstIndex(of: "=") else { throw fail("bad --env '\(kv)', want K=V") }
            env[String(kv[..<eq])] = String(kv[kv.index(after: eq)...])
        }
        var args = req.list("args")
        if !req.bool("restoreState") { args = ["-ApplePersistenceIgnoreState", "YES"] + args }
        let sdir = Paths.session(id)
        var home: URL? = sdir.appendingPathComponent("home", isDirectory: true)
        if req.bool("sharedHome") { home = nil }
        else if let h = req.str("home") { home = URL(fileURLWithPath: (h as NSString).expandingTildeInPath) }
        if let home { try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true) }

        let s = Session(id: id, appURL: url, home: home, env: env, args: args)
        if req.bool("fresh") {
            if let home { try? FileManager.default.removeItem(at: home); try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true) }
            s.wipeDefaults()
        }
        if !req.bool("asIs") { try s.makeClone() }
        let before = NSWorkspace.shared.frontmostApplication
        // Hidden launch keeps the window off the user's screen entirely. A few
        // sandboxed, document-based apps (TextEdit) never create their window
        // while hidden — --no-hide launches them visible and the observer/
        // warden yank the window to the virtual display on the next frame.
        let hidden = !req.bool("noHide")
        try await s.launch(openFiles: req.list("open").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }, hidden: hidden)
        sessions[id] = s
        log("launched \(id) pid \(s.pid) from \(url.path)")
        s.onWindowCreated = { [weak self, weak s] in
            guard let self, let s else { return }
            self.moveAllWindows(s, tag: "observer")
        }

        // Phase 1: the app is hidden; most apps still create their window,
        // which we park on the virtual display before anyone sees it.
        let timeout = req.dbl("wait") ?? 20
        let hiddenBudget = min(req.dbl("hidden-wait") ?? 4, timeout)
        let deadline = Date().addingTimeInterval(timeout)
        let hiddenDeadline = Date().addingTimeInterval(hiddenBudget)
        var wins: [AXUIElement] = []
        while Date() < (hidden ? hiddenDeadline : deadline) {
            if !s.isAlive { throw fail("app exited during launch (pid \(s.pid)); see `offstage log \(id)`") }
            wins = s.windowElements
            if !wins.isEmpty { moveAllWindows(s); break }
            try await Task.sleep(nanoseconds: UInt64(hidden ? 100 : 30) * 1_000_000)
        }
        moveAllWindows(s)
        s.app?.unhide()
        // Phase 2: some apps (document-based ones like TextEdit) only order
        // their window in once unhidden. Poll fast so it is moved within a
        // frame or two of appearing.
        if wins.isEmpty && hidden {
            s.notes.append("window did not appear while hidden; unhid after \(hiddenBudget)s and caught it on arrival")
            while Date() < deadline {
                if !s.isAlive { throw fail("app exited during launch (pid \(s.pid)); see `offstage log \(id)`") }
                wins = s.windowElements
                if !wins.isEmpty { moveAllWindows(s); break }
                try await Task.sleep(nanoseconds: 30_000_000)
            }
            if wins.isEmpty { s.notes.append("no window appeared within \(timeout)s; the warden will park one if it shows up") }
        } else if wins.isEmpty {
            s.notes.append("no window appeared within \(timeout)s; if this is a sandboxed document app, retry with --no-hide, else the warden will park one if it shows up")
        }
        s.launched = true
        log("observer for \(id): \(s.installObserver())")
        try await Task.sleep(nanoseconds: UInt64((req.dbl("settle") ?? 0.6) * 1e9))
        moveAllWindows(s)
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier == s.pid {
            s.notes.append("app activated itself on launch; focus was restored")
            if let before { lastUserApp = before }
            restoreFocus(from: front)
        }
        var j = s.json(displayBounds: display.bounds)
        j["display"] = display.json
        return j
    }

    // MARK: capture

    private func shot(_ req: JSON) async throws -> JSON {
        let s = try session(req)
        try ensureAlive(s)
        let scale = req.int("scale") ?? display.scale
        var region: CGRect? = nil
        var windowID: CGWindowID? = nil
        if let wid = req.int("window") { windowID = CGWindowID(wid) }
        if let rx = req.dbl("rx"), let ry = req.dbl("ry"), let rw = req.dbl("rw"), let rh = req.dbl("rh") {
            let o = try coordinateOrigin(s, req)
            region = CGRect(x: o.x + rx, y: o.y + ry, width: rw, height: rh)
        }
        if req.bool("display") { region = display.bounds }
        let r = try await Capture.shoot(pid: s.pid, displayID: display.id, displayBounds: display.bounds,
                                        region: region, scale: scale, windowID: windowID)
        s.shotCounter += 1
        let label = (req.str("label") ?? "shot").replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "-", options: .regularExpression)
        let base = String(format: "%03d-%@", s.shotCounter, label)
        let full: URL
        if let out = req.str("out") {
            full = URL(fileURLWithPath: (out as NSString).expandingTildeInPath)
        } else {
            full = s.dir.appendingPathComponent("\(base).png")
        }
        try Capture.writePNG(r.image, to: full)
        var j: JSON = [
            "session": s.id, "path": full.path, "width": r.image.width, "height": r.image.height,
            "scale": r.scale, "frame": rectJSON(r.frame), "windows": r.windows,
        ]
        if r.scale > 1, let small = Capture.downscale(r.image, by: r.scale) {
            let su = full.deletingPathExtension().appendingPathExtension("small.png")
            try Capture.writePNG(small, to: su)
            j["small"] = su.path
        }
        if let mw = s.mainWindow(), let f = AX.frame(mw) {
            j["mainWindow"] = ["frame": rectJSON(f), "title": AX.string(mw, kAXTitleAttribute) ?? "",
                               "offsetInImage": ["x": Int((f.minX - r.frame.minX) * CGFloat(r.scale)),
                                                 "y": Int((f.minY - r.frame.minY) * CGFloat(r.scale))]]
        }
        s.lastShot = (r.frame, r.scale)
        return j
    }

    // MARK: coordinates

    private func targetWindow(_ s: Session, _ req: JSON) throws -> AXUIElement? {
        if let wid = req.int("window") {
            guard let w = s.window(byID: CGWindowID(wid)) else { throw fail("no window with id \(wid)") }
            return w
        }
        return s.mainWindow()
    }

    /// Window that keyboard events are addressed to: --window, else the
    /// app's focused window, else its main window.
    private func keyWindow(_ s: Session, _ req: JSON) throws -> CGWindowID? {
        if let wid = req.int("window") { return CGWindowID(wid) }
        if let f = AX.attr(s.ax, kAXFocusedWindowAttribute), let wid = AX.windowID(f as! AXUIElement) { return wid }
        return s.mainWindow().flatMap { AX.windowID($0) }
    }

    /// Origin that relative coordinates are measured from.
    private func coordinateOrigin(_ s: Session, _ req: JSON) throws -> CGPoint {
        if req.bool("abs") { return .zero }
        if req.bool("image") {
            guard let last = s.lastShot else { throw fail("--image needs a previous `shot` of this session") }
            return last.frame.origin
        }
        guard let w = try targetWindow(s, req), let f = AX.frame(w) else { throw fail("no window to measure from") }
        return f.origin
    }

    private func resolvePoint(_ s: Session, _ req: JSON) throws -> CGPoint {
        if req["id"] != nil || req["title"] != nil || req["path"] != nil || req["value"] != nil || req["desc"] != nil {
            guard let n = try findElement(s, req) else { throw fail("element not found") }
            guard let f = n.frame, f.width > 0 else { throw fail("element has no frame") }
            return CGPoint(x: f.midX, y: f.midY)
        }
        guard let x = req.dbl("x"), let y = req.dbl("y") else { throw fail("need X Y or an element selector") }
        let o = try coordinateOrigin(s, req)
        if req.bool("image"), let last = s.lastShot {
            return CGPoint(x: o.x + x / CGFloat(last.scale), y: o.y + y / CGFloat(last.scale))
        }
        return CGPoint(x: o.x + x, y: o.y + y)
    }

    private func click(_ req: JSON) async throws -> JSON {
        let s = try session(req)
        try ensureAlive(s)
        let p = try resolvePoint(s, req)
        let vb = display.bounds
        guard vb.contains(p) else {
            throw fail("point \(Int(p.x)),\(Int(p.y)) is outside the virtual display \(rectJSON(vb)); window frames: \(s.json(displayBounds: vb)["windows"] ?? [])")
        }
        var flags: CGEventFlags = []
        for m in req.list("mods") {
            switch m { case "cmd": flags.insert(.maskCommand); case "shift": flags.insert(.maskShift)
            case "alt", "opt": flags.insert(.maskAlternate); case "ctrl": flags.insert(.maskControl); default: break }
        }
        let inp = Input(pid: s.pid)
        let wid = inp.click(at: p, button: req.bool("right") ? .right : .left, count: req.bool("double") ? 2 : 1, flags: flags)
        var j: JSON = ["clicked": ["x": Int(p.x), "y": Int(p.y)], "right": req.bool("right"), "double": req.bool("double"),
                       "window": wid.map { Int($0) } ?? 0]
        if wid == nil { j["warning"] = "no window of this app under the point — the click was dropped" }
        return j
    }

    // MARK: accessibility tree

    private static let boring: Set<String> = ["AXGroup", "AXSplitGroup", "AXScrollArea", "AXLayoutArea",
                                              "AXUnknown", "AXGenericElement", "AXSplitter", "AXLayoutItem"]

    private func tree(_ req: JSON) throws -> JSON {
        let s = try session(req)
        try ensureAlive(s)
        let depth = req.int("depth") ?? 14
        let all = req.bool("all")
        let roleFilter = req.str("role")
        var windows: [AXUIElement] = []
        if req.bool("allWindows") { windows = s.windowElements }
        else if let w = try targetWindow(s, req) { windows = [w] }
        var lines: [String] = []
        var nodes: [JSON] = []
        for (wi, w) in windows.enumerated() {
            let origin = req.bool("abs") ? nil : AX.frame(w)?.origin
            AX.walk(w, maxDepth: depth, rootPath: "\(wi)") { n in
                let informative = !(n.title ?? "").isEmpty || !(n.identifier ?? "").isEmpty
                    || !(n.value ?? "").isEmpty || !(n.description ?? "").isEmpty || n.focused == true
                if let roleFilter, n.role != roleFilter { return true }
                if !all && Self.boring.contains(n.role) && !informative && n.depth > 0 { return true }
                lines.append(n.line(relativeTo: origin))
                if req.bool("json") { nodes.append(n.json(relativeTo: origin)) }
                return true
            }
        }
        var j: JSON = ["session": s.id, "count": lines.count, "tree": lines.joined(separator: "\n"),
                       "coordinates": req.bool("abs") ? "global points" : "points relative to window top-left"]
        if req.bool("json") { j["nodes"] = nodes }
        return j
    }

    private func findElement(_ s: Session, _ req: JSON) throws -> AX.Node? {
        let nth = req.int("nth") ?? 0
        var windows: [AXUIElement] = []
        if let p = req.str("path") {
            // "#1.3.0" → window index first
            let clean = p.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            let wi = Int(clean.split(separator: ".").first ?? "0") ?? 0
            let wins = s.windowElements
            guard wi < wins.count, let el = AX.element(at: clean, in: wins[wi]) else { return nil }
            return AX.node(el, depth: 0, path: clean)
        }
        if req.bool("allWindows") { windows = s.windowElements }
        else if let w = try targetWindow(s, req) { windows = [w] }
        let id = req.str("id")?.lowercased()
        let title = req.str("title")?.lowercased()
        let value = req.str("value")?.lowercased()
        let desc = req.str("desc")?.lowercased()
        let role = req.str("role")
        guard id != nil || title != nil || value != nil || desc != nil || role != nil else {
            throw fail("selector required: --id, --title, --value, --desc, --role or --path")
        }
        var exact: [AX.Node] = [], loose: [AX.Node] = []
        for (wi, w) in windows.enumerated() {
            AX.walk(w, maxDepth: req.int("depth") ?? 20, rootPath: "\(wi)") { n in
                if let role, n.role != role { return true }
                func m(_ want: String?, _ have: String?) -> Int {  // 2 exact, 1 contains, 0 miss
                    guard let want else { return 2 }
                    guard let have = have?.lowercased(), !have.isEmpty else { return 0 }
                    return have == want ? 2 : (have.contains(want) ? 1 : 0)
                }
                let scores = [m(id, n.identifier), m(title, n.title ?? n.description), m(value, n.value), m(desc, n.description ?? n.help)]
                guard scores.allSatisfy({ $0 > 0 }) else { return true }
                if scores.allSatisfy({ $0 == 2 }) { exact.append(n) } else { loose.append(n) }
                return true
            }
        }
        let found = exact + loose
        return nth < found.count ? found[nth] : nil
    }

    private func find(_ req: JSON) throws -> JSON {
        let s = try session(req)
        try ensureAlive(s)
        guard let n = try findElement(s, req) else { return ["found": false] }
        let origin = try? coordinateOrigin(s, req)
        var j = n.json(relativeTo: origin)
        j["found"] = true
        j["actions"] = AX.actions(n.element)
        if let f = n.frame, let origin { j["center"] = ["x": Int(f.midX - origin.x), "y": Int(f.midY - origin.y)] }
        return j
    }
}
