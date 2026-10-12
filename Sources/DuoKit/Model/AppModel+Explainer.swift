import AppKit
import Foundation

extension AppModel {
    /// Opens an Explainer at its trigger from the keyboard or VoiceOver (Help › Explain Tasks, Explain):
    /// it stays until Esc, a click or typing. Works after Don't show again too.
    func explain(_ id: ExplainerID, key: String, origin: String) {
        guard SheetCenter.shared.current == nil, !search.isOpen else { return }
        if explainer.show(id, key: key, origin: origin, pinned: true) {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: ExplainerContent.tasks.spoken, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    /// Help › Explain Tasks: at the New task row, or the Tasks fold's header when the fold is closed.
    func explainTasks() {
        for (key, origin) in [("tasks.new-row", "tasks.new-row"), ("tasks.fold-plus", "tasks.fold-head"), ("tasks.fold-head", "tasks.fold-head")] where explainer.frames[key] != nil {
            return explain(.tasks, key: key, origin: origin)
        }
        info("Open a project to see Tasks.")
    }
}
