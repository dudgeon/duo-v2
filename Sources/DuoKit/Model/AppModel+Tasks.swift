import AppKit
import DuoControl
import Foundation
import SwiftUI

/// Tasks (DL-87, DL-93): Markdown notes in `tasks/`, whose `sessions:` frontmatter links the
/// sessions working on them. Make a Task works on a session or a group; Add to Task adds a
/// session's link to an existing note.
extension AppModel {
    /// The project's task notes, for Add to Task and `duo2 tasks`.
    public func taskNotes(in project: String) -> [TaskNote] {
        liveFolders[project].map { TaskNotes.load(project: $0) } ?? []
    }

    /// Make a Task from sessions (one session, or a group's). Writes `tasks/<slug>.md` linking
    /// them, opens it so it can be named and written, and for a group removes the group (the task
    /// replaces it). One undo puts everything back. Returns the note's path, or why not.
    @discardableResult
    public func makeTask(title: String, sessionIds: [String], project: String, replacingGroup group: String? = nil) -> Result<String, Error> {
        struct Refused: Error, CustomStringConvertible { let description: String }
        guard let folder = liveFolders[project] else { return .failure(Refused(description: "no project '\(project)'")) }
        let dir = folder.appending(path: "tasks")
        var slug = TaskNotes.slug(title), n = 2
        while FileManager.default.fileExists(atPath: dir.appending(path: "\(slug).md").path) { slug = TaskNotes.slug(title) + "-\(n)"; n += 1 }
        let file = dir.appending(path: "\(slug).md")
        let links = sessionIds.map { id in
            TaskNotes.link(title: fixture.sessions.first { $0.sessionId == id }?.name ?? id, id: id)
        }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(TaskNotes.newNote(title: title, links: links).utf8).write(to: file, options: .withoutOverwriting)
        } catch { return .failure(error) }
        let before = SessionIndex.load(project: folder)
        if let group {
            var index = before
            index.groups.removeAll { $0.name == group }
            try? index.save(project: folder)
            showGroups(project, index)
        }
        registerUndo("Make a Task") { model in
            try? FileManager.default.trashItem(at: file, resultingItemURL: nil)
            if group != nil {
                var now = SessionIndex.load(project: folder)
                now.groups = before.groups
                try? now.save(project: folder)
                model.showGroups(project, now)
            }
            model.refreshLive()
        }
        refreshLive()
        let path = "tasks/\(slug).md"
        if currentProject?.name != project { open(project: project) }
        openDocument(path)
        return .success(path)
    }

    /// + New task: a note with no sessions yet, opened to be named and written.
    public func newTask(in project: String, title: String = "Untitled task") {
        if case .failure(let e) = makeTask(title: title, sessionIds: [], project: project) { info("Couldn't make the task: \(e)") }
    }

    /// Status ▸ on a task: rewrites only `status:` (and `completed:` when done or dropped). Undoable.
    @discardableResult
    public func setTaskStatus(project: String, path: String, _ status: String) -> String? {
        guard let folder = liveFolders[project] else { return "no project '\(project)'" }
        let file = folder.appending(path: path)
        guard let data = FileManager.default.contents(atPath: file.path), let text = String(data: data, encoding: .utf8) else { return "\(path) isn't readable" }
        do { try Data(TaskNotes.settingStatus(status, in: text).utf8).write(to: file, options: .atomic) } catch { return error.localizedDescription }
        registerUndo("Set Task Status") { model in try? data.write(to: file, options: .atomic); model.refreshLive() }
        refreshLive()
        return nil
    }

    /// Opens a task's note in its project (from Home's list or a fold).
    public func openTask(project: String, path: String) {
        if currentProject?.name != project { open(project: project) }
        openDocument(path)
    }

    /// Make a Task on a session's right-click menu: titled after the session.
    public func makeTask(fromSession key: String) {
        guard let s = fixture.sessions.first(where: { $0.tabKey == key || $0.sessionId == key }), let id = s.sessionId else { return }
        let title = s.name.trimmingCharacters(in: CharacterSet(charactersIn: "“”\""))
        if case .failure(let e) = makeTask(title: title, sessionIds: [id], project: s.project) { info("Couldn't make the task: \(e)") }
    }

    /// Make a Task on a group's right-click menu: the group becomes a task with its sessions.
    public func makeTask(fromGroup name: String, project: String) {
        guard let folder = liveFolders[project], let g = SessionIndex.load(project: folder).groups.first(where: { $0.name == name }) else { return }
        if case .failure(let e) = makeTask(title: name, sessionIds: g.sessions, project: project, replacingGroup: name) { info("Couldn't make the task: \(e)") }
    }

    /// Add to Task ▸ <task>: the session's link goes into the note's `sessions:` list, nothing else
    /// in the note changes (DL-13's surgical edit). Undo puts the note's bytes back.
    @discardableResult
    public func addToTask(sessionKey key: String, task path: String) -> String? {
        guard let s = fixture.sessions.first(where: { $0.tabKey == key || $0.sessionId == key }), let id = s.sessionId,
              let folder = liveFolders[s.project] else { return "no session '\(key)'" }
        let file = folder.appending(path: path)
        guard let data = FileManager.default.contents(atPath: file.path), let text = String(data: data, encoding: .utf8) else { return "\(path) isn't readable" }
        guard let updated = TaskNotes.adding(TaskNotes.link(title: s.name, id: id), to: text) else { return "\(s.name) is already in \(path)" }
        do { try Data(updated.utf8).write(to: file, options: .atomic) } catch { return error.localizedDescription }
        registerUndo("Add to Task") { model in
            try? data.write(to: file, options: .atomic)
            model.refreshLive()
        }
        refreshLive()
        return nil
    }

    func taskVerb(_ id: ActionID, _ inv: Invocation, _ req: ControlRequest, _ done: @escaping @MainActor (Reply) -> Void) {
        switch id {
        case .tasks:
            let projects = inv.flags["project"].map { [$0] } ?? liveFolders.keys.sorted()
            let rows = projects.flatMap { p in taskNotes(in: p).map { (p, $0) } }
            done(.ok(rows.isEmpty ? "No task notes." : rows.map { p, t in
                "\(p)/\(t.path)  \(t.title)\(t.status.map { " (\($0))" } ?? "")  \(t.sessionIds.count) session\(t.sessionIds.count == 1 ? "" : "s")"
            }.joined(separator: "\n"), rows.map { p, t in ["project": p, "path": t.path, "title": t.title, "status": t.status ?? "", "sessions": t.sessionIds] }))
        case .taskMake:
            guard let k = inv[0] else { return done(.fail("usage: \(id.action.usage)")) }
            if let s = findSession(k, in: nil), let sid = s.sessionId {
                let title = inv.flags["title"] ?? s.name.trimmingCharacters(in: CharacterSet(charactersIn: "“”\""))
                switch makeTask(title: title, sessionIds: [sid], project: s.project) {
                case .success(let p): done(.ok("Made \(s.project)/\(p) with \(s.name). Undo: duo2 undo"))
                case .failure(let e): done(.fail("\(e)"))
                }
            } else if let g = findGroup(k, project: inv.flags["project"] ?? projectFor(cwd: req.cwd)?.name), let folder = liveFolders[g.project],
                      let ids = SessionIndex.load(project: folder).groups.first(where: { $0.name == g.name })?.sessions {
                switch makeTask(title: inv.flags["title"] ?? g.name, sessionIds: ids, project: g.project, replacingGroup: g.name) {
                case .success(let p): done(.ok("Group \(g.name) is now the task \(g.project)/\(p). Undo: duo2 undo"))
                case .failure(let e): done(.fail("\(e)"))
                }
            } else { done(.fail("no session or group '\(k)'")) }
        case .taskNew:
            let name = inv.flags["project"] ?? projectFor(cwd: req.cwd)?.name ?? currentProject?.name
            guard let name, project(named: name) != nil else { return done(.fail("which project? --project <p>")) }
            switch makeTask(title: inv.positional.isEmpty ? "Untitled task" : inv.positional.joined(separator: " "), sessionIds: [], project: name) {
            case .success(let p): done(.ok("Made \(name)/\(p). Undo: duo2 undo"))
            case .failure(let e): done(.fail("\(e)"))
            }
        case .taskStatus:
            guard let t = inv[0], let status = inv[1], TaskNotes.statuses.contains(status) else {
                return done(.fail("usage: \(id.action.usage) (\(TaskNotes.statuses.joined(separator: " | ")))"))
            }
            // From disk, not the snapshot: a task made a moment ago is found too.
            let all = liveFolders.keys.sorted().flatMap { p in taskNotes(in: p).map { Fixture.TaskSummary(project: p, path: $0.path, title: $0.title, status: $0.status, sessionIds: $0.sessionIds) } }
            let hit = all.filter { $0.path == t || $0.path == "tasks/\(t)" || $0.path == "tasks/\(t).md" || $0.title.caseInsensitiveCompare(t) == .orderedSame }
                .first { inv.flags["project"] == nil || $0.project == inv.flags["project"] }
            guard let hit else { return done(.fail("no task '\(t)'")) }
            if let why = setTaskStatus(project: hit.project, path: hit.path, status) { return done(.fail(why)) }
            done(.ok("\(hit.title) is \(status). Undo: duo2 undo"))
        case .taskAdd:
            guard let t = inv[0], let k = inv[1], let s = findSession(k, in: nil) else { return done(.fail("usage: \(id.action.usage)")) }
            let path = t.hasPrefix("tasks/") ? t : taskNotes(in: s.project).first { $0.title.caseInsensitiveCompare(t) == .orderedSame || $0.path == "tasks/\(t)" || $0.path == "tasks/\(t).md" }?.path
            guard let path else { return done(.fail("no task '\(t)' in \(s.project)")) }
            if let why = addToTask(sessionKey: s.tabKey, task: path) { return done(.fail(why)) }
            done(.ok("Added \(s.name) to \(s.project)/\(path). Undo: duo2 undo"))
        default: done(.fail("not a task verb"))
        }
    }
}

