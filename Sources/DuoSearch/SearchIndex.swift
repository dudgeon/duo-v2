import Accelerate
import CryptoKit
import Foundation

/// The central search index (SRCH § 8, L5, D-1–D-6): one SQLite file in Duo's Application
/// Support folder, readable only by the user. Content is keyed by the hash of its (redacted)
/// text, so a passage is embedded once wherever it appears (FR-7.3.5). Rollback-journal mode:
/// readers need no shared-memory file, so the sandboxed CLI can open it read-only (FR-7.7.2).
public final class SearchIndex: @unchecked Sendable {
    public let db: SQLiteDB
    public let readOnly: Bool
    static let schema = 1

    public init(at url: URL = SearchPaths.index, readOnly: Bool) throws {
        if !readOnly {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } else if !FileManager.default.fileExists(atPath: url.path) {
            throw SearchError("no search index yet: open Duo once so it can build one")
        }
        db = try SQLiteDB(path: url.path, readOnly: readOnly)
        self.readOnly = readOnly
        if !readOnly {
            chmod(url.path, 0o600)
            try db.exec("""
            PRAGMA journal_mode=DELETE; PRAGMA foreign_keys=ON;
            CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);
            CREATE TABLE IF NOT EXISTS content(id INTEGER PRIMARY KEY, hash TEXT UNIQUE NOT NULL, vector BLOB NOT NULL);
            CREATE TABLE IF NOT EXISTS items(id INTEGER PRIMARY KEY, kind TEXT NOT NULL, project TEXT NOT NULL,
                path TEXT UNIQUE NOT NULL, title TEXT, modified REAL, size INTEGER, indexed REAL);
            CREATE INDEX IF NOT EXISTS items_project ON items(project);
            CREATE TABLE IF NOT EXISTS chunks(id INTEGER PRIMARY KEY, item INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
                content INTEGER NOT NULL, start INTEGER, end INTEGER, text TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS chunks_item ON chunks(item);
            CREATE INDEX IF NOT EXISTS chunks_content ON chunks(content);
            CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(text, content='chunks', content_rowid='id', tokenize='porter unicode61');
            CREATE TRIGGER IF NOT EXISTS chunks_ai AFTER INSERT ON chunks BEGIN INSERT INTO chunks_fts(rowid, text) VALUES (new.id, new.text); END;
            CREATE TRIGGER IF NOT EXISTS chunks_ad AFTER DELETE ON chunks BEGIN INSERT INTO chunks_fts(chunks_fts, rowid, text) VALUES ('delete', old.id, old.text); END;
            CREATE TABLE IF NOT EXISTS coverage(project TEXT PRIMARY KEY, known INTEGER, indexed INTEGER, updated REAL);
            """)
            // Schema 2: items kept only in Duo's archive (DL-49).
            try? db.exec("ALTER TABLE items ADD COLUMN archived INTEGER NOT NULL DEFAULT 0")
            try ensureModel()
        }
    }

    public func meta(_ key: String) -> String? {
        guard let s = try? db.prepare("SELECT value FROM meta WHERE key = ?").bind([key]), (try? s.step()) == true else { return nil }
        return s.string(0)
    }

    /// FR-7.3.8: an index built with another model is never queried; switching rebuilds it.
    func ensureModel() throws {
        let key = ModelIdentity.current.key
        if let have = meta("model"), have == key { return }
        try db.transaction {
            try db.exec("DELETE FROM chunks; DELETE FROM items; DELETE FROM content; DELETE FROM coverage;")
            try db.prepare("INSERT OR REPLACE INTO meta(key, value) VALUES ('model', ?)").run([key])
            try db.prepare("INSERT OR REPLACE INTO meta(key, value) VALUES ('schema', ?)").run([String(Self.schema)])
        }
    }

    public var modelMatches: Bool { meta("model") == ModelIdentity.current.key }

    static func hash(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func blob(_ v: [Float]) -> Data { v.withUnsafeBufferPointer { Data(buffer: $0) } }
    static func vector(_ d: Data, dim: Int) -> [Float] {
        d.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(dim)) }
    }
}

// MARK: - Writing (the app's indexer)

public struct IndexStats: Sendable, Equatable {
    public var files = 0, changed = 0, removed = 0, chunks = 0, embedded = 0, reused = 0
}

