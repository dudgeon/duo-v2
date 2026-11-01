import CryptoKit
import DuoControl
import DuoDeck
import Foundation

// Duo Decks P3b: the pure parts of the deck viewer's cards, export state, pins and comments (P3-1, P3-3).
// DuoChecks run all of it; nothing here touches the app.

/// What a card under a slide offers, by id: `fix`, `goto`, `send`, `move:<slot>`, `split`, `undo`.
public struct DeckCardButton: Equatable, Sendable {
    public var id: String
    public var label: String
    public init(id: String, label: String) { self.id = id; self.label = label }
}

/// A card under a slide (P3-3): a problem, or content moved to the notes (DL-281).
public struct DeckCard: Equatable, Sendable {
    public enum Kind: String, Sendable { case problem, notesMove }
    public var kind: Kind
    public var slide: Int
    /// The template the slide uses.
    public var template: String
    /// The slot a problem names (shown semibold), if it names one.
    public var slot: String?
    /// The message without its `slide n (template), slot:` prefix.
    public var message: String
    /// The source line to go to.
    public var line: Int
    public var buttons: [DeckCardButton]
    /// What the one-answer fix writes: replace the text of `line` with this (nil without a fix).
    public var fixLine: String?
}

/// A pin on the slides (P3-1): where a comment is, how many comments, and the thread a click opens.
public struct DeckPin: Equatable, Sendable {
    public var anchor: String
    public var slide: Int
    public var slot: String?
    public var count: Int
    public var thread: String
}

/// The state of the newest dated export beside a deck (DL-282, DL-286).
public struct DeckExportState: Equatable, Sendable {
    /// The newest dated export's file name, nil when there is none.
    public var newest: String?
    public var date: Date?
    /// The buffer's text differs from what that export was made from.
    public var changed: Bool

    public static let none = DeckExportState(newest: nil, date: nil, changed: false)

    /// Reads the newest dated export of `deck` and compares its `duoSourceSha` with `text`'s.
    public static func read(deck: URL, text: String) -> DeckExportState {
        let dir = deck.deletingLastPathComponent()
        let name = deck.deletingPathExtension().lastPathComponent
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { Deck.isExport($0, of: name) }.sorted()
        guard let newest = files.last else { return .none }
        let sha = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        let theirs = exportSha(dir.appending(path: newest))
        return DeckExportState(newest: newest, date: date(ofExport: newest), changed: theirs != sha)
    }

    nonisolated(unsafe) private static var shaCache: [String: String] = [:]
    private static let shaLock = NSLock()

    /// The `duoSourceSha` an export carries, remembered per file and modification time (a render runs often).
    static func exportSha(_ url: URL) -> String? {
        let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)@\(m)"
        shaLock.lock(); let hit = shaCache[key]; shaLock.unlock()
        if let hit { return hit }
        guard let sha = (try? Deck.inspect(url))?.customProperties["duoSourceSha"] else { return nil }
        shaLock.lock(); shaCache[key] = sha; shaLock.unlock()
        return sha
    }

    /// `name 2026-11-01 0912.pptx` → that time (local).
    public static func date(ofExport file: String) -> Date? {
        guard let m = file.firstMatch(of: /(\d{4})-(\d{2})-(\d{2}) (\d{2})(\d{2})\.pptx$/) else { return nil }
        var c = DateComponents()
        c.year = Int(m.1); c.month = Int(m.2); c.day = Int(m.3); c.hour = Int(m.4); c.minute = Int(m.5)
        return Calendar(identifier: .gregorian).date(from: c)
    }

    /// The bar's text in `text2`: "Changed since export", "Exported 5 m ago", or nothing.
    public func label(now: Date = Date()) -> String {
        guard newest != nil else { return "" }
        if changed { return "Changed since export" }
        guard let date else { return "Exported" }
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60 { return "Exported just now" }
        if s < 3600 { return "Exported \(s / 60) m ago" }
        if s < 86400 { return "Exported \(s / 3600) h ago" }
        return "Exported \(s / 86400) d ago"
    }

    /// The date part of the name, for the menu's "replaces 2026-11-01 0912".
    public var stamp: String? {
        guard let n = newest, let m = n.firstMatch(of: /(\d{4}-\d{2}-\d{2} \d{4})\.pptx$/) else { return nil }
        return String(m.1)
    }
}

