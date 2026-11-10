import Foundation

/// A message typed while a turn runs isn't a `user` entry: Claude Code stores it as an
/// `attachment` of type `queued_command` whose `origin.kind` is `human` (F-625, F-638).
/// Every transcript reader that asks "what did the user say" goes through this, so a
/// peer message, a task notification or a hook's queued command never counts as a prompt.
public enum MidTurnPrompt {
    /// The text the user typed mid-turn, or nil for any other record (including a queued
    /// command from a task notification or a peer, whose origin isn't `human`).
    public static func text(_ r: [String: Any]) -> String? {
        guard r["type"] as? String == "attachment", let a = r["attachment"] as? [String: Any],
              a["type"] as? String == "queued_command",
              (a["origin"] as? [String: Any])?["kind"] as? String == "human",
              let p = a["prompt"] as? String else { return nil }
        return p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : p
    }
}
