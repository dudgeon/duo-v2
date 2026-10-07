import AppKit
import DuoControl
import Foundation
import SwiftUI

/// A task's right-click menu (DL-115, task-menu-handoff): rename, complete, link, reveal, move,
/// archive and delete a task note. Archive, Delete and Move ask first whether the task's sessions
/// (its `sessions:` list) go too, in a Duo question; a running session is never archived or deleted.
extension AppModel {
    func taskFile(_ project: String, _ path: String) -> URL? {
        guard let folder = liveFolders[project] else { return nil }
        let file = folder.appending(path: path)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    public func loadTask(_ project: String, _ path: String) -> TaskNote? {
        guard let file = taskFile(project, path), let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return TaskNotes.parse(text, path: path)
    }

    /// Runs `body`, gathering every undo it registers into one step named `name`.
    func asOneUndo(_ name: String, _ body: () -> Void) {
        let outer = undoBatch
        undoBatch = []
        body()
        let steps = undoBatch ?? []
        undoBatch = outer
        guard !steps.isEmpty else { return }
        registerUndo(name) { model in
            model.asOneUndo(name) { for s in steps.reversed() { s.1(model) } }
            model.refreshLive()
        }
    }

    /// Whether a session is running anywhere: a tab open in Duo, or live in another app.
    func isRunning(_ id: String) -> Bool {
        let key = (fixture.sessions + (fixture.archivedSessions ?? [])).first { $0.sessionId == id }?.tabKey ?? id
        return (terminals.existing(key).map { !$0.exited } ?? false) || liveElsewhere.contains(id)
    }

    /// The task's linked sessions Duo knows, listed or archived.
    func linkedSessions(_ t: TaskNote) -> [Fixture.Session] {
        let all = fixture.sessions + (fixture.archivedSessions ?? [])
        return t.sessionIds.compactMap { id in all.first { $0.sessionId == id } }
    }

    /// Saves the note first if it's open in the editor, so nothing typed is lost to a move or rewrite.
    func flushTask(_ file: URL, then: @escaping @MainActor () -> Void) {
        if let e = editorIfLoaded, e.url?.standardizedFileURL == file.standardizedFileURL { e.saveNow(force: true, completion: then) } else { then() }
    }

    /// Tabs, the editor and tab restore follow a note that moved within its project.
    func followTaskMove(project: String, from old: String, to new: String) {
        if currentProject?.name == project {
            moved(old, to: new, url: liveFolders[project]?.appending(path: new) ?? URL(fileURLWithPath: new))
        } else {
            openDocumentsByProject[project] = openDocumentsByProject[project]?.map { $0 == old ? new : $0 }
            if lastRightTab[project] == old { lastRightTab[project] = new }
            if let folder = liveFolders[project], let e = editorIfLoaded, e.url?.standardizedFileURL == folder.appending(path: old).standardizedFileURL {
                e.fileMoved(to: folder.appending(path: new))
            }
        }
        if let k = taskTitlesSeen?.removeValue(forKey: "\(project)/\(old)") { taskTitlesSeen?["\(project)/\(new)"] = k }
        if hoveredTaskRow == "\(project)/\(old)" { hoveredTaskRow = nil }
    }

    /// Moves a note within its project's tasks/ (no undo of its own). Returns the new path.
    func moveTaskFile(project: String, from old: String, to new: String) throws {
        guard let folder = liveFolders[project] else { return }
        try FileManager.default.moveItem(at: folder.appending(path: old), to: folder.appending(path: new))
        followTaskMove(project: project, from: old, to: new)
    }

    // MARK: Rename

    /// Rename (DL-115): the name changes in `title:` and the heading, and the note moves to the new
    /// name's slug (C-24; `-2`, `-3` when taken). One undo puts the name and the file back.
    @discardableResult
    public func renameTask(project: String, path: String, to raw: String) -> Result<String, Error> {
        struct Refused: Error, CustomStringConvertible { let description: String }
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !title.contains("\n") else { return .failure(Refused(description: "a task needs a name")) }
        guard let folder = liveFolders[project], let file = taskFile(project, path),
              let data = FileManager.default.contents(atPath: file.path), let text = String(data: data, encoding: .utf8) else {
            return .failure(Refused(description: "no task '\(path)' in \(project)"))
        }
        let new = TaskNotes.pathForTitle(title, current: path) { FileManager.default.fileExists(atPath: folder.appending(path: $0).path) }
        do {
            try Data(TaskNotes.renaming(to: title, in: text).utf8).write(to: file, options: .atomic)
            if new != path { try moveTaskFile(project: project, from: path, to: new) }
        } catch { return .failure(error) }
        taskTitlesSeen?["\(project)/\(new)"] = title
        registerUndo("Rename Task") { model in
            if new != path, (try? FileManager.default.moveItem(at: folder.appending(path: new), to: file)) != nil {
                model.followTaskMove(project: project, from: new, to: path)
            }
            try? data.write(to: file, options: .atomic)
            model.taskTitlesSeen?["\(project)/\(path)"] = TaskNotes.parse(text, path: path).title
            model.refreshLive()
        }
        refreshLive()
        return .success(new)
    }

    /// Rename on the menu: the note opens with its name selected, as + New task does; what's typed
    /// renames it (F-87), and the file follows once typing pauses (`followTaskTitles`).
    public func beginRenameTask(project: String, path: String) {
        openTask(project: project, path: path)
        editor.selectHeading(path: path)
    }

    /// A task whose name changed (in the editor, by an agent, on disk) moves to its new name's slug
    /// once the name has settled: saved, and nobody typing in it for 3 seconds (C-24). Runs after each refresh.
    public func followTaskTitles() {
        guard terminalsMode == .live else { return }
        let tasks = fixture.tasks ?? []
        guard var seen = taskTitlesSeen else {
            taskTitlesSeen = Dictionary(tasks.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
            return
        }
        for t in tasks {
            guard let before = seen[t.id] else { seen[t.id] = t.title; continue }
            guard before != t.title, let folder = liveFolders[t.project] else { continue }
            let file = folder.appending(path: t.path)
            if let e = editorIfLoaded, e.url?.standardizedFileURL == file.standardizedFileURL,
               e.dirty || e.conflict || Date().timeIntervalSince(e.lastTyped) < 3 { continue }   // still being typed: next time
            let new = TaskNotes.pathForTitle(t.title, current: t.path) { FileManager.default.fileExists(atPath: folder.appending(path: $0).path) }
            seen[t.id] = t.title
            guard new != t.path else { continue }
            do {
                try FileManager.default.moveItem(at: file, to: folder.appending(path: new))
                taskTitlesSeen = seen
                followTaskMove(project: t.project, from: t.path, to: new)
                seen = taskTitlesSeen ?? seen
                FileHandle.standardError.write(Data("task: \(t.project)/\(t.path) renamed to \(new) for its title\n".utf8))
                refreshLive()
            } catch {
                FileHandle.standardError.write(Data("task: couldn't move \(t.path) to \(new): \(error)\n".utf8))
            }
        }
        taskTitlesSeen = seen
    }

    // MARK: Complete, link, reveal

    /// Mark Complete (DL-130): the line shows checked, struck through and grey at once, stays for
    /// `rowHold` (5 s) in case it was a mistake (⌘Z or Mark Open keeps it), then leaves.
    public func completeTask(project: String, path: String) {
        let key = project + "/" + path
        // Only a listed (open) task holds; one already done just stays done.
        let listed = fixture.tasks?.first(where: { $0.id == key })?.isOpen == true
        if listed { completingTasks.insert(key) }
        if let why = setTaskStatus(project: project, path: path, "done") { completingTasks.remove(key); info(why); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + DuoMotionToken.rowHold.delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.completingTasks.contains(key) else { return }
                withDuoAnimation(.rowMove) { _ = self.completingTasks.remove(key) }
            }
        }
    }

    /// `[Title](duo2://task/<id>)`. A note without an `id:` gets one (a lowercase UUID), written once.
    public func taskLink(project: String, path: String) -> String? {
        guard let file = taskFile(project, path), let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        var t = TaskNotes.parse(text, path: path)
        if t.id == nil {
            let id = UUID().uuidString.lowercased()
            guard (try? Data(TaskNotes.setting("id", id, in: text).utf8).write(to: file, options: .atomic)) != nil else { return nil }
            t.id = id
        }
        let title = t.title.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        return "[\(title)](\(Self.taskURL(t.id!)))"
    }

    public static func taskURL(_ id: String) -> String {
        "duo2://task/" + (id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id)
    }

    public func copyTaskLink(project: String, path: String) {
        if let link = taskLink(project: project, path: path) { FileActions.copy(link) } else { info("Couldn't link \(path).") }
    }

    /// Opens the task a `duo2://task/<id>` link names, wherever its note is now.
    public func openTaskLink(_ id: String) {
        for p in liveFolders.keys.sorted() {
            if let t = taskNotes(in: p).first(where: { $0.id == id }) { return openTask(project: p, path: t.path) }
        }
        info("No task with the id \(id.prefix(8))… is in any project. Its note may have been deleted.")
    }

    public func revealTask(project: String, path: String) {
        if let file = taskFile(project, path) { FileActions.reveal(file) }
    }

    // MARK: Archive

    /// Archive (DL-115): the note gets `archived: true` and leaves the lists; with `sessions`, its
    /// sessions are archived too, except any that are running. One undo. Returns what was left out.
    @discardableResult
    public func archiveTask(project: String, path: String, sessions: Bool) -> Result<[String], Error> {
        struct Refused: Error, CustomStringConvertible { let description: String }
        guard let file = taskFile(project, path), let data = FileManager.default.contents(atPath: file.path),
              let text = String(data: data, encoding: .utf8) else { return .failure(Refused(description: "no task '\(path)' in \(project)")) }
        let t = TaskNotes.parse(text, path: path)
        var skipped: [String] = []
        var failed: Error?
        asOneUndo("Archive Task") {
            do { try Data(TaskNotes.setting("archived", "true", in: text).utf8).write(to: file, options: .atomic) } catch { failed = error; return }
            showNow { setShownTask(project, path) { $0.archived = true } }
            registerUndo("Archive Task") { model in try? data.write(to: file, options: .atomic); model.refreshLive() }
            guard sessions else { return }
            for s in linkedSessions(t) where !(fixture.archivedSessions ?? []).contains(where: { $0.sessionId == s.sessionId }) {
                if let why = setSessionArchived(s.tabKey, true) { skipped.append(s.name); FileHandle.standardError.write(Data("task archive: \(why)\n".utf8)) }
            }
        }
        if let failed { return .failure(failed) }
        if currentProject?.name == project, hoveredTaskRow == "\(project)/\(path)" { hoveredTaskRow = nil }
        refreshLive()
        return .success(skipped)
    }

    /// Unarchive: the task comes back to the lists, with the sessions that were archived with it.
    @discardableResult
    public func unarchiveTask(project: String, path: String) -> String? {
        guard let file = taskFile(project, path), let data = FileManager.default.contents(atPath: file.path),
              let text = String(data: data, encoding: .utf8) else { return "no task '\(path)' in \(project)" }
        let t = TaskNotes.parse(text, path: path)
        var failed: String?
        asOneUndo("Unarchive Task") {
            do { try Data(TaskNotes.setting("archived", nil, in: text).utf8).write(to: file, options: .atomic) } catch { failed = error.localizedDescription; return }
            showNow { setShownTask(project, path) { $0.archived = nil } }
            registerUndo("Unarchive Task") { model in try? data.write(to: file, options: .atomic); model.refreshLive() }
            for s in fixture.archivedSessions ?? [] where s.sessionId.map(t.sessionIds.contains) ?? false {
                _ = setSessionArchived(s.tabKey, false)
            }
        }
        refreshLive()
        return failed
    }

    // MARK: Delete

    /// Delete (DL-115): the note goes to the Trash (Edit › Undo brings it back); with `sessions`,
    /// its sessions are deleted for good as Delete Session… deletes them, except any that are running.
    @discardableResult
    public func deleteTask(project: String, path: String, sessions: Bool) -> Result<String, Error> {
        struct Refused: Error, CustomStringConvertible { let description: String }
        guard let file = taskFile(project, path), let text = try? String(contentsOf: file, encoding: .utf8) else {
            return .failure(Refused(description: "no task '\(path)' in \(project)"))
        }
        let t = TaskNotes.parse(text, path: path)
        var trashed: NSURL?
        do {
            if currentProject?.name == project { closeDocumentsUnder(path) }
            else if let e = editorIfLoaded, e.url?.standardizedFileURL == file.standardizedFileURL { e.closeFile() }
            openDocumentsByProject[project]?.removeAll { $0 == path }
            try FileManager.default.trashItem(at: file, resultingItemURL: &trashed)
        } catch { return .failure(error) }
        let inTrash = trashed as URL?
        registerUndo("Delete Task") { model in
            if let inTrash, !FileManager.default.fileExists(atPath: file.path) { try? FileManager.default.moveItem(at: inTrash, to: file) }
            model.refreshLive()
        }
        var said = ["Moved \(t.title) to the Trash."]
        if sessions {
            var kept: [String] = [], gone: [String] = []
            for s in linkedSessions(t) {
                guard let id = s.sessionId else { continue }
                if isRunning(id) { kept.append(s.name); continue }
                do { _ = try deleteSessionNow(s); gone.append(s.name) } catch { kept.append(s.name); FileHandle.standardError.write(Data("task delete: \(error)\n".utf8)) }
            }
            if !gone.isEmpty { said.append("Deleted \(gone.count) session\(gone.count == 1 ? "" : "s"): \(gone.joined(separator: ", ")).") }
            if !kept.isEmpty { said.append("Kept \(kept.joined(separator: ", ")) (running, or not on disk).") }
        }
        refreshLive()
        return .success(said.joined(separator: " "))
    }

    // MARK: Move

    /// Move to Project (DL-115): the note moves to the other project's tasks/ (numbered if the name
    /// is taken); with `sessions`, its sessions move there too, as Move to Project moves them. One undo.
    @discardableResult
    public func moveTask(project: String, path: String, to target: String, sessions: Bool) -> Result<String, Error> {
        struct Refused: Error, CustomStringConvertible { let description: String }
        guard let file = taskFile(project, path), let text = try? String(contentsOf: file, encoding: .utf8) else {
            return .failure(Refused(description: "no task '\(path)' in \(project)"))
        }
        guard target != project, let targetFolder = liveFolders[target], fixture.projects.contains(where: { $0.name == target && !$0.isFolderOnly }) else {
            return .failure(Refused(description: "no project '\(target)' to move it to"))
        }
        let t = TaskNotes.parse(text, path: path)
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        var new = "tasks/\(name).md", n = 2
        while FileManager.default.fileExists(atPath: targetFolder.appending(path: new).path) { new = "tasks/\(name)-\(n).md"; n += 1 }
        let dest = targetFolder.appending(path: new)
        var failed: Error?
        asOneUndo("Move Task") {
            do {
                try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                if currentProject?.name == project { closeDocumentsUnder(path) }
                else if let e = editorIfLoaded, e.url?.standardizedFileURL == file.standardizedFileURL { e.closeFile() }
                openDocumentsByProject[project]?.removeAll { $0 == path }
                try FileManager.default.moveItem(at: file, to: dest)
            } catch { failed = error; return }
            registerUndo("Move Task") { model in
                if !FileManager.default.fileExists(atPath: file.path) { try? FileManager.default.moveItem(at: dest, to: file) }
                model.refreshLive()
            }
            if sessions {
                let moving = fixture.sessions.filter { s in (s.sessionId.map(t.sessionIds.contains) ?? false) && s.project == project }
                if !moving.isEmpty { apply(moving, to: target, folder: targetFolder, action: "Move Task") }
            }
        }
        if let failed { return .failure(failed) }
        taskTitlesSeen?.removeValue(forKey: "\(project)/\(path)")
        refreshLive()
        return .success("\(target)/\(new)")
    }

    // MARK: The questions (task-menu-handoff board C)

    /// Each linked session as a line in the question's box: its name, then its state and age, or that it's running.
    func questionItems(_ t: TaskNote, runningSays: String?) -> [DuoQuestion.Item] {
        linkedSessions(t).map { s in
            let running = s.sessionId.map(isRunning) ?? false
            if running, let runningSays { return .init(what: s.name, path: runningSays) }
            return .init(what: s.name, path: s.state.spokenName + (s.wait.map { " · \($0)" } ?? "") + (s.project != (fixture.tasks?.first { $0.path == t.path }?.project ?? s.project) ? " · in \(s.project)" : ""))
        }
    }

    /// Asks in Duo; a scripted run (DUO_AUTOCONFIRM) logs the question and takes its default.
    func ask(_ q: DuoQuestion) {
        if Env.autoconfirm {
            FileHandle.standardError.write(Data("question: \(q.title) | \(q.choices.map(\.label).joined(separator: " / "))\n".utf8))
            return q.choices.first(where: \.isDefault)?.action() ?? ()
        }
        SheetCenter.shared.ask(q)
    }

    func sessionCount(_ n: Int) -> String { n == 1 ? "1 session" : "\(n) sessions" }

    func runningNote(_ t: TaskNote, verb: String) -> String? {
        let running = linkedSessions(t).filter { $0.sessionId.map(isRunning) ?? false }
        guard !running.isEmpty else { return nil }
        let names = running.map { "“\($0.name)”" }.joined(separator: ", ")
        return "\(names) \(running.count == 1 ? "is" : "are") running, so \(running.count == 1 ? "it isn’t" : "they aren’t") \(verb). End \(running.count == 1 ? "it" : "them") first to \(verb == "archived" ? "archive" : "delete") \(running.count == 1 ? "it" : "them") too."
    }

    /// Archive Task…: with no sessions it just happens (undoable); otherwise the three-button question.
    public func askArchiveTask(project: String, path: String, answered: (@MainActor (String) -> Void)? = nil) {
        guard let t = loadTask(project, path) else { return }
        let report: @MainActor (Result<[String], Error>) -> Void = { [weak self] r in
            switch r {
            case .success(let skipped): answered?("Archived \(t.title)" + (skipped.isEmpty ? "." : "; kept \(skipped.joined(separator: ", ")) (running)."))
            case .failure(let e): self?.info("Couldn't archive the task: \(e)"); answered?("Not archived: \(e)")
            }
        }
        let n = linkedSessions(t).count
        guard n > 0 else { return report(archiveTask(project: project, path: path, sessions: false)) }
        var q = DuoQuestion(title: "Archive “\(t.title)”?", choices: [])
        q.paragraphs = ["Its note stays in `tasks/` and leaves the lists. Its \(sessionCount(n)) can be archived with it:"]
        q.items = questionItems(t, runningSays: "running: stays listed")
        q.note = runningNote(t, verb: "archived") ?? "Bring \(n == 1 ? "it" : "them") back from \(project)’s Archived fold. Edit › Undo puts \(n == 1 ? "it" : "them") back now."
        q.choices = [
            .init(label: "Cancel", isCancel: true) { answered?("Not archived: the user clicked Cancel in Duo.") },
            .init(label: "Archive Task Only") { [weak self] in if let self { report(self.archiveTask(project: project, path: path, sessions: false)) } },
            .init(label: "Archive Task and Its Sessions", isDefault: true) { [weak self] in if let self { report(self.archiveTask(project: project, path: path, sessions: true)) } },
        ]
        ask(q)
    }

    /// Delete Task…: always asks. With sessions, three buttons; Delete Task Only is the default (board C).
    public func askDeleteTask(project: String, path: String, answered: (@MainActor (String) -> Void)? = nil) {
        guard let t = loadTask(project, path) else { return }
        let run: @MainActor (Bool) -> Void = { [weak self] sessions in
            guard let self else { return }
            switch self.deleteTask(project: project, path: path, sessions: sessions) {
            case .success(let m): answered?(m)
            case .failure(let e): self.info("Couldn't delete the task: \(e)"); answered?("Not deleted: \(e)")
            }
        }
        let cancel = DuoQuestion.Choice(label: "Cancel", isCancel: true) { answered?("Not deleted: the user clicked Cancel in Duo.") }
        let n = linkedSessions(t).count
        var q = DuoQuestion(title: "Delete “\(t.title)”?", choices: [])
        if n == 0 {
            q.paragraphs = ["Its note goes to the Trash. Edit › Undo brings it back."]
            q.choices = [cancel, .init(label: "Move to Trash", isDefault: true) { run(false) }]
        } else {
            q.paragraphs = ["Its note goes to the Trash. Its \(sessionCount(n)) can be deleted with it, transcripts and Duo’s copies:"]
            q.items = questionItems(t, runningSays: "running: never deleted")
            q.note = runningNote(t, verb: "deleted")
                ?? "Edit › Undo brings the note back. Deleted sessions can be put back from the Trash, but Duo can’t undo that. A running session is never deleted."
            q.choices = [cancel, .init(label: "Delete Task and Its Sessions") { run(true) }, .init(label: "Delete Task Only", isDefault: true) { run(false) }]
        }
        ask(q)
    }

    /// Move to Project ▸ <project>: with no sessions it just moves (undoable); otherwise the question.
    public func askMoveTask(project: String, path: String, to target: String, answered: (@MainActor (String) -> Void)? = nil) {
        guard let t = loadTask(project, path) else { return }
        let run: @MainActor (Bool) -> Void = { [weak self] sessions in
            guard let self else { return }
            switch self.moveTask(project: project, path: path, to: target, sessions: sessions) {
            case .success(let p): answered?("Moved \(t.title) to \(p).")
            case .failure(let e): self.info("Couldn't move the task: \(e)"); answered?("Not moved: \(e)")
            }
        }
        let here = fixture.sessions.filter { s in (s.sessionId.map(t.sessionIds.contains) ?? false) && s.project == project }
        guard !here.isEmpty else { return run(false) }
        var q = DuoQuestion(title: "Move “\(t.title)” to \(target)?", choices: [])
        q.paragraphs = ["Its note moves to `\(target)/tasks/`. Its \(sessionCount(here.count)) can move with it:"]
        q.items = here.map { .init(what: $0.name, path: "from \(project)") }
        q.note = "Sessions left behind stay linked from the note. Edit › Undo puts it all back."
        q.choices = [
            .init(label: "Cancel", isCancel: true) { answered?("Not moved: the user clicked Cancel in Duo.") },
            .init(label: "Move Task Only") { run(false) },
            .init(label: "Move Task and Its Sessions", isDefault: true) { run(true) },
        ]
        ask(q)
    }
}

// MARK: - The menu (task-menu-handoff boards A and B)

/// A task's right-click menu, wherever a task is listed: a line in the Tasks fold, a task group in
/// the session list, Open tasks at All projects (board A), and an archived task (board B).
struct TaskMenuItems: View {
    let model: AppModel
    let project: String
    let path: String

