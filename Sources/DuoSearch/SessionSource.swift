import Foundation
import DuoControl

/// Claude Code sessions and memory for search (SRCH L1, L7, FR-7.1.3–7.1.5, FR-7.2).
/// Conversation text only: user prompts and assistant prose, plus the session's title. No tool
/// calls, tool results, thinking or snapshots. Unknown record types are skipped and partial
/// lines tolerated, since the format is internal to Claude Code (FR-7.2.2).
public enum SessionSource {
    public struct Transcript: Sendable, Equatable {
        public var sessionId: String
        public var path: String
        public var cwd: String?
        public var size: Int
        public var modified: Date
    }

    public struct Turn: Sendable, Equatable {
        public var index: Int           // 1-based turn number
        public var text: String         // "You: …\n\nClaude: …"
    }

    /// Top-level transcripts in `~/.claude/projects/*/` (subagent transcripts live deeper and
    /// aren't indexed separately).
    public static func transcripts(in projects: URL) -> [Transcript] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil) else { return [] }
        var out: [Transcript] = []
        for d in dirs {
            guard let files = try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { continue }
            for f in files where f.pathExtension == "jsonl" {
                let v = try? f.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                out.append(Transcript(sessionId: f.deletingPathExtension().lastPathComponent, path: f.path, cwd: nil,
                                      size: v?.fileSize ?? 0, modified: v?.contentModificationDate ?? .distantPast))
            }
        }
        return out
    }

    /// Memory notes: `~/.claude/projects/<dir>/memory/*.md`, attributed through the folder's cwd.
    public static func memoryFiles(in projects: URL) -> [(path: String, bucket: String)] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil) else { return [] }
        return dirs.flatMap { d -> [(String, String)] in
            let mem = d.appending(path: "memory")
            let files = (try? fm.contentsOfDirectory(at: mem, includingPropertiesForKeys: nil)) ?? []
            return files.filter { $0.pathExtension == "md" }.map { ($0.path, d.path) }
        }
    }

    /// Turns, the title (custom → AI → first prompt) and the cwd from one transcript.
    public static func read(_ path: String) -> (turns: [Turn], title: String?, cwd: String?) {
        guard let data = FileManager.default.contents(atPath: path) else { return ([], nil, nil) }
        var turns: [Turn] = []
        var prompt: String?, replies: [String] = []
        var custom: String?, ai: String?, cwd: String?, relocated: String?
        func close() {
            guard let p = prompt else { return }
            let reply = replies.joined(separator: "\n\n")
            turns.append(Turn(index: turns.count + 1, text: "You: \(p)" + (reply.isEmpty ? "" : "\n\nClaude: \(reply)")))
            prompt = nil; replies = []
        }
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let r = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any], let type = r["type"] as? String else { continue }
            if cwd == nil, let c = r["cwd"] as? String { cwd = c }
            switch type {
            case "custom-title": custom = r["customTitle"] as? String ?? custom
            case "ai-title": ai = r["aiTitle"] as? String ?? ai
            case "relocated": relocated = r["relocatedCwd"] as? String ?? relocated
            case "user":
                guard r["isMeta"] as? Bool != true, r["isSidechain"] as? Bool != true, let text = promptText(r) else { continue }
                close()
                prompt = text
            case "assistant":
                guard r["isSidechain"] as? Bool != true, prompt != nil else { continue }
                let parts = (r["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
                let prose = parts.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
                if !prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { replies.append(prose) }
            default: continue
            }
        }
        close()
        let first = turns.first.map { String($0.text.dropFirst(5).prefix(80)) }
        return (turns, custom ?? ai ?? first, relocated ?? cwd)
    }

    /// A real prompt: string content or text parts, not tool results or harness-wrapped commands.
    static func promptText(_ r: [String: Any]) -> String? {
        let content = (r["message"] as? [String: Any])?["content"]
        var text: String?
        if let s = content as? String { text = s }
        else if let parts = content as? [[String: Any]] {
            guard !parts.contains(where: { $0["type"] as? String == "tool_result" }) else { return nil }
            text = parts.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        guard var t = text else { return nil }
        if t.hasPrefix("<local-command") || t.hasPrefix("<command-") || t.hasPrefix("Caveat:") { return nil }
        t = t.replacingOccurrences(of: #"<system-reminder>[\s\S]*?</system-reminder>"#, with: "", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

extension SearchIndex {
    /// Indexes every session (and memory note) Claude Code has on this Mac: attributed to the
    /// project whose folder holds its cwd, else "Unfiled" (FR-7.1.5). Transcripts the retention
    /// sweep removed leave the index (L17). Changed transcripts are re-read whole (FR-7.2.4).
    public func indexSessions(projects: [String: URL], claudeProjects: URL, embedder: Embedder,
                              archived: [(id: String, copy: URL, cwd: String)] = [],
                              pause: () async -> Void = {}) async throws -> IndexStats {
        var stats = IndexStats()
        let roots = projects.map { (name: $0.key, path: $0.value.realPath) }
        func owner(_ cwd: String?) -> String {
            guard let c = cwd.map({ URL(fileURLWithPath: $0).realPath }) else { return Self.unfiled }
            return roots.filter { c == $0.path || c.hasPrefix($0.path + "/") }.max { $0.path.count < $1.path.count }?.name ?? Self.unfiled
        }
        let transcripts = SessionSource.transcripts(in: claudeProjects).sorted { $0.modified > $1.modified }
        let memory = SessionSource.memoryFiles(in: claudeProjects)
        stats.files = transcripts.count + memory.count

        var known: [String: (id: Int, modified: Double, size: Int, project: String)] = [:]
        let q = try db.prepare("SELECT id, path, modified, size, project FROM items WHERE kind IN ('session', 'memory')")
        while try q.step() { known[q.string(1) ?? ""] = (q.int(0), q.double(2), q.int(3), q.string(4) ?? "") }
        let present = Set(transcripts.map { "session:" + $0.path } + memory.map { "memory:" + $0.path } + archived.map { "session:" + $0.copy.path })
        let gone = known.filter { !present.contains($0.key) }
        if !gone.isEmpty {
            try db.transaction { for (_, v) in gone { try db.prepare("DELETE FROM items WHERE id = ?").run([v.id]) } }
            stats.removed = gone.count
        }

        for t in transcripts {
            let key = "session:" + t.path
            let mod = t.modified.timeIntervalSince1970
            if let k = known[key], k.modified == mod, k.size == t.size { continue }
            let (turns, title, cwd) = SessionSource.read(t.path)
            guard !turns.isEmpty else { continue }
            let chunks = turns.flatMap { turn -> [Chunk] in
                let text = Secrets.redact(turn.text)
                let pieces = Chunker.chunks(path: "turn.txt", text: text, tokenizer: embedder.tokenizer)
                return pieces.map { Chunk(text: $0.text, startLine: turn.index, endLine: turn.index) }
            }
            try store(key: key, kind: "session", project: owner(cwd), title: title ?? t.sessionId, modified: mod, size: t.size,
                      chunks: chunks, replacing: known[key]?.id, embedder: embedder, stats: &stats)
            await pause()
        }
        // Sessions Claude's cleanup removed but Duo kept (DL-49): indexed from the archive, marked.
        for a in archived {
            let key = "session:" + a.copy.path
            let v = try? a.copy.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let mod = v?.contentModificationDate?.timeIntervalSince1970 ?? 0
            if let k = known[key], k.modified == mod, k.size == (v?.fileSize ?? 0) { continue }
            let (turns, title, _) = SessionSource.read(a.copy.path)
            guard !turns.isEmpty else { continue }
            let chunks = turns.flatMap { turn -> [Chunk] in
                Chunker.chunks(path: "turn.txt", text: Secrets.redact(turn.text), tokenizer: embedder.tokenizer)
                    .map { Chunk(text: $0.text, startLine: turn.index, endLine: turn.index) }
            }
            try store(key: key, kind: "session", project: owner(a.cwd), title: title ?? a.id, modified: mod, size: v?.fileSize ?? 0,
                      chunks: chunks, replacing: known[key]?.id, embedder: embedder, stats: &stats)
            try db.prepare("UPDATE items SET archived = 1 WHERE path = ?").run([key])
        }
        for m in memory {
            let key = "memory:" + m.path
            let v = try? URL(fileURLWithPath: m.path).resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mod = v?.contentModificationDate?.timeIntervalSince1970 ?? 0
            if let k = known[key], k.modified == mod, k.size == (v?.fileSize ?? 0) { continue }
            guard let raw = FileSource.read(m.path) else { continue }
            // The bucket folder's sessions tell us its cwd.
            let cwd = transcripts.first { $0.path.hasPrefix(m.bucket + "/") }.flatMap { SessionSource.read($0.path).cwd }
            let chunks = Chunker.chunks(path: m.path, text: Secrets.redact(raw), tokenizer: embedder.tokenizer)
            try store(key: key, kind: "memory", project: owner(cwd), title: "Memory: " + (m.path as NSString).lastPathComponent,
                      modified: mod, size: v?.fileSize ?? 0, chunks: chunks, replacing: known[key]?.id, embedder: embedder, stats: &stats)
        }
        return stats
    }

    public static let unfiled = "Unfiled"

    /// Writes one item's chunks, embedding only passages the index hasn't seen.
    func store(key: String, kind: String, project: String, title: String, modified: Double, size: Int,
               chunks: [Chunk], replacing: Int?, embedder: Embedder, stats: inout IndexStats) throws {
        let hashes = chunks.map { Self.hash($0.text) }
        var ids: [String: Int] = [:]
        let look = try db.prepare("SELECT id FROM content WHERE hash = ?")
        for h in Set(hashes) { look.bind([h]); if try look.step() { ids[h] = look.int(0) } }
        let missing = Array(Set(hashes).subtracting(ids.keys))
        let vectors = try embedder.embedDocuments(missing.map { h in chunks[hashes.firstIndex(of: h)!].text })
        stats.embedded += missing.count
        stats.reused += Set(hashes).count - missing.count
        try db.transaction {
            let ins = try db.prepare("INSERT OR IGNORE INTO content(hash, vector) VALUES (?, ?)")
            for (h, v) in zip(missing, vectors) {
                try ins.run([h, Self.blob(v)])
                look.bind([h]); if try look.step() { ids[h] = look.int(0) }
            }
            if let replacing { try db.prepare("DELETE FROM items WHERE id = ?").run([replacing]) }
            try db.prepare("INSERT INTO items(kind, project, path, title, modified, size, indexed) VALUES (?, ?, ?, ?, ?, ?, ?)")
                .run([kind, project, key, title, modified, size, Date().timeIntervalSince1970])
            let item = db.lastRowID
            let c = try db.prepare("INSERT INTO chunks(item, content, start, end, text) VALUES (?, ?, ?, ?, ?)")
            for (chunk, h) in zip(chunks, hashes) { try c.run([item, ids[h] ?? 0, chunk.startLine, chunk.endLine, chunk.text]) }
        }
        stats.changed += 1
        stats.chunks += chunks.count
    }
}
