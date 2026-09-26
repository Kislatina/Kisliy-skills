import Foundation
import AppKit
import ApplicationServices

/// One launched, store-isolated app instance living on the virtual display.
final class Session {
    let id: String
    let appURL: URL
    let bundleID: String?
    let dir: URL
    let home: URL?
    let env: [String: String]
    let args: [String]
    let startedAt = Date()
    private(set) var app: NSRunningApplication?
    var pid: pid_t { app?.processIdentifier ?? 0 }
    var ax: AXUIElement { AXUIElementCreateApplication(pid) }
    var shotCounter = 0
    private var observer: AXObserver?
    /// Called on the main run loop the moment the app creates a window.
    var onWindowCreated: (() -> Void)?

    /// Subscribe to window creation so a new window is parked on the virtual
    /// display within milliseconds instead of waiting for the warden tick.
    @discardableResult
    func installObserver() -> String {
        guard pid > 0 else { return "no pid" }
        guard observer == nil else { return "already installed" }
        var obs: AXObserver?
        let cb: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let session = Unmanaged<Session>.fromOpaque(refcon).takeUnretainedValue()
            session.onWindowCreated?()
        }
        let cr = AXObserverCreate(pid, cb, &obs)
        guard cr == .success, let obs else { return "AXObserverCreate failed: \(cr.rawValue)" }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var results: [String] = []
        for n in [kAXWindowCreatedNotification, kAXApplicationShownNotification, kAXFocusedWindowChangedNotification] {
            let r = AXObserverAddNotification(obs, ax, n as CFString, refcon)
            results.append("\(n)=\(r.rawValue)")
            if r != .success && r != .notificationAlreadyRegistered { return "add failed: " + results.joined(separator: " ") }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
        return "ok " + results.joined(separator: " ")
    }

    var needsObserver: Bool { observer == nil && isAlive }
    /// Set once the launch sequence has finished.
    var launched = false

    func removeObserver() {
        guard let obs = observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = nil
    }
    /// Frame + scale of the last screenshot, so `--image x y` can be mapped
    /// back to global points.
    var lastShot: (frame: CGRect, scale: Int)?
    var notes: [String] = []

    /// The bundle the instance actually runs from: an APFS clone with its own
    /// bundle identifier, unless the caller asked for the original.
    private(set) var launchURL: URL
    private(set) var cloned = false

    init(id: String, appURL: URL, home: URL?, env: [String: String], args: [String]) {
        self.id = id
        self.appURL = appURL
        self.launchURL = appURL
        self.bundleID = Bundle(url: appURL)?.bundleIdentifier
        self.dir = Paths.session(id)
        self.home = home
        self.env = env
        self.args = args
    }

    /// UserDefaults go through cfprefsd, which ignores HOME: a plain launch
    /// of a dev build writes into the very same domain the user's installed
    /// copy reads (observed: a theme click leaked into the real app). A clone
    /// with `<bundleID>.offstage` gets its own domain, its own saved window
    /// frames and its own Application Support. Copy-on-write, so it costs
    /// nothing; re-signed ad-hoc with entitlements and flags preserved.
    /// Per session id, so parallel agents never share state and a relaunch
    /// with the same id keeps it (until --fresh / --purge).
    var cloneBundleID: String {
        (bundleID ?? "app") + ".offstage." + id.replacingOccurrences(of: "[^A-Za-z0-9]+", with: "-", options: .regularExpression)
    }