/// A group or task row's right-click menu (DL-93): a group can become a task; a task opens its note.
struct GroupRowMenu: ViewModifier {
    @Environment(AppModel.self) private var model
    let name: String
    let task: String?

    func body(content: Content) -> some View {
        if model.terminalsMode == .live, let project = model.currentProject?.name {
            content.contextMenu {
                if let task {
                    Button("Open Task Note") { model.openDocument(task) }
                    TaskStatusMenu(project: project, path: task)
                } else {
                    Button("Make a Task") { model.makeTask(fromGroup: name, project: project) }
                }
            }
        } else {
            content
        }
    }
}

/// Status ▸ open / in-progress / waiting / review / done / dropped, the current one checked.
struct TaskStatusMenu: View {
    @Environment(AppModel.self) private var model
    let project: String
    let path: String

    var body: some View {
        let current = model.fixture.tasks?.first { $0.project == project && $0.path == path }?.status ?? "open"
        Menu("Status") {
            ForEach(TaskNotes.statuses, id: \.self) { st in
                Button { if let why = model.setTaskStatus(project: project, path: path, st) { model.info(why) } } label: {
                    if st == current { Label(st, systemImage: "checkmark") } else { Text(st) }
                }
            }
        }
    }
}

/// Tasks with no sessions yet (DL-93): a fold under the session list. Stand-in look (S2-1).
struct TasksFold: View {
    @Environment(AppModel.self) private var model
    let project: String

