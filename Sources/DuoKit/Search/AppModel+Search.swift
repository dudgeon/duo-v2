import AppKit
import DuoSearch
import Foundation

/// Search's behaviour (search-handoff §4–5; DL-76, DL-79, DL-80): open and close, keys, filters,
/// the live query (names from the workspace, content from the index), and the actions.
extension AppModel {
    // MARK: Opening

    /// ⇧⌘A. Inside a project with the modal open, it narrows to the project and back (DL-79 a).
    public func openSearch() {
        let s = search
        if s.isOpen {
            if let p = s.openedIn { setSearchScope(s.scopeProject == p ? nil : p) }
            s.wantsFocus = true
            return
        }
        s.reset()
        s.openedIn = altitude.isAllProjects ? nil : currentProject?.name
        s.sendTargetName = (try? sendTarget.get()).flatMap { t in fixture.sessions.first { $0.tabKey == t.key }?.name }
        s.recents = SearchRecents.load().map { ($0.query, SearchRecents.age($0.at)) }
        s.coverage = liveSearchCoverage()
        s.isOpen = true
        s.wantsFocus = true
    }

    public func closeSearch() {
        rememberSearch()
        search.isOpen = false
        search.menuOpen = false
        visibleTerminal.map { t in t.view.window?.makeFirstResponder(t.view) }
    }

    // MARK: Keys

    @discardableResult
    public func searchKey(_ key: SearchKey) -> Bool {
        let s = search
        if s.menuOpen, let item = s.selectedItem {
            let actions = s.actions(for: item)
            switch key {
            case .up: s.menuIndex = max(0, s.menuIndex - 1); return true
            case .down: s.menuIndex = min(actions.count - 1, s.menuIndex + 1); return true
            case .returnKey: if actions.indices.contains(s.menuIndex) { runSearchAction(actions[s.menuIndex].id) }; return true
            case .escape, .tab: s.menuOpen = false; return true
            default: break
            }
        }
        switch key {
        case .up:
            if case .empty = s.phase { s.recentSelected = max(0, (s.recentSelected ?? 0) - 1) } else { s.move(-1) }
        case .down:
            if case .empty = s.phase { s.recentSelected = min(s.recents.count - 1, (s.recentSelected.map { $0 + 1 }) ?? 0) } else { s.move(1) }
        case .extendUp: s.move(-1, extend: true)
        case .extendDown: s.move(1, extend: true)
        case .returnKey: searchReturn()
        case .tab:
            guard case .results = s.phase, s.selectedItem != nil else { return true }
            s.menuIndex = 0; s.menuOpen = true
        case .backTab: return false  // the filters are pop-ups after the field in the key loop
        case .escape:
            // Esc steps back: menu, then find similar, then close (DL-79 h).
            if s.menuOpen { s.menuOpen = false }
            else if let back = s.similarReturnsTo { s.similarTo = nil; s.similarReturnsTo = nil; searchQueryChanged(back) }
            else { closeSearch() }
        case .toggleExact: toggleExact()
        case .narrow: openSearch()
        case .chord(let id):
            guard let item = s.selectedItem, s.actions(for: item).contains(where: { $0.id == id && $0.enabled }) else { return id == .sendToClaude }
            runSearchAction(id)
        }
        if s.isOpen { loadSelectedTurns() }
        return true
    }

    func searchReturn() {
        let s = search
        switch s.phase {
        case .empty:
            if let i = s.recentSelected, s.recents.indices.contains(i) { runRecent(s.recents[i].query) }
        case .none: clearSearchFilters()
        case .unreadable: rebuildSearchIndex()
        case .rebuilding: break
        case .results:
            if s.multi.count > 1 { runSearchAction(.sendToClaude); return }
            guard let item = s.selectedItem else { return }
            runSearchAction(s.actions(for: item).first?.id ?? .open)
        }
    }

    // MARK: Filters

    public var searchProjectNames: [String] { fixture.projects.map(\.name).sorted() }

