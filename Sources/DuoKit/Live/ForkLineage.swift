import Foundation

/// Fork lineage for threads (handoff §11, spike S11, findings F-31). Claude writes no "forked
/// from" field: `--fork-session` (and the TUI's fork) copies the parent's records into the new
/// transcript with the same message `uuid`s and timestamps, rewriting only `sessionId`. So:
/// - sessions whose first user message has the same `uuid` are one thread (a head read);
/// - a fork's first new record has a `parentUuid` from the copied part: the fork point;
/// - copies keep the source's timestamps, but a transcript's first record of any kind (a queue
///   or mode record) carries the session's own start, so the parent is the latest-started
///   session that holds the fork point and started before the fork.
public enum ForkLineage {
    public struct Info: Sendable, Equatable {
        public var sessionId: String
        /// The first user message's uuid: equal across a thread.
        public var root: String?
        /// Where this session left its parent, if it is a fork.
        public var forkPoint: String?
        /// When the session's own first record was written.
        public var started: String?
        public var uuids: Set<String>
    }

    /// One transcript's lineage facts, from its parsed records.
    public static func info(sessionId: String, records: [[String: Any]]) -> Info {
        let msgs = records.filter { $0["uuid"] is String }
        let root = msgs.first { $0["type"] as? String == "user" }?["uuid"] as? String
        return Info(sessionId: sessionId, root: root, forkPoint: nil,
                    started: records.lazy.compactMap { $0["timestamp"] as? String }.first,
                    uuids: Set(msgs.compactMap { $0["uuid"] as? String }))
    }

    /// Parent of each session within one thread (sessions sharing a root), by session id.
    public static func parents(_ sessions: [Info], records: [String: [[String: Any]]]) -> [String: String] {
        var out: [String: String] = [:]
        let byStart = sessions.sorted { ($0.started ?? "") < ($1.started ?? "") }
        for s in byStart {
            // Copies only flow forward in time: what this session holds that no earlier session
            // does is its own, and its first own record's parentUuid is the fork point.
            let others = byStart.filter { $0.sessionId != s.sessionId && ($0.started ?? "") <= (s.started ?? "") }
            let known = others.reduce(into: Set<String>()) { $0.formUnion($1.uuids) }
            guard let recs = records[s.sessionId],
                  let firstOwn = recs.first(where: { ($0["uuid"] as? String).map { !known.contains($0) } ?? false }),
                  let point = firstOwn["parentUuid"] as? String, known.contains(point) else { continue }
            let forkedAt = firstOwn["timestamp"] as? String ?? "~"
            if let parent = others.filter({ $0.uuids.contains(point) && ($0.started ?? "") <= forkedAt })
                .max(by: { ($0.started ?? "") < ($1.started ?? "") }) {
                out[s.sessionId] = parent.sessionId
            }
        }
        return out
    }
}
