import AppKit
import Foundation

/// The intro video's scene 14, Windows (multi-window, 0.2.24; DL-308, DL-311 to DL-313): the second and third windows, each its
/// own capture, each drawn as a capture draws window 1 (it keeps its number and its "Duo" title, which the capture finds it by), with only its colour set (`--state video-mw-<what>`, with `--fixture video/fixture/fixture.json`). The first window is scene 9's own states
/// (the Board, shelf-scan's project view), plain, as a first window is. A new window takes the next colour no open window has:
/// Blue for the second, Ochre for the third. These windows are 1440 × 900 (LaunchOptions), so the film can cascade them over the
/// first one on the desk the way macOS places new windows.
extension VideoTargets {
    nonisolated static let mwScreens = [
        "video-mw-beta",   // window 2: Open in New Window on the beta-feedback tile; its project view, Blue
        "video-mw-new",    // window 3: File › New Window ⌥⌘N, at All projects (the Board), Ochre
        "video-mw-map",    // window 3 after its neighborhood-map tile is clicked: that project's view, Ochre
    ]
    nonisolated static let mwWindowSize = CGSize(width: 1440, height: 900)

    static func applyWindows(_ screen: String, _ model: AppModel) {
        switch screen {
        case "video-mw-beta":
            applyS9Beta(model)
            model.windowColourID = "blue"
        case "video-mw-new":
            applyS9Home("video-s9-board", model)
            model.windowColourID = "ochre"
        default:
            applyProjectView(model, project: "neighborhood-map", session: "Freshness badge spec", term: "freshness.ans",
                             files: ["PROJECT.md", "notes/map-tile-costs.md", "specs/freshness.md"], document: "specs/freshness.md")
            model.windowColourID = "ochre"
        }
    }

    /// A project's view as scene 9's beta-feedback has it: its own sessions and files, one session in a terminal tab (the
    /// fixture's `terms/<term>`), one document open on the right. Built from the fixture's `projects/<project>` folder.
    static func applyProjectView(_ model: AppModel, project: String, session: String, term: String, files: [String], document: String) {
        TargetState.project.apply(to: model)
        guard let base = model.fixture.baseDir else { return }
        let dir = URL(fileURLWithPath: base)
        let folder = dir.appending(path: "projects/\(project)").standardizedFileURL
        let key = model.fixture.sessions.first { $0.project == project && $0.name == session }?.tabKey ?? session
        model.altitude = .project(project)
        model.fixture.groups = model.fixture.groups.filter { $0.project != project }
        model.fixture.projectFiles[project] = files
        model.selectedSidebarItem = nil
        model.expandedGroups = []
        model.liveFolders[project] = folder
        model.videoDemoFolder = folder
        model.listClock = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 9, minute: 41))
        WindowCapture.underlay = DuoNSColor.console
        model.videoRightWidth = 640
        let text = (try? String(contentsOf: dir.appending(path: "terms/\(term)"), encoding: .utf8)) ?? ""
        model.fixtureTerminals[key] = TerminalSession(key: key, screen: text)
        model.parkedTabs = [key]
        model.openDocuments = [document]
        model.rightTab = document; model.selectedFile = document
        model.consoleTab = key
    }
}