    var body: some View {
        let summary = model.fixture.tasks?.first { $0.project == project && $0.path == path }
        if summary?.archived == true {
            Button("Open Task Note") { model.openTask(project: project, path: path) }
            Divider()
            Button("Copy Link") { model.copyTaskLink(project: project, path: path) }
            Button("Reveal in Finder") { model.revealTask(project: project, path: path) }
            Divider()
            Button("Unarchive Task") { if let why = model.unarchiveTask(project: project, path: path) { model.info(why) } }
            Button("Delete Task…") { model.askDeleteTask(project: project, path: path) }
        } else {
            Button("Open Task Note") { model.openTask(project: project, path: path) }
            Button("New Session in Task") { model.startSession(inTask: path, project: project) }
            AddSessionMenu(model: model, project: project, path: path, linked: summary?.sessionIds ?? [])
            Divider()
            Button("Rename") { model.beginRenameTask(project: project, path: path) }
            Button("Mark Complete") { model.completeTask(project: project, path: path) }
            TaskStatusMenu(project: project, path: path)
            Divider()
            Button("Copy Link") { model.copyTaskLink(project: project, path: path) }
            Button("Reveal in Finder") { model.revealTask(project: project, path: path) }
            MoveTaskMenu(model: model, project: project, path: path)
            Divider()
            Button("Archive Task…") { model.askArchiveTask(project: project, path: path) }
            Button("Delete Task…") { model.askDeleteTask(project: project, path: path) }
        }
    }
}

/// Add Session ▸ the project's sessions not linked yet (as the note's `+ Add` lists them).
struct AddSessionMenu: View {
    let model: AppModel
    let project: String
    let path: String
    let linked: [String]

