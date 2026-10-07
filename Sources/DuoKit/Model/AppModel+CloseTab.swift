import Foundation

/// Closing a console or Home tab while it's busy asks first (Q-71, DL-127): Claude working in
/// the session, or a shell running a command. An idle tab closes at once, as before. ⌘W, the
/// tab's × (DL-126) and End Session all come through here; `duo2 session close` refuses instead
/// unless given --force.
extension AppModel {
    public enum TabBusy: Equatable {
        case claudeWorking(name: String, project: String)
        case shellRunning(command: String)
    }

    /// Why closing this tab would interrupt something, or nil when it's idle.
    public func busy(_ key: String) -> TabBusy? {
        if isShell(key) {
            guard let t = terminals.existing(key), let proc = t.view.process, proc.running, proc.childfd >= 0 else { return nil }
            let pgid = tcgetpgrp(proc.childfd)
            guard pgid > 0, pgid != proc.shellPid else { return nil }   // at its prompt
            return .shellRunning(command: ForegroundCommand.title(ptyFD: proc.childfd, shellPid: proc.shellPid) ?? consoleTitle(key))
        }
        guard let s = fixture.sessions.first(where: { $0.tabKey == key }), s.state == .working else { return nil }
        return .claudeWorking(name: s.name, project: s.project)
    }

    /// The question for a busy tab, as `standins2-handoff/close-busy` words it (DL-132 k): the title
    /// asks the real question, the line says what stops and what's kept.
    func closeQuestion(_ why: TabBusy, close: @escaping @MainActor () -> Void) -> DuoQuestion {
        var q = DuoQuestion(title: "", choices: [
            .init(label: "Cancel", isCancel: true) {},
            .init(label: "Close Tab", isDefault: true, action: close),
        ])
        switch why {
        case .claudeWorking(let name, let project):
            q.title = "Stop Claude and close “\(name)”?"
            q.paragraphs = ["Claude is working on a reply. The session stays in \(project); resume it any time."]
        case .shellRunning(let command):
            q.title = "Stop “\(command)” and close the tab?"
            q.paragraphs = ["The command is still running. Closing the tab stops it."]
        }
        return q
    }

    /// Runs `close` at once when the tab is idle, or after the user says Close Tab when it's busy.
    public func confirmClose(_ key: String, _ close: @escaping @MainActor () -> Void) {
        guard let why = busy(key) else { return close() }
        ask(closeQuestion(why, close: close))
    }
}
