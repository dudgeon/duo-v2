import Foundation

/// The backbook, read only (CONS §7.1 inventory, §7.8 repair findings, §7.10 junk-drawer evidence;
/// DL-41: deterministic facts, no proposals). Nothing here moves, writes or deletes anything.
public enum Inventory {
    public struct Bucket: Sendable, Equatable {
        public var folder: String            // the encoded directory under ~/.claude/projects
        public var cwds: [String]            // distinct working directories its sessions record
        public var sessions: Int
        public var bytes: Int64
        public var newest: Date?
        public var cwdMissing: Bool          // every recorded cwd is gone (an orphan bucket)
        public var collision: Bool { cwds.count > 1 }   // FR-7.8.2
        public var sweepSoon: Int            // sessions Claude's cleanup takes within 7 days
        public var archivedByDuo: Int        // of those, how many Duo's archive already holds
        public var junkDrawer: Bool          // a home or catch-all folder (FR-7.2.8)
    }

    public struct Report: Sendable {
        public var buckets: [Bucket]
        public var duplicates: [String: [String]]   // session id → the buckets holding it (FR-7.8.1)
        public var periodDays: Int
    }

    /// Every bucket in Claude's storage, with what's worth knowing about it.
    public static func build(claudeDir: URL = ClaudeStorage.root, now: Date = Date(), periodDays: Int? = nil) -> Report {
        let fm = FileManager.default
        let period = periodDays ?? SessionArchive.cleanupPeriodDays(claudeDir: claudeDir) ?? 30
        let soon = now.addingTimeInterval(-TimeInterval(max(0, period - 7)) * 86_400)
        let archived = Set(SessionArchive.manifest().sessions.keys)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let projects = claudeDir.appending(path: "projects")
        var buckets: [Bucket] = []
        var where_: [String: [String]] = [:]
        for dir in (try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? [] {
            let files = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? [])
                .filter { $0.pathExtension == "jsonl" }
            guard !files.isEmpty else { continue }
            var cwds: [String] = []
            var bytes: Int64 = 0
            var newest: Date?
            var sweep = 0, held = 0
            for f in files {
                let id = f.deletingPathExtension().lastPathComponent
                where_[id, default: []].append(dir.lastPathComponent)
                let v = try? f.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                bytes += Int64(v?.fileSize ?? 0)
                if let m = v?.contentModificationDate {
                    newest = max(newest ?? m, m)
                    if m < soon { sweep += 1; if archived.contains(id) { held += 1 } }
                }
                if let c = ClaudeStorage.filedCwd(f), !cwds.contains(c) { cwds.append(c) }
            }
            let missing = !cwds.isEmpty && cwds.allSatisfy { !fm.fileExists(atPath: $0) }
            buckets.append(Bucket(folder: dir.lastPathComponent, cwds: cwds, sessions: files.count, bytes: bytes, newest: newest,
                                  cwdMissing: missing, sweepSoon: sweep, archivedByDuo: held,
                                  junkDrawer: cwds.contains { $0 == home || $0 == "/" || $0 == home + "/Desktop" || $0 == home + "/Documents" }))
        }
        return Report(buckets: buckets.sorted { ($0.newest ?? .distantPast) > ($1.newest ?? .distantPast) },
                      duplicates: where_.filter { $0.value.count > 1 }, periodDays: period)
    }

    // MARK: Junk-drawer evidence (FR-7.10.2 to 7.10.4)

    public struct Evidence: Sendable, Equatable {
        public var sessionId: String
        public var title: String?
        public var first: Date?
        public var last: Date?
        public var edited: [String]          // files the session edited, deduplicated, in order
        public var candidateHome: String?    // the deepest folder holding every edited file
        public var partial: Bool             // the transcript was larger than the cap

        public init(sessionId: String, title: String?, first: Date?, last: Date?, edited: [String], candidateHome: String?, partial: Bool) {
            self.sessionId = sessionId; self.title = title; self.first = first; self.last = last
            self.edited = edited; self.candidateHome = candidateHome; self.partial = partial
        }
    }

