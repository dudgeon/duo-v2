import Foundation

/// Chat mode's composer is Claude Code's own external editor (Ctrl+G, F-104). Duo's Claude
/// sessions get `duo2 compose` as `EDITOR` and `VISUAL`; before pressing Ctrl+G, Duo leaves the
/// composer's text in `<dir>/<session>.json` with the basis it showed (what Claude's prompt held
/// when the composer opened on it). The helper then:
///   - Claude's prompt file (`claude-prompt-*.md`) and a hand-over waiting: if the prompt still
///     holds the basis, the text replaces it; if not (typed into in the terminal meanwhile), it is
///     left alone and `<session>.refused` says what it holds. Nothing is lost either way.
///   - anything else (Claude's Bash running `git commit`, Ctrl+G pressed in the terminal): the
///     user's own editor (`DUO_USER_VISUAL`, `DUO_USER_EDITOR`, else vi), as if Duo weren't there.
public enum ChatCompose {
    public static let dirVariable = "DUO_COMPOSE_DIR"
    public static let userEditor = "DUO_USER_EDITOR"
    public static let userVisual = "DUO_USER_VISUAL"

    public struct Handover: Codable, Equatable, Sendable {
        public var text: String
        public var basis: String
        public init(text: String, basis: String) { self.text = text; self.basis = basis }
    }

    public static func handoverFile(_ dir: URL, _ session: String) -> URL { dir.appending(path: "\(session).json") }
    public static func refusedFile(_ dir: URL, _ session: String) -> URL { dir.appending(path: "\(session).refused") }

    /// Duo, before Ctrl+G.
    public static func leave(_ h: Handover, in dir: URL, session: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: refusedFile(dir, session))
        try JSONEncoder().encode(h).write(to: handoverFile(dir, session), options: .atomic)
    }

    /// Whitespace runs folded: the screen shows Claude's prompt wrapped and trimmed.
    public static func same(_ a: String, _ b: String) -> Bool {
        func n(_ s: String) -> String { s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        return n(a) == n(b)
    }

    public enum Outcome: Equatable, Sendable { case handedOver, refused, notOurs }

    /// The helper's work on one file. `notOurs` means: open the user's editor instead.
    public static func take(file: URL, dir: URL?, session: String?) -> Outcome {
        guard let dir, let session, file.lastPathComponent.hasPrefix("claude-prompt-"), file.pathExtension == "md" else { return .notOurs }
        let hf = handoverFile(dir, session)
        guard let data = try? Data(contentsOf: hf), let h = try? JSONDecoder().decode(Handover.self, from: data) else { return .notOurs }
        try? FileManager.default.removeItem(at: hf)   // used once, whatever happens next
        let now = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        guard same(now, h.basis) else {
            try? now.write(to: refusedFile(dir, session), atomically: true, encoding: .utf8)
            return .refused
        }
        do { try h.text.write(to: file, atomically: false, encoding: .utf8) } catch { return .refused }
        return .handedOver
    }

    /// The user's own editor, for everything that isn't a hand-over.
    public static func userEditorCommand(_ env: [String: String]) -> String {
        for k in [userVisual, userEditor] { if let v = env[k], !v.isEmpty { return v } }
        return "vi"
    }
}
