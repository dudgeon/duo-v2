import AppKit
import DuoSearch

// The List's filter (DL-142 (4), home-evolution `filter`, F-170): Duo's default search, hybrid by
// meaning and by words, over each session's title and what was said in it (search's session index),
// fused with a word match on what Duo holds beside it: the project, its folder, the task, the
// question a session is waiting on. One ranking, best first, one row per session.

extension SessionList {
    /// A session that matched, and the passage that did: who and when first (`question`, `Claude, 6m`,
    /// `you, 2d`), then the words, its matched ones in `bold`.
    public struct Match: Identifiable, Sendable, Equatable {
        public var row: Row
        public var who: String?
        public var passage: String?
        public var id: String { row.id }
    }

    /// A session hit from search's index, as the filter uses it.
    public struct SearchMatch: Sendable, Equatable {
        public var sessionId: String
        public var snippet: String
        public init(sessionId: String, snippet: String) { self.sessionId = sessionId; self.snippet = snippet }
    }

    /// The words of a filter that count (as search's own: three letters or more, or a quoted phrase),
    /// lightly stemmed so `saved cards` finds `save a card`: five letters or more lose their last.
    public static func words(_ text: String) -> [String] {
        AppModel.queryWords(text).map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
            .map { $0.count >= 5 && !$0.contains(" ") ? String($0.dropLast()) : $0 }
    }

    /// How many of the words start a word in a row's names: its title, project, folder (and the folder
    /// it's in), task, and the question it waits on. Words too common to mean anything don't count.
    static func nameHits(_ r: Row, words: [String], in f: Fixture) -> Int {
        let path = f.projects.first { $0.name == r.session.project }?.path ?? ""
        let folders = path.split(separator: "/").suffix(2).joined(separator: " ")
        let hay = [r.session.name, r.project, r.session.project, folders, r.task ?? "", r.session.question ?? ""]
            .joined(separator: " ").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let tokens = hay.split { !$0.isLetter && !$0.isNumber }
        return words.filter { w in !stopWords.contains(w) && (w.contains(" ") ? hay.contains(w) : tokens.contains { $0.hasPrefix(w) }) }.count
    }

    static let stopWords: Set<String> = ["the", "and", "with", "for", "why", "what", "how", "who", "when", "about", "from", "that",
                                         "this", "into", "are", "was", "were", "you", "your", "our", "its", "but", "not", "all", "any"]

    /// Every session the filter can show: needs you too (a filter is a search), the sections, Earlier.
    var filterable: [Row] { needsYou + sections.flatMap(\.rows) + earlier }

    /// Fuses the two rankings by reciprocal rank, as search fuses meaning and words (F-36): search's
    /// session hits in its order, and the word match on names (more words first, then the list's
    /// order). A session in both ranks above one in either.
    public func matches(_ text: String, search: [SearchMatch], in f: Fixture) -> [Match] {
        let words = Self.words(text)
        let rows = filterable
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        var score: [String: Double] = [:]
        var snippet: [String: String] = [:]
        var seen = Set<String>()
        var rank = 0
        for h in search {
            guard let r = rows.first(where: { $0.session.sessionId == h.sessionId }), !seen.contains(r.id) else { continue }
            seen.insert(r.id)
            score[r.id, default: 0] += 1 / (SearchIndex.rrfK + Double(rank))
            snippet[r.id] = h.snippet
            rank += 1
        }
        let named = rows.enumerated().map { (i: $0.offset, r: $0.element, n: Self.nameHits($0.element, words: words, in: f)) }
            .filter { $0.n > 0 }
            .sorted { $0.n != $1.n ? $0.n > $1.n : $0.i < $1.i }
        for (k, x) in named.enumerated() { score[x.r.id, default: 0] += 1 / (SearchIndex.rrfK + Double(k)) }
        let order = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) })
        return rows.filter { score[$0.id] != nil }
            .sorted { a, b in score[a.id]! != score[b.id]! ? score[a.id]! > score[b.id]! : order[a.id]! < order[b.id]! }
            .map { r in Self.passage(r, snippet: snippet[r.id], words: words) }
    }

    /// The line under a match: the question it waits on when that matched, else the turn search
    /// found (Claude's part when the words are there, else what you said), else none.
    static func passage(_ r: Row, snippet: String?, words: [String]) -> Match {
        func has(_ s: String) -> Bool {
            let t = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return words.contains { t.contains($0) }
        }
        if let q = r.session.question, has(q) { return Match(row: r, who: "question", passage: oneLine(q)) }
        guard let snippet else { return Match(row: r, who: nil, passage: nil) }
        let parts = snippet.components(separatedBy: "Claude: ")
        let you = parts[0].replacingOccurrences(of: "You: ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let claude = parts.count > 1 ? parts[1...].joined(separator: "Claude: ").trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let when = r.session.wait.map { ", \($0)" } ?? ""
        if let claude, has(claude) || you.isEmpty { return Match(row: r, who: "Claude\(when)", passage: oneLine(claude)) }
        return Match(row: r, who: "you\(when)", passage: oneLine(you))
    }

    static func oneLine(_ s: String) -> String {
        s.split(whereSeparator: \.isNewline).joined(separator: " ").replacingOccurrences(of: "  ", with: " ")
    }
}

@MainActor
extension AppModel {
    /// Each change of the List's filter: the word match at once, then search's answer fused in.
    func listFilterChanged(answered: (@MainActor ([SessionList.Match]) -> Void)? = nil) {
        listGeneration += 1
        let gen = listGeneration
        let text = listFilter.trimmingCharacters(in: .whitespaces)
        let list = sessionList
        let f = fixture
        listSelection = nil
        guard !text.isEmpty else { listMatches = []; listSearching = false; answered?([]); return }
        listMatches = list.matches(text, search: [], in: f)
        // Fixture mode has no index to ask; live sessions are in search's (F-170).
        guard terminalsMode == .live, f.sessions.contains(where: { $0.sessionId != nil }) else { listSearching = false; answered?(listMatches); return }
        listSearching = true
        var query = SearchQuery(text: text)
        query.kinds = ["session"]
        query.limit = 60
        query.passagesPerItem = 1
        query.exactOnly = SearchIndex.literal(in: text) != nil
        Task.detached(priority: .userInitiated) {
            let hits = (try? SearchIndex(readOnly: true).search(query, embedder: query.exactOnly ? nil : try? Embedder(use: .query))) ?? []
            let found = hits.map { SessionList.SearchMatch(sessionId: URL(fileURLWithPath: $0.path).deletingPathExtension().lastPathComponent, snippet: $0.snippet) }
            await MainActor.run {
                guard gen == self.listGeneration else { return }
                self.listMatches = list.matches(text, search: found, in: f)
                self.listSearching = false
                answered?(self.listMatches)
            }
        }
    }

    /// The link under "Nothing in your sessions is about …": search everything with the same words.
    public func searchFromListFilter() {
        let text = listFilter
        openSearch()
        searchQueryChanged(text)
    }

    /// ⌘F in the List: its filter takes the keyboard. SwiftUI's field is an NSTextField underneath.
    public func focusListFilter() {
        guard let w = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.title == "Duo" }), let root = w.contentView else { return }
        func find(_ v: NSView) -> NSTextField? {
            if let t = v as? NSTextField, t.placeholderString == "Filter sessions" { return t }
            for s in v.subviews { if let t = find(s) { return t } }
            return nil
        }
        if let field = find(root) { w.makeFirstResponder(field) }
    }
}
