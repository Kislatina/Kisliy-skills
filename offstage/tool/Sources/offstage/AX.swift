import Foundation
import ApplicationServices
import AppKit

/// Thin Accessibility wrappers. Everything reads; the only writes are
/// position/size/value/focus, and AXPress.
struct AX {
    static func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
        return v
    }
    static func string(_ el: AXUIElement, _ name: String) -> String? {
        guard let v = attr(el, name) else { return nil }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        if let u = v as? URL { return u.absoluteString }
        if CFGetTypeID(v) == AXValueGetTypeID() { return nil }
        if let a = v as? NSAttributedString { return a.string }
        return nil
    }
    static func bool(_ el: AXUIElement, _ name: String) -> Bool? {
        (attr(el, name) as? NSNumber)?.boolValue
    }
    static func point(_ el: AXUIElement, _ name: String) -> CGPoint? {
        guard let v = attr(el, name), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }
    static func size(_ el: AXUIElement, _ name: String) -> CGSize? {
        guard let v = attr(el, name), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }
    static func frame(_ el: AXUIElement) -> CGRect? {
        guard let p = point(el, kAXPositionAttribute), let s = size(el, kAXSizeAttribute) else { return nil }
        return CGRect(origin: p, size: s)
    }
    static func children(_ el: AXUIElement) -> [AXUIElement] {
        (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }
    static func windows(_ app: AXUIElement) -> [AXUIElement] {
        (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    }
    static func actions(_ el: AXUIElement) -> [String] {
        var arr: CFArray?
        guard AXUIElementCopyActionNames(el, &arr) == .success else { return [] }
        return (arr as? [String]) ?? []
    }
    @discardableResult
    static func setPosition(_ el: AXUIElement, _ p: CGPoint) -> Bool {
        var pp = p
        guard let v = AXValueCreate(.cgPoint, &pp) else { return false }
        return AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, v) == .success
    }
    @discardableResult
    static func setSize(_ el: AXUIElement, _ s: CGSize) -> Bool {
        var ss = s
        guard let v = AXValueCreate(.cgSize, &ss) else { return false }
        return AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, v) == .success
    }
    static func setValue(_ el: AXUIElement, _ value: String) -> AXError {
        AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, value as CFString)
    }
    static func setFocused(_ el: AXUIElement) -> AXError {
        AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }
    static func press(_ el: AXUIElement, _ action: String = kAXPressAction) -> AXError {
        AXUIElementPerformAction(el, action as CFString)
    }
    static func windowID(_ el: AXUIElement) -> CGWindowID? {
        var wid: CGWindowID = 0
        return _AXUIElementGetWindow(el, &wid) == .success ? wid : nil
    }
    static func pid(_ el: AXUIElement) -> pid_t? {
        var p: pid_t = 0
        return AXUIElementGetPid(el, &p) == .success ? p : nil
    }

    /// One node of the tree as the agent sees it.
    struct Node {
        let element: AXUIElement
        let role: String
        let subrole: String?
        let title: String?
        let identifier: String?
        let value: String?
        let description: String?
        let help: String?
        let placeholder: String?
        let enabled: Bool?
        let focused: Bool?
        let selected: Bool?
        let frame: CGRect?
        let depth: Int
        let path: String

        func json(relativeTo origin: CGPoint?) -> JSON {
            var j: JSON = ["role": role, "depth": depth, "path": path]
            if let subrole { j["subrole"] = subrole }
            if let title, !title.isEmpty { j["title"] = title }
            if let identifier, !identifier.isEmpty { j["id"] = identifier }
            if let value, !value.isEmpty { j["value"] = String(value.prefix(200)) }
            if let description, !description.isEmpty { j["description"] = description }
            if let help, !help.isEmpty { j["help"] = help }
            if let placeholder, !placeholder.isEmpty { j["placeholder"] = placeholder }
            if let enabled { j["enabled"] = enabled }
            if let focused, focused { j["focused"] = true }
            if let selected, selected { j["selected"] = true }
            if var f = frame {
                if let origin { f.origin.x -= origin.x; f.origin.y -= origin.y }
                j["frame"] = rectJSON(f)
            }
            return j
        }

        /// Compact one-line rendering used by `tree` (text mode).
        func line(relativeTo origin: CGPoint?) -> String {
            var parts: [String] = [String(repeating: "  ", count: depth) + role]
            if let subrole { parts.append("<\(subrole)>") }
            if let title, !title.isEmpty { parts.append("\"\(title)\"") }
            if let identifier, !identifier.isEmpty { parts.append("id=\(identifier)") }
            if let value, !value.isEmpty { parts.append("value=\"\(String(value.prefix(60)).replacingOccurrences(of: "\n", with: "⏎"))\"") }
            if let description, !description.isEmpty, description != title { parts.append("desc=\"\(description)\"") }
            if let placeholder, !placeholder.isEmpty { parts.append("placeholder=\"\(placeholder)\"") }
            if let enabled, !enabled { parts.append("disabled") }
            if let focused, focused { parts.append("FOCUSED") }
            if let selected, selected { parts.append("selected") }
            if var f = frame {
                if let origin { f.origin.x -= origin.x; f.origin.y -= origin.y }
                parts.append("@(\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height)))")
            }
            parts.append("#\(path)")
            return parts.joined(separator: " ")
        }
    }

    static func node(_ el: AXUIElement, depth: Int, path: String) -> Node {
        Node(element: el,
             role: string(el, kAXRoleAttribute) ?? "?",
             subrole: string(el, kAXSubroleAttribute),
             title: string(el, kAXTitleAttribute),
             identifier: string(el, kAXIdentifierAttribute),
             value: string(el, kAXValueAttribute),
             description: string(el, kAXDescriptionAttribute),
             help: string(el, kAXHelpAttribute),
             placeholder: string(el, kAXPlaceholderValueAttribute),
             enabled: bool(el, kAXEnabledAttribute),
             focused: bool(el, kAXFocusedAttribute),
             selected: bool(el, kAXSelectedAttribute),
             frame: frame(el),
             depth: depth, path: path)
    }

    /// Depth-first walk. `maxNodes` guards against pathological trees
    /// (a terminal with thousands of cells, a huge outline).
    static func walk(_ root: AXUIElement, maxDepth: Int, maxNodes: Int = 4000,
                     rootPath: String = "0", visit: (Node) -> Bool) {
        var count = 0
        func rec(_ el: AXUIElement, _ depth: Int, _ path: String) {
            guard count < maxNodes else { return }
            count += 1
            let n = node(el, depth: depth, path: path)
            let descend = visit(n)
            guard descend, depth < maxDepth else { return }
            for (i, c) in children(el).enumerated() { rec(c, depth + 1, path + "." + String(i)) }
        }
        rec(root, 0, rootPath)
    }

    /// Resolve a `#path` produced by `tree` back to an element.
    static func element(at path: String, in window: AXUIElement) -> AXUIElement? {
        var parts = path.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        parts.removeFirst() // the window itself
        var el = window
        for i in parts {
            let kids = children(el)
            guard i < kids.count else { return nil }
            el = kids[i]
        }
        return el
    }
}

/// Private but long-stable: maps an AX window element to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError
