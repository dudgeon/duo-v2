import AppKit
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
    public let places: [HomePlace]
    public var into: HomePlace
    public var startSession: Bool
    /// Sessions to file in the new project: Move to Project ▸ New Project… (Q-30).
    public let moving: [String]

    init(name: String, places: [HomePlace], moving: [String]) {
        self.name = name; self.places = places; self.into = places[0]; self.moving = moving
        self.startSession = moving.isEmpty
    }

    public var path: String { into.folder.appending(path: name.trimmingCharacters(in: .whitespacesAndNewlines)).path }
}

extension AppModel {
    /// Where in Home a project can go: its top level, then each topic folder (a folder directly in
    /// Home, not itself a project, that holds projects), by name.
    public func homePlaces() -> [HomePlace] {
        guard let root = liveRoot?.standardizedFileURL else { return [] }
        let fm = FileManager.default
        var topics = Set<String>()
        for url in liveFolders.values {
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(root.path + "/") else { continue }
            let first = String(path.dropFirst(root.path.count + 1).split(separator: "/").first ?? "")
            let top = root.appending(path: first)
            if !first.isEmpty, top.path != path, !fm.fileExists(atPath: top.appending(path: "PROJECT.md").path) { topics.insert(first) }
        }
        return [HomePlace(label: "Home (top level)", folder: root)]
            + topics.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { HomePlace(label: "\($0) /", folder: root.appending(path: $0)) }
    }

    /// The place a duo2 `--into` names: a topic folder's name, or Home's top level when absent.
    func homePlace(named name: String?) -> HomePlace? {
        let places = homePlaces()
        guard let name = name?.trimmingCharacters(in: CharacterSet(charactersIn: " /")), !name.isEmpty else { return places.first }
        return places.first { $0.folder.lastPathComponent == name }
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
