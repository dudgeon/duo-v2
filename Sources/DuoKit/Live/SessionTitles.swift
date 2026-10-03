import Foundation

/// Session titles (LR-6): custom title → AI title → compaction summary → slash command → cleaned
/// first prompt. Read from Claude's transcript, never written (no `/rename` injection). Reads are
/// bounded to the head and tail of the file (LR-9) and cached by size and modification date, so
/// the 2 s refresh doesn't reread unchanged transcripts.
public enum SessionTitles {
    static let headBytes = 64 * 1024
    static let tailBytes = 256 * 1024

    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var entries: [String: (size: UInt64, mtime: Date, title: String?)] = [:]
    }
    private static let cache = Cache()

    public static func title(transcript url: URL) -> String? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
        let mtime = attrs?[.modificationDate] as? Date ?? .distantPast
        cache.lock.lock()
        if let hit = cache.entries[url.path], hit.size == size, hit.mtime == mtime { cache.lock.unlock(); return hit.title }
        cache.lock.unlock()
        let t = read(url, size: size)
        cache.lock.lock()
        cache.entries[url.path] = (size, mtime, t)
        cache.lock.unlock()
        return t
    }

    static func read(_ url: URL, size: UInt64) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let head = (try? h.read(upToCount: headBytes)) ?? Data()
        var tail = Data()
        if size > UInt64(headBytes) {
            try? h.seek(toOffset: size > UInt64(tailBytes) ? size - UInt64(tailBytes) : UInt64(headBytes))
            tail = (try? h.readToEnd()) ?? Data()
        }
        return title(head: lines(head, dropFirst: false), tail: lines(tail, dropFirst: true))
    }

    static func lines(_ d: Data, dropFirst: Bool) -> [[String: Any]] {
        var parts = d.split(separator: UInt8(ascii: "\n"))
        if dropFirst, !parts.isEmpty { parts.removeFirst() }  // probably cut mid-line
        return parts.compactMap { try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] }
    }

    /// The ladder over parsed records; later records win within a rung.
    public static func title(head: [[String: Any]], tail: [[String: Any]]) -> String? {
        let all = head + tail
        func last(_ type: String, _ key: String) -> String? {
            all.last { $0["type"] as? String == type && ($0[key] as? String)?.isEmpty == false }?[key] as? String
        }
        if let t = last("custom-title", "customTitle") { return t }
        if let t = last("ai-title", "aiTitle") { return t }
        if let t = last("summary", "summary") { return t }
        for r in head where r["type"] as? String == "user" && r["isMeta"] as? Bool != true {
            guard let text = promptText(r) else { continue }
            if let cmd = firstMatch(#"<command-name>\s*(/[^<\s]+)"#, in: text) { return cmd }
            if let p = clean(text) { return p }
        }
        return nil
    }

    static func promptText(_ r: [String: Any]) -> String? {
        let content = (r["message"] as? [String: Any])?["content"]
        if let s = content as? String { return s }
        // Arrays carry tool results too; only plain text parts are prompts.
        let texts = (content as? [[String: Any]])?.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
        return texts?.isEmpty == false ? texts?.joined(separator: " ") : nil
    }

    /// Strips harness wrapper tags and their contents, collapses whitespace, and shortens to a
    /// title on a word boundary.
    public static func clean(_ text: String, limit: Int = 60) -> String? {
        var s = text.replacingOccurrences(of: #"<([a-zA-Z][\w-]*)[^>]*>[\s\S]*?</\1>"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        guard s.count > limit else { return s }
        let cut = s.prefix(limit)
        let word = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return word.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) + "…"
    }

    static func firstMatch(_ pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }
}
