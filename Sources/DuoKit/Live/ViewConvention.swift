import Foundation
import DuoControl

/// What a session is told about the view the user is reading it in (DL-339 Q-513, F-661, F-676):
/// the primer says what holds in both views; this says what only one view does. Chat and terminal
/// are the same process (DL-118) and the user switches at will, so it goes by `duo2 hook context`
/// (DL-116's route): in full at SessionStart, and at UserPromptSubmit only when the view differs from
/// the one Duo last told this session, so a session that never switches pays for it once.
/// A fact and a default, never a "must": the user's own CLAUDE.md is read after it and wins.
public enum ViewConvention {
    public enum View: String, Sendable { case chat, terminal }

    public static func text(_ view: View) -> String {
        switch view {
        case .chat:
            return "Duo: The user is reading this session in Duo's chat view. Markdown renders (lists, tables, code blocks). "
                + "A file name in backticks is a link that opens the file beside the conversation, so write a path from the project folder "
                + "(`docs/plan.md`, `src/app.py:42` with a line, `Makefile`, a whole path even if it has a space) and never paste a file's contents to show it."
        case .terminal:
            return "Duo: The user is reading this session in Duo's terminal view. Plain text only: no tables or Markdown links. "
                + "Write file names as a path from the project folder (`docs/plan.md`, `src/app.py:42`); ⌘-click opens it beside the conversation."
        }
    }

    public static func toldFile(_ sessionId: String, in dir: URL = DuoPaths.events) -> URL {
        dir.appending(path: "\(sessionId).view.txt")
    }

    static func told(_ sessionId: String, in dir: URL) -> View? {
        (try? String(contentsOf: toldFile(sessionId, in: dir), encoding: .utf8)).flatMap { View(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// A hook's answer (empty for none), recording what was told. `view` nil (not known): says nothing.
    public static func hook(_ event: String, sessionId: String, view: View?, in dir: URL = DuoPaths.events) -> String {
        guard let view else { return "" }
        if event != "start", told(sessionId, in: dir) == view { return "" }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data(view.rawValue.utf8).write(to: toldFile(sessionId, in: dir), options: .atomic)
        return text(view)
    }
}
