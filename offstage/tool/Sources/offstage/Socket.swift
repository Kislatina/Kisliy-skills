import Foundation
import Darwin

/// Newline-delimited JSON over a unix socket. One request, one response,
/// connection closed.
enum Sock {
    static func address(_ path: String) -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = path.withCString { cs in
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 104) { strlcpy($0, cs, 104) }
            }
        }
        return addr
    }

    static func listen(at path: String) throws -> Int32 {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw fail("socket() failed: \(String(cString: strerror(errno)))") }
        var addr = address(path)
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) } }
        guard bound == 0 else { throw fail("bind() failed: \(String(cString: strerror(errno)))") }
        guard Darwin.listen(fd, 16) == 0 else { throw fail("listen() failed") }
        chmod(path, 0o600)
        return fd
    }

    static func connect(to path: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = address(path)
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let r = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, len) } }
        guard r == 0 else { close(fd); return nil }
        return fd
    }

    static func readAll(_ fd: Int32, untilNewline: Bool) -> Data {
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
            if untilNewline, buf[..<n].contains(10) { break }
        }
        return data
    }

    static func writeAll(_ fd: Int32, _ data: Data) {
        data.withUnsafeBytes { raw in
            var off = 0
            while off < raw.count {
                let n = write(fd, raw.baseAddress! + off, raw.count - off)
                if n <= 0 { break }
                off += n
            }
        }
    }
}

/// Accept loop on a background thread; each request is handled on the main
/// actor so daemon state stays single-threaded.
func serve(daemon: Daemon, fd: Int32) {
    Thread.detachNewThread {
        while true {
            let c = accept(fd, nil, nil)
            guard c >= 0 else { continue }
            Thread.detachNewThread {
                let data = Sock.readAll(c, untilNewline: true)
                let req = (try? JSONSerialization.jsonObject(with: data)) as? JSON ?? [:]
                let done = DispatchSemaphore(value: 0)
                var resp: JSON = [:]
                Task { @MainActor in
                    resp = await daemon.handle(req)
                    done.signal()
                }
                done.wait()
                Sock.writeAll(c, (jsonString(resp, pretty: false) + "\n").data(using: .utf8)!)
                close(c)
            }
        }
    }
}
