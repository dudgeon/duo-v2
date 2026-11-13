import DuoControl
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

extension AppModel {
    /// `duo2 session turns | copy-turn | rewind` (DL-338).
    func chatTurnVerb(_ id: ActionID, _ inv: Invocation, _ done: @escaping @MainActor (Reply) -> Void) {
        let usage = "usage: \(id.action.usage)"
        guard let k = inv[0], let s = findSession(k, in: nil) else { return done(.fail(usage)) }
        guard let chat = chat(for: s.tabKey) else { return done(.fail("\(s.name) has no chat yet: open it in Duo first")) }
        if id == .sessionTurns {
            let list = chat.turnList
            let text = list.isEmpty ? "No turns yet." : list.map { "\($0.n)  \($0.role)  \($0.uuid.map { String($0.prefix(8)) } ?? "-")  \($0.preview)" }.joined(separator: "\n")
            return done(.ok(text, list.map { ["n": $0.n, "role": $0.role, "uuid": $0.uuid ?? "", "preview": $0.preview] as [String: Any] }))
        }
        guard let ref = inv[1] else { return done(.fail(usage)) }
        guard let turn = chat.turnID(for: ref) else { return done(.fail("no turn '\(ref)' in \(s.name): `duo2 session turns \(k)` lists them")) }
        if id == .sessionCopyTurn {
            return done(chat.copyTurn(turn) ? .ok("Copied turn \(ref) of \(s.name) as Markdown.") : .fail("turn \(ref) has no words to copy"))
        }
        guard chat.canRewind(turn) else { return done(.fail("turn \(ref) isn't one of your messages that Claude Code knows (the transcript has no id for it yet)")) }
        guard chat.screen.kind != .busy else { return done(.fail("Claude is working in \(s.name); rewind when it finishes")) }
        // Always asks, in Duo's sheet, and waits for the user's answer (no --yes, DL-338).
        let shown = chat.askRewind(turn, preferCode: inv.has("code")) { result in
            guard let result else { return done(.fail("cancelled: the user clicked Cancel in Duo. Nothing changed.")) }
            done(result.ok ? .ok("Rewound \(s.name) to before turn \(ref); the message waits in its composer.") : .fail("not rewound: \(result.why ?? "refused"). The terminal is showing."))
        }
        if !shown { done(.fail("couldn't ask: \(s.name) isn't at a prompt Duo can rewind")) }
    }
}
