import Foundation
import AppKit

enum Client {
    static func daemonRunning() -> Bool {
        guard let fd = Sock.connect(to: Paths.socket.path) else { return false }
        Sock.writeAll(fd, "{\"cmd\":\"ping\"}\n".data(using: .utf8)!)
        let d = Sock.readAll(fd, untilNewline: true)
        close(fd)
        return ((try? JSONSerialization.jsonObject(with: d)) as? JSON)?.bool("ok") ?? false
    }

    static func send(_ req: JSON) throws -> JSON {
        guard let fd = Sock.connect(to: Paths.socket.path) else {
            throw fail("offstage daemon is not running — run `offstage up` first")
        }
        Sock.writeAll(fd, (jsonString(req, pretty: false) + "\n").data(using: .utf8)!)
        let d = Sock.readAll(fd, untilNewline: false)
        close(fd)
        guard let j = (try? JSONSerialization.jsonObject(with: d)) as? JSON else {
            throw fail("daemon returned garbage (\(d.count) bytes); see \(Paths.daemonLog.path)")
        }
        return j
    }

    /// Spawn `offstage serve` detached (own session, no controlling tty) and
    /// wait for its socket. TCC attribution stays with the terminal host that
    /// runs us, which is the one that already holds the permissions.
    static func startDaemon(width: Int, height: Int, scale: Int) throws -> JSON {
        if daemonRunning() { return try send(["cmd": "up"]) }
        // A stale socket from a crashed daemon.
        try? FileManager.default.removeItem(at: Paths.socket)
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
        let resolved = (try? FileManager.default.destinationOfSymbolicLink(atPath: exe)).map {
            $0.hasPrefix("/") ? $0 : URL(fileURLWithPath: exe).deletingLastPathComponent().appendingPathComponent($0).standardizedFileURL.path
        } ?? exe
        let argv = [resolved, "serve", "--size", "\(width)x\(height)", "--scale", "\(scale)"]
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
        var fa: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fa)
        posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&fa, 1, Paths.daemonLog.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        posix_spawn_file_actions_addopen(&fa, 2, Paths.daemonLog.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        var pid: pid_t = 0
        let cargs = argv.map { strdup($0) } + [nil]
        defer { cargs.forEach { free($0) } }
        let rc = posix_spawn(&pid, resolved, &fa, &attr, cargs, environ)
        posix_spawn_file_actions_destroy(&fa)
        posix_spawnattr_destroy(&attr)
        guard rc == 0 else { throw fail("could not spawn daemon: \(String(cString: strerror(rc)))") }
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if daemonRunning() { return try send(["cmd": "up"]) }
            if kill(pid, 0) != 0 {
                let tail = (try? String(contentsOf: Paths.daemonLog, encoding: .utf8))?.split(separator: "\n").suffix(8).joined(separator: "\n") ?? ""
                throw fail("daemon exited during start-up:\n\(tail)")
            }
            usleep(150_000)
        }
        throw fail("daemon did not come up within 15s; see \(Paths.daemonLog.path)")
    }

    static func localStatus() -> JSON {
        [
            "daemon": daemonRunning(),
            "permissions": ["screenRecording": CGPreflightScreenCaptureAccess(), "accessibility": AXIsProcessTrusted()],
            "socket": Paths.socket.path, "log": Paths.daemonLog.path, "sessions": Paths.sessions.path,
        ]
    }
}