    public func setSearchScope(_ p: String?) { search.scopeProject = p; requery() }
    public func setSearchKind(_ k: SearchItem.Kind?) { search.kind = k; requery() }
    public func setSearchTime(_ t: SearchTime) { search.time = t; requery() }
    public func setIncludeArchived(_ on: Bool) { search.includeArchived = on; requery() }
    public func toggleExact() { search.exact.toggle(); requery() }
    public func clearSearchFilters() {
        search.scopeProject = nil; search.kind = nil; search.time = .any; requery()
    }

    public func selectSearchRow(_ i: Int) {
        search.menuOpen = false
        if NSEvent.modifierFlags.contains(.shift), search.items.indices.contains(i), search.items[i].isContent {
            if search.multi.isEmpty { search.multi = [search.selected] }
            search.multi.insert(i)
        } else { search.multi = [] }
        search.selected = i
        loadSelectedTurns()
    }

    public func runRecent(_ q: String) { searchQueryChanged(q) }

    func requery() { searchQueryChanged(search.query) }

    // MARK: The query

    /// Every keystroke: names now (no index needed, DL-80), content once the index answers.
    public func searchQueryChanged(_ text: String) {
        let s = search
        s.query = text
        s.menuOpen = false
        s.multi = []
        let q = text.trimmingCharacters(in: .whitespaces)
        if q.isEmpty, s.similarTo == nil { s.phase = .empty; s.items = []; s.newProjectName = nil; s.recentSelected = nil; return }
        // Exact turns on by itself for quoted phrases and identifier-like input (search-exact).
        if !s.exact, SearchIndex.literal(in: q) != nil || RecentSearches.looksLikeIdentifier(q) { s.exact = true }
        let names = nameMatches(q)
        s.newProjectName = fixture.projects.contains(where: { $0.name.caseInsensitiveCompare(q) == .orderedSame }) || q.count < 2 ? nil : q
        s.generation += 1
        let gen = s.generation
        let state = indexState()
        switch state {
        case .rebuilding(let why): s.phase = names.isEmpty ? .rebuilding(why) : .results; s.items = names; s.selected = 0; return
        case .unreadable(let e): s.phase = names.isEmpty ? .unreadable(e) : .results; s.items = names; s.selected = 0; return
        default: break
        }
        s.items = names
        s.phase = .results
        s.selected = 0
        s.stillSearching = "Searching…"
        var query = SearchQuery(text: q)
        query.projects = s.scopeProject.map { [$0] } ?? []
        query.kinds = s.kind.map { [$0.rawValue] } ?? []
        query.currentProject = s.openedIn
        query.exactOnly = s.exact
        query.limit = 30
        query.passagesPerItem = 4
        query.similarTo = s.similarTo?.path
        let includeArchived = s.includeArchived, time = s.time
        Task.detached(priority: .userInitiated) {
            // Query and build the rows off the main thread: files are read for passage headings.
            let rows = Result { () throws -> [SearchItem] in
                let index = try SearchIndex(readOnly: true)
                let embedder = query.exactOnly || query.similarTo != nil ? nil : try? Embedder(use: .query)
                return Self.rows(try index.search(query, embedder: embedder), words: q, includeArchived: includeArchived, time: time)
            }
            await MainActor.run { self.searchAnswered(rows, gen: gen, words: q) }
        }
    }

    private func searchAnswered(_ r: Result<[SearchItem], Error>, gen: Int, words: String) {
        let s = search
        guard gen == s.generation else { return }
        s.stillSearching = nil
        let names = s.items.filter(\.goTo)
        switch r {
        case .failure(let e):
            if names.isEmpty { s.phase = .unreadable("\(e)") }
        case .success(let content):
            s.items = names + content
            s.selected = min(s.selected, max(0, s.items.count - 1))
            if s.items.isEmpty {
                s.phase = .none(noneSentence(words), 0)
                if s.filtersSet { countWithoutFilters(words, gen: gen) }
            } else { s.phase = .results }
        }
        loadSelectedTurns()
    }

