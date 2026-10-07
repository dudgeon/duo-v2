import DuoControl
import Foundation

/// A session attributed to a task knows it (DL-116): `duo2 session task`, and the `context` hook
/// that Duo's sessions run at SessionStart and UserPromptSubmit (`duo2 hook context`). The same
/// hook tells every session its project's brief (ENH-16, F-146).
extension AppModel {
    /// `duo2 session task [id]`; with `--hook start|prompt` (from `duo2 hook context`), the text
    /// for Claude's context, empty for none, and what was told is recorded per session.
    func sessionTaskVerb(_ inv: Invocation, _ req: ControlRequest, _ done: @escaping @MainActor (Reply) -> Void) {
        guard let key = inv[0] ?? req.session else { return done(.fail("which session? Run it from a Claude session, or name one")) }
        // A session Duo hasn't listed yet (one starting now) is still looked up by its id.
        let sid = findSession(key, in: nil)?.sessionId ?? key
        guard let event = inv.flags["hook"] else {
            let now = TaskContext.entries(for: [sid], folders: liveFolders)
            return done(.ok(TaskContext.atStart(now, cwd: req.cwd) ?? TaskContext.none, ["tasks": now.map(Self.taskJSON)]))
        }
        var ids = [sid]
        if event == "start", inv.flags["source"] == "clear",
           let before = predecessor(of: sid, pid: inv.flags["pid"].flatMap { Int32($0) }, origin: inv.flags["origin"]) {
            continueTasks(from: before, to: sid)
            ids.append(before)  // a note open with unsaved text takes the link in its buffer, not yet on disk
        }
        let now = TaskContext.entries(for: ids, folders: liveFolders)
        let task = TaskContext.hook(event, sessionId: sid, now: now, cwd: req.cwd)
        // The project's brief comes first (ENH-16, F-146).
        let brief = ProjectContext.folder(project: findSession(key, in: nil)?.project, cwd: req.cwd, folders: liveFolders)
            .flatMap { ProjectContext.brief(name: $0.name, folder: $0.folder) }
        let text = ProjectContext.joined(ProjectContext.hook(event, sessionId: sid, now: brief), task)
        done(.ok(text, ["context": text, "tasks": now.map(Self.taskJSON), "project": brief?.name ?? ""]))
    }

    static func taskJSON(_ t: TaskContext.Entry) -> [String: Any] {
        ["project": t.project, "path": t.path, "file": (t.folder as NSString).appendingPathComponent(t.path), "title": t.title,
         "status": t.status ?? "open", "id": t.id ?? "", "archived": t.archived]
    }

    /// The session `/clear` replaced: the id of the terminal the hook runs in, if Duo hasn't
    /// re-keyed it yet; else the provenance Duo filed (F-29); else the id Duo started it with.
    func predecessor(of sid: String, pid: Int32?, origin: String?) -> String? {
        if let pid, let t = terminals.all.first(where: { t in t.view.process.map { AppOwning.descends(pid, from: $0.shellPid) } ?? false }),
           t.key != sid { return t.key }
        for folder in liveFolders.values {
            if let p = SessionIndex.load(project: folder).sessions.first(where: { $0.sessionId == sid })?.provenance,
               p.hasPrefix("continued-from:") { return String(p.dropFirst("continued-from:".count)) }
        }
        return origin.flatMap { $0 == sid || $0.isEmpty ? nil : $0 }
    }

    /// After `/clear`, the new session joins every task the old one was in (Geoff, 2026-10-06):
    /// its link goes into each note's `sessions:` list, next to the old one.
    func continueTasks(from old: String, to new: String) {
        let title = fixture.sessions.first { $0.sessionId == old }?.name.trimmingCharacters(in: CharacterSet(charactersIn: "“”\"")) ?? "Continued session"
        let link = TaskNotes.link(title: title, id: new)
        var changed = false
        for t in TaskContext.entries(for: [old], folders: liveFolders) {
            let file = URL(fileURLWithPath: t.folder).appending(path: t.path)
            if let e = editorIfLoaded, e.url?.standardizedFileURL == file.standardizedFileURL {
                e.run("duo.addListItem('sessions', i); return 1", ["i": "\"" + link + "\""]) { _ in }
            } else if let text = try? String(contentsOf: file, encoding: .utf8), let updated = TaskNotes.adding(link, to: text) {
                try? Data(updated.utf8).write(to: file, options: .atomic)
                changed = true
            }
        }
        if changed { refreshLive() }
    }
}
