import Foundation

/// Counts of work that idle Duo must not repeat needlessly (F-600). Cheap (one locked increment), always on, read by the
/// perf regression checks (`DUO_CHECKS=perf`) so a change that reintroduces a scan per session fails a check, not a
/// field report weeks later.
public enum Work {
    public enum Kind: String, CaseIterable, Sendable {
        /// `ClaudeStorage.transcript` fell back to listing every bucket (a miss by path).
        case bucketScan
        /// `ClaudeStorage.stampOrStat` had no listing stamp and stat'ed the file.
        case statFallback
        /// The archive manifest was decoded (not served from the cache).
        case manifestDecode
        /// `TerminalMicView.tick` read a terminal's screen (not skipped as unchanged).
        case micScreenRead
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var counts: [Kind: Int] = [:]
    public static func count(_ k: Kind, by n: Int = 1) { lock.lock(); counts[k, default: 0] += n; lock.unlock() }
    public static func value(_ k: Kind) -> Int { lock.lock(); defer { lock.unlock() }; return counts[k, default: 0] }
    /// The counts from here on.
    public static func reset() { lock.lock(); counts = [:]; lock.unlock() }
}
