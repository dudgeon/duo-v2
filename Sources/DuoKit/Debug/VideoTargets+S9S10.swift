import AppKit
import Foundation

/// The intro video's scenes 9 and 10 as window states (`--state video-s9-<what>`, `video-s10-<what>`, with
/// `--fixture video/fixture/fixture.json`).
///
/// Scene 9, Duo Projects: All projects as a Board and as a List, then the project view as scene 7 left it (`video-s9-project`
/// is `video-s7-pptx-after` with the file tree's research/ folder closed, as a live project's folders start; `video-s9-files-open`
/// is `video-s7-pptx-after` itself, research/ open).
///
/// Scene 10, Tasks: the same project view with tasks. The task notes are the fixture's own (`docs/tasks/*.md`, Duo's format), the
/// sessions they link are told by id (`videoS10.sessionIds`: set on the model here, only for these states, since the other scenes
/// key their tabs by name), and the lists are what Duo draws from them: a task's sessions grouped under it, a task with no
/// session in the Tasks fold, the board (Sessions | Tasks) by status. The new task's three stages are the fixture's `s10/` notes.
/// New Task in Duo has no sheet: File › New Task (or + New task) writes `tasks/untitled-task.md` and opens it with its name selected,
/// so `video-s10-newtask-untitled` is that moment and the typed name's note is `video-s10-newtask-created`.
extension VideoTargets {
    nonisolated static let s9Screens = ["video-s9-board", "video-s9-list", "video-s9-project", "video-s9-files-open", "video-s9-beta"]
    nonisolated static let s10Screens = ["video-s10-flat", "video-s10-grouped", "video-s10-tasknote", "video-s10-newtask-untitled",
                                         "video-s10-newtask-created", "video-s10-newtask-details", "video-s10-newsession", "video-s10-newsession-sent",
                                         "video-s10-board", "video-s10-board-deck", "video-s10-deck-resumed",
                                         "video-s10-collapsed", "video-s10-workstreams", "video-s10-task-menu-target", "video-s10-archive-ask", "video-s10-archived"]
    nonisolated static var s9s10Screens: [String] { s9Screens + s10Screens }

    /// The scene 7 state a scene 9 or 10 project state stands on: the project as scene 7 ended, the deck's slide 3 after the edit.
    nonisolated static func s9s10Base(_ screen: String) -> String {
        screen.hasPrefix("video-s9-") || screen.hasPrefix("video-s10-") ? "video-s7-pptx-after" : screen
    }

    nonisolated static let newTaskTitle = "Warn about glare before the photo"
    nonisolated static let untitledPath = "tasks/untitled-task.md"
    static let boardProject = "shelf-scan"
    nonisolated static let archivedTaskTitle = "Beta interview synthesis"   // the done task scene 10 archives, with its three sessions

    // MARK: Scene 9

