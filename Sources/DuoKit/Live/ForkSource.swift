import Foundation

/// Which kind of fork a session start is, and where the fork's parent is written (DL-227, F-344).
/// - `/branch` switches the same TUI process to a new id: SessionStart `source: "fork"`, same pid, and the
///   new transcript's records carry `forkedFrom: {sessionId, messageUuid}`.
/// - `/fork` copies the conversation into a background session in Claude's daemon: SessionStart
///   `source: "fork"` from a daemon pid, and `‹config›/jobs/‹short›/state.json` holds `forkParentSessionId`.
/// - `/clear` and `/resume` keep today's behaviour (re-key, `continued-from`).
public enum ForkSource {
    public enum Kind: String, Sendable, Equatable { case branch, fork }

    /// What a SessionStart means for the terminal that hosts `pid`'s process tree.
    /// `ownsPid`: the pid is, or descends from, one of Duo's terminals. `parentIsDuoTab`: the job's
    /// `forkParentSessionId` is one of Duo's open tabs.
    public static func classify(source: String?, ownsPid: Bool, parentIsDuoTab: Bool) -> Kind? {
        guard source == "fork" else { return nil }
        if ownsPid { return .branch }
        return parentIsDuoTab ? .fork : nil
    }

    /// One background job's fork facts, from `‹config›/jobs/‹short›/state.json`.
    public struct Job: Sendable, Equatable {
        /// The job's folder name: what `claude attach` takes.
        public var short: String
        public var parent: String
        /// The forked session's id, when the job names it.
        public var sessionId: String?
        /// "send a prompt to start": the fork is waiting for its first prompt.
        public var needs: String?

        public init(short: String, parent: String, sessionId: String?, needs: String? = nil) {
            self.short = short; self.parent = parent; self.sessionId = sessionId; self.needs = needs
        }
    }

    /// Verdicts already reached, by job folder: a fork's parent and ids are written when the job starts and don't change, and
    /// a job that isn't a fork and hasn't changed for two minutes isn't going to be one. Claude's `jobs` folder holds hundreds
    /// of finished jobs, and this is read on every 2 s refresh. (`needs` is as it was when the verdict was reached.)
    private final class Settled: @unchecked Sendable {
        let lock = NSLock()
        var verdicts: [String: Job?] = [:]
    }
    private static let settled = Settled()

    /// Every job that is a fork, read from Claude's `jobs` folder. A job without `forkParentSessionId` isn't one.
    public static func jobs(in root: URL = ClaudeStorage.root) -> [Job] {
        let dir = root.appending(path: "jobs")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.sorted().compactMap { short in
            let cacheKey = dir.path + "/" + short
            settled.lock.lock(); let known = settled.verdicts[cacheKey]; settled.lock.unlock()
            if let known { return known }
            let file = dir.appending(path: short).appending(path: "state.json")
            guard let data = try? Data(contentsOf: file) else { return nil }
            var job: Job?
            if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let parent = json["forkParentSessionId"] as? String, !parent.isEmpty {
                job = Job(short: short, parent: parent, sessionId: (json["forkSessionId"] as? String) ?? (json["sessionId"] as? String),
                          needs: json["needs"] as? String)
            }
            let age = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { -$0.timeIntervalSinceNow } ?? 0
            if job?.sessionId != nil || (job == nil && age > 120) {
                settled.lock.lock(); settled.verdicts[cacheKey] = .some(job); settled.lock.unlock()
            }
            return job
        }
    }

    /// The parent a transcript's records name (`/branch`), from the head of its text.
    public static func forkedFrom(records: [[String: Any]]) -> String? {
        for r in records {
            if let f = r["forkedFrom"] as? [String: Any], let id = f["sessionId"] as? String, !id.isEmpty { return id }
        }
        return nil
    }
}

/// Where a new tab goes in a strip (DL-228): right after the tab it came from, wherever that is.
public enum ForkPlacement {
    /// `order` with `key` right after `after`; at the end when `after` isn't in it. `key` is moved if already there.
    public static func inserting(_ key: String, after: String, in order: [String]) -> [String] {
        var out = order.filter { $0 != key }
        if let i = out.firstIndex(of: after) { out.insert(key, at: i + 1) } else { out.append(key) }
        return out
    }
}

/// A thread's members in the order the pane lists them (DL-228): the original first, then its forks.
public enum ForkThread {
    /// `members` as `(key, parent)` in age order (oldest first); the original is the one without a parent
    /// among them. A fork of a fork lines up under the same rule, by age: one list, not a tree.
    public static func ordered(_ members: [(key: String, parent: String?)]) -> [String] {
        let keys = Set(members.map(\.key))
        let roots = members.filter { $0.parent.map { !keys.contains($0) } ?? true }.map(\.key)
        let rest = members.map(\.key).filter { !roots.contains($0) }
        return roots.prefix(1) + rest + roots.dropFirst()
    }
}