extension SearchIndex {
    /// Brings one project's files up to date: removed files leave, changed files are re-chunked,
    /// and only passages the index hasn't seen are embedded. Recent files first (FR-7.3.2).
    /// `pause` runs between files so the caller can throttle (FR-7.3.3).
    /// `excluding`: searched folders inside this one, indexed under their own names.
    public func indexProject(_ name: String, root: URL, excluding: Set<String> = [], embedder: Embedder,
                             pause: () async -> Void = {}) async throws -> IndexStats {
        var stats = IndexStats()
        let root = root.resolvingSymlinksInPath()
        let files = FileSource.files(in: root, excluding: excluding).sorted { $0.modified > $1.modified }
        stats.files = files.count
        var known: [String: (id: Int, modified: Double, size: Int)] = [:]
        let q = try db.prepare("SELECT id, path, modified, size FROM items WHERE project = ? AND kind = 'file'").bind([name])
        while try q.step() { known[q.string(1) ?? ""] = (q.int(0), q.double(2), q.int(3)) }

        let present = Set(files.map(\.path))
        let gone = known.filter { !present.contains($0.key) || !$0.key.hasPrefix(root.path + "/") }
        if !gone.isEmpty {
            try db.transaction { for (_, v) in gone { try db.prepare("DELETE FROM items WHERE id = ?").run([v.id]) } }
            stats.removed = gone.count
        }
        try updateCoverage(name, known: files.count)

        for f in files {
            let mod = f.modified.timeIntervalSince1970
            if let k = known[f.path], k.modified == mod, k.size == f.size { continue }
            guard let raw = FileSource.read(f.path) else { continue }
            let text = Secrets.redact(raw)
            let chunks = Chunker.chunks(path: f.path, text: text, tokenizer: embedder.tokenizer)
            let hashes = chunks.map { Self.hash($0.text) }
            var ids: [String: Int] = [:]
            let look = try db.prepare("SELECT id FROM content WHERE hash = ?")
            for h in Set(hashes) { look.bind([h]); if try look.step() { ids[h] = look.int(0) } }
            let missing = Array(Set(hashes).subtracting(ids.keys))
            let texts = missing.map { h in chunks[hashes.firstIndex(of: h)!].text }
            let vectors = try embedder.embedDocuments(texts)
            stats.embedded += missing.count
            stats.reused += Set(hashes).count - missing.count
            try db.transaction {
                let ins = try db.prepare("INSERT OR IGNORE INTO content(hash, vector) VALUES (?, ?)")
                for (h, v) in zip(missing, vectors) {
                    try ins.run([h, Self.blob(v)])
                    look.bind([h]); if try look.step() { ids[h] = look.int(0) }
                }
                if let k = known[f.path] { try db.prepare("DELETE FROM items WHERE id = ?").run([k.id]) }
                try db.prepare("INSERT INTO items(kind, project, path, title, modified, size, indexed) VALUES ('file', ?, ?, ?, ?, ?, ?)")
                    .run([name, f.path, f.relative, mod, f.size, Date().timeIntervalSince1970])
                let item = db.lastRowID
                let c = try db.prepare("INSERT INTO chunks(item, content, start, end, text) VALUES (?, ?, ?, ?, ?)")
                for (chunk, h) in zip(chunks, hashes) {
                    try c.run([item, ids[h] ?? 0, chunk.startLine, chunk.endLine, chunk.text])
                }
            }
            stats.changed += 1
            stats.chunks += chunks.count
            try updateCoverage(name, known: files.count)
            await pause()
        }
        return stats
    }

    /// A project that left the registry leaves search (FR-7.1.1).
    public func removeProject(_ name: String) throws {
        try db.transaction {
            try db.prepare("DELETE FROM items WHERE project = ?").run([name])
            try db.prepare("DELETE FROM coverage WHERE project = ?").run([name])
        }
    }

    /// Drops vectors no chunk uses any more.
    public func vacuumContent() throws {
        try db.exec("DELETE FROM content WHERE id NOT IN (SELECT DISTINCT content FROM chunks)")
    }

