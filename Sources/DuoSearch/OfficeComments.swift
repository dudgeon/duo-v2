import Foundation

/// Comments in Word and PowerPoint files (DL-331; Geoff, 2026-11-10: "A: write into file"). Duo reads a .docx's
/// `word/comments.xml` (with `commentsExtended.xml` for replies and done) and a .pptx's modern comment parts, and writes a
/// comment, a reply or a resolved state into them: the comment parts, the anchors a comment needs in `word/document.xml`,
/// and the relationships and content types of a part that is new. Every other part of the package is copied raw, byte for
/// byte (`OfficeZip`). Edits are made on the XML text at the spot, so the rest of each part is untouched too.
public enum OfficeComments {
    public enum Kind: Sendable { case word, powerpoint }

    public struct Failure: Error, CustomStringConvertible { public let description: String; public init(_ d: String) { description = d } }

    public struct Item: Equatable, Sendable {
        /// `c4` for a thread's first comment, `c4.1` for its first reply (Word); `s3c1`, `s3c1.1` (PowerPoint).
        public var id: String
        public var author: String
        /// ISO 8601, as the file has it.
        public var date: String
        public var text: String
    }

    public struct Thread: Equatable, Sendable {
        public var id: String
        /// The text it is on (Word) or the shape's text (PowerPoint), nil for a comment on nothing in particular.
        public var anchor: String?
        /// Where it is, for the turn: `paragraph 1A2B007F`, `slide 3`.
        public var place: String
        public var items: [Item]
        public var resolved: Bool
        /// Legacy PowerPoint comments can be read but not written.
        public var legacy: Bool = false
        /// PowerPoint (DL-337): what the comment is on: `slide`, `shape` or `text`; the shape (id and name) and, for a run of text, its
        /// character range in the shape's text. `lost`: the anchor no longer matches the file (the shape is gone, or the text moved).
        public var anchorKind: String = "slide"
        public var shapeId: String?
        public var shapeName: String?
        public var rangeStart: Int?
        public var rangeLength: Int?
        public var anchorLost = false
        public var root: Item { items[0] }
    }

    public static func kind(_ url: URL) -> Kind? {
        switch url.pathExtension.lowercased() {
        case "docx", "docm", "dotx": return .word
        case "pptx", "pptm", "potx": return .powerpoint
        default: return nil
        }
    }

    // MARK: Reading

    public static func threads(_ url: URL) throws -> [Thread] {
        switch kind(url) {
        case .word: return try Word.read(Pptx.Zip(url))
        case .powerpoint: return try Slides.read(Pptx.Zip(url))
        case nil: throw Failure("\(url.lastPathComponent) isn't a Word or PowerPoint file")
        }
    }

    // MARK: Writing

    public struct Written: Sendable { public var id: String; public var summary: String }

    /// Comment on `at`: Word: a text that appears once (or a paragraph number); PowerPoint: a slide number.
    public static func add(_ url: URL, at: String, author: String, text: String, now: Date = Date(), backups: URL? = nil) throws -> Written {
        try write(url, backups: backups) { zip, files in
            switch kind(url) {
            case .word: return try Word.add(zip, &files, at: at, author: author, text: text, now: now)
            case .powerpoint: return try Slides.add(zip, &files, at: at, author: author, text: text, now: now)
            case nil: throw Failure("not a Word or PowerPoint file")
            }
        }
    }

    public static func reply(_ url: URL, to thread: String, author: String, text: String, now: Date = Date(), backups: URL? = nil) throws -> Written {
        try write(url, backups: backups) { zip, files in
            switch kind(url) {
            case .word: return try Word.reply(zip, &files, to: thread, author: author, text: text, now: now)
            case .powerpoint: return try Slides.reply(zip, &files, to: thread, author: author, text: text, now: now)
            case nil: throw Failure("not a Word or PowerPoint file")
            }
        }
    }

    /// Mark a thread resolved (Word `done`, PowerPoint `status`), or active again.
    public static func resolve(_ url: URL, thread: String, resolved: Bool, backups: URL? = nil) throws -> Written {
        try write(url, backups: backups) { zip, files in
            switch kind(url) {
            case .word: return try Word.resolve(zip, &files, thread: thread, resolved: resolved)
            case .powerpoint: return try Slides.resolve(zip, &files, thread: thread, resolved: resolved)
            case nil: throw Failure("not a Word or PowerPoint file")
            }
        }
    }

    /// Delete a thread (DL-337): the comment, its replies and its anchors go from the file's comment parts.
    public static func delete(_ url: URL, thread: String, backups: URL? = nil) throws -> Written {
        try write(url, backups: backups) { zip, files in
            switch kind(url) {
            case .word: return try Word.delete(zip, &files, thread: thread)
            case .powerpoint: return try Slides.delete(zip, &files, thread: thread)
            case nil: throw Failure("not a Word or PowerPoint file")
            }
        }
    }

