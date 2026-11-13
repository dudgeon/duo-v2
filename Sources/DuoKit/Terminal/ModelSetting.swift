import Foundation

/// Settings › Claude Code › Model for sessions (DL-339, Q-516; supersedes DL-153's "Duo never passes a model" for the user's
/// own choice). Aliases only; nothing chosen is Claude's default and changes nothing. Applied through ANTHROPIC_MODEL in
/// `ChildEnvironment`, for every session Duo starts (new, resume, fork). `duo2 settings model opus|sonnet|haiku|default`.
public enum ModelSetting {
    public static let aliases = ["opus", "sonnet", "haiku"]

    /// What is saved, if it is one of the aliases.
    public static var saved: String? { DuoState.load().sessionModel.flatMap { aliases.contains($0) ? $0 : nil } }

    public static func label(_ m: String?) -> String { m.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Claude’s default" }

    public static let help = "Used by new sessions, and by sessions you resume or reopen. A model you pick inside a session with /model lasts until you close it; reopened, it goes back to this. A model your organisation has locked still wins."
}
