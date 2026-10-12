import DuoKit
import Foundation

/// The session glyph's kind and the task row's hand-or-empty rule (DL-174).
@MainActor func sessionGlyphChecks(_ base: Fixture) {
    print("session glyph: kind and the task row's mark (DL-174)")
    var p = ChatPrefs()
    func kind(_ key: String, home: Bool = false, chat: ChatViewMode? = nil, outside: Bool = false) -> ChatViewMode {
        SessionKind.resolve(prefs: p, key: key, home: home, chatMode: chat, outsideDuo: outside)
    }
    check(kind("a") == .terminal, "no choice yet: the default, a terminal")
    p.set(.chat, for: "b")
    check(kind("b") == .chat && kind("a") == .chat, "chat.json: a session's own mode, and the mode used last for the rest")
    p.fixedDefault = .terminal
    check(kind("b") == .chat && kind("c") == .terminal, "a fixed default applies to sessions with no mode of their own")
    p.fixedDefault = nil
    check(kind("home-s", home: true) == .chat, "Home sessions open in chat")
    p.home = .terminal
    check(kind("home-s", home: true) == .terminal, "Home's setting decides for Home sessions")
    check(kind("b", chat: .terminal) == .terminal && kind("c", chat: .chat) == .chat, "a tab's live chat mode wins (the pill changes the row)")
    check(kind("x", chat: .chat) == .chat, "a fixture chat's meta.json mode shows the bubble")
    check(kind("b", outside: true) == .terminal, "a session running outside Duo is a terminal session")
    check(kind("zz", outside: true) == .terminal, "outside Duo with no choice of its own: a terminal")
    check(kind("b", chat: .chat, outside: true) == .chat, "outside only when no chat is open for it in Duo")

    check(SessionGlyph.taskMark(.needsYou), "a task row shows the hand while a session needs you")
    check(SessionState.allCases.filter(SessionGlyph.taskMark) == [.needsYou], "and nothing for any other state")
    check(SessionGlyph.spokenKind(.chat) == "chat session" && SessionGlyph.spokenKind(.terminal) == "terminal session", "accessibility words")
}
