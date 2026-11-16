import AppKit
import DuoControl
import DuoKit
import Foundation

// Multi-window slice 2's restore (DL-351, C-153, Q-432 a): quit with several windows and relaunch, and the
// window set comes back: every window, its project, frame and colour, each window's tabs as the one-window
// restore keeps them; restore file v2 with `windows[]`, and a one-time v1 backup. No AppKit windows: two
// cores on one support folder stand for the quit and the relaunch. `DUO_CHECKS=window-restore swift run DuoChecks`.
@MainActor func windowRestoreChecks() throws {
    print("the window set survives a relaunch (DL-351, C-153)")
    _ = NSApplication.shared
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appending(path: "duo-wr-\(UUID().uuidString.prefix(8))").resolvingSymlinksInPath()
    let support = root.appending(path: "support"), home = root.appending(path: "home")
    let saved = ProcessInfo.processInfo.environment["DUO_SUPPORT_DIR"]
    setenv("DUO_SUPPORT_DIR", support.path, 1)
    defer {
        if let saved { setenv("DUO_SUPPORT_DIR", saved, 1) } else { unsetenv("DUO_SUPPORT_DIR") }
        try? fm.removeItem(at: root)
    }
    try fm.createDirectory(at: support, withIntermediateDirectories: true)
    let f = try repoFixture()
    let names = f.projects.filter { $0.name != f.home?.name }.map(\.name)
    let (p, q, r) = (names[0], names[1], names[2])
    var folders: [String: URL] = [:]
    for n in [p, q, r] {
        let d = home.appending(path: n)
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
        folders[n] = d
    }
    /// A Duo on Home, live, restoring: what a launch with `restoreEnabled` has by its first refresh.
    func launch() -> (AppCore, AppModel) {
        let core = AppCore(fixture: f)
        core.setColourNewWindows(true, save: false)
        let m = AppModel(core: core)
        m.liveRoot = home
        m.liveFolders = folders
        m.isLive = true
        m.restoreEnabled = true
        return (core, m)
    }
    let file = RestoreState.file(root: home.path)

    // MARK: Quit with three windows
    let (core, one) = launch()
    one.applyRestore()   // nothing saved yet: one window, as before
    check(core.models.count == 1, "a first launch has one window")
    one.open(project: p)
    one.setWindowColour("ochre")
    one.leftCollapsedProject = true
    let two = core.openWindow(project: q)   // Blue (the first free colour)
    let three = core.openWindow()            // at All projects, Purple
    three.setWindowColour("deep-teal")
    two.restoreFrame = CGRect(x: 140, y: 90, width: 1400, height: 880)
    core.keyWindowID = nil
    one.saveRestoreState(force: true)
    let state = RestoreState.load(file)
    check(state?.version == 2, "the restore file is version 2 (\(state?.version ?? 0))")
    check(state?.windows?.map(\.number) == [1, 2, 3], "it lists every window, the primary first (\(state?.windows?.map(\.number) ?? []))")
    check(state?.windows?.map(\.colour) == ["ochre", "blue", "deep-teal"], "with each window's colour (\(String(describing: state?.windows?.map(\.colour))))")
    check(state?.windows?.map(\.project) == [folders[p]!.path, folders[q]!.path, nil], "and its project, by folder (nil at All projects)")
    check(state?.windows?[1].frame == [140, 90, 1400, 880], "and its frame (\(String(describing: state?.windows?[1].frame)))")
    check(state?.project == folders[p]!.path && state?.leftCollapsedProject == true, "the top level is still the primary window's, as v1 wrote it")

    // MARK: Relaunch
    let (core2, first) = launch()
    first.applyRestore()
    let back = core2.models
    check(back.count == 3, "relaunch brings back three windows (\(back.count))")
    if back.count == 3 {
        check(back.map(\.windowNumber) == [1, 2, 3], "numbered as they were")
        check(back.map(\.altitude) == [.project(p), .project(q), .allProjects], "each on its project, or All projects (\(back.map(\.altitude)))")
        check(back.map(\.windowColourID) == ["ochre", "blue", "deep-teal"], "each in its colour (\(back.map(\.windowColourID)))")
        check(back[1].restoreFrame == CGRect(x: 140, y: 90, width: 1400, height: 880), "window 2 has its frame to open at")
        check(back[0].leftCollapsedProject && !back[1].leftCollapsedProject, "each window's panes as they were")
    }

    // MARK: Closing a window (not quitting) keeps its project's tabs; the set no longer lists it
    if back.count == 3 {
        try Data("# Brief\n".utf8).write(to: folders[q]!.appending(path: "brief.md"))
        back[1].openDocumentsByProject[q] = ["brief.md"]
        core2.closeWindow(back[1])
        first.saveRestoreState(force: true)
        let after = RestoreState.load(file)
        check(after?.windows?.map(\.number) == [1, 3], "a closed window leaves the set (\(after?.windows?.map(\.number) ?? []))")
        check(after?.projects.first { $0.folder == folders[q]!.path }?.documents == ["brief.md"],
              "its project keeps its tabs, as leaving a project does")
    }

    // MARK: v1: an older file restores one window; the first v2 save keeps a backup an older Duo can use
    do {
        var v1 = RestoreState(); v1.version = 1; v1.root = home.path; v1.project = folders[r]!.path
        v1.projects = [.init(folder: folders[r]!.path, sessions: [], consoleTab: nil, documents: [], rightTab: "Project")]
        let data = try JSONEncoder().encode(v1)
        try? fm.removeItem(at: RestoreState.backupFile(root: home.path))
        try data.write(to: file)
        let (c3, m3) = launch()
        m3.applyRestore()
        check(c3.models.count == 1 && m3.altitude == .project(r), "a v1 file restores one window on its project")
        m3.saveRestoreState(force: true)
        let backup = try? Data(contentsOf: RestoreState.backupFile(root: home.path))
        check(backup == data, "the first v2 save keeps the v1 file as restore-<key>.v1.json")
        check(RestoreState.load(file)?.version == 2, "and writes v2")
        m3.saveRestoreState(force: true)
        check((try? Data(contentsOf: RestoreState.backupFile(root: home.path))) == data, "the backup is written once, never over")
    }

    // MARK: A window whose project folder is gone opens at All projects, the rest as they were
    do {
        var s = RestoreState(); s.root = home.path; s.project = folders[p]!.path
        s.windows = [.init(number: 1, project: folders[p]!.path, colour: nil),
                     .init(number: 2, project: home.appending(path: "gone").path, colour: "green"),
                     .init(number: 4, project: folders[r]!.path, colour: "coral")]
        try JSONEncoder().encode(s).write(to: file)
        let (c4, m4) = launch()
        m4.applyRestore()
        let ws = c4.models
        check(ws.count == 3 && ws.map(\.windowColourID) == [nil, "green", "coral"], "the window with a gone project still opens, in its colour")
        check(ws.count == 3 && ws[1].altitude == .allProjects && ws[2].altitude == .project(r) && ws[2].windowNumber == 4,
              "at All projects; the others on theirs, under their own numbers")
    }

    // MARK: Two windows on one project (an older file) can't both show it (DL-308)
    do {
        var s = RestoreState(); s.root = home.path
        s.windows = [.init(number: 1, project: nil, colour: nil), .init(number: 2, project: folders[q]!.path, colour: nil),
                     .init(number: 3, project: folders[q]!.path, colour: nil)]
        try JSONEncoder().encode(s).write(to: file)
        let (c5, m5) = launch()
        m5.applyRestore()
        check(c5.models.filter { $0.altitude == .project(q) }.count == 1, "a project shows in one window (DL-308)")
    }

    // MARK: A frame off every screen comes back onto one
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1079)
    let onIt = CGRect(x: 100, y: 100, width: 1400, height: 880)
    check(RestoreState.Window.placed(onIt, screens: [screen]) == onIt, "a frame on a screen stays where it was")
    let off = RestoreState.Window.placed(CGRect(x: 4000, y: 2000, width: 1400, height: 880), screens: [screen])
    check(screen.contains(off) && off.size == onIt.size, "a frame off every screen moves onto one, its size kept (\(off))")
    let big = RestoreState.Window.placed(CGRect(x: -3000, y: 0, width: 2560, height: 1440), screens: [screen])
    check(screen.contains(big), "a frame bigger than the screen left shrinks to fit it (\(big))")
    let edge = RestoreState.Window.placed(CGRect(x: 1700, y: 100, width: 1400, height: 880), screens: [screen])
    check(screen.contains(edge), "a frame with only a sliver showing comes fully on (\(edge))")
    let second = CGRect(x: 1728, y: 0, width: 2560, height: 1440)
    let there = CGRect(x: 2000, y: 200, width: 1400, height: 880)
    check(RestoreState.Window.placed(there, screens: [screen, second]) == there, "a frame on a second screen stays there")
}