    /// Undo the last write to this file (⌘Z, DL-337): restores it from the backup kept before that write.
    public static func undo(_ url: URL, backups: URL) throws -> Written {
        let journal = backups.appendingPathComponent(url.lastPathComponent + ".undo")
        var lines = (try? String(contentsOf: journal, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
        guard let last = lines.popLast() else { throw Failure("nothing to undo in \(url.lastPathComponent): Duo has no earlier copy from before a comment was written") }
        let backup = backups.appendingPathComponent(last)
        guard let data = try? Data(contentsOf: backup) else { throw Failure("the earlier copy \(last) is gone from \(backups.path)") }
        try data.write(to: url, options: .atomic)
        try (lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")).write(to: journal, atomically: true, encoding: .utf8)
        return Written(id: "", summary: "Restored \(url.lastPathComponent) to how it was before the last comment change.")
    }

    static func write(_ url: URL, backups: URL?, _ make: (Pptx.Zip, inout [String: Data]) throws -> Written) throws -> Written {
        let original = try Data(contentsOf: url)
        let zip = try Pptx.Zip(url)
        var files: [String: Data] = [:]
        let w = try make(zip, &files)
        if let backups {
            // One copy of each original, named by its content, so a second write doesn't replace the first backup.
            try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
            let b = backups.appendingPathComponent(String(format: "%08x-", OfficeZip.crc32(original)) + url.lastPathComponent)
            if !FileManager.default.fileExists(atPath: b.path) { try original.write(to: b) }
            // The journal lists the backups in order, so undo can step back through several writes.
            let journal = backups.appendingPathComponent(url.lastPathComponent + ".undo")
            let prior = (try? String(contentsOf: journal, encoding: .utf8)) ?? ""
            try (prior + b.lastPathComponent + "\n").write(to: journal, atomically: true, encoding: .utf8)
        }
        let patched = try OfficeZip.patch(original, changes: files)
        guard (try? Pptx.Zip(patchedData: patched)) != nil else { throw Failure("the changed file didn't read back; nothing was written") }
        try patched.write(to: url, options: .atomic)
        return w
    }

    // MARK: Shared text helpers

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    static func unesc(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
         .replacingOccurrences(of: "&apos;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
    }
    static func string(_ d: Data?) -> String? { d.map { String(decoding: $0, as: UTF8.self) } }
    static func iso(_ d: Date, millis: Bool = false) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = millis ? "yyyy-MM-dd'T'HH:mm:ss.SSS" : "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f.string(from: d)
    }
    static func initials(_ name: String) -> String {
        let parts = name.split(whereSeparator: { " -_.".contains($0) }).prefix(2)
        let s = parts.compactMap { $0.first }.map { String($0).uppercased() }.joined()
        return s.isEmpty ? "?" : s
    }
    /// The name a file shows: `claude` is Claude.
    static func display(_ author: String) -> String { author.lowercased() == "claude" ? "Claude" : author }
    /// Text of a snippet of XML: its `w:t`/`a:t` contents, tags dropped.
    static func plain(_ xml: String, tag: String) -> String {
        var out = "", rest = Substring(xml)
        while let a = rest.range(of: "<\(tag)") {
            guard let close = rest[a.upperBound...].firstIndex(of: ">") else { break }
            if rest[rest.index(before: close)] == "/" { rest = rest[rest.index(after: close)...]; continue }
            guard let end = rest[close...].range(of: "</\(tag)>") else { break }
            out += unesc(String(rest[rest.index(after: close)..<end.lowerBound]))
            rest = rest[end.upperBound...]
        }
        return out
    }
    /// Replaces the first occurrence of `marker` by `with + marker`... or after it.
    static func insert(_ s: inout String, _ piece: String, before marker: String) -> Bool {
        guard let r = s.range(of: marker) else { return false }
        s.insert(contentsOf: piece, at: r.lowerBound); return true
    }
    static func insert(_ s: inout String, _ piece: String, after marker: String) -> Bool {
        guard let r = s.range(of: marker) else { return false }
        s.insert(contentsOf: piece, at: r.upperBound); return true
    }
    /// Adds a relationship and, if missing, a content type override.
    static func addRel(_ rels: inout String, id: String, type: String, target: String) {
        let rel = "<Relationship Id=\"\(id)\" Type=\"\(type)\" Target=\"\(target)\"/>"
        if !insert(&rels, rel, before: "</Relationships>") { rels += rel }
    }
    static func addOverride(_ ct: inout String, part: String, type: String) {
        if ct.contains("PartName=\"\(part)\"") { return }
        _ = insert(&ct, "<Override PartName=\"\(part)\" ContentType=\"\(type)\"/>", before: "</Types>")
    }
    static func freshID(_ prefix: String, in text: String) -> String {
        var n = 1
        while text.contains("Id=\"\(prefix)\(n)\"") { n += 1 }
        return "\(prefix)\(n)"
    }
}

extension Pptx.Zip {
    /// Reads zip bytes already in memory (the check that a changed file still opens).
    init(patchedData d: Data) throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("duo-oc-\(UUID().uuidString).zip")
        try d.write(to: tmp); defer { try? FileManager.default.removeItem(at: tmp) }
        try self.init(tmp)
    }
}
