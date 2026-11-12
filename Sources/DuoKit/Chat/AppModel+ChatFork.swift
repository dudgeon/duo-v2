import Foundation

// Fork from a chat turn (DL-338, Q-508): a whole fork under a minted `--session-id` (DL-14), a new tab right after the
// original, focused, in chat; then a conversation-only rewind in the copy to that point, worked through Claude's own
// /rewind menu (Claude Code can't cut a forked session at a turn in its interface, F-652). Files are never restored in a
// fork: both sessions share the folder. The chain was run end to end on the mock API on 2.1.284 and 2.1.316 (F-667).

extension AppModel {
    /// Forks the session `key` from the chat turn `turnId`. False when it can't be asked (the transcript doesn't have the
    /// turn's ids yet, or the session isn't in a project). The rewind in the copy runs after, in the background; if it
    /// can't, the copy shows its terminal, uncut.
    @discardableResult
    public func forkFromTurn(sessionKey key: String, turnId: String) -> Bool {
        guard let chat = chat(for: key), let plan = chat.forkPlan(turnId), let s = findSession(key, in: nil), let sid = s.sessionId,
              let new = open(project: s.project).resumeAsFork(sid, in: s.project) else { return false }
        guard case .rewind(let uuid, let keep) = plan else { return true }
        Task { @MainActor [weak self] in
            // The copy's Claude starts, loads the history and reaches its prompt; its chat is made when the tab shows.
            for _ in 0..<400 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self else { return }
                let fork = self.chat(for: new) ?? self.terminals.existing(new).flatMap { self.attachChat($0) }
                guard let fork, fork.terminal != nil,
                      fork.log.items.contains(where: { if case .you(let y) = $0 { y.uuid == uuid } else { false } }),
                      fork.reread().kind == .idle else { continue }
                _ = await fork.rewind(toPromptUuid: uuid, code: false, keepPrompt: keep)   // a refusal shows the terminal, uncut
                return
            }
        }
        return true
    }
}

extension ChatSession {
    /// The row's Fork, the Chat menu, `duo2 session fork --at`: asks the app, which owns the tabs.
    @discardableResult
    public func askFork(_ turnId: String) -> Bool {
        guard screen.kind != .busy, forkPlan(turnId) != nil else { return false }
        return onFork?(turnId) ?? false
    }
}
