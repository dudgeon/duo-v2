import AppKit
import DuoControl
import Foundation

/// The templates new projects and tasks are made from (DL-146, `templates-handoff/`): edited as
/// documents in the right pane, with a template bar over them.
extension AppModel {
    /// What a template file is for, shown in its bar: the kind, and Home's or a project's.
    public struct TemplateInfo: Equatable {
        public var kind: Templates.Kind
        /// The project whose own template it is, or nil for Home's.
        public var project: String?
        public var file: URL
    }

    /// The template bar for a right-pane tab, if the tab is a template: `templates/new-task.md`
    /// or `templates/new-project.md` in Home or a project, opened from anywhere (board A4, 3).
    public func templateInfo(forTab tab: String) -> TemplateInfo? {
        guard let url = liveFile(tab), let kind = Templates.Kind.allCases.first(where: { $0.fileName == url.lastPathComponent }),
              url.deletingLastPathComponent().lastPathComponent == "templates" else { return nil }
        let owner = url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
        if let home = homeFolder, owner == home.standardizedFileURL { return TemplateInfo(kind: kind, project: nil, file: url) }
        guard kind == .task, let name = liveFolders.first(where: { $0.value.standardizedFileURL == owner })?.key else { return nil }
        return TemplateInfo(kind: kind, project: name, file: url)
    }

    /// The template file a project's new tasks come from now: its own, else Home's (which may not
    /// exist yet: the base is used then).
    public func templateFile(_ kind: Templates.Kind, project: String?) -> URL? {
        let folder = project.flatMap { liveFolders[$0] }
        if let f = Templates.file(kind, project: folder, home: homeFolder) { return f.url }
        return homeFolder.map { Templates.path(kind, in: $0) }
    }

    /// The template in use, as text, and whose it is ("refunds", "Home" or "base").
    public func templateText(_ kind: Templates.Kind, project: String?) -> (text: String, whose: String) {
        let t = Templates.text(kind, project: project.flatMap { liveFolders[$0] }, home: homeFolder)
        switch t.scope {
        case .project: return (t.text, project ?? "project")
        case .home: return (t.text, "Home")
        case .base: return (t.text, "base")
        }
    }

    /// Edit Task Template / Settings › Templates › Edit…: opens the template a project uses (its
    /// own, else Home's). With no file yet, the base is written to Home's `templates/` first, so
    /// there's always a file to edit (board A4, 1).
    @discardableResult
    public func editTemplate(_ kind: Templates.Kind, project: String?) -> Result<URL, Error> {
        struct Refused: Error, CustomStringConvertible { let description: String }
        guard let file = templateFile(kind, project: kind == .task ? project : nil) else {
            return .failure(Refused(description: "no Home folder yet: choose one first (File › Choose Home Folder…)"))
        }
        do {
            if !FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(Templates.base(kind).utf8).write(to: file, options: .withoutOverwriting)
            }
        } catch { return .failure(error) }
        show(file, in: project)
        return .success(file)
    }

    /// Make a Template for <project>: the template it uses now, copied into its own
    /// `templates/new-task.md`, and opened (board A3).
    @discardableResult
    public func copyTemplate(toProject project: String) -> Result<URL, Error> {
        struct Refused: Error, CustomStringConvertible { let description: String }
        guard let folder = liveFolders[project] else { return .failure(Refused(description: "no project '\(project)'")) }
        let file = Templates.path(.task, in: folder)
        if FileManager.default.fileExists(atPath: file.path) {
            show(file, in: project)
            return .success(file)
        }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(templateText(.task, project: nil).text.utf8).write(to: file, options: .withoutOverwriting)
        } catch { return .failure(error) }
        registerUndo("Make a Template") { model in
            try? FileManager.default.trashItem(at: file, resultingItemURL: nil)
            model.refreshLive()
        }
        refreshLive()
        show(file, in: project)
        return .success(file)
    }

    /// Reset… (Home's template: back to Duo's base) or Use Home's… (a project's own: Home's is used
    /// again). Asks first; the file goes to the Trash, so nothing is lost (board A1, A3).
    public func resetTemplate(_ info: TemplateInfo, done: (@MainActor (Bool) -> Void)? = nil) {
        let what = info.kind == .task ? "new tasks" : "new projects"
        let q: DuoQuestion
        if let project = info.project {
            q = DuoQuestion(title: "Use Home's template in \(project)?",
                            paragraphs: ["New tasks in \(project) will use Home's template again. This one goes to the Trash."],
                            items: [.init(what: "", path: abbreviated(info.file))],
                            choices: [.init(label: "Cancel", isCancel: true) { done?(false) },
                                      .init(label: "Use Home's Template", isDefault: true) { [weak self] in self?.applyReset(info); done?(true) }])
        } else {
            q = DuoQuestion(title: "Reset the template for \(what)?",
                            paragraphs: ["It goes back to Duo's base template. Your version goes to the Trash."],
                            items: [.init(what: "", path: abbreviated(info.file))],
                            choices: [.init(label: "Cancel", isCancel: true) { done?(false) },
                                      .init(label: "Reset to Base", isDefault: true) { [weak self] in self?.applyReset(info); done?(true) }])
        }
        ask(q)
    }

    func applyReset(_ info: TemplateInfo) {
        if let e = editorIfLoaded, e.url?.standardizedFileURL == info.file.standardizedFileURL { e.saveNow(force: true) }
        var trashed: NSURL?
        try? FileManager.default.trashItem(at: info.file, resultingItemURL: &trashed)
        if info.project == nil {
            // Home's: the base, at the same path, so the open tab shows it.
            try? Data(Templates.base(info.kind).utf8).write(to: info.file, options: .withoutOverwriting)
        }
        registerUndo(info.project == nil ? "Reset Template" : "Use Home's Template") { model in
            guard let back = trashed as URL? else { return }
            try? FileManager.default.removeItem(at: info.file)
            try? FileManager.default.moveItem(at: back, to: info.file)
            model.refreshLive()
        }
        refreshLive()
        if let project = info.project { _ = editTemplate(.task, project: project) }
    }

    /// The file a template makes, for Preview and `duo2 template preview` (board A2).
    public func previewTemplate(_ text: String, title: String = "Draft PRD v2") -> String {
        Templates.render(text, title: title)
    }

    /// Opens a template file: in the project asked for, else the one on screen, else Home.
    func show(_ file: URL, in project: String?) {
        if let project, currentProject?.name != project { open(project: project) }
        if currentProject == nil, let home = fixture.home { open(project: home.name) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            MainActor.assumeIsolated { _ = self?.openFile(at: file) }
        }
    }

    func abbreviated(_ url: URL) -> String {
        url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}
