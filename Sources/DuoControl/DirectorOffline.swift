import Foundation

/// What a director needs to work with Duo closed (DL-231): Claude's own beacons say which workers run
/// and what they're doing, `.duo/director.json` says whose they are, and the task notes are plain
/// files. Foundation only, so `duo2` and the checks share it; the app's own versions (DuoKit) read
/// the same files and say the same words.
public enum DirectorOffline {
    /// A Claude process running now, from its beacon (`<config>/sessions/<pid>.json`).
    public struct LiveSession: Equatable, Sendable {
        public var sessionId: String
        public var pid: Int32
        public var cwd: String
        public var name: String?
        /// `busy`, `idle` or `waiting`.
        public var status: String
        /// What a `waiting` session waits for ("input needed", "permission prompt").
        public var waitingFor: String?
        /// The name a SendMessage goes to: the session's name, when it has messaging.
        public var peerName: String?
        public init(sessionId: String, pid: Int32, cwd: String, name: String?, status: String, waitingFor: String? = nil, peerName: String? = nil) {
            self.sessionId = sessionId; self.pid = pid; self.cwd = cwd; self.name = name; self.status = status; self.waitingFor = waitingFor; self.peerName = peerName
        }
    }

    /// Every beacon whose process is alive (`kill(pid, 0)`).
    public static func beacons(claudeDir: URL = LegacyDuo.claudeDir) -> [LiveSession] {
        let files = (try? FileManager.default.contentsOfDirectory(at: claudeDir.appending(path: "sessions"), includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }.compactMap { url in
            guard let j = ClientCaps.json(url), let pid = j["pid"] as? Int, pid > 0, kill(pid_t(pid), 0) == 0, let id = j["sessionId"] as? String else { return nil }
            let name = j["name"] as? String
            let peer = ((j["peerFeatures"] as? [String]) ?? []).isEmpty ? nil : name
            return LiveSession(sessionId: id, pid: Int32(pid), cwd: (j["cwd"] as? String) ?? "", name: name,
                               status: (j["status"] as? String) ?? "idle", waitingFor: j["waitingFor"] as? String, peerName: peer)
        }
    }

    /// Links pending background workers whose name has appeared (as the app does at each refresh).
    /// The workers it linked.
    public static func linkPending(_ reg: inout DirectorRegistry, beacons: [LiveSession]) -> [DirectorRegistry.Worker] {
        guard reg.workers.contains(where: \.pending) else { return [] }
        var linked: [DirectorRegistry.Worker] = []
        for b in beacons { if let n = b.name, let w = reg.link(pendingNamed: n, to: b.sessionId) { linked.append(w) } }
        return linked
    }

    /// A session's transcript: the first `<config>/projects/*/<id>.jsonl`.
    public static func transcript(sessionId: String, claudeDir: URL = LegacyDuo.claudeDir) -> URL? {
        guard !sessionId.isEmpty, !sessionId.contains("/") else { return nil }
        let fm = FileManager.default
        let dirs = ((try? fm.contentsOfDirectory(at: claudeDir.appending(path: "projects"), includingPropertiesForKeys: nil)) ?? []).sorted { $0.path < $1.path }
        return dirs.map { $0.appending(path: sessionId + ".jsonl") }.first { fm.fileExists(atPath: $0.path) }
    }

    /// The full id a prefix of one names (what `status` prints is the first 8): a live session, else a transcript.
    public static func fullId(_ given: String, beacons: [LiveSession], claudeDir: URL = LegacyDuo.claudeDir) -> String? {
        if given.count >= 36 { return given }
        if let b = beacons.first(where: { $0.sessionId.hasPrefix(given) }) { return b.sessionId }
        let fm = FileManager.default
        for d in ((try? fm.contentsOfDirectory(at: claudeDir.appending(path: "projects"), includingPropertiesForKeys: nil)) ?? []).sorted(by: { $0.path < $1.path }) {
            if let f = ((try? fm.contentsOfDirectory(atPath: d.path)) ?? []).sorted().first(where: { $0.hasPrefix(given) && $0.hasSuffix(".jsonl") }) { return String(f.dropLast(6)) }
        }
        return nil
    }

    /// The folder a transcript was started in (its first `cwd`), from its first 64 KB.
    public static func filedCwd(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let head = (try? h.read(upToCount: 64 * 1024)) ?? Data()
        for line in String(decoding: head, as: UTF8.self).split(separator: "\n") where line.contains("\"cwd\"") {
            if let cwd = ((try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any])?["cwd"] as? String { return cwd }
        }
        return nil
    }

    /// When the user took the worker over (DL-200): their turn in its transcript after the director's
    /// last message and after they last handed it back. Nil when the director may send.
    public static func userTurn(sessionId: String, director: String, reg: DirectorRegistry, claudeDir: URL = LegacyDuo.claudeDir) -> Date? {
        guard !sessionId.isEmpty, let t = transcript(sessionId: sessionId, claudeDir: claudeDir),
              let typed = DirectorTranscript.userTurnSinceDirector(t, tag: Director.tag(director)) else { return nil }
        if let back = reg.handedBack[sessionId].flatMap({ ISO8601DateFormatter().date(from: $0) }), typed <= back { return nil }
        return typed
    }

    /// One task this director directs, with its worker as `status` and `watch` show it.
    public struct Task: Equatable, Sendable {
        public var path: String
        public var title: String
        public var status: String?
        public var noteModified: Double
        /// The worker's session id once it's linked, and the name it was started under.
        public var session: String?
        public var workerName: String?
        /// Always `background` here: with Duo closed, nothing else can be running.
        public var place: String
        /// `starting`, `working`, `idle`, `needs-you`, `stopped` or `no worker`: the app's words.
        public var state: String
        /// A background worker that hasn't appeared yet: the name it will.
        public var pendingName: String?
        public var peerName: String?
        /// The worker's permission class, from its transcript (F-421).
        public var permissionClass: PermissionClass?
        public var question: String?
        public var userTyping: Bool
        public var userTurnAt: Date?
        /// Running: unfinished, and its worker runs or is still starting.
        public var running: Bool
    }

    /// Every task note whose `directed_by:` is `director`, not archived, with its worker's state
    /// read from the registry, the beacons and the worker's transcript.
    public static func tasks(project: URL, director: String, reg: DirectorRegistry, beacons: [LiveSession],
                             claudeDir: URL = LegacyDuo.claudeDir, now: Date = Date()) -> [Task] {
        let files = (try? FileManager.default.contentsOfDirectory(at: project.appending(path: "tasks"), includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let iso = ISO8601DateFormatter()
        return files.filter { $0.pathExtension.lowercased() == "md" }.sorted { $0.path < $1.path }.compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8), Director.frontmatter("directed_by", in: text) == director,
                  Director.frontmatter("archived", in: text)?.lowercased() != "true" else { return nil }
            let path = "tasks/" + url.lastPathComponent
            let status = Director.frontmatter("status", in: text)
            let mod = ((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast).timeIntervalSince1970
            var t = Task(path: path, title: title(of: text, stem: url.deletingPathExtension().lastPathComponent), status: status, noteModified: mod,
                         session: nil, workerName: nil, place: "background", state: "no worker", pendingName: nil, peerName: nil, permissionClass: nil, question: nil,
                         userTyping: false, userTurnAt: nil, running: false)
            let unfinished = Director.unfinished(status: status, archived: false)
            guard let w = reg.worker(task: path) else { return t }
            t.workerName = w.name
            if w.pending {
                if let since = iso.date(from: w.since), now.timeIntervalSince(since) <= pendingLasts {
                    t.state = "starting"; t.pendingName = w.name; t.running = unfinished
                }
                return t
            }
            t.session = w.session
            if let b = beacons.first(where: { $0.sessionId == w.session }) {
                t.state = b.status == "busy" ? "working" : b.status == "waiting" ? "needs-you" : "idle"
                t.peerName = b.peerName
                if b.status == "waiting" { t.question = b.waitingFor }
                t.running = unfinished
            } else {
                t.state = "stopped"
            }
            t.permissionClass = transcript(sessionId: w.session, claudeDir: claudeDir).flatMap { PermissionClass.latestMode(inTranscript: $0) }.flatMap { PermissionClass.of(mode: $0) }
            t.userTurnAt = userTurn(sessionId: w.session, director: director, reg: reg, claudeDir: claudeDir)
            t.userTyping = t.userTurnAt != nil
            return t
        }
    }

    static var pendingLasts: TimeInterval { Director.pendingLasts }

    /// A note's title: its `title:`, else its first `# ` heading, else its file name.
    public static func title(of text: String, stem: String) -> String {
        if let t = Director.frontmatter("title", in: text) { return t }
        var lines = text.components(separatedBy: "\n")
        if lines.first == "---", let close = lines.dropFirst().firstIndex(of: "---") { lines = Array(lines[(close + 1)...]) }
        if let h = lines.first(where: { $0.hasPrefix("# ") }) {
            let t = h.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t }
        }
        return stem
    }

    // MARK: Note edits

    /// The note with `- yyyy-MM-dd HH:mm <line>` after the last non-blank line of its `## Progress`
    /// (or the section added at the end): the same text the app's `DirectorNotes` writes.
    public static func appendProgress(_ text: String, _ line: String, now: Date = Date()) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.locale = Locale(identifier: "en_US_POSIX")
        let one = line.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return appending("- \(f.string(from: now)) \(one)", toSection: "Progress", in: text)
    }

