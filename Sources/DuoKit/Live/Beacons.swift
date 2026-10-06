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

    /// Reads every beacon whose process is still running: one that's exiting or a zombie has ended,
    /// though `kill -0` still reaches it (C-30, F-126).
    public static func readAll(in dir: URL = ClaudeStorage.sessions) -> [Beacon] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let b = try? JSONDecoder().decode(Beacon.self, from: data),
                  ProcessLiveness.isRunning(b.pid) else { return nil }
            return b
        }
    }
}

/// Whether a process is still running. `kill(pid, 0)` also succeeds for one that is exiting (state
/// `E`: a Claude whose last output its terminal never read waits there, F-126) or a zombie
/// nobody has reaped; both have ended as far as Duo cares.
public enum ProcessLiveness {
    public static func isRunning(_ pid: Int32) -> Bool {
        guard pid > 0, kill(pid, 0) == 0 else { return false }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return true }  // can't tell: as kill says
        return !isEnded(stat: info.kp_proc.p_stat, flag: info.kp_proc.p_flag)
    }

    /// A zombie, or past `exit` (P_WEXIT).
    public static func isEnded(stat: CChar, flag: Int32) -> Bool { Int32(stat) == SZOMB || flag & P_WEXIT != 0 }

    /// The parent of a process; 0 when it can't be read.
    public static func parent(_ pid: Int32) -> Int32 {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return 0 }
        return info.kp_eproc.e_ppid
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