    var body: some View {
        let listed = Set(model.fixture.sessions(inProject: project).compactMap(\.sessionId))
        let tasks = (model.fixture.tasks ?? []).filter { $0.project == project && $0.isOpen && !$0.sessionIds.contains(where: listed.contains) }
        if !tasks.isEmpty {
            let key = "\(project)/tasks-fold"
            let expanded = !model.expandedGroups.contains(key)   // open unless folded
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DuoSpace.gapRowItems) {
                    Chevron(direction: expanded ? .down : .right).frame(width: 10)
                    Text("Tasks · \(tasks.count)").duoText(.body).foregroundStyle(DuoColor.text2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8 + DuoSpace.selectionInset)
                .frame(height: DuoMetric.rowGroup)
                .contentShape(Rectangle())
                .onActivate { if expanded { model.expandedGroups.insert(key) } else { model.expandedGroups.remove(key) } }  // action: view group
                .accessibilityLabel(expanded ? "Hide tasks without sessions" : "Show \(tasks.count) tasks without sessions")
                .padding(.top, 8)
                if expanded {
                    ForEach(tasks) { t in TaskLine(task: t, showsProject: false, indented: true) }
                }
            }
        }
    }
}

/// One task as a line: a box, its title, its status (and project at All projects). Opens its note.
struct TaskLine: View {
    @Environment(AppModel.self) private var model
    let task: Fixture.TaskSummary
    let showsProject: Bool
    /// Inside the Tasks fold, lines sit under the fold's label (DL-100).
    var indented = false

