import Foundation
import DuoControl

/// Claude Code's on-disk layout under `~/.claude` (DL-14: Duo shares it). Reverse-engineered
/// from CLI 2.1.288 (docs/research/claude-code-session-path-binding.md); every rule here is
/// checked against the real folders on launch (`calibrate`) before Duo relies on it.
public enum ClaudeStorage {
    public static var root: URL {
        if let dir = Env.value("CLAUDE_CONFIG_DIR") { return URL(fileURLWithPath: dir) }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude")
    }

    public static var projects: URL { root.appending(path: "projects") }
    public static var sessions: URL { root.appending(path: "sessions") }

    /// A session's transcript, if Claude has written one. Claude writes it on the first message,
    /// so a session that was started and never used has none and can't be resumed (F-25).
    /// Looks in the cwd's folder first, then every project folder (the session may have moved).
    public static func transcript(sessionId: String, cwd: String) -> URL? {
        let fm = FileManager.default
        let name = sessionId + ".jsonl"
        let direct = projects.appending(path: encode(URL(fileURLWithPath: cwd).realPath)).appending(path: name)
        if fm.fileExists(atPath: direct.path) { return direct }
        let dirs = (try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
        return dirs.map { $0.appending(path: name) }.first { fm.fileExists(atPath: $0.path) }
    }

    /// The folder name Claude Code stores a working directory's sessions under: every character
    /// outside [A-Za-z0-9] becomes "-"; over 200 characters, the first 200 plus "-" and a base-36
    /// hash of the unsanitized path (Java's String.hashCode, absolute value).
    public static func encode(_ path: String) -> String {
        let sanitized = String(path.unicodeScalars.map { s -> Character in
            (s.isASCII && (CharacterSet.alphanumerics.contains(s))) ? Character(s) : "-"
        })
        guard sanitized.count > 200 else { return sanitized }
        return String(sanitized.prefix(200)) + "-" + String(abs(Int64(javaHash(path))), radix: 36)
    }

    /// Java's `String.hashCode` over UTF-16 code units, as a 32-bit signed integer.
    static func javaHash(_ s: String) -> Int32 {
        var h: Int32 = 0
        for unit in s.utf16 { h = h &* 31 &+ Int32(unit) }
        return h
    }

    public struct Calibration: Sendable {
        public var checked = 0
        public var matched = 0
        public var collisions = 0          // folders holding sessions from more than one cwd
        public var mismatches: [(folder: String, cwd: String, encoded: String)] = []
        public var ok: Bool { checked > 0 && mismatches.isEmpty }
    }

    /// Checks `encode` against every project folder: some transcript in it must record a cwd
    /// that encodes to the folder's name (where it was filed after any `/cd`, its first cwd, or its
    /// last: a fork opens with its parent's records, from the parent's folder, F-31). One folder
    /// with none means Claude Code changed the rule, and Duo must not perform physical operations
    /// until it is updated (CONS §6.3 item 5). `dir`: the projects folder (checks pass their own).
    public static func calibrate(in dir: URL = ClaudeStorage.projects, limit: Int = .max) -> Calibration {
        var c = Calibration()
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(atPath: dir.path) else { return c }
        for folder in folders.prefix(limit) {
            let d = dir.appending(path: folder)
            guard let files = try? fm.contentsOfDirectory(atPath: d.path) else { continue }
            var cwds = Set<String>(), recorded = Set<String>()
            for f in files where f.hasSuffix(".jsonl") {
                let r = filingCwds(d.appending(path: f))
                if let filed = r.first { cwds.insert(filed) }
                recorded.formUnion(r)
            }
            guard !cwds.isEmpty else { continue }
            if cwds.count > 1 { c.collisions += 1 }
            c.checked += 1
            if recorded.contains(where: { encode($0) == folder }) {
                c.matched += 1
            } else if let cwd = cwds.first {
                c.mismatches.append((folder, cwd, encode(cwd)))
            }
        }
        return c
    }

    /// The folder a transcript is filed under: the last `relocated` record's `relocatedCwd` if
    /// there is one (`/cd` moves the file, F-32), else the first `cwd`. Reads at most the first
    /// and last 64 KB (LR-9: never slurp).
    public static func filedCwd(_ url: URL) -> String? { firstCwd(url) }

    private final class CwdCache: @unchecked Sendable {
        let lock = NSLock()
        var entries: [String: (mtime: Date, cwd: String?)] = [:]
    }
    private static let cwdCache = CwdCache()

    /// Every top-level transcript on this Mac with the folder it belongs to (after any /cd),
    /// cached by modification time so the 2 s refresh rereads only what changed.
    public static func history() -> [(id: String, transcript: URL, cwd: String)] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil) else { return [] }
        var out: [(String, URL, String)] = []
        for d in dirs {
            let files = (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for f in files where f.pathExtension == "jsonl" {
                let mtime = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                cwdCache.lock.lock()
                let hit = cwdCache.entries[f.path]
                cwdCache.lock.unlock()
                let cwd: String?
                if let hit, hit.mtime == mtime { cwd = hit.cwd } else {
                    cwd = firstCwd(f)
                    cwdCache.lock.lock(); cwdCache.entries[f.path] = (mtime, cwd); cwdCache.lock.unlock()
                }
                if let cwd { out.append((f.deletingPathExtension().lastPathComponent, f, cwd)) }
            }
        }
        return out
    }

    static func firstCwd(_ url: URL) -> String? { filingCwds(url).first }

    /// The cwds a transcript can be filed under, most likely first: the last `relocated` record's
    /// `relocatedCwd`, the first `cwd`, the last `cwd`. Reads at most the first and last 64 KB.
    static func filingCwds(_ url: URL) -> [String] {
        guard let h = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? h.close() }
        let head = (try? h.read(upToCount: 64 * 1024)) ?? Data()
        let size = (try? h.seekToEnd()) ?? 0
        var tail = Data()
        if size > 64 * 1024 {
            try? h.seek(toOffset: max(64 * 1024, size - 64 * 1024))
            tail = (try? h.readToEnd()) ?? Data()
        }
        func lines(_ d: Data) -> [Substring] { (String(data: d, encoding: .utf8) ?? "").split(separator: "\n") }
        func object(_ line: Substring) -> [String: Any]? { try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] }
        let all = lines(head) + lines(tail)
        var out: [String] = []
        for line in all.reversed() where line.contains("\"relocated\"") {
            if let o = object(line), o["type"] as? String == "relocated", let to = o["relocatedCwd"] as? String { out.append(to); break }
        }
        for line in all where line.contains("\"cwd\"") {
            if let cwd = object(line)?["cwd"] as? String { out.append(cwd); break }
        }
        for line in all.reversed() where line.contains("\"cwd\"") {
            if let cwd = object(line)?["cwd"] as? String { out.append(cwd); break }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }
}