    /// One row per item (search-handoff §3): later hits on the same file or session become its passages.
    nonisolated public static func rows(_ hits: [SearchHit], words: String, includeArchived: Bool, time: SearchTime) -> [SearchItem] {
        let cutoff = time.seconds.map { Date().addingTimeInterval(-$0) }
        var grouped: [(SearchHit, [SearchHit])] = []
        for h in hits where includeArchived || !h.archived {
            if let i = grouped.firstIndex(where: { $0.0.path == h.path && $0.0.kind == h.kind }) {
                if !grouped[i].1.contains(where: { $0.startLine == h.startLine }) && grouped[i].0.startLine != h.startLine { grouped[i].1.append(h) }
            } else { grouped.append((h, [])) }
        }
        var content = grouped.map { item(from: $0.0, more: $0.1, words: words) }
        if let cutoff { content = content.filter { ($0.modified ?? .distantFuture) >= cutoff } }
        return content.map(\.item)
    }

    /// A session's turns either side of the match, read from its transcript when it's selected
    /// (transcripts can be tens of MB, so never for every row).
    func loadSelectedTurns() {
        guard let item = search.selectedItem, item.kind == .session, !item.goTo, let path = item.path,
              !item.turns.contains(where: { !$0.matched }) else { return }
        let n = Int(item.location.split(separator: " ").last ?? "") ?? 0
        let id = item.id
        Task.detached(priority: .userInitiated) {
            let turns = SessionSource.read(path).turns.filter { abs($0.index - n) <= 1 }.map { t -> SearchItem.Turn in
                let parts = t.text.components(separatedBy: "\n\nClaude: ")
                let you = parts.first.map { $0.hasPrefix("You: ") ? String($0.dropFirst(5)) : $0 }
                return .init(number: t.index, you: you.map { String($0.prefix(400)) }, claude: parts.count > 1 ? String(parts[1].prefix(600)) : nil, matched: t.index == n)
            }
            await MainActor.run {
                guard !turns.isEmpty, let i = self.search.items.firstIndex(where: { $0.id == id }) else { return }
                self.search.items[i].turns = turns
            }
        }
    }

    /// search-none: "3 results without these filters." The same query, no project, kind or date.
    private func countWithoutFilters(_ q: String, gen: Int) {
        var query = SearchQuery(text: q)
        query.exactOnly = search.exact
        query.limit = 50
        Task.detached(priority: .utility) {
            let n = (try? SearchIndex(readOnly: true).search(query, embedder: query.exactOnly ? nil : try? Embedder(use: .query)))?.count ?? 0
            await MainActor.run {
                guard gen == self.search.generation, case .none(let sentence, _) = self.search.phase else { return }
                self.search.phase = .none(sentence, n)
            }
        }
    }

    private func noneSentence(_ raw: String) -> String {
        let q = SearchIndex.literal(in: raw) ?? raw
        let s = search
        let what = s.kind.map { $0 == .memory ? "in memory" : $0 == .file ? "in files" : "in sessions" } ?? ""
        let when = s.time == .any ? "" : "from the \(s.time.rawValue.lowercased().replacingOccurrences(of: "past ", with: "past "))"
        let scope = s.scopeProject.map { "in \($0)" } ?? ""
        let middle = [what, scope, when].filter { !$0.isEmpty }.joined(separator: " ")
        return middle.isEmpty ? "Nothing matches “\(q)”." : "Nothing \(middle) matches “\(q)”."
    }