    var body: some View {
        HStack(spacing: DuoSpace.gapRowItems) {
            TaskBox()
            Text(task.title).duoText(.body).lineLimit(1)
            if showsProject { Text(task.project).duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1) }
            Spacer(minLength: 8)
            if let st = task.status, st != "open" { Text(st.replacingOccurrences(of: "-", with: " ")).duoText(.body).foregroundStyle(DuoColor.text2) }
        }
        .padding(.horizontal, 8 + DuoSpace.selectionInset)
        .padding(.leading, indented ? 18 : 0)
        .frame(height: DuoMetric.rowSession)
        .contentShape(Rectangle())
        .onActivate { model.openTask(project: task.project, path: task.path) }  // action: doc open
        .contextMenu {
            Button("Open Task Note") { model.openTask(project: task.project, path: task.path) }
            TaskStatusMenu(project: task.project, path: task.path)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.title), task, \(task.status ?? "open")")
    }
}

/// A task's box: a 10 pt rounded square, stroke 1.3 (DL-100, slice2 `session-rows`).
struct TaskBox: View {
    var color: Color = DuoColor.text2

    var body: some View {
        RoundedRectangle(cornerRadius: 2).strokeBorder(color, lineWidth: 1.3)
            .frame(width: 8, height: 8).frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}

// MARK: - The properties block's controls (S2-5, DL-100)

extension AppModel {
    /// Tells the editor every session's state, name and wait, for the session lines and link glyphs
    /// in a note. Sent only when it changes.
    func pushNoteContext() {
        guard let e = editorIfLoaded else { return }
        var sessions: [String: [String: String]] = [:]
        for s in fixture.sessions + (fixture.archivedSessions ?? []) {
            guard let id = s.sessionId?.lowercased() else { continue }
            sessions[id] = ["state": s.state.rawValue, "name": s.name, "wait": s.wait ?? ""]
        }
        var ctx: [String: Any] = ["sessions": sessions]
        // Names and values used in this project's notes and Home's, for suggestions (frontmatter-handoff §4).
        // Read off the main thread, at most once a minute per project.
        let project = currentProject?.name ?? ""
        if let c = propertyCorpus, c.project == project { ctx.merge(c.json) { $1 } }
        if propertyCorpus?.project != project || (propertyCorpus?.at.timeIntervalSinceNow ?? -999) < -60, !scanningCorpus {
            scanningCorpus = true
            let here = liveFolders[project], home = liveRoot
            Task.detached(priority: .utility) { [weak self] in
                let json = PropertyCorpus.scan(here: here, others: home.map { [$0] } ?? [])
                await MainActor.run {
                    guard let self else { return }
                    self.propertyCorpus = (project, Date(), json)
                    self.scanningCorpus = false
                    self.pushNoteContext()
                }
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: ctx, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        e.setNoteContext(json)
    }

    /// The status popup (a native menu of the six statuses, with a tick on the current one) and
    /// `+ Add` on `sessions:` (this project's sessions not yet linked). Both edit the note's own text.
    func propertyAction(_ kind: String, _ body: [String: Any], in e: EditorController) {
        let at = NSPoint(x: body["x"] as? Double ?? 0, y: (body["y"] as? Double ?? 0) + 2)
        let menu = NSMenu()
        if kind == "propertiesFolded" {
            e.rememberFold(body["folded"] as? Bool == true)
            return
        }
        if kind == "propertyType", let line = body["line"] as? Int {
            // The seven types, a tick on the current one (frontmatter-handoff §3).
            let current = body["type"] as? String
            for (t, title) in [("text", "Text"), ("list", "List"), ("number", "Number"), ("checkbox", "Checkbox"), ("date", "Date"), ("datetime", "Date and Time"), ("link", "Link")] {
                let item = ActionMenuItem(title) { [weak self, weak e] in   // action: doc prop
                    guard let e else { return }
                    e.run("return duo.convertProperty(l, t)", ["l": line, "t": t]) { v in
                        let r = (v as? [String: Any])?["result"] as? String ?? ""
                        if r == "needs date" {
                            // Not a date yet: the calendar opens, and nothing changes until one is picked.
                            self?.showDatePicker(line: line, value: "", time: t == "datetime", at: at, in: e)
                        } else if r != "changed" && r != "unchanged" {
                            NSSound.beep()
                        }
                    }
                }
                item.state = t == current ? .on : .off
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: at, in: e.webView)
            return
        }
        if kind == "propertyDate", let line = body["line"] as? Int {
            showDatePicker(line: line, value: body["value"] as? String ?? "", time: body["time"] as? Bool == true, at: at, in: e)
            return
        }
        if kind == "propertyMenu", body["key"] as? String == "status" {
            let current = body["value"] as? String
            for st in TaskNotes.statuses {
                let item = ActionMenuItem(st.replacingOccurrences(of: "-", with: " ")) { [weak e] in   // action: task status
                    let closed = st == "done" || st == "dropped"
                    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
                    // Status, plus `completed:` when it's done or dropped, as Status ▸ writes it (F-70).
                    e?.run("duo.setProperty('status', s); duo.setProperty('completed', c); return 1", ["s": st, "c": closed ? f.string(from: Date()) : NSNull()]) { _ in }
                }
                item.state = st == current ? .on : .off
                menu.addItem(item)
            }
        } else if kind == "propertyAdd", let project = currentProject?.name {
            e.run("return duo.text()") { [weak self, weak e] v in
                guard let self, let e else { return }
                let text = v as? String ?? ""
                let linked = Set(text.matches(of: /duo2:\/\/session\/([0-9a-fA-F-]+)/).map { String($0.1).lowercased() })
                let candidates = self.fixture.sessions(inProject: project).filter { s in s.sessionId.map { !linked.contains($0.lowercased()) } ?? false }
                for s in candidates.prefix(30) {
                    guard let id = s.sessionId else { continue }
                    let title = s.name.trimmingCharacters(in: CharacterSet(charactersIn: "“”\""))
                    menu.addItem(ActionMenuItem(title) { [weak e] in   // action: task add
                        e?.run("duo.addListItem('sessions', i); return 1", ["i": "\"" + TaskNotes.link(title: title, id: id) + "\""]) { _ in }
                    })
                }
                if candidates.isEmpty { menu.addItem(ActionMenuItem("No other sessions in \(project)", enabled: false) {}) }
                menu.popUp(positioning: nil, at: at, in: e.webView)
            }
            return
        }
        menu.popUp(positioning: nil, at: at, in: e.webView)
    }

    /// The Mac's own date picker in a popover (frontmatter-handoff §4, Geoff's [G]); a pick writes
    /// the ISO form, `2026-10-14` (or `2026-10-14T09:30`), on that line only.
    func showDatePicker(line: Int, value: String, time: Bool, at: NSPoint, in e: EditorController) {
        let picker = NSDatePicker()
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerElements = time ? [.yearMonthDay, .hourMinute] : [.yearMonthDay]
        picker.isBezeled = false
        picker.drawsBackground = false
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = time ? "yyyy-MM-dd'T'HH:mm" : "yyyy-MM-dd"
        picker.dateValue = f.date(from: value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))) ?? Date()
        picker.sizeToFit()
        let host = NSViewController()
        host.view = NSView(frame: NSRect(x: 0, y: 0, width: picker.frame.width + 16, height: picker.frame.height + 16))
        picker.frame.origin = NSPoint(x: 8, y: 8)
        host.view.addSubview(picker)
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = host
        let target = DatePickTarget { [weak e] d in
            e?.run("return duo.setPropertyLine(l, v)", ["l": line, "v": f.string(from: d)]) { _ in }
        }
        picker.target = target
        picker.action = #selector(DatePickTarget.changed(_:))
        objc_setAssociatedObject(picker, &DatePickTarget.key, target, .OBJC_ASSOCIATION_RETAIN)
        pop.show(relativeTo: NSRect(x: at.x, y: at.y - 4, width: 1, height: 4), of: e.webView, preferredEdge: .maxY)
    }
}

/// Carries a date picker's changes to a closure.
@MainActor
final class DatePickTarget: NSObject {
    nonisolated(unsafe) static var key = 0
    let onPick: @MainActor (Date) -> Void
    init(_ onPick: @escaping @MainActor (Date) -> Void) { self.onPick = onPick }
    @objc func changed(_ sender: NSDatePicker) { onPick(sender.dateValue) }
}

