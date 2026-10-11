import AppKit
import Foundation

/// The intro video's scene 2 as window states (`--state video-s2-<what>`, with `--fixture video/fixture/fixture.json`):
/// the checkout-redesign project with three session tabs in the middle pane and four documents in
/// the right pane, each drawn by its real view (the editor, the HTML viewer, the deck and Word
/// viewers) from files beside the fixture. Terminals show a recorded screen with no process behind
/// them; the chat state shows the last tab's recorded chat. `video-s2-middle-<0..2>` activates a
/// session tab, `video-s2-chat` the last one in chat view, `video-s2-right-<1..4>` a document tab
/// (0 is the Project tab). Without the fixture's `videoS2` section these do nothing.
@MainActor
public enum VideoTargets {
    nonisolated public static let screens = ["video-s2-middle-0", "video-s2-middle-1", "video-s2-middle-2", "video-s2-chat",
                                             "video-s2-right-1", "video-s2-right-2", "video-s2-right-3", "video-s2-right-4"]

    public static func apply(_ screen: String, to model: AppModel) {
        TargetState.project.apply(to: model)
        guard let v = model.fixture.videoS2, let base = model.fixture.baseDir else { return }
        let dir = URL(fileURLWithPath: base)
        let project = "checkout-redesign"
        let folder = dir.appending(path: v.folder).standardizedFileURL
        // The project's sessions are the three the story tells, none grouped.
        guard let template = model.fixture.sessions.first(where: { $0.project == project }) else { return }
        var sessions: [Fixture.Session] = []
        for t in v.terminals {
            var s = template
            s.name = t.name; s.state = t.state; s.wait = t.wait; s.question = nil; s.options = nil; s.summary = nil
            s.forkOf = nil; s.document = nil; s.reason = nil
            sessions.append(s)
        }
        model.fixture.sessions = model.fixture.sessions.filter { $0.project != project } + sessions
        model.fixture.groups = model.fixture.groups.filter { $0.project != project }
        model.fixture.projectFiles[project] = v.files
        model.selectedSidebarItem = nil
        model.expandedGroups = []
        model.liveFolders[project] = folder
        model.videoDemoFolder = folder
        for t in v.terminals {
            let text = (try? String(contentsOf: dir.appending(path: t.screen), encoding: .utf8)) ?? ""
            model.fixtureTerminals[t.name] = TerminalSession(key: t.name, screen: text)
        }
        WindowCapture.underlay = DuoNSColor.console
        model.videoRightWidth = 700
        model.parkedTabs = Set(v.terminals.map(\.name))   // all three tabs show, as sessions Duo has open
        model.openDocuments = v.tabs
        let docs = v.tabs
        var middle = 0, right = 1
        if screen == "video-s2-chat" {
            middle = v.terminals.count - 1
            let name = v.terminals[middle].name
            let rec = dir.appending(path: v.chat)
            let chat = ChatSession(key: name, mode: .chat)
            chat.log.cwd = "/Users/pm/work/payments/checkout-redesign"
            ChatRecording.play(rec, into: chat)
            model.fixtureChats[name] = chat
        } else if screen.hasPrefix("video-s2-middle-") {
            middle = Int(screen.dropFirst("video-s2-middle-".count)) ?? 0
        } else if screen.hasPrefix("video-s2-right-") {
            right = Int(screen.dropFirst("video-s2-right-".count)) ?? 1
        }
        model.consoleTab = v.terminals[min(middle, v.terminals.count - 1)].name
        if right >= 1, right <= docs.count {
            model.rightTab = docs[right - 1]
            model.selectedFile = docs[right - 1]
        } else {
            model.rightTab = "Project"
        }
    }
}
