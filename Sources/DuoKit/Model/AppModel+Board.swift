import DuoControl
import Foundation

/// The task board (DL-148, DL-150, `task-board-handoff/`): a project's Sessions | Tasks switch. The
/// board covers the session list and the console; the right pane keeps the selected card's note.
/// Everything on it is computed from the task notes; a board action writes only `status`.
extension AppModel {
    /// The board is up: at a project, in live mode, with Tasks chosen.
    public var boardShown: Bool {
        guard !altitude.isAllProjects, terminalsMode == .live, let p = currentProject?.name else { return false }
        return boardProjects.contains(p)
    }

    /// Sessions | Tasks for the project on screen (or `project`).
    public func showBoard(_ shown: Bool, project: String? = nil) {
        guard let p = project ?? currentProject?.name else { return }
        if shown { boardProjects.insert(p) } else { boardProjects.remove(p) }
        if shown, currentProject?.name != p { open(project: p) }
    }

    /// The project's lanes: its brief's `lanes:` list, or the default five (DL-150). Read from disk,
    /// kept until the brief changes.
    public func boardLanes(_ project: String) -> [String] {
        guard let folder = liveFolders[project], let brief = ProjectBrief.url(in: folder) else { return TaskBoard.defaultLanes }
        let stamp = (try? brief.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let hit = briefLanesCache[project], hit.url == brief, hit.stamp == stamp { return hit.lanes }
        let lanes = TaskBoard.lanes(brief: try? String(contentsOf: brief, encoding: .utf8))
        briefLanesCache[project] = (brief, stamp, lanes)
        return lanes
    }

    /// The project's board: its tasks through the filter and the owner popup, in lanes.
    public func board(_ project: String) -> [TaskBoard.Lane] {
        let user = fixture.user
        let q = boardFilter.trimmingCharacters(in: .whitespaces)
        let tasks = (fixture.tasks ?? []).filter { t in
            guard t.project == project else { return false }
            if !q.isEmpty, t.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) == nil { return false }
            switch boardOwner {
            case nil: return true
            case ""?: return t.owner.map { TaskBoard.isYou($0, user: user) } ?? true
            case let who?: return t.owner.map { TaskBoard.plain($0).caseInsensitiveCompare(who) == .orderedSame } ?? false
            }
        }
        let states = Dictionary(fixture.sessions.compactMap { s in s.sessionId.map { ($0.lowercased(), s.state) } }, uniquingKeysWith: { a, _ in a })
        return TaskBoard.lanes(tasks: tasks, lanes: boardLanes(project), state: { states[$0] })
    }

    /// The owners named on the project's tasks, other than you, for Anyone ▾.
    public func boardOwners(_ project: String) -> [String] {
        let user = fixture.user
        let names = (fixture.tasks ?? []).filter { $0.project == project && $0.archived != true }.compactMap(\.owner)
            .filter { !TaskBoard.isYou($0, user: user) }.map(TaskBoard.plain)
        return Array(Set(names)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// A card's linked sessions, most urgent first (as a task row orders them, DL-93).
    public func cardSessions(_ t: Fixture.TaskSummary) -> [Fixture.Session] {
        let all = fixture.sessions.filter { $0.project == t.project }
        return t.sessionIds.compactMap { id in all.first { $0.sessionId?.lowercased() == id } }
            .enumerated().sorted { a, b in a.element.state != b.element.state ? a.element.state < b.element.state : a.offset < b.offset }.map(\.element)
    }

    /// A click on a card: its note in the right pane, beside the board (DL-148 (2)).
    public func selectCard(project: String, path: String) {
        if rightCollapsed { rightCollapsed = false }
        openTask(project: project, path: path)
    }

    /// A click on a card's session row (DL-148 (4)): the board switches to Sessions with that
    /// session selected and its tab in front, resumed if it was closed; the note stays on the right.
    public func openCardSession(_ id: String, project: String) {
        showBoard(false, project: project)
        if let s = fixture.sessions.first(where: { $0.sessionId?.lowercased() == id.lowercased() }) { selectedSidebarItem = s.id }
        openSessionLink(id)
    }

    func boardVerb(_ id: ActionID, _ inv: Invocation, _ req: ControlRequest, _ done: @escaping @MainActor (Reply) -> Void) {
        let name = inv.flags["project"] ?? projectFor(cwd: req.cwd)?.name ?? currentProject?.name
        guard let name, project(named: name) != nil else { return done(.fail("which project? --project <p>")) }
        guard terminalsMode == .live else { return done(.fail("the task board needs live projects")) }
        switch inv[0] {
        case "show"?: showBoard(true, project: name)
        case "hide"?: showBoard(false, project: name)
        case "toggle"?: showBoard(!boardProjects.contains(name), project: name)
        case nil: break
        case let other?: return done(.fail("usage: \(id.action.usage) (not '\(other)')"))
        }
        let lanes = board(name)
        let shown = boardProjects.contains(name)
        let text = "\(name): \(shown ? "Tasks (the board)" : "Sessions")\n" + lanes.map { l in
            "\(l.title.uppercased()) · \(l.count)\(l.extra ? " (not a column)" : "")" + l.cards.map { "\n  \($0.task.title)  \($0.task.path)" }.joined()
                + (l.earlier.isEmpty ? "" : "\n  Earlier · \(l.earlier.count)") + (l.dropped.isEmpty ? "" : "\n  Dropped · \(l.dropped.count)")
        }.joined(separator: "\n")
        done(.ok(text, ["project": name, "board": shown, "lanes": lanes.map { l in
            ["status": l.status, "title": l.title, "extra": l.extra, "cards": l.cards.map(\.task.path), "earlier": l.earlier.map(\.task.path), "dropped": l.dropped.map(\.task.path)] as [String: Any]
        }]))
    }
}