    func updateCoverage(_ project: String, known: Int) throws {
        let s = try db.prepare("SELECT count(*) FROM items WHERE project = ? AND kind = 'file'").bind([project])
        _ = try s.step()
        try db.prepare("INSERT OR REPLACE INTO coverage(project, known, indexed, updated) VALUES (?, ?, ?, ?)")
            .run([project, known, s.int(0), Date().timeIntervalSince1970])
    }
}

// MARK: - Reading (the CLI and the app)

public struct SearchQuery: Sendable {
    public var text: String
    public var projects: [String] = []          // empty: all (L2)
    public var kinds: [String] = []             // file, session, memory; empty: all (FR-7.4.6)
    public var currentProject: String?          // modest boost (FR-7.4.3)
    public var exactOnly = false                // FR-7.4.2
    public var limit = 10
    public var passagesPerItem = 1              // FR-7.4.4: grouped by item by default
    /// Find similar (FR-7.6.4): an item's stored path ("…/file.md", or a session's transcript);
    /// its passages' mean vector is the query, and the item itself is left out.
    public var similarTo: String?
    public init(text: String) { self.text = text }
}

public struct SearchHit: Sendable, Codable, Equatable {
    public var project: String
    public var kind: String
    public var path: String
    public var title: String
    public var locator: String
    public var startLine: Int
    public var endLine: Int
    public var score: Double
    public var matched: [String]                // "meaning", "words", "exact"
    public var snippet: String
    /// The same passage elsewhere (FR-7.4.5): shown once, with the other places listed.
    public var alsoIn: [String] = []
    /// Only in Duo's archive: Claude's cleanup removed the original (DL-49).
    public var archived = false
}

public struct Coverage: Sendable, Codable, Equatable {
    public var project: String
    public var known: Int
    public var indexed: Int
    public var complete: Bool { indexed >= known }
}

extension SearchIndex {
    public func coverage() throws -> [Coverage] {
        let s = try db.prepare("SELECT project, known, indexed FROM coverage ORDER BY project")
        var out: [Coverage] = []
        while try s.step() { out.append(Coverage(project: s.string(0) ?? "", known: s.int(1), indexed: s.int(2))) }
        return out
    }

