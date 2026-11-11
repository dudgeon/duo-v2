import DuoControl
import Foundation

/// `duo2 window list|new|focus|close|colour|home` (DL-71, DL-311). Each runs on the window the request
/// resolved to (Q-430: `--window`, else the caller's session's window, else the primary).
extension AppModel {
    func windowVerb(_ id: ActionID, _ inv: Invocation, _ done: @escaping @MainActor (Reply) -> Void) {
        switch id {
        case .windowList:
            let all = core.models
            done(.ok(all.map(\.windowLine).joined(separator: "\n"), all.map(\.windowJSON)))
        case .windowNew:
            if let name = inv[0] {
                guard let p = project(named: name) else { return done(noProject(name)) }
                let had = core.model(showing: p.name)
                let m = core.openWindow(project: p.name)
                done(.ok(had != nil ? "\(p.name) is in window \(m.windowNumber); brought it forward." : "Opened \(p.name) in window \(m.windowNumber).", m.windowJSON))
            } else {
                let m = core.openWindow()
                done(.ok("Opened window \(m.windowNumber)" + (m.windowColour.map { ", \($0.name)" } ?? "") + ".", m.windowJSON))
            }
        case .windowFocus:
            guard let n = inv[0] else { return done(.fail("usage: \(id.action.usage)")) }
            guard let m = core.model(named: n) else { return done(.fail("no window '\(n)'")) }
            core.bringForward(m)
            done(.ok("Window \(m.windowNumber) (\(m.windowTitle)) is in front.", m.windowJSON))
        case .windowClose:
            let m: AppModel
            if let n = inv[0] {
                guard let found = core.model(named: n) else { return done(.fail("no window '\(n)'")) }
                m = found
            } else { m = self }
            let number = m.windowNumber
            done(core.closeWindow(m) ? .ok("Closed window \(number).") : .ok("Window \(number) is the last; it's hidden and Duo keeps running."))
        case .windowColour:
            if let a = inv.flags["auto"] {
                guard a == "on" || a == "off" else { return done(.fail("usage: \(id.action.usage)")) }
                core.colourNewWindows = a == "on"
            }
            if let name = inv[0]?.lowercased() {
                if name == "none" { setWindowColour(nil) }
                else {
                    let key = name.replacingOccurrences(of: " ", with: "-")
                    guard let c = DuoWindowColour.all.first(where: { $0.id == key || $0.name.lowercased() == name }) else {
                        return done(.fail("no colour '\(name)'. Colours: none, " + DuoWindowColour.all.map(\.id).joined(separator: ", ")))
                    }
                    setWindowColour(c.id)
                }
            }
            let colour = windowColourID.flatMap { id in DuoWindowColour.all.first { $0.id == id }?.name } ?? "None"
            let classic = core.classicOn ? " Window colours are off while Classic is on." : ""
            done(.ok("Window \(windowNumber): \(colour). Colour new windows automatically: \(core.colourNewWindows ? "on" : "off").\(classic)", windowJSON))
        default:
            done(.fail("not a window verb"))
        }
    }

    /// One line of `duo2 window list` and `status`.
    var windowLine: String {
        var marks: [String] = []
        if core.primary === self { marks.append("primary") }
        if core.keyModel === self, core.keyWindowID != nil { marks.append("key") }
        if hiddenByClose { marks.append("hidden") }
        let colour = windowColourID.flatMap { id in DuoWindowColour.all.first { $0.id == id }?.name } ?? "None"
        return "\(windowNumber)  \(windowTitle)  \(colour)" + (marks.isEmpty ? "" : "  (" + marks.joined(separator: ", ") + ")")
    }

    var windowJSON: [String: Any] {
        var j: [String: Any] = ["number": windowNumber, "title": windowTitle, "colour": windowColourID ?? "none",
                                "primary": core.primary === self]
        if let p = currentProject?.name { j["project"] = p }
        return j
    }
}