    var body: some View {
        let candidates = model.fixture.sessions(inProject: project).filter { s in s.sessionId.map { !linked.contains($0) } ?? false }
        if candidates.isEmpty {
            Button("Add Session") {}.disabled(true)   // nothing in the project left to link
        } else {
            Menu("Add Session") {
                ForEach(candidates.prefix(30), id: \.tabKey) { s in
                    Button(s.name.trimmingCharacters(in: CharacterSet(charactersIn: "“”\""))) {
                        if let why = model.addToTask(sessionKey: s.tabKey, task: path) { model.info(why) }
                    }
                }
            }
        }
    }
}

/// Move to Project ▸ every other project (not a plain folder: a task lives in a project's tasks/).
struct MoveTaskMenu: View {
    let model: AppModel
    let project: String
    let path: String

    var body: some View {
        let targets = model.moveTargets(excluding: project).filter { !$0.isFolderOnly && !$0.isMissing }
        if targets.isEmpty {
            Button("Move to Project") {}.disabled(true)
        } else {
            Menu("Move to Project") {
                ForEach(targets) { p in
                    Button(p.name) { model.askMoveTask(project: project, path: path, to: p.name) }
                }
            }
        }
    }
}

// MARK: - duo2 task rename | archive | unarchive | delete | move | link | reveal (DL-71)

extension AppModel {
    func taskMenuVerb(_ id: ActionID, _ inv: Invocation, _ req: ControlRequest, _ done: @escaping @MainActor (Reply) -> Void) {
        guard let t = inv[0] else { return done(.fail("usage: \(id.action.usage)")) }
        guard let hit = findTask(t, project: inv.flags["project"] ?? projectFor(cwd: req.cwd)?.name) ?? findTask(t, project: nil) else {
            return done(.fail("no task '\(t)'"))
        }
        let both = inv.has("sessions") && inv.has("keep-sessions")
        let choice: Bool? = inv.has("sessions") ? true : inv.has("keep-sessions") ? false : nil
        switch id {
        case .taskRename:
            let title = inv.positional.dropFirst().joined(separator: " ")
            guard !title.isEmpty else { return done(.fail("usage: \(id.action.usage)")) }
            switch renameTask(project: hit.project, path: hit.path, to: title) {
            case .success(let p): done(.ok("Renamed \(hit.title) to \(title)\(p == hit.path ? "" : "; its note is now \(hit.project)/\(p)"). Undo: duo2 undo", ["project": hit.project, "path": p, "title": title]))
            case .failure(let e): done(.fail("\(e)"))
            }
        case .taskArchive:
            guard !both else { return done(.fail("--sessions or --keep-sessions, not both")) }
            if hit.archived == true { return done(.ok("\(hit.title) is already archived.")) }
            if let choice {
                switch archiveTask(project: hit.project, path: hit.path, sessions: choice) {
                case .success(let skipped):
                    done(.ok("Archived \(hit.title)\(choice ? " and its sessions" : "")\(skipped.isEmpty ? "" : "; kept \(skipped.joined(separator: ", ")) (running)"). It's in \(hit.project)'s Archived fold, still searchable. Undo: duo2 undo"))
                case .failure(let e): done(.fail("\(e)"))
                }
            } else {
                askArchiveTask(project: hit.project, path: hit.path) { done(.ok($0)) }
            }
        case .taskUnarchive:
            if let why = unarchiveTask(project: hit.project, path: hit.path) { return done(.fail(why)) }
            done(.ok("\(hit.title) is back in \(hit.project)'s lists. Undo: duo2 undo"))
        case .taskDelete:
            askDeleteTask(project: hit.project, path: hit.path) { done(.ok($0)) }
        case .taskMove:
            guard !both else { return done(.fail("--sessions or --keep-sessions, not both")) }
            guard let target = inv[1], project(named: target) != nil else { return done(.fail("usage: \(id.action.usage)")) }
            if let choice {
                switch moveTask(project: hit.project, path: hit.path, to: target, sessions: choice) {
                case .success(let p): done(.ok("Moved \(hit.title) to \(p)\(choice ? " with its sessions" : ""). Undo: duo2 undo", ["project": target, "path": String(p.dropFirst(target.count + 1))]))
                case .failure(let e): done(.fail("\(e)"))
                }
            } else {
                askMoveTask(project: hit.project, path: hit.path, to: target) { done(.ok($0)) }
            }
        case .taskLink:
            guard let link = taskLink(project: hit.project, path: hit.path) else { return done(.fail("couldn't link \(hit.path)")) }
            done(.ok(link, ["link": link, "project": hit.project, "path": hit.path]))
        case .taskReveal:
            revealTask(project: hit.project, path: hit.path)
            done(.ok("Showed \(hit.project)/\(hit.path) in Finder."))
        default: done(.fail("not a task verb"))
        }
    }
}