    /// Hybrid search (L4, FR-7.4): semantic and keyword candidates fused by reciprocal rank,
    /// literal matches of an identifier or quoted phrase on top, a modest current-project boost,
    /// grouped by item. Scores are relative (FR-7.4.7).
    public func search(_ q: SearchQuery, embedder: Embedder?) throws -> [SearchHit] {
        let literal = Self.literal(in: q.text)
        var semantic: [Int: Int] = [:]   // chunk id → rank
        var lexical: [Int: Int] = [:]
        var exact = Set<Int>()

        var excluded: Set<String> = []
        if let target = q.similarTo {
            guard let (qv, stored, own) = try meanVector(of: target) else { throw SearchError("not in the index: \(target)") }
            excluded.insert(stored)
            // The item itself would be the best match and set the margin; leave its passages out first.
            for (rank, chunk) in try semanticChunks(qv, limit: 200, excluding: own).enumerated() where semantic[chunk] == nil { semantic[chunk] = rank }
        } else if !q.exactOnly, let embedder {
            let qv = try embedder.embedQuery(q.text)
            for (rank, chunk) in try semanticChunks(qv, limit: 200).enumerated() where semantic[chunk] == nil { semantic[chunk] = rank }
        }
        if q.similarTo == nil, let fts = Self.ftsQuery(q.text, exact: q.exactOnly || literal != nil) {
            let s = try db.prepare("SELECT rowid FROM chunks_fts WHERE chunks_fts MATCH ? ORDER BY bm25(chunks_fts) LIMIT 200").bind([fts])
            var rank = 0
            while try s.step() { lexical[s.int(0)] = rank; rank += 1 }
        }
        if q.similarTo == nil, let lit = literal ?? (q.exactOnly ? q.text : nil) {
            // Exact matches among the candidates, plus a direct scan for strings FTS can't tokenise.
            let s = try db.prepare("SELECT id FROM chunks WHERE instr(lower(text), lower(?)) > 0 LIMIT 500").bind([lit])
            while try s.step() { exact.insert(s.int(0)) }
        }

        // Reciprocal-rank fusion with a small k, so rank differences matter (F-36).
        var fused: [Int: Double] = [:]
        for (c, r) in semantic { fused[c, default: 0] += 1.0 / (Self.rrfK + Double(r)) }
        for (c, r) in lexical { fused[c, default: 0] += 1.0 / (Self.rrfK + Double(r)) }
        for c in exact { fused[c, default: 0] += 1.0 }   // exact matches rank first (S-EXACT)
        if q.exactOnly { fused = fused.filter { exact.contains($0.key) } }

        // Load candidates' items, apply filters and the boost, group by item.
        var hits: [SearchHit] = []
        let s = try db.prepare("""
            SELECT c.id, c.start, c.end, c.text, i.project, i.kind, i.path, i.title, c.content, i.archived FROM chunks c JOIN items i ON i.id = c.item WHERE c.id = ?
            """)
        var contentOf: [Int: Int] = [:]
        for (chunk, base) in fused {
            s.bind([chunk])
            guard try s.step() else { continue }
            let project = s.string(4) ?? ""
            if !q.projects.isEmpty && !q.projects.contains(project) { continue }
            let kind = s.string(5) ?? "file"
            if !q.kinds.isEmpty && !q.kinds.contains(kind) { continue }
            var score = base
            if project == q.currentProject { score *= Self.projectBoost }
            var matched: [String] = []
            if semantic[chunk] != nil { matched.append("meaning") }
            if lexical[chunk] != nil { matched.append("words") }
            if exact.contains(chunk) { matched.append("exact") }
            let text = s.string(3) ?? ""
            // Sessions and memory are stored as "session:<transcript>"; their locator is the turn.
            let stored = s.string(6) ?? ""
            if excluded.contains(stored) { continue }
            contentOf[chunk] = s.int(8)
            let path = kind == "file" ? stored : String(stored.drop { $0 != ":" }.dropFirst())
            let locator = kind == "session" ? "turn \(s.int(1))" : s.int(1) == s.int(2) ? "L\(s.int(1))" : "L\(s.int(1))-\(s.int(2))"
            hits.append(SearchHit(project: project, kind: kind, path: path, title: s.string(7) ?? "",
                                  locator: locator,
                                  startLine: s.int(1), endLine: s.int(2), score: score, matched: matched,
                                  snippet: Self.snippet(text, around: literal ?? q.text), alsoIn: [], archived: s.int(9) != 0))
        }
        hits.sort { $0.score > $1.score }
        // Identical passages (same content hash) in several items: keep the best, list the rest.
        var firstForContent: [String: Int] = [:]   // snippet+locator key → index in `deduped`
        var deduped: [SearchHit] = []
        for h in hits {
            let key = Self.hash(h.snippet)
            if let i = firstForContent[key], deduped[i].path != h.path {
                if !deduped[i].alsoIn.contains(h.path) { deduped[i].alsoIn.append(h.path) }
                continue
            }
            firstForContent[key] = deduped.count
            deduped.append(h)
        }
        var perItem: [String: Int] = [:]
        var out: [SearchHit] = []
        for h in deduped {
            let n = perItem[h.path, default: 0]
            guard n < q.passagesPerItem else { continue }
            perItem[h.path] = n + 1
            out.append(h)
            if Set(out.map(\.path)).count >= q.limit && perItem[h.path] == q.passagesPerItem { break }
        }
        return out
    }

    static let rrfK = 10.0
    static let projectBoost = 1.08
    /// Semantic candidates must score within this much of the best match: relative, never an
    /// absolute cutoff (FR-7.4.7). Keeps weak "nearest" passages out of small corpora.
    static let semanticMargin: Float = 0.12

    /// The normalised mean of an item's passage vectors, and the item's stored path.
    func meanVector(of target: String) throws -> ([Float], String, Set<Int>)? {
        let s = try db.prepare("""
            SELECT i.path, v.vector, v.id FROM items i JOIN chunks c ON c.item = i.id JOIN content v ON v.id = c.content
            WHERE i.path = ? OR i.path = 'session:' || ? OR i.path LIKE '%' || ?
            """).bind([target, target, target])
        var sum: [Float] = [], stored = "", own = Set<Int>()
        while try s.step() {
            stored = s.string(0) ?? ""
            own.insert(s.int(2))
            let v = Self.vector(s.blob(1), dim: ModelIdentity.current.dimensions)
            sum = sum.isEmpty ? v : zip(sum, v).map(+)
        }
        guard !sum.isEmpty else { return nil }
        let norm = sqrt(sum.reduce(0) { $0 + $1 * $1 })
        return (sum.map { $0 / max(norm, 1e-9) }, stored, own)
    }

