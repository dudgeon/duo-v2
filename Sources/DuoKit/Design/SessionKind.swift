import Foundation

/// A session's kind, the mode a click would open it in (DL-174; handoff 01, "Where kind and state
/// come from"). `ChatPrefs.mode(for:home:)` for a session Duo can open; the tab's live
/// `ChatSession.mode` (or a fixture chat's `meta.json` mode) when one exists; and a terminal for a
/// session running outside Duo, which Duo can't switch.
public enum SessionKind {
    public static func resolve(prefs: ChatPrefs, key: String, home: Bool, chatMode: ChatViewMode?, outsideDuo: Bool) -> ChatViewMode {
        if let chatMode { return chatMode }
        if outsideDuo { return .terminal }
        return prefs.mode(for: key, home: home)
    }
}

extension AppModel {
    /// The kind a session row's glyph draws. Fixture sessions take their recording's mode from the fixture's own chats.
    public func sessionKind(key: String, project: String) -> ChatViewMode {
        let s = fixture.sessions.first { $0.tabKey == key }
        let outside = s?.liveProcess == true && !hasOpenTerminal(key)
        return SessionKind.resolve(prefs: chats.prefs, key: key, home: project == fixture.home?.name,
                                   chatMode: chat(for: key)?.mode, outsideDuo: outside)
    }

    public func sessionKind(_ s: Fixture.Session) -> ChatViewMode { sessionKind(key: s.tabKey, project: s.project) }

    /// "chat session" / "terminal session", for a row's accessibility label.
    public func spokenKind(key: String, project: String) -> String { SessionGlyph.spokenKind(sessionKind(key: key, project: project)) }
}
