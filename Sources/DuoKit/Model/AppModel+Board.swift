import AppKit
import WebKit
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

    /// The board shows and a card is selected (its note is the right pane's tab).
    var boardCardSelected: Bool {
        guard boardShown, let project = currentProject?.name, let path = rightTab else { return false }
        return fixture.tasks?.contains { $0.project == project && $0.path == path } == true
    }

    /// The board's keys, while it shows with a card selected: ⌥⌘← / ⌥⌘→ move the card a lane, unless a text
    /// field or the editor has the keyboard. Otherwise they pass on to Next / Previous Pane (DL-165).
    func watchBoardKeys() {
        guard boardKeyMonitor == nil else { return }
        boardKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.boardShown, self.boardCardSelected, event.modifierFlags.intersection([.option, .command, .shift, .control]) == [.option, .command],
                  [123, 124].contains(event.keyCode) else { return event }
            if let r = event.window?.firstResponder, r is NSTextView || r is WKWebView { return event }
            return self.moveSelectedCard(by: event.keyCode == 123 ? -1 : 1) ? nil : event
        }
    }

    // MARK: References (DL-150, board 13)

    /// Adds a reference to a task: a file or folder (a URL in or outside the project) or a web
    /// link. Through the editor's buffer when the note is open; otherwise the file, undoable.
    @discardableResult
    public func addReference(project: String, path: String, file: URL? = nil, url: String? = nil, title: String? = nil) -> String? {
        guard let folder = liveFolders[project] else { return "no project '\(project)'" }
        let link: String
        if let url { link = TaskReferences.link(url: url, title: title) }
        else if let file {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir)
            let base = folder.standardizedFileURL.path, p = file.standardizedFileURL.path
            if p.hasPrefix(base + "/") {
                link = TaskReferences.link(projectPath: String(p.dropFirst(base.count + 1)) + (isDir.boolValue ? "/" : ""), notePath: path, title: title)
            } else {
                // Outside the project: a link from the note's folder all the same (relative, as Obsidian keeps them).
                let note = folder.appending(path: path).deletingLastPathComponent().standardizedFileURL.pathComponents
                let to = file.standardizedFileURL.pathComponents
                var i = 0; while i < note.count, i < to.count - 1, note[i] == to[i] { i += 1 }
                let rel = String(repeating: "../", count: note.count - i) + to[i...].joined(separator: "/") + (isDir.boolValue ? "/" : "")
                let name = file.lastPathComponent
                link = "[\(TaskReferences.escape(title ?? (name.lowercased().hasSuffix(".md") ? String(name.dropLast(3)) : name)))](\(rel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rel))"
            }
        } else { return "nothing to add" }
        let note = folder.appending(path: path)
        if let e = editorIfLoaded, e.url?.standardizedFileURL == note.standardizedFileURL {
            e.run("duo.addListItem('references', i); return 1", ["i": TaskNotes.item(link)]) { _ in }
            return nil
        }
        guard let data = FileManager.default.contents(atPath: note.path), let text = String(data: data, encoding: .utf8) else { return "\(path) isn't readable" }
        guard let updated = TaskReferences.adding(link, to: text) else { return "that's already a reference of \(path)" }
        do { try Data(updated.utf8).write(to: note, options: .atomic) } catch { return error.localizedDescription }
        registerUndo("Add Reference") { model in try? data.write(to: note, options: .atomic); model.refreshLive() }
        refreshLive()
        return nil
    }

    /// Remove from Task on a reference: its line goes (the key too, if it was the last).
    @discardableResult
    public func removeReference(project: String, path: String, target: String) -> String? {
        guard let folder = liveFolders[project] else { return "no project '\(project)'" }
        let note = folder.appending(path: path)
        if let e = editorIfLoaded, e.url?.standardizedFileURL == note.standardizedFileURL {
            e.run("return duo.removeListItem('references', u)", ["u": target]) { _ in }
            return nil
        }
        guard let data = FileManager.default.contents(atPath: note.path), let text = String(data: data, encoding: .utf8) else { return "\(path) isn't readable" }
        guard let updated = TaskReferences.removing(target: target, from: text) else { return "\(path) has no reference to \(target)" }
        do { try Data(updated.utf8).write(to: note, options: .atomic) } catch { return error.localizedDescription }
        registerUndo("Remove Reference") { model in try? data.write(to: note, options: .atomic); model.refreshLive() }
        refreshLive()
        return nil
    }

    func referenceVerb(_ id: ActionID, _ inv: Invocation, _ project: String, _ done: @escaping @MainActor (Reply) -> Void) {
        guard let verb = inv[0], let t = inv[1], let what = inv[2] else { return done(.fail("usage: \(id.action.usage)")) }
        guard let hit = findTask(t, project: project) else { return done(.fail("no task '\(t)' in \(project)")) }
        let web = URL(string: what)?.scheme.map { ["http", "https"].contains($0.lowercased()) } ?? false
        var why: String?
        switch verb {
        case "add":
            if web { why = addReference(project: hit.project, path: hit.path, url: what, title: inv.flags["title"]) }
            else {
                let base = liveFolders[hit.project]
                let file = what.hasPrefix("/") || what.hasPrefix("~") ? URL(fileURLWithPath: (what as NSString).expandingTildeInPath) : base?.appending(path: what)
                guard let file, FileManager.default.fileExists(atPath: file.path) else { return done(.fail("\(what) isn't there")) }
                why = addReference(project: hit.project, path: hit.path, file: file, title: inv.flags["title"])
            }
        case "remove":
            let note = loadTask(hit.project, hit.path)
            let target = note?.references.map(TaskReferences.target).first { $0 == what || $0.hasSuffix(what) || ($0.removingPercentEncoding ?? $0).hasSuffix(what) } ?? what
            why = removeReference(project: hit.project, path: hit.path, target: target)
        default: return done(.fail("usage: \(id.action.usage)"))
        }
        if let why { return done(.fail(why)) }
        done(.ok("\(verb == "add" ? "Added" : "Removed") \(what) \(verb == "add" ? "to" : "from") \(hit.title)'s references. Undo: duo2 undo"))
    }

    // MARK: The Obsidian board (DL-20, DL-148 (1))

    /// `tasks.base` beside the brief, if there is one.
    public func obsidianBoard(_ project: String) -> URL? {
        guard let folder = liveFolders[project] else { return nil }
        let base = (ProjectBrief.url(in: folder)?.deletingLastPathComponent() ?? folder).appending(path: ObsidianBoard.fileName)
        return FileManager.default.fileExists(atPath: base.path) ? base : nil
    }

    /// The base's columns differ from the project's (the board says so, with Update).
    public func obsidianBoardOutOfDate(_ project: String) -> Bool {
        guard let base = obsidianBoard(project) else { return false }
        // Read when the base changes, not on every pass of the board's header.
        let stamp = (try? base.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let order: [String]?
        if let hit = baseOrderCache[project], hit.url == base, hit.stamp == stamp { order = hit.order } else {
            order = (try? String(contentsOf: base, encoding: .utf8)).flatMap(ObsidianBoard.groupOrder)
            baseOrderCache[project] = (base, stamp, order)
        }
        guard let order else { return false }
        return order.map(TaskBoard.key) != boardLanes(project)
    }

    /// Add Obsidian Board: writes `tasks.base` (never over one that's there). Undo removes it.
    @discardableResult
    public func addObsidianBoard(_ project: String) -> String? {
        guard let folder = liveFolders[project] else { return "no project '\(project)'" }
        if obsidianBoard(project) != nil { return "\(project) already has \(ObsidianBoard.fileName); Update Obsidian Board sets its columns" }
        let base = (ProjectBrief.url(in: folder)?.deletingLastPathComponent() ?? folder).appending(path: ObsidianBoard.fileName)
        do { try Data(ObsidianBoard.text(lanes: boardLanes(project)).utf8).write(to: base, options: .withoutOverwriting) } catch { return error.localizedDescription }
        registerUndo("Add Obsidian Board") { model in try? FileManager.default.trashItem(at: base, resultingItemURL: nil); model.refreshLive() }
        refreshLive()
        return nil
    }

    /// Update Obsidian Board: rewrites only the base's `groupOrder` lines, to the project's lanes.
    @discardableResult
    public func updateObsidianBoard(_ project: String) -> String? {
        guard let base = obsidianBoard(project), let data = FileManager.default.contents(atPath: base.path),
              let text = String(data: data, encoding: .utf8) else { return "\(project) has no \(ObsidianBoard.fileName): Add Obsidian Board writes one" }
        guard let updated = ObsidianBoard.updating(text, lanes: boardLanes(project)) else { return "\(ObsidianBoard.fileName) has no groupOrder for Duo to set" }
        do { try Data(updated.utf8).write(to: base, options: .atomic) } catch { return error.localizedDescription }
        registerUndo("Update Obsidian Board") { model in try? data.write(to: base, options: .atomic); model.refreshLive() }
        refreshLive()
        return nil
    }

    func baseVerb(_ id: ActionID, _ inv: Invocation, _ project: String, _ done: @escaping @MainActor (Reply) -> Void) {
        switch inv[0] {
        case "add"?:
            if let why = addObsidianBoard(project) { return done(.fail(why)) }
            done(.ok("Wrote \(project)/\(ObsidianBoard.fileName): open it in Obsidian 1.14.4 or later for the same board. Undo: duo2 undo"))
        case "update"?:
            if let why = updateObsidianBoard(project) { return done(.fail(why)) }
            done(.ok("\(ObsidianBoard.fileName)'s columns are now \(boardLanes(project).joined(separator: ", ")). Undo: duo2 undo"))
        case nil, "show"?:
            guard let base = obsidianBoard(project) else { return done(.ok("\(project) has no Obsidian board. duo2 task base add writes one.")) }
            done(.ok("\(base.path)\(obsidianBoardOutOfDate(project) ? " (out of date: duo2 task base update)" : "")", ["path": base.path, "outOfDate": obsidianBoardOutOfDate(project)]))
        default: done(.fail("usage: \(id.action.usage)"))
        }
    }

    // MARK: Columns (DL-150, board 12)

    /// Writes the project's lanes to its brief's `lanes:` list (added the first time, then edited
    /// in place); one undo puts the brief's bytes back.
    @discardableResult
    func setLanes(_ lanes: [String], project: String) -> String? {
        guard let folder = liveFolders[project] else { return "no project '\(project)'" }
        let brief = ProjectBrief.url(in: folder) ?? folder.appending(path: "PROJECT.md")
        let data = FileManager.default.contents(atPath: brief.path)
        let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        do { try Data(ProjectBrief.settingLanes(lanes, in: text).utf8).write(to: brief, options: .atomic) } catch { return error.localizedDescription }
        briefLanesCache[project] = nil
        registerUndo("Change Columns") { model in
            if let data { try? data.write(to: brief, options: .atomic) } else { try? FileManager.default.removeItem(at: brief) }
            model.briefLanesCache[project] = nil
            model.refreshLive()
        }
        refreshLive()
        return nil
    }

    /// + Add Column, or Add Column After…: the name's slug is the status (Blocked → `blocked`).
    @discardableResult
    public func addColumn(_ name: String, after: String? = nil, project: String) -> String? {
        guard let status = TaskBoard.status(forColumn: name) else { return "a column needs a name" }
        var lanes = boardLanes(project)
        guard status != "dropped" else { return "dropped isn't a column: it's the fold under Done" }
        guard !lanes.contains(status) else { return "\(TaskBoard.title(status)) is already a column" }
        if let after, let i = lanes.firstIndex(of: after) { lanes.insert(status, at: i + 1) } else { lanes.append(status) }
        return setLanes(lanes, project: project)
    }

    /// Keep as Column, on a lane for a status that isn't listed: it joins the list where it shows.
    @discardableResult
    public func keepColumn(_ status: String, project: String) -> String? {
        var lanes = boardLanes(project)
        guard !lanes.contains(status) else { return nil }
        lanes.append(status)
        return setLanes(lanes, project: project)
    }

    /// Move Left / Move Right on a lane's ⋯ menu.
    @discardableResult
    public func moveColumn(_ status: String, by step: Int, project: String) -> String? {
        var lanes = boardLanes(project)
        guard let i = lanes.firstIndex(of: status) else { return "no column '\(status)'" }
        let j = i + step
        guard lanes.indices.contains(j) else { return nil }
        lanes.swapAt(i, j)
        return setLanes(lanes, project: project)
    }

    /// The tasks a column holds (not archived ones).
    func tasks(inLane status: String, project: String) -> [Fixture.TaskSummary] {
        (fixture.tasks ?? []).filter { $0.project == project && $0.archived != true && TaskBoard.key($0.status) == status }
    }

    /// Remove Column…: Open and Done can't go. A column holding tasks asks where they go (a Duo
    /// question, never an alert) and writes each one's `status`; one undo puts it all back.
    public func askRemoveColumn(_ status: String, project: String, answered: (@MainActor (String) -> Void)? = nil) {
        guard !TaskBoard.fixedLanes.contains(status) else { return info("\(TaskBoard.title(status)) can't be removed: new tasks start in Open, and Mark Complete needs Done.") }
        let lanes = boardLanes(project)
        guard let i = lanes.firstIndex(of: status) else { return }
        let held = tasks(inLane: status, project: project)
        if held.isEmpty {
            var rest = lanes; rest.remove(at: i)
            if let why = setLanes(rest, project: project) { info(why) }
            answered?("Removed"); return
        }
        let others = lanes.filter { $0 != status }
        let fallback = i > 0 ? lanes[i - 1] : "open"
        let pick = DuoQuestion.Pick(label: "Move \(held.count == 1 ? "it" : "them") to", options: others.map { ($0, TaskBoard.title($0)) }, selected: fallback)
        let n = held.count
        let q = DuoQuestion(
            title: "Remove the \(TaskBoard.title(status)) column?",
            paragraphs: [n == 1 ? "Its task moves to the column you choose. Nothing else in the note changes."
                               : "Its \(n) tasks move to the column you choose. Nothing else in their notes changes."],
            items: held.map { .init(what: $0.title, path: "") },
            pick: pick,
            choices: [
                .init(label: "Cancel", isCancel: true) { answered?("Cancel") },
                .init(label: "Remove Column", isDefault: true) { [weak self] in
                    self?.removeColumn(status, movingTo: pick.selected, project: project)
                    answered?("Remove Column")
                },
            ])
        if Env.autoconfirm { FileHandle.standardError.write(Data("question: \(q.title) [\(q.choices.map(\.label).joined(separator: " | "))] → \(fallback)\n".utf8)) }
        SheetCenter.shared.ask(q)
    }

    /// Removes a column, its tasks moving to `target` first.
    @discardableResult
    public func removeColumn(_ status: String, movingTo target: String, project: String) -> String? {
        guard !TaskBoard.fixedLanes.contains(status) else { return "\(TaskBoard.title(status)) can't be removed" }
        var lanes = boardLanes(project)
        guard let i = lanes.firstIndex(of: status), target != status else { return "no column '\(status)'" }
        var failed: String?
        asOneUndo("Remove Column") {
            for t in tasks(inLane: status, project: project) {
                if let why = setTaskStatus(project: project, path: t.path, target) { failed = why }
            }
            lanes.remove(at: i)
            if let why = setLanes(lanes, project: project) { failed = why }
        }
        return failed
    }

    func boardVerb(_ id: ActionID, _ inv: Invocation, _ req: ControlRequest, _ done: @escaping @MainActor (Reply) -> Void) {
        let name = inv.flags["project"] ?? projectFor(cwd: req.cwd)?.name ?? currentProject?.name
        guard let name, project(named: name) != nil else { return done(.fail("which project? --project <p>")) }
        guard terminalsMode == .live else { return done(.fail("the task board needs live projects")) }
        if id == .taskColumn { return columnVerb(id, inv, name, done) }
        if id == .taskReference { return referenceVerb(id, inv, name, done) }
        if id == .taskBase { return baseVerb(id, inv, name, done) }
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

    /// `duo2 task column add|remove|move|keep <name>`.
    func columnVerb(_ id: ActionID, _ inv: Invocation, _ project: String, _ done: @escaping @MainActor (Reply) -> Void) {
        guard let verb = inv[0], inv.positional.count > 1 else { return done(.fail("usage: \(id.action.usage)")) }
        let name = inv.positional.dropFirst().joined(separator: " ")
        let status = TaskBoard.status(forColumn: name) ?? name
        let after = inv.flags["after"].map { TaskBoard.status(forColumn: $0) ?? $0 }
        var why: String?
        switch verb {
        case "add": why = addColumn(name, after: after, project: project)
        case "keep": why = keepColumn(status, project: project)
        case "move":
            guard let dir = inv.has("left") ? "left" : inv.has("right") ? "right" : nil else { return done(.fail("move needs --left or --right")) }
            why = moveColumn(status, by: dir == "left" ? -1 : 1, project: project)
        case "remove":
            if TaskBoard.fixedLanes.contains(status) { return done(.fail("\(TaskBoard.title(status)) can't be removed")) }
            let held = tasks(inLane: status, project: project)
            if !held.isEmpty {
                guard let to = inv.flags["to"].map({ TaskBoard.status(forColumn: $0) ?? $0 }) else {
                    askRemoveColumn(status, project: project) { answer in done(.ok(answer == "Cancel" ? "Kept the \(TaskBoard.title(status)) column." : "Removed the \(TaskBoard.title(status)) column. Undo: duo2 undo")) }
                    return
                }
                why = removeColumn(status, movingTo: to, project: project)
            } else {
                var lanes = boardLanes(project); lanes.removeAll { $0 == status }
                why = setLanes(lanes, project: project)
            }
        default: return done(.fail("usage: \(id.action.usage)"))
        }
        if let why { return done(.fail(why)) }
        done(.ok("\(project)'s columns: \(boardLanes(project).map(TaskBoard.title).joined(separator: ", ")). Undo: duo2 undo", ["lanes": boardLanes(project)]))
    }
}
