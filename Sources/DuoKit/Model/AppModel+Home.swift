import AppKit
import Foundation

/// Home is optional (DL-82): Duo lists every Claude session without one. Choosing a folder makes it
/// Home, the container of the projects you track (DL-85); Move into Home brings a project or folder
/// in with its sessions, through the migrator's folder move so no session loses its project.
extension AppModel {
    /// File › Choose Home Folder… and the no-Home prompt (DL-84). Never in scripted runs: a panel
    /// would block them (use `duo2 home set`).
    public func chooseHomeFolder() {
        guard interactivePrompts else { return info("Choose Home Folder… opens a folder picker; scripted runs use `duo2 home set <folder>`.") }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Make Home"
        panel.message = "Home holds the projects you track. Duo adds a HOME.md to the folder if it has none."
        if let r = liveRoot { panel.directoryURL = r } else { panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let why = setHome(url) { info(why) }
    }

    /// Makes `folder` Home: writes a HOME.md if there's none (DL-42: Duo helps create it), remembers
    /// it, and rescans. Returns why it couldn't, or nil. Undo puts the previous Home back and
    /// removes only a HOME.md this made.
    @discardableResult
    public func setHome(_ folder: URL) -> String? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let folder = folder.standardizedFileURL
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { return "\(Self.short(folder.path)) isn't a folder." }
        if folder.path == fm.homeDirectoryForCurrentUser.standardizedFileURL.path {
            return "Your home folder can't be Home: every folder on the Mac would sit inside it. Choose or make a folder in it, like ~/work."
        }
        let file = folder.appending(path: "HOME.md")
        var made = false
        if !fm.fileExists(atPath: file.path) {
            let starter = "---\ntype: home\n---\n\n# Home\n\nThe projects I track live in this folder. Home's session sorts what comes in and sends it to them.\n"
            do { try Data(starter.utf8).write(to: file, options: .withoutOverwriting); made = true } catch { return error.localizedDescription }
        }
        let before = DuoState.load()
        DuoState.update { s in s.root = folder.path; s.home = folder.path }
        rememberedHome = folder.path
        homeTab = nil
        startLive(root: folder)
        registerUndo("Choose Home Folder") { model in
            if made { try? FileManager.default.trashItem(at: file, resultingItemURL: nil) }
            DuoState.update { s in s.root = before.root; s.home = before.home }
            model.rememberedHome = before.home
            model.homeTab = nil
            model.startLive(root: before.root.map { URL(fileURLWithPath: $0) })
        }
        return nil
    }

    /// Whether a project or folder already sits in Home's folder.
    public func isInHome(_ project: String) -> Bool {
        guard let root = liveRoot?.standardizedFileURL.path, let folder = liveFolders[project]?.standardizedFileURL.path else { return false }
        return folder == root || folder.hasPrefix(root + "/")
    }

    /// Move into Home… (DL-85): the folder moves into Home with every session filed under it, as one
    /// journaled, undoable migration (CONS §7.5). The user confirms in Duo.
    public func moveIntoHome(_ project: String, done: (@MainActor (Result<String, Error>) -> Void)? = nil) {
        struct Refused: Error, CustomStringConvertible { let description: String }
        let fail = { (m: String) in if let done { done(.failure(Refused(description: m))) } else { self.info(m) } }
        guard let root = liveRoot else { return fail("There's no Home folder yet: choose one first (File › Choose Home Folder…).") }
        guard let folder = liveFolders[project] else { return fail("No project or folder named '\(project)'.") }
        guard !isInHome(project) else { return fail("\(project) is already in Home.") }
        guard Migrator.cliUnderstandsRelocation(ClaudeLocator.resolve()) else {
            return fail("This Claude Code doesn't understand moved sessions, so Duo can't move \(project)'s folder without losing them (FR-7.4.8).")
        }
        let from = folder.resolvingSymlinksInPath().path
        let dest = root.resolvingSymlinksInPath().appending(path: folder.lastPathComponent).path
        let m = Migrator()
        let plan: Migrator.Journal
        do {
            plan = try m.planFolderMove(from, to: dest, live: Set(Beacon.readAll().map(\.sessionId)), openFolders: terminals.all.map(\.cwd))
            try m.save(plan)
        } catch { return fail("Can't move \(project) into Home: \(error)") }
        let sessions = plan.steps.filter { $0.op == .appendRelocated }.count
        confirm(title: "Move \(project) into Home?",
                detail: "\(Self.short(from)) moves to \(Self.short(dest)), with its \(sessions) session\(sessions == 1 ? "" : "s"): they stay \(project)'s and resume from the new place. Every step is journaled, and Edit › Undo puts it all back.\n\n"
                    + plan.warnings.joined(separator: "\n"),
                button: "Move") { [weak self] ok in
            guard let self else { return }
            guard ok else { return fail("Not moved: you clicked Cancel. Nothing changed.") }
            do {
                let r = try m.apply(plan, live: Set(Beacon.readAll().map(\.sessionId)))
                Self.repointState(from: from, to: dest)
                self.extraProjects = DuoState.load().projects.map { URL(fileURLWithPath: $0) }
                self.archivedProjectPaths = DuoState.load().archivedProjects
                self.registerUndo("Move into Home") { model in
                    do {
                        try Migrator().undo(r)
                        Self.repointState(from: dest, to: from)
                        model.extraProjects = DuoState.load().projects.map { URL(fileURLWithPath: $0) }
                        model.archivedProjectPaths = DuoState.load().archivedProjects
                    } catch { model.info("Couldn't undo the move: \(error)") }
                    model.refreshLive()
                }
                self.refreshLive()
                done?(.success("Moved \(project) into Home with \(sessions) session\(sessions == 1 ? "" : "s"). Undo: duo2 undo"))
            } catch { fail("Stopped and put back: \(error)") }
        }
    }

    /// Duo's own records name folders by path: follow a moved folder.
    static func repointState(from: String, to: String) {
        func map(_ p: String) -> String { p == from ? to : p.hasPrefix(from + "/") ? to + p.dropFirst(from.count) : p }
        DuoState.update { s in
            s.projects = s.projects.map(map)
            s.archivedProjects = s.archivedProjects.map(map)
            s.home = s.home.map(map)
        }
    }
}
