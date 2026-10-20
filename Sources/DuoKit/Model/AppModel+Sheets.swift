import AppKit
import DuoSearch
import Foundation
import Observation

/// A folder a project can go into, inside Home: Home's top level or one of its topic folders (DL-100).
public struct HomePlace: Hashable, Sendable {
    public var label: String
    public var folder: URL
}

/// Move into Home…'s sheet (S2-4): what moves, where to, and the Into choice.
@Observable public final class MoveIntoHomeForm {
    public let project: String
    public let from: String
    public let sessions: Int
    public let warnings: [String]
    public let places: [HomePlace]
    public var into: HomePlace
    @ObservationIgnored let finish: @MainActor (HomePlace?) -> Void

    init(project: String, from: String, sessions: Int, warnings: [String], places: [HomePlace], finish: @escaping @MainActor (HomePlace?) -> Void) {
        self.project = project; self.from = from; self.sessions = sessions; self.warnings = warnings
        self.places = places; self.into = places[0]; self.finish = finish
    }

    public var dest: String { into.folder.appending(path: URL(fileURLWithPath: from).lastPathComponent).path }
}

/// New project's sheet (S2-6): name, goal, where, and whether to start a session in it.
@Observable public final class NewProjectForm {
    public var name: String
    public var goal = ""
    public var places: [HomePlace]
    public var into: HomePlace {
        didSet { if !canUseFolder { useFolder = false } }
    }
    /// Make the chosen folder itself the project instead of a new folder in it (DL-211): Name then
    /// titles the project and the folder keeps its name. Not for Home's top level.
    public var useFolder = false
    public var startSession: Bool
    /// Sessions to file in the new project: Move to Project ▸ New Project… (Q-30).
    public let moving: [String]

    public init(name: String, places: [HomePlace], moving: [String]) {
        self.name = name; self.places = places; self.into = places[0]; self.moving = moving
        self.startSession = moving.isEmpty
    }

    /// Home's top level can't be the project: it's Home.
    public var canUseFolder: Bool { into.folder.standardizedFileURL.path != places.first?.folder.standardizedFileURL.path }

    public var path: String {
        useFolder ? into.folder.path : into.folder.appending(path: name.trimmingCharacters(in: .whitespacesAndNewlines)).path
    }
}

extension AppModel {
    /// Where in Home a project can go (DL-211): its top level, then every folder in Home, by name.
    public func homePlaces() -> [HomePlace] {
        guard let root = liveRoot?.standardizedFileURL else { return [] }
        return Self.homePlaces(root: root)
    }

    /// Home's top level, then every folder directly in Home that isn't a project, by name.
    public static func homePlaces(root: URL) -> [HomePlace] {
        [HomePlace(label: "Home (top level)", folder: root)]
            + homeFolders(root: root).map { HomePlace(label: "\($0.lastPathComponent) /", folder: $0) }
    }

    /// Duo's own folders in Home, never offered as a place: templates (DL-146) and Home's tasks.
    nonisolated static let duoOwnFolders: Set<String> = ["templates", "tasks"]