    /// Chunks whose content vectors are nearest the query (cosine; vectors are normalised).
    func semanticChunks(_ qv: [Float], limit: Int, excluding: Set<Int> = []) throws -> [Int] {
        let dim = qv.count
        var scored: [(Int, Float)] = []
        let s = try db.prepare("SELECT id, vector FROM content")
        while try s.step() {
            let d = s.blob(1)
            guard d.count == dim * 4, !excluding.contains(s.int(0)) else { continue }
            var dot: Float = 0
            d.withUnsafeBytes { raw in
                qv.withUnsafeBufferPointer { q in vDSP_dotpr(q.baseAddress!, 1, raw.bindMemory(to: Float.self).baseAddress!, 1, &dot, vDSP_Length(dim)) }
            }
            scored.append((s.int(0), dot))
        }
        scored.sort { $0.1 > $1.1 }
        if let best = scored.first?.1 { scored = scored.filter { $0.1 >= best - Self.semanticMargin } }
        var chunks: [Int] = []
        let c = try db.prepare("SELECT id FROM chunks WHERE content = ?")
        for (content, _) in scored.prefix(limit) {
            c.bind([content])
            while try c.step() { chunks.append(c.int(0)) }
            if chunks.count >= limit { break }
        }
        return chunks
    }

    /// A quoted phrase, or a single identifier-like token (snake_case, dotted, camelCase, a path).
    public static func literal(in q: String) -> String? {
        let t = q.trimmingCharacters(in: .whitespaces)
        if t.count > 2, t.hasPrefix("\""), t.hasSuffix("\"") { return String(t.dropFirst().dropLast()) }
        if !t.contains(" "), t.count >= 3,
           t.contains(where: { "_./-:#@".contains($0) }) || (t.contains(where: \.isUppercase) && t.contains(where: \.isLowercase) && t.first!.isLowercase) {
            return t
        }
        return nil
    }

    /// Words OR'ed (or the phrase for exact), each quoted so FTS syntax in a query can't break it.
    public static func ftsQuery(_ q: String, exact: Bool) -> String? {
        let cleaned = q.replacingOccurrences(of: "\"", with: " ")
        let all = cleaned.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 1 }
        guard !all.isEmpty else { return nil }
        if exact { return "\"" + all.joined(separator: " ") + "\"" }
        // Words that match everything carry no signal in an OR query (F-36).
        let words = all.filter { !stopwords.contains($0.lowercased()) }
        guard !words.isEmpty else { return nil }
        return words.map { "\"\($0)\"" }.joined(separator: " OR ")
    }

    static let stopwords: Set<String> = ["a", "an", "and", "are", "as", "at", "be", "but", "by", "can", "do", "does", "every",
        "for", "from", "had", "has", "have", "how", "i", "if", "in", "into", "is", "it", "its", "me", "my", "no", "not", "of",
        "on", "or", "our", "so", "that", "the", "their", "them", "then", "there", "these", "they", "this", "to", "too", "up",
        "us", "was", "we", "were", "what", "when", "where", "which", "who", "why", "will", "with", "would", "you", "your"]

    static func snippet(_ text: String, around needle: String, width: Int = 220) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        let lower = flat.lowercased()
        let parts: [Substring] = needle.lowercased().split(whereSeparator: { $0 == " " })
        let word = parts.max(by: { $0.count < $1.count }).map(String.init) ?? ""
        guard let r = lower.range(of: needle.lowercased()) ?? (word.count > 3 ? lower.range(of: word) : nil) else {
            return String(flat.prefix(width))
        }
        let pos = lower.distance(from: lower.startIndex, to: r.lowerBound)
        let start = max(0, pos - width / 3)
        let s = flat.index(flat.startIndex, offsetBy: start)
        let e = flat.index(s, offsetBy: min(width, flat.distance(from: s, to: flat.endIndex)))
        return (start > 0 ? "…" : "") + flat[s..<e] + (e < flat.endIndex ? "…" : "")
    }
}