    nonisolated static func item(from h: SearchHit, more: [SearchHit] = [], words: String) -> (item: SearchItem, modified: Date?) {
        let unfiled = h.project == SearchIndex.unfiled
        let attrs = try? FileManager.default.attributesOfItem(atPath: h.path)
        let modified = attrs?[.modificationDate] as? Date
        var i = SearchItem(id: "\(h.kind):\(h.path):\(h.startLine)", kind: SearchItem.Kind(rawValue: h.kind) ?? .file,
                           project: unfiled ? nil : h.project, unfiled: unfiled, title: h.title)
        i.location = Self.dashed(h.kind == "file" && h.locator.isEmpty ? "L\(h.startLine)–\(h.endLine)" : h.locator)
        i.matchedBy = h.matched
        i.date = modified.map { SearchRecents.age($0) }
        i.snippet = h.snippet
        i.matchedWords = Self.queryWords(words)
        let lines = h.kind == "file" ? (try? String(contentsOfFile: h.path, encoding: .utf8))?.components(separatedBy: "\n") : nil
        func heading(_ line: Int) -> String? {
            guard let lines, line > 0 else { return nil }
            for n in stride(from: min(line, lines.count) - 1, through: 0, by: -1) where lines[n].hasPrefix("#") {
                return lines[n].drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            }
            return nil
        }
        i.passages = ([h] + more).map { .init(location: Self.dashed($0.locator.isEmpty ? "L\($0.startLine)" : $0.locator), heading: heading($0.startLine), snippet: $0.snippet) }
        i.alsoIn = h.alsoIn
        i.archived = h.archived
        i.path = h.path
        i.startLine = h.startLine; i.endLine = h.endLine
        if h.kind == "session" {
            i.sessionId = URL(fileURLWithPath: h.path).deletingPathExtension().lastPathComponent
            // The matched turn now; the ones either side load when the row is selected (loadSelectedTurns).
            let n = Int(h.locator.split(separator: " ").last ?? "") ?? 0
            let parts = h.snippet.components(separatedBy: " Claude: ")
            i.turns = [.init(number: n, you: parts.count > 1 ? parts[0].replacingOccurrences(of: "You: ", with: "") : nil,
                             claude: parts.count > 1 ? parts[1] : h.snippet, matched: true)]
        }
        return (i, modified)
    }

    /// `L40-58` → `L40–58`, as the design writes ranges.
    nonisolated public static func dashed(_ s: String) -> String { s.replacingOccurrences(of: "-", with: "–") }

    nonisolated public static func queryWords(_ q: String) -> [String] {
        if let lit = SearchIndex.literal(in: q) { return [lit] }
        return q.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" && $0 != "-" }).map(String.init).filter { $0.count >= 3 }
    }

