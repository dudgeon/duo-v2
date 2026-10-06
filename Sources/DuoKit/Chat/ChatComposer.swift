import DuoControl
import Foundation

/// Where Duo leaves the composer's text for `duo2 compose`, and how Claude runs it.
public enum ChatComposer {
    public static var dir: URL { DuoPaths.support.appending(path: "compose") }

    /// `EDITOR` for Duo's Claude sessions (F-112). Claude Code splits it on spaces and runs it
    /// without a shell (quotes are taken literally), so a path with a space can't be used: then
    /// there's no helper, and the composer pastes.
    public static func editorCommand(cli: String) -> String? {
        cli.contains(where: \.isWhitespace) ? nil : cli + " compose"
    }

    /// The user's keybindings move Ctrl+G (`chat:externalEditor`): then the composer pastes.
    public static var ctrlGIsTheEditor: Bool {
        let file = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/keybindings.json")
        guard let data = try? Data(contentsOf: file), let text = String(data: data, encoding: .utf8), text.contains("chat:externalEditor") else { return true }
        // Bound to something: only ctrl+g (or its default ctrl+x ctrl+e) keeps it ours.
        return text.range(of: #""ctrl\+g"\s*:\s*"chat:externalEditor""#, options: .regularExpression) != nil
    }
}
