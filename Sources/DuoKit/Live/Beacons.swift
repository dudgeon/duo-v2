import Foundation

/// Live Claude Code sessions from their beacons, `~/.claude/sessions/<pid>.json` (findings F-23).
/// Same data as `claude agents --json`, read as files: no process to spawn, cheap to poll.
public struct Beacon: Sendable, Equatable, Decodable {
    public var pid: Int32
    public var sessionId: String
    public var cwd: String
    public var name: String?
    /// `user` when named with /rename (stable); `derived` names change per process (F-26).
    public var nameSource: String?
    public var status: String          // busy | idle | waiting
    public var waitingFor: String?     // "input needed" | "permission prompt"
    public var statusUpdatedAt: Double?
    public var entrypoint: String?
    public var kind: String?

    public init(pid: Int32, sessionId: String, cwd: String, name: String?, status: String, waitingFor: String?,
                statusUpdatedAt: Double?, entrypoint: String?, kind: String?, nameSource: String? = nil) {
        self.pid = pid; self.sessionId = sessionId; self.cwd = cwd; self.name = name; self.status = status
        self.waitingFor = waitingFor; self.statusUpdatedAt = statusUpdatedAt; self.entrypoint = entrypoint; self.kind = kind
        self.nameSource = nameSource
    }

    /// Reads every beacon whose process is still alive.
    public static func readAll(in dir: URL = ClaudeStorage.sessions) -> [Beacon] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let b = try? JSONDecoder().decode(Beacon.self, from: data),
                  kill(b.pid, 0) == 0 else { return nil }
            return b
        }
    }
}

/// Maps Claude's signals to the five attention states (handoff §2.2, LR-1–LR-3).
public enum Attention {
    public enum Reason: String, Sendable { case permission, question, plan, blocked }

    /// The state for a live session. `lastStop` is the last `Stop` hook's message, if any; a turn
    /// that ends by asking something needs you even though Claude reports `idle` (F-23).
    public static func state(for beacon: Beacon, lastStopMessage: String? = nil) -> (SessionState, Reason?) {
        switch beacon.status {
        case "waiting":
            return (.needsYou, beacon.waitingFor == "permission prompt" ? .permission : .question)
        case "busy":
            return (.working, nil)
        default:
            if let m = lastStopMessage?.trimmingCharacters(in: .whitespacesAndNewlines), m.hasSuffix("?") {
                return (.needsYou, .question)
            }
            return (.idle, nil)
        }
    }

    /// `now`, `4m`, `1h`, `3d` (handoff §8) from a millisecond timestamp.
    public static func waitText(since ms: Double?, now: Date = Date()) -> String? {
        guard let ms else { return nil }
        let s = max(0, Int(now.timeIntervalSince1970 - ms / 1000))
        switch s {
        case ..<60: return "now"
        case ..<3600: return "\(s / 60)m"
        case ..<86400: return "\(s / 3600)h"
        default: return "\(s / 86400)d"
        }
    }
}
