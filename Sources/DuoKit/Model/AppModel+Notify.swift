import AppKit
import Foundation
import UserNotifications

/// Notifications and the Dock badge (S3-6, DL-101; DB-27). Needs you only: one notification per
/// wait, never while Duo is in front, never for the session you're looking at. Title: the session;
/// subtitle: project · reason; text: Claude's question as asked. Clicking opens the project with
/// the card selected. Permission is asked the first time Duo would notify, never at launch and
/// never in a scripted run (F-54). The badge counts sessions that need you. Both switch off in Settings.
extension AppModel {
    public func updateDockBadge() {
        let n = fixture.sessions.filter { $0.state == .needsYou }.count
        NSApp.dockTile.badgeLabel = DuoState.load().dockBadge && n > 0 ? "\(n)" : nil
    }

    /// Called with each snapshot: notifies for sessions that started needing you since the last one.
    func notifyNeedsYou() {
        updateDockBadge()
        let waiting = Dictionary(fixture.sessions.compactMap { s in s.state == .needsYou ? s.sessionId.map { ($0, s) } : nil }, uniquingKeysWith: { a, _ in a })
        // A session that stopped waiting can notify again next time it waits.
        notified = notified.filter { waiting[$0] != nil }
        guard interactivePrompts, terminalsMode == .live, ProcessInfo.processInfo.environment["DUO_AUTOCONFIRM"] == nil,
              !NSApp.isActive, DuoState.load().notifyNeedsYou, Bundle.main.bundleIdentifier != nil else { return }
        for (id, s) in waiting where !notified.contains(id) && id != visibleSessionId {
            notified.insert(id)
            Notifier.shared.post(id: id, title: s.name, subtitle: s.project + (s.reason.map { " · \($0)" } ?? ""), body: s.question ?? "Needs you", project: s.project)
        }
    }

    /// A notification was clicked: the project, with its card selected.
    func openFromNotification(sessionId: String, project: String) {
        DuoFocus.take()
        if let s = fixture.sessions.first(where: { $0.sessionId == sessionId }) { selectedActionSession = s.id }
        open(project: project)
    }
}

/// Posts through the system and hands clicks back to the model.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    weak var model: AppModel?
    private var asked = false

    func post(id: String, title: String, subtitle: String, body: String, project: String) {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            if !asked {
                let status = await center.notificationSettings().authorizationStatus
                asked = true
                // Asked the first time Duo would notify (S3-6), not at launch.
                if status == .notDetermined {
                    guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
                } else if status != .authorized && status != .provisional {
                    return
                }
            }
            let c = UNMutableNotificationContent()
            c.title = title
            c.subtitle = subtitle
            c.body = body
            c.threadIdentifier = project
            c.userInfo = ["session": id, "project": project]
            try? await center.add(UNNotificationRequest(identifier: "needs-\(id)", content: c, trigger: nil))
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler done: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let id = info["session"] as? String ?? "", project = info["project"] as? String ?? ""
        DispatchQueue.main.async { MainActor.assumeIsolated { Notifier.shared.model?.openFromNotification(sessionId: id, project: project) } }
        done()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([])   // never while Duo is in front
    }
}
