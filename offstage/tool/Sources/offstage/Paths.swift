import Foundation

/// Everything offstage writes lives under ~/Library/Caches/offstage.
/// Nothing is ever written into a project directory.
enum Paths {
    static let root: URL = {
        let u = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("offstage", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    static var socket: URL { root.appendingPathComponent("offstage.sock") }
    static var pidFile: URL { root.appendingPathComponent("daemon.pid") }
    static var daemonLog: URL { root.appendingPathComponent("daemon.log") }
    static var sessions: URL {
        let u = root.appendingPathComponent("sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static func session(_ id: String) -> URL {
        let u = sessions.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}

/// Tiny JSON helpers: every command in and out is one JSON object.
typealias JSON = [String: Any]

enum OffstageError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self { case .message(let m): return m }
    }
}

func fail(_ m: String) -> OffstageError { .message(m) }

extension JSON {
    func str(_ k: String) -> String? { self[k] as? String }
    func int(_ k: String) -> Int? {
        if let i = self[k] as? Int { return i }
        if let d = self[k] as? Double { return Int(d) }
        if let s = self[k] as? String { return Int(s) }
        return nil
    }
    func dbl(_ k: String) -> Double? {
        if let d = self[k] as? Double { return d }
        if let i = self[k] as? Int { return Double(i) }
        if let s = self[k] as? String { return Double(s) }
        return nil
    }
    func bool(_ k: String) -> Bool { (self[k] as? Bool) ?? false }
    func list(_ k: String) -> [String] { (self[k] as? [String]) ?? [] }
}

func jsonString(_ obj: Any, pretty: Bool = true) -> String {
    var opts: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
    if pretty { opts.insert(.prettyPrinted) }
    guard JSONSerialization.isValidJSONObject(obj),
          let d = try? JSONSerialization.data(withJSONObject: obj, options: opts),
          let s = String(data: d, encoding: .utf8) else {
        return "{\"ok\":false,\"error\":\"unserialisable response\"}"
    }
    return s
}

func rectJSON(_ r: CGRect) -> JSON {
    ["x": Int(r.origin.x.rounded()), "y": Int(r.origin.y.rounded()),
     "w": Int(r.size.width.rounded()), "h": Int(r.size.height.rounded())]
}

func now() -> String {
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f.string(from: Date())
}
