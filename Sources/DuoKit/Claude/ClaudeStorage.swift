import Foundation

/// Claude Code's on-disk layout under `~/.claude` (DL-14: Duo shares it). Reverse-engineered
/// from CLI 2.1.288 (docs/research/claude-code-session-path-binding.md); every rule here is
/// checked against the real folders on launch (`calibrate`) before Duo relies on it.
public enum ClaudeStorage {
    public static var root: URL {
        if let dir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] { return URL(fileURLWithPath: dir) }
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
        let direct = projects.appending(path: encode(URL(fileURLWithPath: cwd).resolvingSymlinksInPath().path)).appending(path: name)
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

    /// Checks `encode` against every project folder: the first `cwd` recorded in a transcript
    /// must encode to the folder's name. One mismatch means Claude Code changed the rule, and
    /// Duo must not perform physical operations until it is updated (CONS §6.3 item 5).
    public static func calibrate(limit: Int = .max) -> Calibration {
        var c = Calibration()
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(atPath: projects.path) else { return c }
        for folder in folders.prefix(limit) {
            let dir = projects.appending(path: folder)
            guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            var cwds = Set<String>()
            for f in files where f.hasSuffix(".jsonl") {
                if let cwd = firstCwd(dir.appending(path: f)) { cwds.insert(cwd) }
            }
            guard !cwds.isEmpty else { continue }
            if cwds.count > 1 { c.collisions += 1 }
            c.checked += 1
            if cwds.contains(where: { encode($0) == folder }) {
                c.matched += 1
            } else if let cwd = cwds.first {
                c.mismatches.append((folder, cwd, encode(cwd)))
            }
        }
        return c
    }

    /// The first `cwd` field in a transcript, reading at most its first 64 KB (LR-9: never slurp).
    static func firstCwd(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let data = try? h.read(upToCount: 64 * 1024), let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.contains("\"cwd\"") {
            if let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
               let cwd = obj["cwd"] as? String { return cwd }
        }
        return nil
    }
}
