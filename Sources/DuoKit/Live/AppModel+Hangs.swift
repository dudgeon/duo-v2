import Foundation

extension AppModel {
    /// What's on screen, in one line, for the hang log (DL-139): where you are, what the console
    /// shows (a chat with its size, a terminal, a shell) and the right pane's kind. No titles or text.
    public func hangScreen() -> String {
        var parts: [String] = []
        switch altitude {
        case .allProjects: parts.append("all projects")
        case .project(let p): parts.append("project \(p)")
        }
        if let k = visibleSessionId {
            if isShell(k) { parts.append("shell") }
            else if let c = chat(for: k), c.showsChat {
                parts.append("chat, \(c.log.items.count) items, \(c.log.steps.count) steps\(c.log.earlierHidden ? ", earlier turns hidden" : "")")
            } else { parts.append("terminal") }
        }
        if case .project = altitude {
            let tab = rightTab ?? "Project"
            let ext = (tab as NSString).pathExtension.lowercased()
            parts.append("right: " + (tab == "Project" ? "project" : ext.isEmpty ? "group" : ext))
        }
        parts.append("\(terminals.all.count) terminals")
        return parts.joined(separator: " · ")
    }
}
