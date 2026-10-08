import AppKit
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
        if shown { boardProjects.insert(p); watchBoardKeys() } else { boardProjects.remove(p) }
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
        // A card just dropped on Done holds ticked where it was (DL-130's hold).
        let held = tasks.map { t -> Fixture.TaskSummary in
            guard let was = boardHeld[t.id] else { return t }
            var t = t; t.status = was; return t
        }
        return TaskBoard.lanes(tasks: held, lanes: boardLanes(project), state: { states[$0] })
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

    /// What a dragged card carries.
    public static func dragPayload(card project: String, path: String) -> String { "duo-card:\(project)/\(path)" }

    /// The card a payload names, if it's one of this project's.
    func card(fromPayload payload: String, project: String) -> String? {
        let prefix = "duo-card:\(project)/"
        return payload.hasPrefix(prefix) ? String(payload.dropFirst(prefix.count)) : nil
    }

    /// A card moved to another lane (a drag, ⌥⌘← / ⌥⌘→, `duo2 task status`): Set Status, which
    /// writes only `status:` (and `completed:` when it closes or reopens). With the note open, the
    /// change goes through the editor's buffer (DL-13), so unsaved typing is kept; ⌘Z undoes it
    /// either way. Onto Done, the card holds ticked where it was for Mark Complete's 5 s (DL-130).
    @discardableResult
    public func moveCard(project: String, path: String, to status: String) -> String? {
        guard let folder = liveFolders[project] else { return "no project '\(project)'" }
        let id = project + "/" + path
        let task = fixture.tasks?.first { $0.id == id }
        let was = TaskBoard.key(task?.status)
        guard was != status else { return nil }
        let file = folder.appending(path: path).standardizedFileURL
        if let e = editorIfLoaded, e.url?.standardizedFileURL == file {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
            let closes = ["done", "dropped"].contains(status)
            let oldStatus = task?.status, oldCompleted = task?.completed
            e.run("duo.setProperty('status', s); duo.setProperty('completed', c); return 1", ["s": status, "c": closes ? f.string(from: Date()) : NSNull()]) { _ in }
            registerUndo("Set Task Status") { model in
                e.run("duo.setProperty('status', s); duo.setProperty('completed', c); return 1", ["s": oldStatus ?? NSNull(), "c": oldCompleted ?? NSNull()]) { _ in }
                model.showNow { model.setShownTask(project, path) { $0.status = oldStatus; $0.completed = oldCompleted } }
            }
            showNow { setShownTask(project, path) { $0.status = status; $0.completed = closes ? f.string(from: Date()) : nil } }
        } else if let why = setTaskStatus(project: project, path: path, status) {
            return why
        }
        if status == "done" && !MotionSettings.shared.reduce {
            boardHeld[id] = was
            completingTasks.insert(id)
            DispatchQueue.main.asyncAfter(deadline: .now() + DuoMotionToken.rowHold.delay) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.boardHeld[id] != nil else { return }
                    withDuoAnimation(.rowMove) { self.boardHeld[id] = nil; self.completingTasks.remove(id) }
                }
            }
        } else {
            boardHeld[id] = nil
        }
        return nil
    }

    /// ⌥⌘← / ⌥⌘→ (board 7 [P]): the selected card (its note in the right pane) one lane over.
    public func moveSelectedCard(by step: Int) -> Bool {
        guard boardShown, let project = currentProject?.name, let path = rightTab,
              let t = fixture.tasks?.first(where: { $0.project == project && $0.path == path }) else { return false }
        let lanes = board(project).map(\.status)
        guard let i = lanes.firstIndex(of: TaskBoard.key(t.status)) else { return false }
        let j = i + step
        guard lanes.indices.contains(j) else { return true }
        if let why = moveCard(project: project, path: path, to: lanes[j]) { info(why) }
        return true
    }

    /// The board's keys, while it shows: ⌥⌘← / ⌥⌘→ move the selected card a lane, unless a text
    /// field or the editor has the keyboard.
    func watchBoardKeys() {
        guard boardKeyMonitor == nil else { return }
        boardKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.boardShown, event.modifierFlags.intersection([.option, .command, .shift, .control]) == [.option, .command],
                  [123, 124].contains(event.keyCode) else { return event }
            if let r = event.window?.firstResponder, r is NSTextView || String(describing: type(of: r)).contains("WKWebView") { return event }
            return self.moveSelectedCard(by: event.keyCode == 123 ? -1 : 1) ? nil : event
        }
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
