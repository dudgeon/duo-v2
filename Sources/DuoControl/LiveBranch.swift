import Foundation

/// A transcript's live branch (F-656). After `/rewind` Claude Code keeps the removed turns in the
/// JSONL as a dead branch: nothing marks them, the next prompt's `parentUuid` just points at the
/// record before the rewound turn. Every reader that asks "what turns does this session have" goes
/// through here instead of trusting file order.
///
/// The records are not a clean line: parallel tool results hang off sibling records, so "not an
/// ancestor of the last record" would throw real turns away (about 45 of 60 recent transcripts
/// here have such records). A *prompt* is what a rewind removes, so the rule is about prompts: a
/// prompt (your typed message, or one typed mid-turn) is live when it is an ancestor of the last
/// record; everything after a dead prompt, up to the next prompt, goes with it.
///
/// Conservative where the chain can't be followed: a parent that isn't in the file ends the walk
/// without proving anything, so prompts before the walk's earliest record are kept.
public enum LiveBranch {
    /// Is this record one of your prompts (a turn's start)?
    public static func isPrompt(_ r: [String: Any]) -> Bool {
        guard r["isSidechain"] as? Bool != true else { return false }
        if r["type"] as? String == "attachment" { return MidTurnPrompt.text(r) != nil }
        guard r["type"] as? String == "user", r["isMeta"] as? Bool != true, r["isCompactSummary"] as? Bool != true,
              r["toolUseResult"] == nil else { return false }
        let content = (r["message"] as? [String: Any])?["content"]
        if content is String { return true }
        guard let parts = content as? [[String: Any]] else { return false }
        return !parts.contains { $0["type"] as? String == "tool_result" }
    }

    static func parent(_ r: [String: Any]) -> String? {
        (r["parentUuid"] as? String) ?? (r["logicalParentUuid"] as? String)   // a compaction's boundary has only the logical one
    }

    /// The records of the live branch, in file order.
    public static func filter(_ records: [[String: Any]]) -> [[String: Any]] {
        let dead = deadPrompts(records)
        if dead.isEmpty { return records }
        var out: [[String: Any]] = []
        out.reserveCapacity(records.count)
        var skipping = false
        for (i, r) in records.enumerated() {
            if r["type"] as? String == "user", isPrompt(r) { skipping = dead.contains(i) }
            if !skipping { out.append(r) }
        }
        return out
    }

    /// File indexes of the prompts a rewind removed.
    public static func deadPrompts(_ records: [[String: Any]]) -> Set<Int> {
        var index: [String: Int] = [:]
        index.reserveCapacity(records.count)
        var leaf: Int?
        var anyPrompt = 0
        for (i, r) in records.enumerated() {
            if let u = r["uuid"] as? String { index[u] = i }
            if r["isSidechain"] as? Bool != true, r["uuid"] is String { leaf = i }
            if isPrompt(r) { anyPrompt += 1 }
        }
        guard anyPrompt > 1, var at = leaf else { return [] }
        var chain = Set<Int>([at]), earliest = at, complete = false
        while true {
            guard let p = parent(records[at]) else { complete = records[at]["subtype"] as? String != "compact_boundary"; break }
            guard let next = index[p] else { break }
            if !chain.insert(next).inserted { complete = false; break }
            at = next
            earliest = min(earliest, next)
        }
        var dead = Set<Int>()
        // Only typed prompts decide: a message typed mid-turn hangs off whatever record was last, often off the chain.
        for (i, r) in records.enumerated() where r["type"] as? String == "user" && isPrompt(r) && !chain.contains(i) && r["uuid"] is String {
            if i < earliest && !complete { continue }   // before where the chain breaks: can't tell
            dead.insert(i)
        }
        return dead
    }

    /// Follows a transcript as it grows and says when a typed prompt starts a rewound branch: its parent is
    /// an ancestor of the last live typed prompt (the record before it, or any earlier one; a rewind writes
    /// nothing else). A normal prompt's parent comes after the last prompt, so walking up from that prompt
    /// never meets it. A message typed mid-turn is never counted.
    public struct Tracker: @unchecked Sendable {
        private var parents: [String: String] = [:]
        private var last: String?
        public init(_ records: [[String: Any]] = []) { for r in records { _ = add(r) } }

        /// Takes one more record; true when it is a typed prompt that rewinds.
        @discardableResult public mutating func add(_ r: [String: Any]) -> Bool {
            guard let u = r["uuid"] as? String else { return false }
            let p = LiveBranch.parent(r)
            if let p { parents[u] = p }
            guard r["type"] as? String == "user", LiveBranch.isPrompt(r) else { return false }
            defer { last = u }
            guard let prev = last else { return false }
            guard let p = r["parentUuid"] as? String else { return true }   // a second root
            var at = prev, steps = 0
            while let up = parents[at], steps < 1_000_000 {
                if up == p { return true }
                at = up; steps += 1
            }
            return false
        }
    }
}
