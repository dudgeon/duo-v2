import AppKit

// Selecting several sessions and acting on them (DL-247, session-multiselect-handoff). The rows say which list
// they're in and how they read on screen; the clicks, the menu, the one Delete sheet and duo2 come here.

extension AppModel {
    /// The project pane's list: one per project (Home's pane is Home's project).
    public var projectSelectionList: String { "project:\(currentProject?.name ?? "")" }

    /// What the click under way carried: ⇧ ranges, ⌘ toggles, anything else is a plain click.
    static func currentClick() -> SessionSelection.Click {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if flags.contains(.shift) { return .shift }
        if flags.contains(.command) { return .command }
        return .plain
    }

    /// A session row's click: a plain click opens it (`open`), as before; ⇧ and ⌘ only select (board 00).
    public func sessionRowClicked(_ key: String, list: String, open: () -> Void) {
        sessionRowClicked(key, Self.currentClick(), list: list, open: open)
    }

    public func sessionRowClicked(_ key: String, _ click: SessionSelection.Click, list: String, open: () -> Void) {
        if sessionSelection.click(key, click, list: list, order: selectionOrders[list] ?? []) { open() }
    }

    /// The list's rows as drawn, so ⇧ ranges over what's on screen. Called from each list's body.
    func noteSelectionOrder(_ list: String, _ order: [String]) {
        selectionOrders[list] = order
        // A session that left the list leaves the selection (on the next change, not mid-draw).
        if sessionSelection.list == list, !sessionSelection.isEmpty {
            let present = Set(order)
            if sessionSelection.keys.contains(where: { !present.contains($0) }) {
                DispatchQueue.main.async { MainActor.assumeIsolated { self.sessionSelection.keepOnly(Set(self.selectionOrders[list] ?? [])) } }
            }
        }
    }

    /// How a row's selected fill joins its neighbours' (board 01, A); `.none` when it isn't selected.
    public func selectionRun(_ key: String, list: String) -> SessionSelection.Run {
        guard sessionSelection.list == list, sessionSelection.contains(key) else { return .none }
        return sessionSelection.run(key, order: selectionOrders[list] ?? [key])
    }

    /// The project pane's rows in order: a session row's key, or a breaker for every row that isn't one.
    public func sidebarOrder(_ items: [SidebarItem], project: String) -> [String] {
        let b = SessionSelection.breaker
        func member(_ r: SidebarRow) -> [String] {
            switch r.kind {
            case .thread(_, let members) where expandedGroups.contains(r.id): return members.map(\.sessionKey)
            case .thread, .session: return [r.sessionKey]
            case .taskLine: return [b]
            case .group(let threads, _): return [b] + (expandedGroups.contains(r.name) ? threads.flatMap(member) : [])
            case .older(let rows): return [b] + (expandedGroups.contains(r.id) ? rows.flatMap(member) : [])
            }
        }
        var out: [String] = []
        for item in items {
            if case .row(let r, _) = item.kind { out += member(r) } else { out.append(b) }
        }
        out.append(b)   // the Archived fold's row
        if expandedGroups.contains("\(project)/archived") { out += fixture.archivedSessions(inProject: project).map(\.tabKey) }
        return out
    }

