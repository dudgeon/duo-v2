import Foundation
import Observation

/// One row in the search modal (search-handoff §3): a content result (file, session, memory) or,
/// first, a "Go to" name match (project, group, session; DL-80).
public struct SearchItem: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case file, session, memory, project, group }

    public struct Passage: Equatable, Sendable {
        public var location: String     // "L71–73"
        public var heading: String?
        public var snippet: String
    }

    /// A session's matched turn and the turns either side, for the preview.
    public struct Turn: Equatable, Sendable {
        public var number: Int
        public var you: String?
        public var claude: String?
        public var matched: Bool
    }

    public var id: String
    public var kind: Kind
    public var goTo = false
    public var project: String?
    public var unfiled = false
    public var title: String
    public var location: String = ""     // "L40–58", "turn 6"
    public var matchedBy: [String] = []  // meaning, words, exact
    public var date: String?
    public var snippet: String?
    public var matchedWords: [String] = []
    public var passages: [Passage] = []
    public var alsoIn: [String] = []
    public var archived = false
    public var turns: [Turn] = []
    // Go to rows
    public var state: SessionState?
    public var wait: String?
    public var groupSessions: Int?
    public var detail: String?           // the project's health line, for a project or group preview
    // Where it lives, for the actions
    public var path: String?             // a file's path in its project, or a session's transcript
    public var startLine = 0, endLine = 0
    public var sessionId: String?

    public var isExact: Bool { matchedBy.contains("exact") }
    public var byMeaningOnly: Bool { matchedBy == ["meaning"] }
    public var isContent: Bool { !goTo }
}

/// What a row's Tab menu offers (search-handoff §4, DL-79 chords). `nil` chord: none.
public struct SearchAction: Identifiable, Equatable, Sendable {
    public enum ID: String, Sendable {
        case open, resume, readOnly, fork, splitView, goToProject, sendToClaude, findSimilar, showPassages
        case copyPath, copyPassage, copyLink, copyResume, reveal, goTo
    }
    public var id: ID
    public var title: String
    public var chord: String?
    public var group: Int
    public var enabled = true
}

public enum SearchTime: String, CaseIterable, Sendable {
    case any = "Any time", day = "Past day", week = "Past week", month = "Past month", year = "Past year"
    var seconds: TimeInterval? {
        switch self { case .any: nil; case .day: 86_400; case .week: 7 * 86_400; case .month: 31 * 86_400; case .year: 366 * 86_400 }
    }
}

/// The search modal's state (DL-76, DL-79, DL-80). One modal, opened by ⇧⌘A; names first, then content.
@Observable
@MainActor
public final class SearchUI {
    public enum Phase: Equatable, Sendable {
        case empty                     // nothing typed: recent searches and help
        case results                   // rows to show
        case none(String, Int)         // nothing matches: the sentence, results without the filters
        case rebuilding(String)        // the index is being rebuilt: why and how long
        case unreadable(String)        // the index can't be read: the error, for Show details
    }

    public var isOpen = false
    public var query = ""
    public var phase: Phase = .empty
    public var items: [SearchItem] = []
    public var selected = 0
    public var multi: Set<Int> = []
    public var menuOpen = false
    public var menuIndex = 0
    // Filters (Q5: pop-ups and a checkbox, no typed syntax)
    public var scopeProject: String?            // nil: all projects
    public var kind: SearchItem.Kind?           // nil: any kind
    public var time: SearchTime = .any
    public var includeArchived = false
    public var exact = false
    /// Find similar: the source, and the query to go back to.
    public var similarTo: SearchItem?
    public var similarReturnsTo: String?
    // Lines around the results
    public var coverage: String?                // shown only while coverage is incomplete
    public var firstRun: (String, String)?      // headline, detail
    public var stillSearching: String?          // "Searching sessions…"
    public var moreElsewhere = 0                // "2 more in other projects" when narrowed
    public var recents: [(query: String, when: String)] = []
    /// Where the menu's Send to Claude goes (DL-69, DL-79 f), named in the item.
    public var sendTargetName: String?
    /// The project the modal opened in, for the narrow hint and the boost.
    public var openedIn: String?

    /// The empty state's highlighted recent search (↑↓ move through them).
    public var recentSelected: Int?
    /// `New project "…"` ends the list when no project has that name (LR-25, DL-80).
    public var newProjectName: String?
    /// Ask the field to take the keyboard (on open, on ⇧⌘A again).
    public var wantsFocus = false
    /// Answers to older keystrokes are dropped.
    public var generation = 0
    /// Fixture mode: the index state and coverage line a target shows, instead of the real index.
    public var forcedIndexState: IndexState?
    public var fixtureCoverage: String?

