import AppKit
import Foundation

/// A project's folder moved or missing (DB-8, LR-23). Duo never drops the sessions: a folder that's
/// gone keeps its tile and says what happened; a moved one is found again by its `.duo` list or
/// its name; its sessions follow it the way Claude's /cd moves them (journaled, undoable). The look
/// is a stand-in until slice 3's S3-2 is approved (Q-32).
extension AppModel {
    /// Sessions follow a folder that was moved outside Duo: `old` → `new`, one journaled migration.
    /// The user confirms in Duo. Returns through `done` for duo2.
    public func reconnect(from old: String, to new: URL, name: String, done: (@MainActor (Result<String, Error>) -> Void)? = nil) {
        struct Refused: Error, CustomStringConvertible { let description: String }
        let fail = { (m: String) in if let done { done(.failure(Refused(description: m))) } else { self.info(m) } }
        guard Migrator.cliUnderstandsRelocation(ClaudeLocator.resolve()) else {
            return fail("This Claude Code doesn't understand moved sessions, so Duo can't reconnect them (FR-7.4.8).")
        }
        let oldPath = (old as NSString).expandingTildeInPath, newPath = new.resolvingSymlinksInPath().path
        let m = Migrator()
        let plan: Migrator.Journal
        do {
            plan = try m.planReconnect(oldPath, to: newPath, live: Set(Beacon.readAll().map(\.sessionId)))
            try m.save(plan)
        } catch { return fail("Can't reconnect \(name): \(error)") }
        let n = Set(plan.steps.compactMap(\.sessionId)).count
        confirm(title: "Reconnect \(name)'s sessions to \(Self.short(newPath))?",
                detail: "\(n) session\(n == 1 ? " is" : "s are") still filed under \(Self.short(oldPath)), which isn't there any more. They move to the new place the way Claude's /cd moves them, so they resume there. Their history isn't changed. Every step is journaled, and Edit › Undo puts it back.",
                button: "Reconnect") { [weak self] ok in
            guard let self else { return }
            guard ok else { return fail("Not reconnected: you clicked Cancel. Nothing changed.") }
            do {
                let r = try m.apply(plan, live: Set(Beacon.readAll().map(\.sessionId)))
                Self.repointState(from: oldPath, to: newPath)
                self.registerUndo("Reconnect Sessions") { model in
                    do { try Migrator().undo(r); Self.repointState(from: newPath, to: oldPath) } catch { model.info("Couldn't undo: \(error)") }
                    model.refreshLive()
                }
                self.refreshLive()
                done?(.success("Reconnected \(n) session\(n == 1 ? "" : "s") to \(Self.short(newPath)). Undo: duo2 undo"))
            } catch { fail("Stopped and put back: \(error)") }
        }
    }

    /// Locate Folder…: the user points Duo at where a missing folder went.
    public func locateFolder(_ project: String) {
        guard let p = fixture.projects.first(where: { $0.name == project }), p.isMissing else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Where is \(project) now? Its sessions will resume there."
        DuoFocus.take()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        reconnect(from: p.path, to: url, name: project)
    }

    /// Use New Place: the folder Duo found the missing one at.
    public func useNewPlace(_ project: String) {
        guard let p = fixture.projects.first(where: { $0.name == project }), let to = p.movedTo else { return }
        reconnect(from: p.path, to: URL(fileURLWithPath: to), name: project)
    }

    /// Reconnect Sessions… on a project whose sessions are still filed under where it was.
    public func reconnectStale(_ project: String) {
        guard let p = fixture.projects.first(where: { $0.name == project }), let from = p.movedFrom, let folder = liveFolders[project] else { return }
        reconnect(from: from, to: folder, name: project)
    }

    /// Remove from Duo: the missing folder's tile goes; its sessions stay in Claude's storage and
    /// in search. Undoable.
    public func forgetFolder(_ project: String) {
        guard let p = fixture.projects.first(where: { $0.name == project }), p.isMissing else { return }
        let path = (p.path as NSString).expandingTildeInPath
        DuoState.update { if !$0.forgottenFolders.contains(path) { $0.forgottenFolders.append(path) } }
        registerUndo("Remove from Duo") { model in
            DuoState.update { $0.forgottenFolders.removeAll { $0 == path } }
            model.refreshLive()
        }
        refreshLive()
    }

    /// A session whose transcript is still filed under a folder that's gone (the project moved
    /// outside Duo) follows it before it resumes, as Claude's /cd would, journaled (F-78). Returns
    /// whether it was moved.
    func reconnectForResume(_ id: String, to folder: URL) -> Bool {
        let m = Migrator()
        guard Migrator.cliUnderstandsRelocation(ClaudeLocator.resolve()),
              let plan = try? m.planRelocate(id, to: folder.resolvingSymlinksInPath().path, live: Set(Beacon.readAll().map(\.sessionId))) else { return false }
        do {
            try m.save(plan)
            _ = try m.apply(plan, live: [])
            DuoLog.write("reconnected \(id.prefix(8)) to \(folder.path) before resuming (\(plan.id))")
            return true
        } catch {
            DuoLog.write("couldn't reconnect \(id.prefix(8)) for resume: \(error)")
            return false
        }
    }
}