public enum DeckCards {
    // MARK: Problems

    /// `slide 3 (kpi), value: msg` → (3, "kpi", "value", "msg"); `slide 3 (kpi): msg` → slot nil.
    public static func split(_ message: String) -> (slide: Int, template: String, slot: String?, text: String)? {
        if let m = message.firstMatch(of: /^slide (\d+) \(([^)]*)\), ([^:]+): (.*)$/) {
            return (Int(m.1) ?? 0, String(m.2), String(m.3), String(m.4))
        }
        if let m = message.firstMatch(of: /^slide (\d+) \(([^)]*)\): (.*)$/) {
            return (Int(m.1) ?? 0, String(m.2), nil, String(m.3))
        }
        return nil
    }

    /// Edit distance, for the near match a typo has.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count { cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)) }
            prev = cur
        }
        return prev[b.count]
    }

    /// The one near match of `word` among `options` (within two edits), nil if none or several.
    public static func nearMatch(_ word: String, in options: [String]) -> String? {
        let near = options.filter { $0 != word && distance($0.lowercased(), word.lowercased()) <= 2 }
        return near.count == 1 ? near[0] : nil
    }

    /// One card per error, under its slide. A fix button only where the answer is single (DL-298): an
    /// unknown template or slot with one near match. Otherwise Go to Line and Send to Claude.
    public static func problemCards(_ problems: [SourceProblem], text: String, anchors: [AnchorRange]) -> [DeckCard] {
        let lines = text.components(separatedBy: "\n")
        var out: [DeckCard] = []
        for p in problems where p.severity == .error {
            guard let s = split(p.message) else { continue }
            var card = DeckCard(kind: .problem, slide: s.slide, template: s.template, slot: s.slot, message: s.text, line: p.line, buttons: [])
            if s.slot == nil, let m = s.text.firstMatch(of: /^no template "([^"]*)" in [^;]*; use one of (.*)$/) {
                let options = m.2.components(separatedBy: ", ")
                if let near = nearMatch(String(m.1), in: options), p.line >= 1, p.line <= lines.count {
                    card.fixLine = lines[p.line - 1].replacingOccurrences(of: String(m.1), with: near)
                    card.buttons.append(DeckCardButton(id: "fix", label: "Use \(near)"))
                }
            } else if s.slot == nil, let m = s.text.firstMatch(of: /^no slot "([^"]*)"; \S+ has (.*)$/) {
                let options = m.2.components(separatedBy: ", ")
                if let near = nearMatch(String(m.1), in: options), p.line >= 1, p.line <= lines.count {
                    card.fixLine = lines[p.line - 1].replacingOccurrences(of: String(m.1), with: near)
                    card.buttons.append(DeckCardButton(id: "fix", label: "Use \(near)"))
                }
            } else if s.slot == nil, let m = s.text.firstMatch(of: /^renamed "([^"]*)" to "([^"]*)"/), p.line >= 1, p.line <= lines.count {
                card.fixLine = lines[p.line - 1].replacingOccurrences(of: String(m.1), with: String(m.2))
                card.buttons.append(DeckCardButton(id: "fix", label: "Use \(m.2)"))
            }
            if card.buttons.isEmpty {
                card.buttons = [DeckCardButton(id: "goto", label: "Go to Line"), DeckCardButton(id: "send", label: "Send to Claude")]
            }
            out.append(card)
        }
        return out
    }

    /// The deck text with line `line` (1-based) replaced.
    public static func replacing(line: Int, with new: String, in text: String) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard line >= 1, line <= lines.count else { return nil }
        lines[line - 1] = new
        return lines.joined(separator: "\n")
    }

    /// What Send to Claude puts in the prompt for a problem.
    public static func request(for card: DeckCard, deck: String) -> String {
        let at = card.slot.map { "slide \(card.slide) (\($0))" } ?? "slide \(card.slide)"
        return "\(deck) line \(card.line), \(at): \(card.message)\nFix it, then run `duo2 deck check \(deck)`."
    }

    // MARK: Content moved to the notes (DL-281)

    static let notPlaced = "Not placed after changing to "

    /// A card for each slide whose notes hold "Not placed after changing to <template>: <slots>".
    public static func notesCards(text: String, pack: Deck.Pack?) -> [DeckCard] {
        let parsed = Deck.parse(text)
        var out: [DeckCard] = []
        for (i, s) in parsed.slides.enumerated() {
            guard let k = s.notes.firstIndex(where: { $0.hasPrefix(notPlaced) }), let nl = s.notesLine else { continue }
            let head = s.notes[k]
            let tname = head.dropFirst(notPlaced.count).prefix { $0 != ":" }
            let content = s.notes[(k + 1)...].filter { !$0.isEmpty && !$0.hasSuffix(":") }
            let n = max(1, content.count)
            var buttons: [DeckCardButton] = []
            if let t = pack?.template(s.template) {
                for spec in t.slots where spec.kind == "bullets" { buttons.append(DeckCardButton(id: "move:\(spec.name)", label: "Move to \(spec.name)")) }
            }
            buttons += [DeckCardButton(id: "split", label: "Split with Claude"), DeckCardButton(id: "undo", label: "Undo Change")]
            out.append(DeckCard(kind: .notesMove, slide: i + 1, template: s.template, slot: nil,
                                message: "\(n) point\(n == 1 ? "" : "s") moved to the notes when this became \(tname).",
                                line: nl + 1 + k, buttons: buttons))
        }
        return out
    }

    /// Moves the content "Not placed after changing to …" left in slide `n`'s notes into the end of
    /// bullets slot `slot`, and removes it from the notes (the callout too when nothing else is in it).
    public static func moveNotes(source: String, slide n: Int, to slot: String) -> String? {
        let parsed = Deck.parse(source)
        guard n >= 1, n <= parsed.slides.count else { return nil }
        let s = parsed.slides[n - 1]
        guard let nl = s.notesLine, let k = s.notes.firstIndex(where: { $0.hasPrefix(notPlaced) }), let target = s.slot(slot) else { return nil }
        var lines = source.components(separatedBy: "\n")
        let first = nl + 1 + k, last = nl + s.notes.count   // 1-based, inclusive
        guard last <= lines.count, first <= last else { return nil }
        let moved = s.notes[(k + 1)...].filter { !$0.isEmpty && !$0.hasSuffix(":") }
            .map { $0.hasPrefix("- ") || $0.hasPrefix("* ") ? $0 : "- \($0)" }
        let others = s.notes[..<k].filter { !$0.isEmpty }
        // The notes block goes (the callout header and its blank line too, when nothing else is in it).
        var cutFrom = first, cutTo = last
        if others.isEmpty {
            cutFrom = nl
            if cutFrom > 1, lines[cutFrom - 2].trimmingCharacters(in: .whitespaces).isEmpty { cutFrom -= 1 }
        }
        let insertAt = max(target.blockEnd, target.line)   // after this line
        // Remove the later block first, so the slot's line numbers hold.
        if insertAt < cutFrom {
            lines.removeSubrange((cutFrom - 1)...(cutTo - 1))
            lines.insert(contentsOf: moved, at: insertAt)
        } else {
            lines.insert(contentsOf: moved, at: insertAt)
            let shift = moved.count
            lines.removeSubrange((cutFrom - 1 + shift)...(cutTo - 1 + shift))
        }
        return lines.joined(separator: "\n")
    }

    /// What Split with Claude puts in the prompt.
    public static func splitRequest(slide n: Int, template: String, deck: String) -> String {
        "In \(deck), slide \(n) became \(template) and some of its content went to the speaker notes under \"Not placed after changing to \(template)\". Split the slide so nothing is lost: insert a slide of another template after it (`duo2 deck insert \(deck) <template> --after \(n)`), move the notes' content into it, then run `duo2 deck check \(deck)`."
    }

    // MARK: Pins and comments (P3-1)

    /// A pin for each anchor holding an open thread, with its comments counted. A closed thread leaves none.
    public static func pins(text: String, anchors: [AnchorRange]) -> [DeckPin] {
        let parsed = Review.parse(text)
        if parsed.threads.isEmpty { return [] }
        let ns = text as NSString
        var by: [String: (count: Int, thread: String)] = [:]
        var order: [String] = []
        for t in parsed.threads where !t.closed {
            var line = 1, i = 0
            let end = min(t.range.location, ns.length)
            while i < end { if ns.character(at: i) == 10 { line += 1 }; i += 1 }
            guard let hit = anchors.filter({ $0.contains(line: line) }).min(by: { ($0.lastLine - $0.firstLine) < ($1.lastLine - $1.firstLine) }) else { continue }
            if let e = by[hit.anchor] { by[hit.anchor] = (e.count + t.comments.count, e.thread) }
            else { by[hit.anchor] = (t.comments.count, t.id); order.append(hit.anchor) }
        }
        return order.compactMap { a in
            guard let (n, slot) = DeckPreviewBuild.parse(anchor: a), let e = by[a] else { return nil }
            return DeckPin(anchor: a, slide: n, slot: slot, count: e.count, thread: e.thread)
        }
    }

    /// Adds a signed Review comment on its own line at the end of the anchor's lines: a slot's end, or
    /// a slide's title line (or its marker line). Returns the new text and the comment's id.
    public static func addComment(source: String, anchor: String, author: String, date: String, body: String) throws -> (text: String, id: String, line: Int) {
        guard let (n, slot) = DeckPreviewBuild.parse(anchor: anchor) else { throw Deck.Failure(description: "\(anchor) isn't a slide or slot: use <slide> or <slide>/<slot>") }
        let parsed = Deck.parse(source)
        guard n >= 1, n <= parsed.slides.count else { throw Deck.Failure(description: "the deck has \(parsed.slides.count) slides; no slide \(n)") }
        let s = parsed.slides[n - 1]
        var after: Int
        if let slot {
            guard let sl = s.slots.first(where: { $0.name == slot }) else {
                throw Deck.Failure(description: "slide \(n) has no slot \"\(slot)\": it has \(s.slots.map(\.name).filter { !$0.hasPrefix("_") }.joined(separator: ", "))")
            }
            after = max(sl.blockEnd, sl.line)
        } else {
            after = s.slot("title")?.line ?? s.line
        }
        var lines = source.components(separatedBy: "\n")
        after = min(after, lines.count)
        let id = Review.nextID("c", in: source)
        lines.insert(Review.comment(author: author, date: date, id: id, text: body), at: after)
        return (lines.joined(separator: "\n"), id, after + 1)
    }

    /// `duo2 deck comments`: the open and closed threads by slide and slot.
    public static func commentLines(text: String) -> [String] {
        let parsed = Review.parse(text)
        let anchors = DeckPreviewBuild.anchors(Deck.parse(text).slides)
        let ns = text as NSString
        var out: [String] = []
        for t in parsed.threads {
            var line = 1, i = 0
            let end = min(t.range.location, ns.length)
            while i < end { if ns.character(at: i) == 10 { line += 1 }; i += 1 }
            let hit = anchors.filter { $0.contains(line: line) }.min { ($0.lastLine - $0.firstLine) < ($1.lastLine - $1.firstLine) }
            let head = t.root
            out.append("\(hit?.anchor ?? "deck") · #\(t.id) [\(t.closed ? "closed" : "open")] \(head?.author.map { "@\($0)" } ?? "unsigned"): \(head?.text ?? "") (line \(line))")
        }
        return out
    }
}
