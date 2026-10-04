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
                } else {
                    Button("Make a Task") { model.makeTask(fromGroup: name, project: project) }
                }
            }
        } else {
            content
        }
    }
}
