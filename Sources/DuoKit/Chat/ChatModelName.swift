import Foundation

// The model chip's words (DL-168, chat-model-chip-handoff): the name Claude Code uses, made from
// whatever it gave: a model id (the SessionStart hook, an assistant record), or a `/model` result line.

public enum ChatModelName {
    /// A model id as Claude Code names it: `claude-opus-5-5` → `Opus 5.5`, `claude-sonnet-5` → `Sonnet 5`,
    /// `claude-haiku-4-5-20251001` → `Haiku 4.5`. An id that doesn't fit shows as given; a name
    /// (`Sonnet 5.5`) is used as is. Nil for nothing, or a synthetic marker (`<synthetic>`).
    public static func display(_ given: String) -> String? {
        var s = given.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || s.hasPrefix("<") { return nil }
        // A long-context suffix (`claude-opus-5-5[1m]`) isn't part of the name.
        let bare = s.replacingOccurrences(of: #"\[[^\]]*\]$"#, with: "", options: .regularExpression)
        if let m = bare.chatMatch(#"^claude-([a-z]+)-(\d+)(?:-(\d{1,2}))?(?:-\d{8})?$"#), let family = m[1], let major = m[2] {
            s = family.capitalized + " " + major + (m[3].map { "." + $0 } ?? "")
        }
        return s
    }

    /// The model a `/model` result line names: "Set model to `X` …" or "Kept model as `X`", with the
    /// backticks and the ANSI bold (`ESC[1m … ESC[22m`, 2.1.219) taken off. Nil for any other text.
    public static func fromResult(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.chatIs(#"(?:Set model to|Kept model as)\s"#) else { return nil }
        let ansi = #"\x{1B}?\[[0-9;]*m"#
        let name: String?
        if let b = t.chatMatch("`([^`]+)`")?[1] { name = b }
        else if let b = t.chatMatch(#"\x{1B}\[1m(.+?)\x{1B}\[22m"#)?[1] { name = b }
        else {
            // Neither marks the name: it runs to the end of the line, or to " for this session" / " and ".
            let plain = t.replacingOccurrences(of: ansi, with: "", options: .regularExpression)
            name = plain.chatMatch(#"(?:Set model to|Kept model as)\s+(.+?)(?:\s+(?:for this session|and\b|·|\().*)?$"#)?[1]
        }
        guard let name else { return nil }
        return display(name.replacingOccurrences(of: ansi, with: "", options: .regularExpression).replacingOccurrences(of: "`", with: ""))
    }
}