    /// The folders directly in Home a project can go into or be made of (DL-211, DL-212): not hidden,
    /// not Duo's own or a build folder, not a package, and not already a project. Sorted by name.
    nonisolated public static func homeFolders(root: URL) -> [URL] {
        let fm = FileManager.default
        // Never a walk into a folder macOS guards with a privacy prompt (F-302).
        guard !ProtectedFolders.neverFileRoot(root) else { return [] }
        let items = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: [.skipsHiddenFiles])) ?? []
        return items.filter { url in
            let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            let name = url.lastPathComponent
            return v?.isDirectory == true && v?.isPackage != true && !name.hasPrefix(".") && !ProtectedFolders.skip(url, root: root)
                && !duoOwnFolders.contains(name.lowercased()) && !LiveSnapshot.neverListed.contains(name)
                && !fm.fileExists(atPath: url.appending(path: "PROJECT.md").path)
                && !fm.fileExists(atPath: url.appending(path: "HOME.md").path)
        }
        .map(\.standardizedFileURL)
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Whether `folder` is inside Home (not Home itself).
    public static func isInside(_ folder: URL, home root: URL) -> Bool {
        let (f, r) = (folder.standardizedFileURL.resolvingSymlinksInPath().path, root.standardizedFileURL.resolvingSymlinksInPath().path)
        return f.hasPrefix(r + "/")
    }

    /// A place for a folder anywhere inside Home (Choose Folder…, duo2's `--into a/b`), labelled by its path in Home.
    public static func homePlace(folder: URL, root: URL) -> HomePlace? {
        var isDir: ObjCBool = false
        guard isInside(folder, home: root), FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        let r = root.standardizedFileURL.resolvingSymlinksInPath().path
        let rel = String(folder.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(r.count + 1))
        return HomePlace(label: "\(rel) /", folder: folder.standardizedFileURL)
    }

    /// The place a duo2 `--into` names: a folder in Home by name, a path inside Home (relative to it,
    /// or absolute), or Home's top level when absent.
    func homePlace(named name: String?) -> HomePlace? {
        let places = homePlaces()
        guard let name = name?.trimmingCharacters(in: CharacterSet(charactersIn: " /")), !name.isEmpty else { return places.first }
        if let p = places.first(where: { $0.folder.lastPathComponent == name }) { return p }
        guard let root = liveRoot else { return nil }
        let expanded = (name as NSString).expandingTildeInPath
        let url = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : root.appending(path: name)
        return Self.homePlace(folder: url, root: root)
    }

    /// Why `folder` can't be made the project itself (DL-211), or nil: it must be a folder inside Home
    /// that isn't a project yet.
    public func useFolderProblem(_ folder: URL) -> String? {
        guard let root = liveRoot else { return "There's no Home folder yet: choose one first (File › Choose Home Folder…)." }
        return Self.useFolderProblem(folder, root: root)
    }

    public static func useFolderProblem(_ folder: URL, root: URL) -> String? {
        guard isInside(folder, home: root) else {
            return folder.standardizedFileURL.path == root.standardizedFileURL.path
                ? "Home can't be a project: choose a folder in it." : "\(short(folder.path)) isn't in Home."
        }
        guard FileManager.default.fileExists(atPath: folder.path) else { return "\(short(folder.path)) isn't there." }
        if FileManager.default.fileExists(atPath: folder.appending(path: "PROJECT.md").path) { return "\(folder.lastPathComponent) is already a project." }
        return nil
    }

    /// The In popup's Choose Folder… (DL-211): an open panel at Home that takes a folder inside Home.
    public func chooseNewProjectFolder() {
        guard let f = newProjectForm, let root = liveRoot else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = f.into.folder
        panel.prompt = "Choose"
        panel.message = "Choose a folder in \(Self.short(root.path)) for the project."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if url.standardizedFileURL.path == root.standardizedFileURL.path { f.into = f.places[0]; return }
        guard let place = Self.homePlace(folder: url, root: root) else {
            return info("\(Self.short(url.path)) isn't in Home (\(Self.short(root.path))). Choose a folder inside it.")
        }
        if !f.places.contains(place) { f.places.append(place) }
        f.into = place
    }

    /// + New project (the map's tile, search's New project "…", Move to Project ▸ New Project…):
    /// opens the sheet. Without a Home there's nowhere to make it yet.
    public func showNewProject(name: String = "", moving: [String] = []) {
        guard liveRoot != nil else { return info("There's no Home folder yet: choose one first (File › Choose Home Folder…).") }
        closeSearch()
        newProjectForm = NewProjectForm(name: name, places: homePlaces(), moving: moving)
    }

    /// The sheet's Create Project. Returns why it couldn't, keeping the sheet up, or nil.
    @discardableResult
    public func commitNewProject() -> String? {
        guard let f = newProjectForm else { return nil }
        if f.useFolder {
            if let why = useFolderProblem(f.into.folder) ?? makeProject(folder: f.into.folder, title: f.name, goal: f.goal, interview: f.startSession) {
                info(why)
                return why
            }
            newProjectForm = nil
            return nil
        }
        if let why = createProject(named: f.name, goal: f.goal, in: f.into.folder, moving: f.moving, startSession: f.startSession) {
            info(why)
            return why
        }
        newProjectForm = nil
        return nil
    }

    public func cancelSheet() {
        if let m = moveIntoHomeForm { moveIntoHomeForm = nil; m.finish(nil) }
        newProjectForm = nil
        pushForm = nil
        gitHubProjectForm = nil
    }

    public func confirmMoveIntoHome() {
        guard let m = moveIntoHomeForm else { return }
        moveIntoHomeForm = nil
        m.finish(m.into)
    }

    public var sheetIsUp: Bool { moveIntoHomeForm != nil || newProjectForm != nil || pushForm != nil || gitHubProjectForm != nil || SheetCenter.shared.current != nil }
}
