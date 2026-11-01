import CryptoKit
import DuoControl
import Foundation

/// Where template packs are found (DL-268, DL-146's scopes): the project's `templates/decks/`, then
/// Home's, then Duo's one built-in pack, "duo-plain".
extension Deck {
    public static let builtInPackName = "duo-plain"

    /// The folders to look in for a deck living in `dir`, nearest first. A project pack of the same name wins.
    /// The built-in folder is last; it is written on first use.
    public static func packDirs(near dir: URL) -> [URL] {
        let fm = FileManager.default
        let (project, homeAbove) = DirectorPlace.resolve(from: dir)
        var home = homeAbove ?? DirectorPlace.configuredHome()
        if let h = home, !fm.fileExists(atPath: h.path) { home = nil }
        var out: [URL] = []
        // From the deck's folder up to the project's (a deck in decks/ finds the project's templates/decks/).
        var d = dir.standardizedFileURL
        let stop = project.standardizedFileURL.path
        for _ in 0..<8 {
            out.append(d.appending(path: "templates/decks"))
            if d.path == stop || d.path == "/" { break }
            d = d.deletingLastPathComponent()
        }
        if let h = home { out.append(h.appending(path: "templates/decks")) }
        if let b = try? builtInPackDir() { out.append(b) }
        var seen = Set<String>()
        return out.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// A folder holding the built-in pack as `duo-plain/duo-plain.md` and `.pptx`, written under the
    /// temporary folder the first time (named by a hash of its content, so a newer Duo never reads an older copy).
    public static func builtInPackDir() throws -> URL {
        guard let pptx = Data(base64Encoded: BuiltInPackData.pptxBase64, options: .ignoreUnknownCharacters) else {
            throw Failure(description: "the built-in pack is damaged")
        }
        let key = SHA256.hash(data: pptx + Data(BuiltInPackData.definition.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        let root = FileManager.default.temporaryDirectory.appending(path: "duo-builtin-packs-\(key)")
        let dir = root.appending(path: builtInPackName)
        let md = dir.appending(path: "\(builtInPackName).md"), px = dir.appending(path: "\(builtInPackName).pptx")
        if !FileManager.default.fileExists(atPath: md.path) || !FileManager.default.fileExists(atPath: px.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try pptx.write(to: px, options: .atomic)
            try Data(BuiltInPackData.definition.utf8).write(to: md, options: .atomic)
        }
        return root
    }

    /// Every pack visible from `dirs`: (name, definition note), the first of each name winning.
    public static func packs(in dirs: [URL]) -> [(name: String, md: URL)] {
        let fm = FileManager.default
        var seen = Set<String>(), out: [(String, URL)] = []
        for d in dirs {
            for name in ((try? fm.contentsOfDirectory(atPath: d.path)) ?? []).sorted() where !seen.contains(name) {
                let md = d.appending(path: name).appending(path: "\(name).md")
                if fm.fileExists(atPath: md.path) { seen.insert(name); out.append((name, md)) }
            }
        }
        return out
    }

    /// The compact catalogue Claude reads instead of any pptx: one pair of lines per template, its
    /// slots with kind and limits, then its purpose.
    public static func catalogue(_ pack: Pack) -> String {
        var out = ["\(pack.name) (\(pack.md.path))"]
        for t in pack.templates {
            let slots = t.slots.map { s -> String in
                var x = "\(s.name): \(s.kind)"
                if let m = s.max { x += " ≤\(m)" }
                if let i = s.items { x += " ×\(i)" }
                if let l = s.levels, l > 1 { x += " levels \(l)" }
                if let r = s.rows { x += " rows ≤\(r)" }
                if let c = s.cols { x += " cols ≤\(c)" }
                if s.isDefault { x += " (default)" }
                return x
            }.joined(separator: ", ")
            let name = t.name.padding(toLength: max(11, t.name.count), withPad: " ", startingAt: 0)
            out.append("  \(name) \(slots)")
            if let first = t.purpose.split(separator: "\n").first { out.append("  \(String(repeating: " ", count: name.count)) \(first)") }
            for (from, map) in t.overrides.sorted(by: { $0.key < $1.key }) {
                out.append("  \(String(repeating: " ", count: name.count)) from \(from): " + map.sorted { $0.key < $1.key }.map { "\($0.key) -> \($0.value)" }.joined(separator: ", "))
            }
        }
        return out.joined(separator: "\n")
    }

    /// A new deck: frontmatter naming the pack and a title slide (the pack's `title` template, else its first).
    public static func newDeckText(title: String, pack: Pack) -> String {
        let first = pack.template("title") ?? pack.templates.first
        return "---\ntype: deck\ntitle: \(title)\ntemplate: \(pack.name)\n---\n\n<!-- slide: \(first?.name ?? "title") -->\n# \(title)\n"
    }

    /// The skeleton for a slide of template `name`: the marker, an empty `#` title and a bare `## slot`
    /// heading for each other slot.
    public static func skeleton(_ t: Template) -> [String] {
        var out = ["<!-- slide: \(t.name) -->"]
        if t.slot("title") != nil { out.append("# ") }
        for s in t.slots where s.name != "title" { out += ["", "## \(s.name)"] }
        return out
    }

    /// `source` with a slide of template `t` added after slide `n` (0 first, nil last).
    public static func insertSlide(source: String, template t: Template, after n: Int?) throws -> String {
        let parsed = parse(source)
        let count = parsed.slides.count
        let at = n ?? count
        guard at >= 0, at <= count else { throw Failure(description: "the deck has \(count) slides; --after \(at) is outside 0...\(count)") }
        var lines = source.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        // Just before the next slide's marker (after the blank lines that follow the slide before), or at the end.
        var insertAt = at < count ? parsed.slides[at].line - 1 : lines.count
        while insertAt > 0, lines[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty { insertAt -= 1 }
        let rules = lines.filter { $0.trimmingCharacters(in: .whitespaces) == "---" }.count > 2   // beyond the frontmatter's two
        var block: [String]
        if at < count {
            block = [""] + skeleton(t) + (rules ? ["", "---"] : [])
        } else {
            let afterRule = insertAt > 0 && lines[insertAt - 1].trimmingCharacters(in: .whitespaces) == "---"
            block = [""] + (rules && count > 0 && !afterRule ? ["---", ""] : []) + skeleton(t)
        }
        lines.insert(contentsOf: block, at: insertAt)
        return lines.joined(separator: "\n") + "\n"
    }
}