    /// All projects as a Board or a List, on the demo's day (Tue 13 Oct, 9:41), with the four sessions scene 7 left open.
    static func applyS9Home(_ screen: String, _ model: AppModel) {
        TargetState.overview.apply(to: model)
        model.homeView = screen == "video-s9-board" ? .board : .list
        model.rightCollapsedAllProjects = false
        model.listClock = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 9, minute: 41))
        if let v = model.fixture.videoS2 {
            let names = Set(v.terminals.map(\.name) + [autoAdd])
            model.fixtureActive = Set(model.fixture.sessions.filter { names.contains($0.name) }.map(\.tabKey))
        }
        WindowCapture.underlay = DuoNSColor.console
    }

    /// The project view of scene 9: scene 7's, with research/ closed until the cursor opens it (`video-s9-files-open`).
    static func applyS9Project(_ screen: String, _ model: AppModel) {
        if screen == "video-s9-project" { model.videoClosedFolders = ["research"] }
    }

    /// The project view of beta-feedback, where the cursor lands from the Board: its own sessions, its files, "Weekly digest draft"
    /// in a terminal tab and the project's own PROJECT.md on the right. Built like `applyS4S5`'s shelf-scan view, from the fixture's
    /// `projects/beta-feedback` folder.
    static func applyS9Beta(_ model: AppModel) {
        TargetState.project.apply(to: model)
        guard let base = model.fixture.baseDir else { return }
        let dir = URL(fileURLWithPath: base)
        let project = "beta-feedback"
        let folder = dir.appending(path: "projects/beta-feedback").standardizedFileURL
        let digest = "Weekly digest draft"
        let key = model.fixture.sessions.first { $0.project == project && $0.name == digest }?.tabKey ?? digest
        model.altitude = .project(project)
        model.fixture.groups = model.fixture.groups.filter { $0.project != project }
        model.fixture.projectFiles[project] = ["PROJECT.md", "digests/2026-10-09.md", "inbox/tester-emails-oct12.md"]
        model.selectedSidebarItem = nil
        model.expandedGroups = []
        model.liveFolders[project] = folder
        model.videoDemoFolder = folder
        model.listClock = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 9, minute: 41))
        WindowCapture.underlay = DuoNSColor.console
        model.videoRightWidth = 700
        let text = (try? String(contentsOf: dir.appending(path: "terms/beta-digest.ans"), encoding: .utf8)) ?? ""
        model.fixtureTerminals[key] = TerminalSession(key: key, screen: text)
        model.parkedTabs = [key]
        model.openDocuments = ["PROJECT.md"]
        model.rightTab = "PROJECT.md"; model.selectedFile = "PROJECT.md"
        model.consoleTab = key
    }

    // MARK: Scene 10

    struct S10Data {
        var ids: [String: String] = [:]
        var tasks: [Fixture.TaskSummary] = []
        var sessions: [Fixture.Session] = []   // the idle sessions the tasks' second and third rows are (every scene 10 state lists them)
        var newTask: [String: Any] = [:]
        var deck: [String: Any] = [:]
        var newSessionId: String { ((newTask["session"] as? [String: Any])?["sessionId"] as? String) ?? "" }
    }

    /// `videoS10` of the fixture, read from its file (Fixture doesn't carry it: its sessions and tasks stay out of the model for scenes 2 to 7).
    static func s10Data(dir: URL) -> S10Data? {
        guard let data = try? Data(contentsOf: dir.appending(path: "fixture.json")),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let s10 = root["videoS10"] as? [String: Any] else { return nil }
        var out = S10Data()
        out.ids = s10["sessionIds"] as? [String: String] ?? [:]
        if let t = s10["tasks"], let json = try? JSONSerialization.data(withJSONObject: t) { out.tasks = (try? JSONDecoder().decode([Fixture.TaskSummary].self, from: json)) ?? [] }
        if let t = s10["sessions"], let json = try? JSONSerialization.data(withJSONObject: t) { out.sessions = (try? JSONDecoder().decode([Fixture.Session].self, from: json)) ?? [] }
        out.newTask = s10["newTask"] as? [String: Any] ?? [:]
        out.deck = s10["deckSession"] as? [String: Any] ?? [:]
        return out
    }

    /// The fixture's sessions with their Claude session ids, so a task note's links reach them.
    static func assignSessionIds(_ model: AppModel, dir: URL) {
        guard let d = s10Data(dir: dir) else { return }
        for i in model.fixture.sessions.indices { if let id = d.ids[model.fixture.sessions[i].name] { model.fixture.sessions[i].sessionId = id } }
        if var archived = model.fixture.archivedSessions {
            for i in archived.indices { if let id = d.ids[archived[i].name] { archived[i].sessionId = id } }
            model.fixture.archivedSessions = archived
        }
    }

    /// The state a scene 10 state is built on: `collapsed` and `workstreams` follow the new session's answer (same panes, the new task's
    /// group folded, or every group open), and the task menu and its two questions stand on the deck resumed (the project view).
    nonisolated static func s10Base(_ name: String) -> String {
        switch name {
        case "collapsed", "workstreams": "newsession-sent"
        case "task-menu-target", "archive-ask", "archived": "deck-resumed"
        default: name
        }
    }

    static func applyS10(_ screen: String, model: AppModel, dir: URL, video: Fixture.VideoS2, project: String) {
        guard let d = s10Data(dir: dir), let folder = model.videoDemoFolder else { return }
        let requested = String(screen.dropFirst("video-s10-".count))
        let name = s10Base(requested)
        model.fixture.sessions += d.sessions.filter { s in !model.fixture.sessions.contains { $0.sessionId == s.sessionId } }   // the same set all through scene 10, flat included
        let fm = FileManager.default
        model.videoTasks = true
        model.listClock = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 9, minute: 41))
        func key(_ n: String) -> String { model.fixture.sessions.first { $0.project == project && $0.name == n }?.tabKey ?? n }
        if name == "flat" { return }   // the project as scene 7 ended: no tasks yet, the list flat
        // The tree as a live project's starts: folders closed, but the ones holding what's open (docs/, and tasks/ with a note showing), so the list has its room.
        let noteShown = ["tasknote", "newtask-untitled", "newtask-created", "newtask-details", "newsession", "newsession-sent", "board-deck"].contains(name)
        model.videoClosedFolders = Set(["eval", "prototype", "research"] + (noteShown ? [] : ["tasks"]))

        // The new task, as far along as the story is: its note (File › New Task, named, described, linked), and its session.
        let nt = d.newTask
        let newPath = nt["path"] as? String ?? "tasks/warn-about-glare-before-the-photo.md"
        let session = nt["session"] as? [String: Any] ?? [:]
        let withNew = ["newtask-untitled", "newtask-created", "newtask-details", "newsession", "newsession-sent", "board", "board-deck", "deck-resumed"].contains(name)
        let linked = ["newsession", "newsession-sent", "board", "board-deck", "deck-resumed"].contains(name)
        var notePath = newPath
        if withNew {
            let note: String?
            switch name {
            case "newtask-untitled":
                notePath = untitledPath
                note = TaskNotes.newNote(title: "Untitled task", links: [], template: Templates.baseTask, date: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 10, minute: 2)) ?? Date())
            case "newtask-created": note = try? String(contentsOf: dir.appending(path: nt["created"] as? String ?? ""), encoding: .utf8)
            case "newtask-details": note = try? String(contentsOf: dir.appending(path: nt["details"] as? String ?? ""), encoding: .utf8)
            default: note = try? String(contentsOf: dir.appending(path: nt["linked"] as? String ?? ""), encoding: .utf8)
            }
            if let note { try? note.write(to: folder.appending(path: notePath), atomically: true, encoding: .utf8) }
        }

        // Tasks as the lists and the board read them from the notes; sessions grouped under their tasks as Duo's snapshot groups them.
        var tasks = d.tasks
        if withNew {
            var t = Fixture.TaskSummary(project: project, path: notePath, title: notePath == untitledPath ? "Untitled task" : (nt["title"] as? String ?? newTaskTitle),
                                        status: "open", sessionIds: linked ? [d.newSessionId] : [])
            t.created = "2026-10-13"
            tasks.append(t)
        }
        if linked, let template = model.fixture.sessions.first(where: { $0.project == project && $0.name == autoAdd }) {
            var s = template
            s.name = session["title"] as? String ?? "Glare warning copy"
            s.sessionId = d.newSessionId
            s.state = name == "newsession" ? .idle : .readyForReview; s.wait = name == "newsession" ? "now" : "2m"
            s.question = nil; s.options = nil; s.summary = nil; s.forkOf = nil; s.document = nil; s.reason = nil
            model.fixture.sessions.append(s)
        }
        // Archive Task and Its Sessions, as the model leaves the lists (the real call's file writes aside): the note and its sessions go to the Archived fold.
        if requested == "archived", let i = tasks.firstIndex(where: { $0.title == archivedTaskTitle }) {
            tasks[i].archived = true
            for id in tasks[i].sessionIds { if let n = model.fixture.sessions.first(where: { $0.sessionId == id })?.name { archive(n, in: model) } }
            model.expandedGroups.insert("\(project)/archived")
        }
        model.fixture.tasks = tasks
        model.fixture.groups = model.fixture.groups.filter { $0.project != project } + tasks.filter { $0.archived != true }.compactMap { t in
            let names = t.sessionIds.compactMap { id in model.fixture.sessions.first { $0.project == project && $0.sessionId == id }?.name }
            return names.isEmpty ? nil : Fixture.Group(name: t.title, project: project, sessions: names, threads: names.map { [$0] }, task: t.path)
        }
        model.expandedGroups.formUnion(["Auto-add decision", "Deck for Thursday"])
        // Every open task unfolded, so every session shows; a done task stays folded, as completing one folds it (Geoff's v10 note).
        if requested == "workstreams" { model.expandedGroups.formUnion(tasks.filter { $0.status != "done" }.map(\.title)) }
        if name == "newsession" || name == "newsession-sent" { model.expandedGroups.insert(nt["title"] as? String ?? newTaskTitle) }   // the new session shows under its task
        if requested == "collapsed" { model.expandedGroups.remove(nt["title"] as? String ?? newTaskTitle) }   // the new task's disclosure clicked: its group folds, "Glare warning copy" hidden
        model.fixture.projectFiles[project] = (model.fixture.projectFiles[project] ?? []) + tasks.map(\.path).sorted()

        // The right pane: a task's note, or scene 7's deck.
        func show(_ path: String) {
            if !model.openDocuments.contains(path) { model.openDocuments.append(path) }
            model.rightTab = path; model.selectedFile = path
        }
        switch name {
        case "tasknote": show("tasks/auto-add-decision.md"); model.selectedSidebarItem = "Auto-add decision"
        case "newtask-untitled", "newtask-created", "newtask-details", "newsession", "newsession-sent": show(notePath)
        case "board": model.boardProjects.insert(project)
        case "board-deck": show("tasks/deck-for-thursday.md"); model.boardProjects.insert(project)
        default: break
        }

        // A new session in the task (New Session in Task): its tab in front, the note's @-reference typed and not sent; answered, the recorded turn.
        if name == "newsession" || name == "newsession-sent" {
            let id = d.newSessionId
            let chat = ChatSession(key: id, mode: .chat)
            chat.videoAnchors = true
            chat.log.cwd = video.cwd ?? "/Users/sam/work/little-shared-library/shelf-scan"
            chat.setVersion("2.1.296")
            chat.log.model = "Opus 5.5"   // what the composer's chip reads once Claude's prompt is up
            if name == "newsession" {
                chat.ui.composer = session["draft"] as? String ?? "@\(newPath) "
                chat.focusComposer += 1
            } else {
                ChatRecording.play(dir.appending(path: nt["chat"] as? String ?? "chat-s10-task"), into: chat)
            }
            if chat.fixtureScreenText == nil { chat.fixtureScreenText = "" }
            model.fixtureChats[id] = chat
            model.fixtureTerminals[id] = TerminalSession(key: id, screen: "")
            model.parkedTabs.insert(id)
            model.consoleTab = id
        }
        // The Deck for Thursday session resumed from its card: its recorded chat in front, selected in the list.
        if name == "deck-resumed" {
            let n = d.deck["name"] as? String ?? "Deck for Thursday", id = key(n)
            let chat = s6Chat(dir.appending(path: d.deck["chat"] as? String ?? "chat-s10-deck"), cwd: video.cwd, picked: false, key: id)
            model.fixtureChats[id] = chat
            model.fixtureTerminals[id] = TerminalSession(key: id, screen: "")
            model.parkedTabs.insert(id)
            model.consoleTab = id
            model.selectedSidebarItem = model.fixture.sessions.first { $0.name == n }?.id
        }
        // Archive Task…'s own question (a Duo sheet, worded by the real code from the task's note and its sessions), over the project view.
        if requested == "archive-ask", let t = tasks.first(where: { $0.title == archivedTaskTitle }) { model.askArchiveTask(project: project, path: t.path) }
        _ = fm
    }

    // MARK: Actions

    /// The `--then` actions a scene 9 or 10 state needs once its window exists: scene 7's deck measure where the deck is on the right,
    /// the task note's properties and text frames where a note is.
    nonisolated static func s9s10Actions(_ screen: String, dir: URL) -> [String] {
        let deck = s7Actions("video-s7-pptx-after", dir: dir)
        if screen.hasPrefix("video-s9-") { return ["video-s9-board", "video-s9-list", "video-s9-beta"].contains(screen) ? [] : deck }
        let name = s10Base(String(screen.dropFirst("video-s10-".count)))
        switch name {
        case "flat", "grouped", "board", "deck-resumed": return deck
        case "newtask-untitled": return ["wait:1.5", "video:notecontext", "video:selectheading=\(untitledPath)", "wait:1", "video:measure=note"]
        default: return ["wait:1.5", "video:notecontext", "wait:1", "video:measure=note"]
        }
    }

    /// Frames in the task note's editor page, named for `--then anchors:`: the goal line, the sessions' links (the key and its rows),
    /// the lines Sam types (from Goal: to the Notes link) and the properties block.
    static let noteMeasureJS: String = {
        let prelude = String(editorMeasureJS.prefix(upTo: editorMeasureJS.range(of: "const added")!.lowerBound))
        return prelude + """
            const goalLine = lines.find((l) => /^(Goal:|Decide whether)/.test(l.textContent.trim()));
            const sessEls = [...document.querySelectorAll('.duo-fm-session')];
            const keyLine = lines.find((l) => /^sessions\\b/.test(l.textContent.trim()));
            const sessRects = [...(keyLine ? textBox(keyLine) : []), ...sessEls.map((e) => e.getBoundingClientRect())];
            const props = lines.filter((l) => l.classList.contains('duo-fm')).map((l) => l.getBoundingClientRect());
            return { goal: goalLine ? box(textBox(goalLine)) : null, sessions: box(sessRects), body: block('Goal:', 'Denise'), props: box(props) };
            """
    }()
}
