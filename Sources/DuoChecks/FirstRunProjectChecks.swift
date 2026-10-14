import DuoKit
import Foundation

/// A new user's first project (DL-211, DL-212): New project's In lists every folder in Home, a folder
/// can be made the project itself, and All projects offers Home's folders while it has no projects.
@MainActor func firstRunProjectChecks(_ base: Fixture) {
    print("first-run projects (DL-211, DL-212)")
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appending(path: "duo-first-run-\(UUID().uuidString)").standardizedFileURL
    defer { try? fm.removeItem(at: root) }
    for d in ["Reading", "aipm-starter-repo", "ESM Product Strategy", "notes 10", "notes 9", ".hidden", "templates", "tasks", "node_modules", "Done.app", "Payments", "Payments/checkout"] {
        try? fm.createDirectory(at: root.appending(path: d), withIntermediateDirectories: true)
    }
    try? Data("---\ntype: home\n---\n".utf8).write(to: root.appending(path: "HOME.md"))
    try? Data("# Checkout\n".utf8).write(to: root.appending(path: "Payments/checkout/PROJECT.md"))
    try? fm.createDirectory(at: root.appending(path: "Already"), withIntermediateDirectories: true)
    try? Data("# Already\n".utf8).write(to: root.appending(path: "Already/PROJECT.md"))
    try? Data("x".utf8).write(to: root.appending(path: "loose.md"))

    // DL-211: every folder in Home, by name; not hidden, Duo's own, build folders, packages or projects.
    let places = AppModel.homePlaces(root: root)
    check(places.map(\.label) == ["Home (top level)", "aipm-starter-repo /", "ESM Product Strategy /", "notes 9 /", "notes 10 /", "Payments /", "Reading /"],
          "In lists Home's top level, then every folder in Home sorted by name (not only folders holding projects)")
    check(places.first?.folder == root, "Home's top level comes first")

    // Choose Folder… and duo2's --into take a folder anywhere inside Home, labelled by its path there.
    let deep = AppModel.homePlace(folder: root.appending(path: "Payments/checkout"), root: root)
    check(deep?.label == "Payments/checkout /", "a deeper folder is labelled by its path in Home")
    check(AppModel.homePlace(folder: fm.temporaryDirectory, root: root) == nil && AppModel.homePlace(folder: root, root: root) == nil,
          "a folder outside Home, or Home itself, isn't a deeper place")

    // The use-this-folder path: the folder itself, never Home's top level, never an existing project.
    let form = NewProjectForm(name: "Strategy", places: places, moving: [])
    check(form.path == root.appending(path: "Strategy").path && !form.canUseFolder, "by default a new folder in Home's top level, which can't itself be the project")
    form.into = places[2]
    form.useFolder = true
    check(form.canUseFolder && form.path == root.appending(path: "ESM Product Strategy").path, "Make this folder the project: the path is the chosen folder, keeping its name")
    form.into = places[0]
    check(!form.useFolder, "choosing Home's top level turns Make this folder the project off")
    check(AppModel.useFolderProblem(root.appending(path: "Reading"), root: root) == nil, "a plain folder in Home can become the project")
    check(AppModel.useFolderProblem(root, root: root) != nil, "Home itself can't")
    check(AppModel.useFolderProblem(root.appending(path: "Already"), root: root) == "Already is already a project.", "a project can't again")
    check(AppModel.useFolderProblem(fm.temporaryDirectory.appending(path: "elsewhere"), root: root) != nil, "nor a folder outside Home")
    let reading = root.appending(path: "Reading")
    let wrote = (try? AppModel.writeProjectFile(in: reading, title: "Reading list", goal: "Read the ten best", home: nil)) ?? false
    let text = (try? String(contentsOf: reading.appending(path: "PROJECT.md"), encoding: .utf8)) ?? ""
    check(wrote && text.contains("Reading list") && text.contains("Read the ten best"), "the project file carries the sheet's Name as its title and the goal")
    check(fm.fileExists(atPath: reading.path) && reading.lastPathComponent == "Reading", "the folder keeps its name")
    check((try? AppModel.writeProjectFile(in: reading, title: "Other", goal: "", home: nil)) == false
          && ((try? String(contentsOf: reading.appending(path: "PROJECT.md"), encoding: .utf8)) ?? "") == text, "an existing project file is never overwritten")
    check(!AppModel.homeFolders(root: root).contains { $0.lastPathComponent == "Reading" }, "once a project, it leaves the folders offered")

    // DL-212: All projects with no projects in Home offers Home's folders.
    check(!MapLayout.homeHasNoProjects(base), "the design fixture has projects in Home")
    var empty = base
    empty.projects = base.projects.filter { $0.isHome == true || $0.topic.map(MapLayout.isPath) != false }
    check(MapLayout.homeHasNoProjects(empty), "with only Home and folders outside it, Home has no projects")
    let m = AppModel(fixture: empty)
    m.homeFolderList = AppModel.homeFolders(root: root)
    check(m.firstRunFolders?.map(\.lastPathComponent) == ["aipm-starter-repo", "ESM Product Strategy", "notes 9", "notes 10", "Payments"],
          "All projects offers each folder in Home to make a project of")
    let busy = AppModel(fixture: base)
    busy.homeFolderList = m.homeFolderList
    check(busy.firstRunFolders == nil, "once Home has a project, the map is the map")
    var withFolderTile = empty
    if var p = base.projects.first(where: { $0.isHome != true }) {
        p.name = "ESM Product Strategy"; p.kind = "folder"; p.topic = ""
        withFolderTile.projects.append(p)
    }
    let tiled = AppModel(fixture: withFolderTile)
    tiled.homeFolderList = m.homeFolderList
    check(MapLayout.homeHasNoProjects(withFolderTile) && tiled.firstRunFolders?.contains { $0.lastPathComponent == "ESM Product Strategy" } == false,
          "a folder with sessions (a folder tile on the map) isn't a project, and isn't offered twice")
}
