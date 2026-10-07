import AppKit
import Foundation
import UserNotifications

/// Notifications and the Dock badge (S3-6, DL-101; DB-27). Needs you only: one notification per
/// wait, never while Duo is in front, never for the session you're looking at. Title: the session;
/// subtitle: project · reason; text: Claude's question as asked. Clicking opens the project with
/// the card selected. Permission is asked the first time Duo would notify, never at launch and
/// never in a scripted run (F-54). The badge counts sessions that need you. Both switch off in Settings.
/// macOS draws the badge only for an app allowed badges in Notification Center, so Duo asks for
/// badges with alerts (DL-138, F-161).
extension AppModel {
    public func updateDockBadge() {
        NSApp.dockTile.badgeLabel = fixture.dockBadgeLabel(enabled: DuoState.load().dockBadge)
    }

    /// Called with each snapshot: notifies for sessions that started needing you since the last one.
    func notifyNeedsYou() {
        updateDockBadge()
        let waiting = Dictionary(fixture.sessions.compactMap { s in s.state == .needsYou ? s.sessionId.map { ($0, s) } : nil }, uniquingKeysWith: { a, _ in a })
        // A session that stopped waiting can notify again next time it waits.
        notified = notified.filter { waiting[$0] != nil }
        guard interactivePrompts, terminalsMode == .live, ProcessInfo.processInfo.environment["DUO_AUTOCONFIRM"] == nil,
              !NSApp.isActive, Bundle.main.bundleIdentifier != nil, !waiting.isEmpty else { return }
        // The badge is allowed at the moment Duo would first notify, even with notifications off (DL-138).
        if DuoState.load().dockBadge { Notifier.shared.authorize { _ in } }
        guard DuoState.load().notifyNeedsYou else { return }
        for (id, s) in waiting where !notified.contains(id) && id != visibleSessionId {
            notified.insert(id)
            Notifier.shared.post(id: id, title: s.name, subtitle: s.project + (s.reason.map { " · \($0)" } ?? ""), body: s.question ?? "Needs you", project: s.project)
        }
    }

    /// Duo's Dock menu (ENH-24, DL-144): "Needs you", then each waiting session; clicking one opens
    /// it as `duo2 open <project> <session>` does. Nothing waiting: macOS's own menu only.
    public func dockMenu() -> NSMenu? {
        let (items, more) = fixture.dockMenuItems()
        guard !items.isEmpty else { return nil }
        let menu = NSMenu()
        let header = NSMenuItem(title: "Needs you", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for (title, s) in items {
            menu.addItem(DockMenuAction(title) { [weak self] in self?.openWaiting(s) })   // action: open
        }
        if more > 0 {
            menu.addItem(DockMenuAction("\(more) more need you…") { [weak self] in DuoFocus.take(); self?.zoomOut() })   // action: go all
        }
        return menu
    }

    func openWaiting(_ s: Fixture.Session) {
        DuoFocus.take()
        selectedActionSession = s.id
        open(project: s.project)
    }

    /// Settings › Notifications › Open Notification Settings… (Q-93, DL-144): System Settings at Duo.
    public func openNotificationSettings() {
        let id = Bundle.main.bundleIdentifier ?? "com.dudgeon.duo"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") { NSWorkspace.shared.open(url) }
    }

    /// A notification was clicked: the project, with its card selected.
    func openFromNotification(sessionId: String, project: String) {
        DuoFocus.take()
        if let s = fixture.sessions.first(where: { $0.sessionId == sessionId }) { selectedActionSession = s.id }
        open(project: project)
    }
}

/// A Dock menu item that runs a closure.
@MainActor final class DockMenuAction: NSMenuItem {
    private let run: @MainActor () -> Void
    init(_ title: String, _ run: @escaping @MainActor () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("not used") }
    @objc private func fire() { run() }
}

/// What macOS hides of Duo's attention (Q-93, DL-144): notifications off, or badges off while
/// Duo's Dock count is on. Nil when nothing is hidden or outside an app bundle.
public enum MacOSHides: String, Sendable { case notifications, badges
    public var line: String {
        switch self {
        case .notifications: "macOS has notifications off for Duo, so neither of these shows."
        case .badges: "macOS has Badge application icon off for Duo, so the Dock shows no count."
        }
    }
}

/// Posts through the system and hands clicks back to the model.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    weak var model: AppModel?
    private var allowed = false

    /// Asked the first time Duo would notify or badge (S3-6), not at launch. Badges come with
    /// alerts (DL-138): an install that allowed alerts before Duo asked for badges asks again,
    /// which macOS answers without a prompt once the user has answered (F-161).
    func authorize(_ then: @escaping @MainActor (Bool) -> Void) {
        if allowed { return then(true) }   // once allowed, asked no more this run; a refusal is read again
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            let ok: Bool
            switch settings.authorizationStatus {
            case .notDetermined:
                ok = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true
            default:
                // Answered before badges were asked for: asking again adds the Badges switch to
                // System Settings › Notifications › Duo, quietly, even where notifications are off.
                if settings.badgeSetting == .notSupported { _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge]) }
                ok = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            }
            allowed = ok
            NSApp.dockTile.display()
            then(ok)
        }
    }

    /// What macOS allows Duo, for `duo2 settings` (DL-138). Nil outside an app bundle.
    func permission() async -> String? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        let s = await UNUserNotificationCenter.current().notificationSettings()
        let status = switch s.authorizationStatus {
            case .notDetermined: "not asked yet"; case .denied: "off"; case .authorized, .provisional: "on"; @unknown default: "unknown"
        }
        let badges = switch s.badgeSetting {
            case .enabled: "on"; case .disabled: "off (System Settings › Notifications › Duo › Badge application icon)"
            case .notSupported: "not asked yet"; @unknown default: "unknown"
        }
        return "macOS: notifications \(status), badges \(badges)"
    }

    /// Which of Duo's signals macOS hides, for the Settings line (Q-93).
    func hidden(dockBadge: Bool) async -> MacOSHides? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        let s = await UNUserNotificationCenter.current().notificationSettings()
        if s.authorizationStatus == .denied { return .notifications }
        return dockBadge && s.badgeSetting == .disabled ? .badges : nil
    }

    func post(id: String, title: String, subtitle: String, body: String, project: String) {
        authorize { ok in
            guard ok else { return }
            self.deliver(id: id, title: title, subtitle: subtitle, body: body, project: project)
        }
    }

    private func deliver(id: String, title: String, subtitle: String, body: String, project: String) {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            center.delegate = self
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