    /// The selected sessions, as the list shows them.
    public var selectedSessions: [Fixture.Session] {
        let all = fixture.sessions + (fixture.archivedSessions ?? [])
        let order = selectionOrders[sessionSelection.list] ?? []
        let keys = sessionSelection.keys.sorted { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
        return keys.compactMap { k in all.first { $0.tabKey == k } }
    }

    /// The session list in the pane that has the keyboard, if one does: a project's pane on the left, All projects'
    /// List in the middle, the action column on the right.
    var selectionListWithKeyboard: String? {
        switch (altitude.isAllProjects, activePane) {
        case (false, .left): return projectSelectionList
        case (true, .middle) where homeView == .list: return "list"
        case (true, .right): return "action"
        default: return nil
        }
    }

    /// Esc and a click on the empty pane.
    public func clearSessionSelection() { sessionSelection.clear() }

    /// ⌘A in a list with the keyboard.
    public func selectAllSessions(list: String) {
        sessionSelection.selectAll(list: list, order: selectionOrders[list] ?? [])
    }

    // MARK: The selection's menu (board 02)

    /// What each item would act on: Archive the unarchived ones that aren't running, Unarchive the archived,
    /// Park those that can park.
    public struct SelectionCounts {
        public var archive: [String] = []
        public var unarchive: [String] = []
        public var park: [String] = []
        /// One project for all of them: the task items need it.
        public var project: String?
    }

    public func selectionCounts(_ sessions: [Fixture.Session]? = nil) -> SelectionCounts {
        let sessions = sessions ?? selectedSessions
        var c = SelectionCounts()
        for s in sessions {
            guard let id = s.sessionId else { continue }
            if isSessionArchived(id) { c.unarchive.append(s.tabKey) }
            else if !hasOpenTerminal(s.tabKey) && !liveElsewhere.contains(id) { c.archive.append(s.tabKey) }
            if parkBlock(s.tabKey, bulk: true, deep: false) == nil { c.park.append(s.tabKey) }
        }
        let projects = Set(sessions.map(\.project))
        c.project = projects.count == 1 ? projects.first : nil
        return c
    }

    /// Archive n Sessions / Unarchive n Sessions: one ⌘Z for the lot.
    @discardableResult
    public func archiveSessions(_ keys: [String], _ on: Bool) -> [String] {
        var refused: [String] = []
        asOneUndo(on ? "Archive Sessions" : "Unarchive Sessions") {
            for k in keys { if let why = setSessionArchived(k, on) { refused.append(why) } }
        }
        sessionSelection.clear()
        return refused
    }

    /// Park n Sessions: those that can; the rest say why.
    @discardableResult
    public func parkSessions(_ keys: [String]) -> [String] {
        var refused: [String] = []
        for k in keys {
            if let why = park(k) {
                let name = (fixture.sessions.first { $0.tabKey == k }?.name).map(ParkCheck.quoted) ?? k
                refused.append("\(name) \(why.why)")
            }
        }
        sessionSelection.clear()
        return refused
    }

    /// Add to Task ▸: every one of them into the task's `sessions:`; one ⌘Z.
    @discardableResult
    public func addSessionsToTask(_ keys: [String], task path: String) -> [String] {
        var refused: [String] = []
        asOneUndo("Add to Task") {
            for k in keys { if let why = addToTask(sessionKey: k, task: path) { refused.append(why) } }
        }
        sessionSelection.clear()
        return refused
    }

    /// Make a Task from several: one task linking all of them, titled after the first.
    public func makeTask(fromSessions keys: [String]) {
        let sessions = keys.compactMap { k in fixture.sessions.first { $0.tabKey == k || $0.sessionId == k } }
        guard let first = sessions.first, sessions.allSatisfy({ $0.project == first.project }) else { return }
        let title = first.name.trimmingCharacters(in: CharacterSet(charactersIn: "“”\""))
        sessionSelection.clear()
        if case .failure(let e) = makeTask(title: title, sessionIds: sessions.compactMap(\.sessionId), project: first.project) { info("Couldn't make the task: \(e)") }
    }

    // MARK: Delete n Sessions… (board 03)

    /// One Duo sheet for all of them. Each delete is planned by its own session id before the sheet shows; a
    /// session running outside Duo is left out and named. `done` gets what happened, for duo2.
    public func deleteSessions(_ keys: [String], done: (@MainActor (Result<String, Error>) -> Void)? = nil) {
        if keys.count == 1, let k = keys.first { return deleteSession(k, done: done) }
        var ready: [PreparedDelete] = []
        var items: [DuoQuestion.Item] = []
        var skipped: [(name: String, why: String)] = []
        for k in keys {
            switch prepareDelete(k) {
            case .success(let p):
                ready.append(p)
                items.append(.init(what: p.session.name, path: p.inDuo ? "running in Duo: Duo ends it first" : p.session.state.spokenName + (p.session.wait.map { " · \($0)" } ?? "")))
            case .failure(let e):
                let s = (fixture.sessions + (fixture.archivedSessions ?? [])).first { $0.tabKey == k || $0.sessionId == k }
                let outside = "\(e)".contains("running outside Duo")
                skipped.append((s?.name ?? k, "\(e)"))
                items.append(.init(what: s?.name ?? k, path: outside ? "running outside Duo: not deleted" : "not deleted"))
            }
        }
        let skippedText = skipped.map { "\($0.name): \($0.why)" }.joined(separator: "; ")
        guard !ready.isEmpty else {
            let why = "None of these can be deleted. " + skipped.map(\.why).joined(separator: " ")
            info(why)
            done?(.failure(Migrator.Refusal(why)))
            return
        }
        let bytes = ByteCountFormatter.string(fromByteCount: ready.reduce(0) { $0 + $1.bytes }, countStyle: .file)
        let outside = skipped.filter { $0.why.contains("running outside Duo") }.map(\.name)
        var q = Self.deleteSessionsQuestion(names: ready.map(\.session.name), items: items, steps: ready.reduce(0) { $0 + $1.plan.steps.count }, bytes: bytes, outside: outside)
        q.choices = [
            .init(label: "Cancel", isCancel: true) { done?(.failure(Migrator.Refusal("Not deleted: the user clicked Cancel in Duo. Nothing changed."))) },
            .init(label: "Move to Trash", isDefault: true) { [weak self] in
                guard let self else { return }
                self.sessionSelection.clear()
                self.runDeletes(ready) { results in
                    let ok = results.filter { if case .success = $0.1 { return true } else { return false } }.map(\.0.session.name)
                    let failed = results.compactMap { r -> String? in if case .failure(let e) = r.1 { return "\(r.0.session.name): \(e)" } else { return nil } }
                    var msg = "Deleted \(ok.count) session\(ok.count == 1 ? "" : "s") and their local logs (\(bytes))"
                    if !ok.isEmpty { msg += ": " + ok.joined(separator: ", ") }
                    msg += "."
                    if !skippedText.isEmpty { msg += " Not deleted: \(skippedText)." }
                    if !failed.isEmpty { msg += " Failed: \(failed.joined(separator: "; "))." }
                    done?(.success(msg))
                }
            },
        ]
        ask(q)
    }

    /// Delete n Sessions…'s question (board 03): the count, every session with its state, and who's left out. Also
    /// drawn by the harness's `select-delete-sheet` on sample data.
    static func deleteSessionsQuestion(names: [String], items: [DuoQuestion.Item], steps: Int, bytes: String, outside: [String]) -> DuoQuestion {
        let n = names.count
        var q = DuoQuestion(title: n == 1 ? "Delete “\(names[0])”?" : "Delete \(n) sessions?", choices: [])
        q.paragraphs = ["\(n == 1 ? "Its transcript goes" : "Their transcripts go") to the Trash, and Duo’s archived \(n == 1 ? "copy" : "copies") with \(n == 1 ? "it" : "them") (\(steps) item\(steps == 1 ? "" : "s"), \(bytes)):"]
        q.items = items
        q.itemsMaxHeight = 182
        if outside.isEmpty {
            q.note = "You can put \(n == 1 ? "it" : "them") back from the Trash, but Duo can’t undo this."
        } else {
            let names = ListFormatter.localizedString(byJoining: outside.map { "“\($0)”" })
            q.note = "\(names) \(outside.count == 1 ? "is" : "are") running outside Duo, so \(outside.count == 1 ? "it isn’t" : "they aren’t") deleted. End \(outside.count == 1 ? "it" : "them") there first. You can put the others back from the Trash, but Duo can’t undo this."
        }
        return q
    }
}
