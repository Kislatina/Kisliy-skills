import Foundation
import AppKit

/// Input that never touches the user's session: every event is posted straight
/// to the target pid with CGEventPostToPid. The real cursor does not move,
/// the target does not become active, and the keyboard focus stays wherever
/// the user has it.
struct Input {
    let pid: pid_t
    private let source = CGEventSource(stateID: .privateState)

    /// Mouse events posted to a pid bypass the window server's hit-testing,
    /// so AppKit receives them with windowNumber 0 and drops them. Two
    /// undocumented integer fields fix that (found by scanning on macOS 26):
    ///   51  — the CGWindowID the event belongs to
    ///   146 — must be non-zero; AppKit then derives the window-local point
    ///         from the event's global location
    static let windowNumberField = CGEventField(rawValue: 51)!
    static let routingFlagField = CGEventField(rawValue: 146)!

    /// Front-most on-screen window of `pid` under `p` (global points), any
    /// layer — so popovers and menus of the same process are clickable.
    static func windowID(under p: CGPoint, pid: pid_t) -> CGWindowID? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let wid = w[kCGWindowNumber as String] as? CGWindowID else { continue }
            let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            if r.contains(p) && r.width > 1 && r.height > 1 { return wid }
        }
        return nil
    }

    private func mouse(_ t: CGEventType, _ p: CGPoint, _ btn: CGMouseButton, window: CGWindowID?) -> CGEvent? {
        guard let e = CGEvent(mouseEventSource: source, mouseType: t, mouseCursorPosition: p, mouseButton: btn) else { return nil }
        let wid = window ?? Input.windowID(under: p, pid: pid)
        if let wid {
            e.setIntegerValueField(Input.windowNumberField, value: Int64(wid))
            e.setIntegerValueField(Input.routingFlagField, value: 1)
        }
        return e
    }

    // US-layout virtual key codes for names the agent will type.
    static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
        "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
        "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
        "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
        "`": 50,
        "enter": 36, "return": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51,
        "esc": 53, "escape": 53, "forwarddelete": 117, "home": 115, "end": 119,
        "pageup": 116, "pagedown": 121, "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111, "capslock": 57,
    ]
    static let namedChars: [String: String] = [
        "enter": "\r", "return": "\r", "tab": "\t", "space": " ", "delete": "\u{8}",
        "backspace": "\u{8}", "esc": "\u{1B}", "escape": "\u{1B}",
    ]

    /// "cmd+shift+n" → (flags, keycode, characters)
    static func parseChord(_ chord: String) throws -> (CGEventFlags, CGKeyCode, String?) {
        let parts = chord.lowercased().split(separator: "+").map(String.init)
        guard let keyName = parts.last, !keyName.isEmpty else { throw fail("empty key chord") }
        var flags: CGEventFlags = []
        for m in parts.dropLast() {
            switch m {
            case "cmd", "command", "meta": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "alt", "opt", "option": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            case "fn": flags.insert(.maskSecondaryFn)
            default: throw fail("unknown modifier '\(m)'")
            }
        }
        let code: CGKeyCode
        var chars: String? = nil
        if let c = keyCodes[keyName] {
            code = c
            if keyName.count == 1 {
                chars = flags.contains(.maskShift) ? keyName.uppercased() : keyName
            } else {
                chars = namedChars[keyName]
            }
        } else if keyName.count == 1 {
            // A non-US character (e.g. Cyrillic): deliver it as unicode on a
            // neutral key code.
            code = 0
            chars = keyName
        } else {
            throw fail("unknown key '\(keyName)'")
        }
        return (flags, code, chars)
    }

    /// `window` is the app's focused window: key equivalents (⌘W, ⌘N…) are
    /// only honoured when the event names a window.
    func key(_ chord: String, window: CGWindowID?) throws {
        let (flags, code, chars) = try Input.parseChord(chord)
        post(code: code, chars: chars, flags: flags, window: window)
    }

    func type(_ text: String, delayMs: Int = 4, window: CGWindowID?) {
        for ch in text {
            switch ch {
            case "\n", "\r": post(code: 36, chars: "\r", flags: [], window: window)
            case "\t": post(code: 48, chars: "\t", flags: [], window: window)
            default:
                let s = String(ch)
                let lower = s.lowercased()
                let code = Input.keyCodes[lower] ?? 0
                post(code: code, chars: s, flags: (s != lower && Input.keyCodes[lower] != nil) ? .maskShift : [], window: window)
            }
            if delayMs > 0 { usleep(useconds_t(delayMs * 1000)) }
        }
    }

    private func post(code: CGKeyCode, chars: String?, flags: CGEventFlags, window: CGWindowID?) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            e.flags = flags
            if let chars {
                var u = Array(chars.utf16)
                e.keyboardSetUnicodeString(stringLength: u.count, unicodeString: &u)
            }
            if let window {
                e.setIntegerValueField(Input.windowNumberField, value: Int64(window))
                e.setIntegerValueField(Input.routingFlagField, value: 1)
            }
            e.postToPid(pid)
            usleep(2000)
        }
    }

    enum Button { case left, right }

    /// Returns the window the click was routed to (nil = AppKit had nothing
    /// under the point and will drop it).
    @discardableResult
    func click(at p: CGPoint, button: Button = .left, count: Int = 1, flags: CGEventFlags = [], window: CGWindowID? = nil) -> CGWindowID? {
        let (downT, upT, btn): (CGEventType, CGEventType, CGMouseButton) = button == .left
            ? (.leftMouseDown, .leftMouseUp, .left) : (.rightMouseDown, .rightMouseUp, .right)
        let wid = window ?? Input.windowID(under: p, pid: pid)
        // A move first so hover state (SwiftUI buttons, hover effects) is
        // consistent with where the click lands.
        mouse(.mouseMoved, p, btn, window: wid)?.postToPid(pid); usleep(15_000)
        for n in 1...max(1, count) {
            for t in [downT, upT] {
                guard let e = mouse(t, p, btn, window: wid) else { continue }
                e.setIntegerValueField(.mouseEventClickState, value: Int64(n))
                e.flags = flags
                e.postToPid(pid)
                usleep(20_000)
            }
            if n < count { usleep(60_000) }
        }
        return wid
    }

    func move(to p: CGPoint, window: CGWindowID? = nil) {
        mouse(.mouseMoved, p, .left, window: window)?.postToPid(pid)
    }

    @discardableResult
    func drag(from a: CGPoint, to b: CGPoint, steps: Int = 12) -> CGWindowID? {
        let wid = Input.windowID(under: a, pid: pid)
        move(to: a, window: wid); usleep(15_000)
        mouse(.leftMouseDown, a, .left, window: wid)?.postToPid(pid); usleep(40_000)
        for i in 1...max(1, steps) {
            let t = CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            mouse(.leftMouseDragged, p, .left, window: wid)?.postToPid(pid)
            usleep(16_000)
        }
        mouse(.leftMouseUp, b, .left, window: wid)?.postToPid(pid)
        return wid
    }

    @discardableResult
    func scroll(at p: CGPoint, dx: Int, dy: Int) -> CGWindowID? {
        let wid = Input.windowID(under: p, pid: pid)
        move(to: p, window: wid); usleep(10_000)
        // Deliver in small wheel ticks so views with momentum behave.
        let steps = max(1, max(abs(dx), abs(dy)) / 10)
        for _ in 0..<steps {
            guard let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                  wheel1: Int32(dy / steps), wheel2: Int32(dx / steps), wheel3: 0) else { continue }
            e.location = p
            if let wid {
                e.setIntegerValueField(Input.windowNumberField, value: Int64(wid))
                e.setIntegerValueField(Input.routingFlagField, value: 1)
            }
            e.postToPid(pid)
            usleep(12_000)
        }
        return wid
    }
}