    /// Files a session edited, from its transcript: file-history records, the editing tools'
    /// inputs, and their results. Reads and shell commands don't count (too noisy).
    public static func evidence(_ transcript: URL, cwd: String?, cap: Int = 64 << 20) -> Evidence {
        let id = transcript.deletingPathExtension().lastPathComponent
        var e = Evidence(sessionId: id, title: nil, first: nil, last: nil, edited: [], candidateHome: nil, partial: false)
        guard let fh = try? FileHandle(forReadingFrom: transcript) else { return e }
        defer { try? fh.close() }
        let data = (try? fh.read(upToCount: cap)) ?? Data()
        e.partial = data.count >= cap
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func add(_ p: String?) {
            guard let p, p.hasPrefix("/") || p.hasPrefix("~") else {
                if let p, let cwd, !p.isEmpty { add((cwd as NSString).appendingPathComponent(p)) }
                return
            }
            let full = (p as NSString).expandingTildeInPath
            if !e.edited.contains(full) { e.edited.append(full) }
        }
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let r = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            if let t = (r["timestamp"] as? String).flatMap({ iso.date(from: $0) }) { e.first = e.first ?? t; e.last = t }
            switch r["type"] as? String {
            case "file-history-snapshot", "file-history-delta":
                for key in ["trackingPath", "realParentDir"] { add(r[key] as? String) }
                if let snap = r["snapshot"] as? [String: Any], let backups = snap["trackedFileBackups"] as? [String: Any] { backups.keys.forEach { add($0) } }
            case "assistant":
                let content = (r["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
                for c in content where c["type"] as? String == "tool_use" && ["Edit", "MultiEdit", "Write", "NotebookEdit"].contains(c["name"] as? String ?? "") {
                    let input = c["input"] as? [String: Any] ?? [:]
                    for key in ["file_path", "notebook_path", "path"] { add(input[key] as? String) }
                }
            case "user":
                if let res = r["toolUseResult"] as? [String: Any], res["type"] as? String != "text" { add(res["filePath"] as? String) }
            case "custom-title", "summary": e.title = e.title ?? (r["customTitle"] as? String ?? r["summary"] as? String)
            default: break
            }
        }
        e.candidateHome = candidateHome(e.edited, cwd: cwd)
        return e
    }

    /// The deepest folder that holds every edited file, ignoring system and temp paths and
    /// ~/.claude. Nil when nothing was edited, or when that folder is the session's own cwd or above.
    public static func candidateHome(_ files: [String], cwd: String?) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let kept = files.filter { f in
            !["/tmp/", "/private/", "/var/", "/System/", "/usr/", "/opt/", "/Library/", home + "/.claude/", home + "/Library/"].contains { f.hasPrefix($0) }
        }
        guard let first = kept.first else { return nil }
        var common = (first as NSString).deletingLastPathComponent.split(separator: "/").map(String.init)
        for f in kept.dropFirst() {
            let parts = (f as NSString).deletingLastPathComponent.split(separator: "/").map(String.init)
            common = Array(zip(common, parts).prefix { $0 == $1 }.map(\.0))
        }
        let dir = "/" + common.joined(separator: "/")
        if let cwd, dir == cwd || cwd.hasPrefix(dir + "/") || dir == "/" || dir == home { return nil }
        return dir
    }

    /// Sessions grouped by activity gaps: within `gap` of each other, one cluster (FR-7.10.4).
    public static func clusters(_ items: [Evidence], gap: TimeInterval = 48 * 3600) -> [[Evidence]] {
        let dated = items.filter { $0.first != nil }.sorted { $0.first! < $1.first! }
        var out: [[Evidence]] = []
        for e in dated {
            if let lastEnd = out.last?.compactMap({ $0.last ?? $0.first }).max(), e.first!.timeIntervalSince(lastEnd) <= gap {
                out[out.count - 1].append(e)
            } else { out.append([e]) }
        }
        return out
    }
}