    public enum IndexState: Sendable { case ok, rebuilding(String), unreadable(String) }

    public init() {}

    public var selectedItem: SearchItem? { items.indices.contains(selected) ? items[selected] : nil }
    public var selectedItems: [SearchItem] {
        multi.count > 1 ? multi.sorted().compactMap { items.indices.contains($0) ? items[$0] : nil } : selectedItem.map { [$0] } ?? []
    }
    public var filtersSet: Bool { scopeProject != nil || kind != nil || time != .any }

    /// The Tab menu for a row (search-handoff §4, with ⌘D for Send to Claude: DL-79 e).
    public func actions(for item: SearchItem) -> [SearchAction] {
        let send = "Send to Claude" + (sendTargetName.map { " in \($0)" } ?? "")
        switch item.kind {
        case .file, .memory:
            return [
                .init(id: .open, title: "Open", chord: "↩", group: 0),
                .init(id: .splitView, title: "Open in split view", chord: "⌥⌘↩", group: 0, enabled: false),
                .init(id: .goToProject, title: "Go to \(item.project ?? "the project")", chord: nil, group: 0, enabled: item.project != nil),
                .init(id: .sendToClaude, title: send, chord: "⌘D", group: 1, enabled: sendTargetName != nil),
                .init(id: .findSimilar, title: "Find similar", chord: nil, group: 1),
                .init(id: .showPassages, title: "Show all \(max(1, item.passages.count)) passages", chord: nil, group: 1),
                .init(id: .copyPath, title: "Copy path", chord: "⌥⌘C", group: 2),
                .init(id: .copyPassage, title: "Copy passage", chord: "⇧⌘C", group: 2),
                .init(id: .copyLink, title: "Copy Markdown link", chord: nil, group: 2),
                .init(id: .reveal, title: "Reveal in Finder", chord: "⌘R", group: 3),
            ]
        case .session:
            if item.goTo { return [.init(id: .goTo, title: "Go to \(item.title)", chord: "↩", group: 0)] }
            let turn = item.location.isEmpty ? "" : " at \(item.location)"
            return [
                .init(id: .resume, title: "Resume", chord: "↩", group: 0),
                .init(id: .readOnly, title: "Open read-only\(turn)", chord: "⇧⌘↩", group: 0),
                .init(id: .fork, title: "Resume as a fork", chord: nil, group: 0),
                .init(id: .splitView, title: "Open in split view", chord: "⌥⌘↩", group: 0, enabled: false),
                .init(id: .goToProject, title: "Go to \(item.project ?? "the project")", chord: nil, group: 0, enabled: item.project != nil),
                .init(id: .sendToClaude, title: send, chord: "⌘D", group: 1, enabled: sendTargetName != nil),
                .init(id: .findSimilar, title: "Find similar", chord: nil, group: 1),
                .init(id: .copyPassage, title: "Copy passage", chord: "⇧⌘C", group: 2),
                .init(id: .copyResume, title: "Copy resume command", chord: "⌥⌘C", group: 2),
            ]
        case .project, .group:
            return [.init(id: .goTo, title: "Go to \(item.title)", chord: "↩", group: 0)]
        }
    }

    /// What Return will do, for the footer (search-handoff §3).
    public var returnLabel: String {
        switch phase {
        case .empty: return ""
        case .none: return "Clear filters"
        case .unreadable: return "Rebuild the index"
        case .rebuilding: return ""
        case .results: break
        }
        if multi.count > 1 { return "Send \(multi.count) to Claude" + (sendTargetName.map { " in \($0)" } ?? "") }
        guard let i = selectedItem else { return "" }
        if i.goTo {
            return i.kind == .project ? "Go to \(i.title)" : "Go to \(i.title)" + (i.project.map { " in \($0)" } ?? "")
        }
        switch i.kind {
        case .session: return "Resume" + (i.project.map { " in \($0)" } ?? "")
        default: return "Open" + (i.project.map { " in \($0)" } ?? "")
        }
    }

    // MARK: Moving

    public func move(_ by: Int, extend: Bool = false) {
        guard !items.isEmpty else { return }
        let next = min(max(0, selected + by), items.count - 1)
        if extend {
            if multi.isEmpty { multi = [selected] }
            if items[next].isContent { multi.insert(next) }
        } else { multi = [] }
        selected = next
    }

    public func reset() {
        query = ""; phase = .empty; items = []; selected = 0; multi = []; menuOpen = false; menuIndex = 0
        scopeProject = nil; kind = nil; time = .any; includeArchived = false; exact = false
        similarTo = nil; similarReturnsTo = nil; stillSearching = nil; moreElsewhere = 0; firstRun = nil
    }
}