    /// Drop the isolated UserDefaults domain of this session.
    func wipeDefaults() {
        let domain = cloneBundleID as CFString
        if let keys = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String], !keys.isEmpty {
            CFPreferencesSetMultiple(nil, keys as CFArray, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            CFPreferencesAppSynchronize(domain)
        }
        try? FileManager.default.removeItem(at: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(cloneBundleID).plist"))
    }

    func makeClone() throws {
        guard bundleID != nil else { throw fail("bundle has no CFBundleIdentifier; use --as-is") }
        let cloneDir = dir.appendingPathComponent("app", isDirectory: true)
        let clone = cloneDir.appendingPathComponent(appURL.lastPathComponent)
        try? FileManager.default.removeItem(at: cloneDir)
        try FileManager.default.createDirectory(at: cloneDir, withIntermediateDirectories: true)
        try run("/bin/cp", ["-Rc", appURL.path, clone.path], fallback: ["/bin/cp", "-R", appURL.path, clone.path])
        let plist = clone.appendingPathComponent("Contents/Info.plist")
        try run("/usr/bin/plutil", ["-replace", "CFBundleIdentifier", "-string", cloneBundleID, plist.path])
        try run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-",
                                      "--preserve-metadata=entitlements,flags,runtime", clone.path])
        launchURL = clone
        cloned = true
    }

    /// Forget the clone in LaunchServices so it never becomes the default
    /// handler for a file type or URL scheme.
    func unregisterClone() {
        guard cloned else { return }
        let ls = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        try? run(ls, ["-u", launchURL.path])
    }

    @discardableResult
    private func run(_ exe: String, _ args: [String], fallback: [String]? = nil) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try p.run(); p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            if let fallback, let fexe = fallback.first {
                return try run(fexe, Array(fallback.dropFirst()))
            }
            throw fail("\(exe) \(args.joined(separator: " ")) failed (\(p.terminationStatus)): \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return out
    }

    var isAlive: Bool {
        guard let app, !app.isTerminated else { return false }
        return kill(app.processIdentifier, 0) == 0
    }

    var windowElements: [AXUIElement] { pid > 0 ? AX.windows(ax) : [] }

    /// The window the agent means by default: focused → main → largest.
    func mainWindow() -> AXUIElement? {
        let wins = windowElements
        if let f = AX.attr(ax, kAXFocusedWindowAttribute), wins.contains(where: { CFEqual($0, f) }) {
            return (f as! AXUIElement)
        }
        if let m = AX.attr(ax, kAXMainWindowAttribute) { return (m as! AXUIElement) }
        return wins.max { (AX.frame($0)?.area ?? 0) < (AX.frame($1)?.area ?? 0) }
    }

    func window(byID wid: CGWindowID) -> AXUIElement? {
        windowElements.first { AX.windowID($0) == wid }
    }

    /// Launch hidden so nothing flashes on the user's screen. `open -n`
    /// semantics (new instance), no activation, no prompts.
    func launch(openFiles: [URL], hidden: Bool) async throws {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        cfg.activates = false
        cfg.hides = hidden
        cfg.promptsUserIfNeeded = false
        cfg.addsToRecentItems = false
        cfg.arguments = args
        var e = ProcessInfo.processInfo.environment
        if let home {
            let h = home.path
            e["HOME"] = h
            e["CFFIXED_USER_HOME"] = h
            e["TMPDIR"] = home.appendingPathComponent("tmp").path
            try? FileManager.default.createDirectory(at: home.appendingPathComponent("tmp"), withIntermediateDirectories: true)
        }
        e["OFFSTAGE"] = "1"
        e["OFFSTAGE_SESSION"] = id
        // Whose window is this? Every app offstage starts is an agent's, and an
        // app that reads the flag says so on itself — NullKit stamps the mark
        // and the Dock tile red. Nothing to remember at the call site: the
        // launch cannot happen without it.
        e["NULL_AGENT"] = "1"
        for (k, v) in env { e[k] = v }
        cfg.environment = e
        let running: NSRunningApplication
        if openFiles.isEmpty {
            running = try await NSWorkspace.shared.openApplication(at: launchURL, configuration: cfg)
        } else {
            running = try await NSWorkspace.shared.open(openFiles, withApplicationAt: launchURL, configuration: cfg)
        }
        app = running
    }

    func terminate(grace: TimeInterval = 5) async -> Bool {
        removeObserver()
        guard let app, isAlive else { return true }
        app.terminate()
        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline {
            if !isAlive { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        app.forceTerminate()
        try? await Task.sleep(nanoseconds: 300_000_000)
        return !isAlive
    }

    func json(displayBounds: CGRect) -> JSON {
        var j: JSON = [
            "id": id, "pid": Int(pid), "alive": isAlive, "app": appURL.path,
            "bundleID": bundleID ?? "", "dir": dir.path, "home": home?.path ?? "(shared)",
            "isolation": cloned ? "clone (\(cloneBundleID)), own HOME" : (home == nil ? "NONE — shared defaults and HOME" : "own HOME only; UserDefaults shared with the real app"),
            "startedAt": ISO8601DateFormatter().string(from: startedAt),
        ]
        let wins = windowElements.compactMap { w -> JSON? in
            guard let f = AX.frame(w) else { return nil }
            var wj: JSON = ["title": AX.string(w, kAXTitleAttribute) ?? "", "frame": rectJSON(f),
                            "onVirtualDisplay": displayBounds.contains(CGPoint(x: f.midX, y: f.midY))]
            if let wid = AX.windowID(w) { wj["id"] = Int(wid) }
            return wj
        }
        j["windows"] = wins
        if !notes.isEmpty { j["notes"] = notes }
        return j
    }
}

extension CGRect {
    var area: CGFloat { width * height }
}