    /// The "Go to" block (DL-80): projects, groups, then sessions whose names contain the query.
    public func nameMatches(_ q: String) -> [SearchItem] {
        guard search.similarTo == nil, !search.exact || !q.contains(" ") else { return [] }
        let needle = q.lowercased()
        var out: [SearchItem] = []
        for p in fixture.projects where p.name.lowercased().contains(needle) && (search.scopeProject == nil || search.scopeProject == p.name) {
            let top = fixture.sessions(inProject: p.name).map(\.state).min()
            var i = SearchItem(id: "project:\(p.name)", kind: .project, goTo: true, project: nil, title: p.name)
            i.state = top; i.detail = [p.health, p.next].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            out.append(i)
        }
        for g in fixture.groups where g.name.lowercased().contains(needle) && (search.scopeProject == nil || search.scopeProject == g.project) {
            let members = fixture.sessions.filter { $0.project == g.project && g.sessions.contains($0.name) }
            let top = members.min { $0.state < $1.state }
            var i = SearchItem(id: "group:\(g.project)/\(g.name)", kind: .group, goTo: true, project: g.project, title: g.name)
            i.state = top?.state; i.wait = top?.wait; i.groupSessions = members.count
            i.detail = fixture.projects.first { $0.name == g.project }.map { [$0.health, $0.next].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") }
            out.append(i)
        }
        for s in fixture.sessions where s.name.lowercased().contains(needle) && (search.scopeProject == nil || search.scopeProject == s.project) {
            var i = SearchItem(id: "session:\(s.id)", kind: .session, goTo: true, project: s.project, title: s.name)
            i.state = s.state; i.wait = s.wait; i.sessionId = s.sessionId
            out.append(i)
            if out.count >= 8 { break }
        }
        return out
    }

    /// A group's or project's sessions, oldest first, for the Go to preview (search-jump).
    func searchGoToSessions(_ item: SearchItem) -> [Fixture.Session] {
        switch item.kind {
        case .group:
            guard let g = fixture.groups.first(where: { $0.project == item.project && $0.name == item.title }) else { return [] }
            return g.sessions.compactMap { n in fixture.sessions.first { $0.project == g.project && $0.name == n } }
        case .project: return Array(fixture.sessions(inProject: item.title).prefix(6))
        default: return []
        }
    }

    // MARK: Find similar from elsewhere (SRCH P3)

    /// Find similar started from the file tree or a session row: opens the modal in the designed
    /// similar view, with nothing to go back to. (Started outside search: DB-23 may restyle it.)
    public func findSimilar(file path: String) {
        guard let folder = projectFolder, let project = currentProject?.name else { return }
        var item = SearchItem(id: "similar:\(path)", kind: .file, project: project, title: path)
        item.path = folder.appending(path: path).path
        startSimilar(item)
    }

    public func findSimilar(session key: String) {
        guard let s = fixture.sessions.first(where: { $0.tabKey == key }), let id = s.sessionId,
              let folder = liveFolders[s.project], let t = ClaudeStorage.transcript(sessionId: id, cwd: folder.path) else { return }
        var item = SearchItem(id: "similar:\(id)", kind: .session, project: s.project, title: s.name)
        item.path = t.path; item.sessionId = id
        startSimilar(item)
    }

    private func startSimilar(_ item: SearchItem) {
        if !search.isOpen { openSearch() }
        search.similarReturnsTo = nil
        search.similarTo = item
        search.exact = false
        searchQueryChanged("")
    }

    // MARK: Index state

    func indexState() -> SearchUI.IndexState {
        if let forced = search.forcedIndexState { return forced }
        do {
            let index = try SearchIndex(readOnly: true)
            if !index.modelMatches { return .rebuilding("The search model changed, so everything is being indexed again.") }
            return .ok
        } catch { return .unreadable("\(error)") }
    }

    func liveSearchCoverage() -> String? {
        if let c = search.fixtureCoverage { return c }
        guard let index = try? SearchIndex(readOnly: true), let cov = try? index.coverage() else { return nil }
        let missing = cov.filter { !$0.complete }
        guard !missing.isEmpty else { return nil }
        return "Indexing: " + missing.prefix(2).map { "\($0.project) \($0.indexed) of \($0.known) files" }.joined(separator: " · ")
    }

    public func rebuildSearchIndex() {
        try? FileManager.default.trashItem(at: SearchPaths.index, resultingItemURL: nil)
        SearchService.shared.rebuild()
        search.phase = .rebuilding("Building the index again from your files and sessions.")
    }

    public func showSearchIndexDetails() {
        if case .unreadable(let e) = search.phase {
            let a = NSAlert(); a.messageText = "Search can’t read its index"; a.informativeText = "\(SearchPaths.index.path)\n\n\(e)"
            DuoAlert.present(a)
        }
    }

    public func newProjectFromSearch(_ name: String) {
        showNewProject(name: name)   // S2-6 (DL-100)
    }

    // MARK: Actions

    /// A search counts as recent once it was acted on or left with results, not at every keystroke.
    func rememberSearch() {
        let q = search.query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty, case .results = search.phase, search.items.contains(where: \.isContent) { SearchRecents.add(q) }
    }

    public func runSearchAction(_ id: SearchAction.ID) {
        let s = search
        let items = s.selectedItems
        guard let item = items.first else { return }
        s.menuOpen = false
        switch id {
        case .open:
            closeSearch()
            guard let project = item.project, let path = item.path ?? item.fixturePath else { return }
            let rel = liveFolders[project].flatMap { relativePathIn(URL(fileURLWithPath: path), folder: $0) } ?? path
            open(project: project, document: rel)
            if item.startLine > 0 { editor.revealFromSearch(path: rel, lines: item.startLine...max(item.startLine, item.endLine), words: item.matchedWords) }
        case .resume, .goTo:
            closeSearch()
            goTo(item)
        case .readOnly:
            closeSearch()
            openReadOnly(item)
        case .fork:
            closeSearch()
            if let id = item.sessionId, let project = item.project ?? fixture.home?.name {
                open(project: project)
                resumeAsFork(id, in: project)   // --resume <id> --fork-session (DB-3)
            }
        case .goToProject:
            closeSearch()
            if let p = item.project { open(project: p) }
        case .sendToClaude:
            let text = items.map(searchReference).joined(separator: "\n")
            closeSearch()
            send(text)
        case .findSimilar:
            s.similarReturnsTo = s.query
            s.similarTo = item
            s.exact = false
            searchQueryChanged("")
        case .showPassages:
            s.selected = s.items.firstIndex(of: item) ?? s.selected
        case .copyPath:
            FileActions.copy(item.path ?? item.title)
        case .copyPassage:
            FileActions.copy(item.passages.first?.snippet ?? item.snippet ?? "")
        case .copyLink:
            if let id = item.sessionId, let link = sessionLink(id) { FileActions.copy(link) }
            else { FileActions.copy(FileActions.markdownLink(name: URL(fileURLWithPath: item.title).lastPathComponent, relative: item.title)) }
        case .copyResume:
            if let id = item.sessionId { FileActions.copy("claude --resume \(id)") }
        case .reveal:
            if let p = item.path { FileActions.reveal(URL(fileURLWithPath: p)) }
        case .carryOn:
            closeSearch()
            if let id = item.sessionId, let new = carryOn(id), let project = item.project ?? fixture.home?.name {
                open(project: project); consoleTab = new
            }
        case .archiveSession:
            closeSearch()
            if let id = item.sessionId, let why = setSessionArchived(id, true) { info(why) }
        case .deleteSession:
            closeSearch()
            if let id = item.sessionId { deleteSession(id) }
        case .splitView:
            break  // split view isn't built (search-handoff §9)
        }
    }

    /// A reference, not the text (search-handoff §4): the path with its lines, or the session with its turn.
    func searchReference(_ i: SearchItem) -> String {
        switch i.kind {
        case .session: return "Session “\(i.title)”\(i.project.map { " in \($0)" } ?? "")\(i.location.isEmpty ? "" : ", \(i.location)")\(i.path.map { " (\($0))" } ?? "")"
        default:
            let lines = i.startLine > 0 ? ":\(i.startLine)\(i.endLine > i.startLine ? "-\(i.endLine)" : "")" : ""
            return "@\(i.path ?? i.title)\(lines)"
        }
    }

    func goTo(_ item: SearchItem) {
        switch item.kind {
        case .project: open(project: item.title)
        case .group:
            if let p = item.project { open(project: p); selectedSidebarItem = item.title; expandedGroups.insert(item.title) }
        case .session:
            let s = item.sessionId.flatMap { id in fixture.sessions.first { $0.sessionId == id } }
                ?? fixture.sessions.first { $0.project == item.project && $0.name == item.title }
            if let s { open(project: s.project, session: s.name) }
            else if let project = item.project ?? fixture.home?.name, let id = item.sessionId {
                // Not on the map (Unfiled, or Claude's): resume it in that project's console, as the harness does.
                open(project: project); consoleTab = id
                _ = terminal(project: project, session: id)
            }
        default: break
        }
    }

    /// Opens a session read-only at the matched turn: a right-pane tab (search-open-session).
    func openReadOnly(_ item: SearchItem) {
        guard let project = item.project ?? fixture.home?.name else { return }
        open(project: project)
        readOnlySession = ReadOnlySession(item: item)
        rightTab = ReadOnlySession.tabKey
    }
}

extension SearchItem {
    /// The fixture's file results carry a path relative to their project.
    var fixturePath: String? { kind == .file ? title : nil }
}

/// The last searches, newest first, for the empty state (DL-79 g). Duo's own state, not Claude's.
enum SearchRecents {
    struct Entry: Codable { var query: String; var at: Date }
    static let key = "searchRecents"

    static func load() -> [Entry] {
        guard let d = UserDefaults.standard.data(forKey: key), let e = try? JSONDecoder().decode([Entry].self, from: d) else { return [] }
        return e
    }

    static func add(_ q: String) {
        var e = load().filter { $0.query.caseInsensitiveCompare(q) != .orderedSame }
        e.insert(Entry(query: q, at: Date()), at: 0)
        if let d = try? JSONEncoder().encode(Array(e.prefix(8))) { UserDefaults.standard.set(d, forKey: key) }
    }

    /// `4m`, `2d`, `3w`, `today`, `yesterday`, as the design writes ages.
    static func age(_ d: Date) -> String {
        let s = Date().timeIntervalSince(d)
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if Calendar.current.isDateInToday(d) { return "today" }
        if Calendar.current.isDateInYesterday(d) { return "yesterday" }
        let days = Int(s / 86_400)
        if days < 7 { return "\(days)d" }
        if days < 60 { return "\(days / 7)w" }
        return "\(days / 30)mo"
    }
}
