import DuoKit
import Foundation

/// Delete Session… from the row's menu, and the open-menu fill (F-229, F-230, Q-147).
@MainActor func sessionRowChecks(_ base: Fixture) {
    print("session row: delete and the open-menu mark (F-229, F-230)")
    let m = AppModel(fixture: base)
    // The menu used to drop the result: a refusal said nothing and the click looked dead. Every outcome now reaches `done`.
    var said: [String] = []
    m.deleteSession("no-such-session") { r in if case .failure(let e) = r { said.append("\(e)") } }
    check(said.count == 1 && said[0].contains("no session"), "an unknown session answers (didn't silently do nothing)")
    if let s = base.sessions.first(where: { $0.sessionId != nil }) {
        said = []
        m.deleteSession(s.tabKey) { r in if case .failure(let e) = r { said.append("\(e)") } }
        check(said.count == 1, "a session with nothing on disk is refused out loud, not dropped")
    }
    // A Claude under a Duo terminal's shell is Duo's to end; one under anything else isn't.
    let me = getpid(), parent = getppid()
    check(AppModel.isDescendant(me, of: [parent]), "a process under a Duo terminal's shell is Duo's")
    check(!AppModel.isDescendant(me, of: [999_999]), "a process under another shell isn't")
    m.contextMenuSession = "x"
    check(m.contextMenuSession == "x", "the open-menu mark is model state the rows read")
    check(DuoNSColor.menuTarget != DuoNSColor.selected, "the open-menu fill is its own token, not the hover/selected fill")
}
