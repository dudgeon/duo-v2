import AppKit
import Foundation

extension AppModel {
    /// Opens an Explainer at its trigger from the keyboard or VoiceOver (Help › Explain Tasks, Explain):
    /// it stays until Esc, a click or typing. Works after Don't show again too.
    func explain(_ id: ExplainerID, key: String, origin: String) {
        guard SheetCenter.shared.current == nil, !search.isOpen else { return }
        if explainer.show(id, key: key, origin: origin, pinned: true) {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: ExplainerContent.content(id).spoken, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    /// Where each Explainer opens: the control it explains when it is on screen, else the window's top centre (X1).
    private static let anchors: [ExplainerID: [(key: String, origin: String)]] = [
        .modes: [("modes.pill", "modes.pill")],
        .tasks: [("tasks.new-row", "tasks.new-row"), ("tasks.fold-plus", "tasks.fold-head"), ("tasks.fold-head", "tasks.fold-head")],
        .director: [("director.slot", "director.slot")],
        .home: [("home.tile", "home.tile")],
        .projects: [],
    ]

    /// Help › Explain ▸ …, `duo2 explain <id>`, and Show me: opens the Explainer on its control, pinned (Esc, a click or
    /// typing closes it). With the control off screen it opens at the window's top centre.
    public func explainOpen(_ id: ExplainerID) {
        for (key, origin) in Self.anchors[id] ?? [] where explainer.frames[key] != nil { return explain(id, key: key, origin: origin) }
        explain(id, key: "window.top", origin: "window.top")
    }

    /// Help › Explain Chat and Terminal: at the mode pill on the selected Claude tab (DL-339).
    func explainModes() { explainOpen(.modes) }

    /// Help › Explain Tasks: at the New task row, or the Tasks fold's header when the fold is closed.
    func explainTasks() { explainOpen(.tasks) }
}