    static func appending(_ line: String, toSection section: String, in text: String) -> String {
        let nl = text.contains("\r\n") ? "\r\n" : "\n"
        var lines = text.components(separatedBy: nl)
        let head = "## " + section.lowercased()
        var bodyStart = 0
        if lines.first == "---", let close = lines.dropFirst().firstIndex(of: "---") { bodyStart = close + 1 }
        guard let h = lines[bodyStart...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).lowercased() == head }) else {
            while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
            lines += ["", "## " + section, "", line, ""]
            return lines.joined(separator: nl)
        }
        let end = lines[(h + 1)...].firstIndex { $0.hasPrefix("# ") || $0.hasPrefix("## ") } ?? lines.endIndex
        var at = end
        while at > h + 1, lines[at - 1].trimmingCharacters(in: .whitespaces).isEmpty { at -= 1 }
        if at == h + 1 { lines.insert(contentsOf: ["", line], at: at) } else { lines.insert(line, at: at) }
        return lines.joined(separator: nl)
    }

    /// The note with one scalar frontmatter key set, touching nothing else (a frontmatter is added if missing).
    public static func setting(_ key: String, _ value: String, in text: String) -> String {
        let nl = text.contains("\r\n") ? "\r\n" : "\n"
        var lines = text.components(separatedBy: nl)
        guard lines.first == "---", let close = lines.dropFirst().firstIndex(of: "---") else {
            return (["---", "\(key): \(value)", "---"] + lines).joined(separator: nl)
        }
        if let i = lines[1..<close].firstIndex(where: { $0.hasPrefix(key + ":") }) { lines[i] = "\(key): \(value)" } else { lines.insert("\(key): \(value)", at: close) }
        return lines.joined(separator: nl)
    }

    public static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: Transcripts and runs

    /// The text of the last assistant message in a Claude transcript (its text blocks, joined), or
    /// nil. Reads from the end, widening the window until one is found: transcripts run to megabytes.
    public static func lastAssistantText(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        var window: UInt64 = 256 * 1024
        while true {
            let from = size > window ? size - window : 0
            try? h.seek(toOffset: from)
            guard let data = try? h.readToEnd() else { return nil }
            var lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true)
            if from > 0, !lines.isEmpty { lines.removeFirst() }   // a partial line
            if let t = lastAssistantText(lines) { return t }
            if from == 0 || window >= 256 * 1024 * 1024 { return nil }
            window *= 4
        }
    }

    static func lastAssistantText(_ lines: [Substring]) -> String? {
        func entry(_ l: Substring) -> (id: String?, text: String)? {
            guard l.contains("\"assistant\""), let e = (try? JSONSerialization.jsonObject(with: Data(l.utf8))) as? [String: Any],
                  e["type"] as? String == "assistant", let m = e["message"] as? [String: Any] else { return nil }
            let text: String
            if let s = m["content"] as? String { text = s }
            else { text = ((m["content"] as? [[String: Any]]) ?? []).filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n") }
            return (m["id"] as? String, text)
        }
        var i = lines.count - 1
        while i >= 0 {
            // A message's blocks are separate lines sharing an id: gather the ones before it too.
            if let e = entry(lines[i]), !e.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                var parts = [e.text]
                var j = i - 1
                while j >= 0, let p = entry(lines[j]), e.id != nil, p.id == e.id { if !p.text.isEmpty { parts.insert(p.text, at: 0) }; j -= 1 }
                return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            i -= 1
        }
        return nil
    }

    /// The environment a `claude` run for a director gets: not Duo's, and not the calling session's.
    public static func runEnvironment(_ env: [String: String]) -> [String: String] {
        env.filter { !($0.key.hasPrefix("DUO_") || $0.key == "CLAUDECODE" || $0.key.hasPrefix("CLAUDE_CODE_SESSION")) }
    }

    /// Keeps the newest few run logs per worker in `.duo/director-runs/` (named `<id8>-<time>.log`):
    /// `kept - 1` besides the one about to be written.
    public static func pruneRuns(beside log: URL, kept: Int = 5) {
        let dir = log.deletingLastPathComponent(), prefix = String(log.lastPathComponent.prefix(9))
        let fm = FileManager.default
        let mine = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix(prefix) && $0.hasSuffix(".log") }.sorted()
        for old in mine.dropLast(kept - 1) { try? fm.removeItem(at: dir.appending(path: old)) }
    }
}
