import Foundation
import ApplicationServices

/// The menu bar of a background app, through Accessibility. Key equivalents
/// posted to an inactive app never reach NSMenu, so ⌘-chords are resolved
/// here and pressed directly.
struct MenuItem {
    let element: AXUIElement
    let path: [String]
    let cmdChar: String?
    let modifiers: Int       // AX mask: 1 shift, 2 option, 4 control, 8 no-command
    let enabled: Bool
    let hasSubmenu: Bool

    var json: JSON {
        var j: JSON = ["path": path.joined(separator: " › "), "enabled": enabled]
        if let c = cmdChar, !c.isEmpty { j["shortcut"] = MenuItem.describe(cmdChar: c, modifiers: modifiers) }
        return j
    }

    static func describe(cmdChar: String, modifiers: Int) -> String {
        var s = ""
        if modifiers & 4 != 0 { s += "ctrl+" }
        if modifiers & 2 != 0 { s += "alt+" }
        if modifiers & 1 != 0 { s += "shift+" }
        if modifiers & 8 == 0 { s += "cmd+" }
        return s + cmdChar.lowercased()
    }
}

enum Menus {
    static func items(of app: AXUIElement, maxDepth: Int = 4) -> [MenuItem] {
        guard let bar = AX.attr(app, kAXMenuBarAttribute) else { return [] }
        var out: [MenuItem] = []
        func walk(_ el: AXUIElement, _ path: [String], _ depth: Int) {
            for child in AX.children(el) {
                let role = AX.string(child, kAXRoleAttribute) ?? ""
                if role == "AXMenu" { walk(child, path, depth); continue }
                let title = AX.string(child, kAXTitleAttribute) ?? ""
                let kids = AX.children(child)
                let hasSub = kids.contains { AX.string($0, kAXRoleAttribute) == "AXMenu" }
                if role == "AXMenuItem", !title.isEmpty {
                    out.append(MenuItem(
                        element: child, path: path + [title],
                        cmdChar: AX.string(child, kAXMenuItemCmdCharAttribute),
                        modifiers: (AX.attr(child, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue ?? 0,
                        enabled: AX.bool(child, kAXEnabledAttribute) ?? true,
                        hasSubmenu: hasSub))
                }
                if (role == "AXMenuBarItem" || hasSub), depth < maxDepth {
                    walk(child, path + [title], depth + 1)
                }
            }
        }
        walk(bar as! AXUIElement, [], 0)
        return out
    }

    /// "cmd+shift+n" → the menu item carrying that key equivalent.
    static func item(for chord: String, in app: AXUIElement) -> MenuItem? {
        let parts = chord.lowercased().split(separator: "+").map(String.init)
        guard parts.contains("cmd") || parts.contains("command"), let key = parts.last, key.count == 1 else { return nil }
        var want = 0
        if parts.contains("shift") { want |= 1 }
        if parts.contains("alt") || parts.contains("opt") || parts.contains("option") { want |= 2 }
        if parts.contains("ctrl") || parts.contains("control") { want |= 4 }
        return items(of: app).first { item in
            guard let c = item.cmdChar?.lowercased(), c == key, item.modifiers & 8 == 0 else { return false }
            return (item.modifiers & 7) == want
        }
    }

    /// Match by trailing path components, case-insensitive:
    /// ["New"] or ["File", "New"] or ["View", "Appearance", "Dark"].
    static func item(titled path: [String], in app: AXUIElement) -> MenuItem? {
        let want = path.map { $0.lowercased() }
        let all = items(of: app)
        return all.first { $0.path.map { $0.lowercased() }.suffix(want.count).elementsEqual(want) }
            ?? all.first { item in
                let p = item.path.map { $0.lowercased() }
                return want.count == 1 && (p.last?.contains(want[0]) ?? false)
            }
    }
}
