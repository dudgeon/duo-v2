import AppKit
import Foundation

/// The intro video's scene 2 as window states (`--state video-s2-<what>`, with `--fixture video/fixture/fixture.json`):
/// the fixture's project (`videoS2.project`) with three session tabs in the middle pane and four documents in
/// the right pane, each drawn by its real view (the editor, the HTML viewer, the deck and Word
/// viewers) from files beside the fixture. Terminals show a recorded screen with no process behind
/// them; the chat state shows the last tab's recorded chat. `video-s2-middle-<0..2>` activates a
/// session tab, `video-s2-chat` the last one in chat view, `video-s2-right-<1..4>` a document tab
/// (0 is the Project tab). Without the fixture's `videoS2` section these do nothing.
@MainActor
public enum VideoTargets {
    nonisolated public static let screens = ["video-s2-middle-0", "video-s2-middle-1", "video-s2-middle-2", "video-s2-chat",
                                             "video-s2-right-1", "video-s2-right-2", "video-s2-right-3", "video-s2-right-4",
                                             // Scene 3: All projects as a List. Scene 4: sessions (resume, menu, archive, delete). Scene 5: the same session in chat.
                                             "video-s3-list",
                                             "video-s4-resumed", "video-s4-menu", "video-s4-archived", "video-s4-delete-ask", "video-s4-deleted",
                                             "video-s5-chat", "video-s5-chat-open", "video-s5-draft", "video-s5-paste-text", "video-s5-paste-image"]

    public static func apply(_ screen: String, to model: AppModel) {
        if screen == "video-s3-list" { return applyS3(model) }
        if screen.hasPrefix("video-s4-") || screen.hasPrefix("video-s5-") { return applyS4S5(screen, to: model) }
        TargetState.project.apply(to: model)
        guard let v = model.fixture.videoS2, let base = model.fixture.baseDir else { return }
        let dir = URL(fileURLWithPath: base)
        let project = v.project ?? "checkout-redesign"
        model.altitude = .project(project)
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
            chat.log.cwd = v.cwd ?? "/Users/pm/work/payments/checkout-redesign"
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

    // MARK: Scene 3: All projects, List

    /// All projects with the List in the middle (every session by recency, the Open section with the three
    /// terminals scene 2 filmed) and the Needs you column on the right, on the demo's day (Tue 13 Oct, 9:41).
    static func applyS3(_ model: AppModel) {
        TargetState.overview.apply(to: model)
        model.homeView = .list
        model.rightCollapsedAllProjects = false
        model.listClock = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 9, minute: 41))
        if let v = model.fixture.videoS2 {
            let names = Set(v.terminals.map(\.name))
            model.fixtureActive = Set(model.fixture.sessions.filter { names.contains($0.name) }.map(\.tabKey))
        }
        WindowCapture.underlay = DuoNSColor.console
    }

    // MARK: Scenes 4 and 5: the shelf-scan project with "Auto-add decision" in the middle pane

    static let autoAdd = "Auto-add decision"
    static let testFlight = "quick q: TestFlight build size"
    static let oldNotes = "Old v1 notes cleanup"

    static func applyS4S5(_ screen: String, to model: AppModel) {
        TargetState.project.apply(to: model)
        guard let v = model.fixture.videoS2, let base = model.fixture.baseDir else { return }
        let dir = URL(fileURLWithPath: base)
        let project = v.project ?? "checkout-redesign"
        model.altitude = .project(project)
        let folder = dir.appending(path: v.folder).standardizedFileURL
        // The project's own sessions stay as the fixture has them (all of them listed); only grouping goes.
        model.fixture.groups = model.fixture.groups.filter { $0.project != project }
        model.fixture.projectFiles[project] = v.files
        model.selectedSidebarItem = nil
        model.expandedGroups = []
        model.liveFolders[project] = folder
        model.videoDemoFolder = folder
        WindowCapture.underlay = DuoNSColor.console
        model.videoRightWidth = 700
        // Scene 2's three terminals stay open; "Auto-add decision" was just resumed and is the tab in front.
        for t in v.terminals {
            let text = (try? String(contentsOf: dir.appending(path: t.screen), encoding: .utf8)) ?? ""
            model.fixtureTerminals[t.name] = TerminalSession(key: t.name, screen: text)
        }
        let screenText = v.s4Terminal.flatMap { try? String(contentsOf: dir.appending(path: $0), encoding: .utf8) } ?? ""
        model.fixtureTerminals[autoAdd] = TerminalSession(key: autoAdd, screen: screenText)
        model.parkedTabs = Set(v.terminals.map(\.name) + [autoAdd])
        model.openDocuments = v.tabs
        if let prd = v.tabs.first { model.rightTab = prd; model.selectedFile = prd } else { model.rightTab = "Project" }
        model.consoleTab = autoAdd

        // The chat of the same session: terminal mode in scene 4 (it makes the toggle show), chat in scene 5.
        if let rec = v.s5Chat {
            let chat = ChatSession(key: autoAdd, mode: screen.hasPrefix("video-s5-") ? .chat : .terminal)
            chat.log.cwd = v.cwd ?? "/Users/pm/work/payments/checkout-redesign"
            chat.videoAnchors = true
            ChatRecording.play(dir.appending(path: rec), into: chat)
            if chat.fixtureScreenText == nil { chat.fixtureScreenText = "" }   // a fixture chat has no TUI: a picture paste takes the next number
            model.fixtureChats[autoAdd] = chat
            if screen == "video-s5-chat-open" { openScoreRow(chat) }
        }

        switch screen {
        case "video-s4-menu":
            // The row as its context menu leaves it (Q-147); the NSMenu is a window of its own that captures don't draw.
            model.contextMenuSession = testFlight
        case "video-s4-archived", "video-s4-delete-ask", "video-s4-deleted":
            archive(testFlight, in: model)
            model.expandedGroups.insert("\(project)/archived")
            if screen == "video-s4-delete-ask" { askDelete(oldNotes, in: model) }
            if screen == "video-s4-deleted" { model.fixture.sessions.removeAll { $0.name == oldNotes } }
        default: break
        }
    }

    /// Archive Session's effect on the lists: the row leaves them for the project's Archived fold.
    static func archive(_ name: String, in model: AppModel) {
        guard let i = model.fixture.sessions.firstIndex(where: { $0.name == name }) else { return }
        model.fixture.archivedSessions = (model.fixture.archivedSessions ?? []) + [model.fixture.sessions.remove(at: i)]
    }

    /// Delete Session…'s own question, worded by the real code, over a sample plan (the demo's session has no files on disk).
    static func askDelete(_ name: String, in model: AppModel) {
        let id = "5b0e1c52-7a3d-4f0e-9c1a-2d8e6f4a9b13"
        let bucket = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects/-Users-sam-work-little-shared-library-shelf-scan")
        func step(_ n: Int, _ url: URL, _ bytes: Int) -> Migrator.Step { .init(n: n, op: .delete, from: url.path, to: "", sessionId: id, bytesBefore: bytes) }
        let plan = Migrator.Journal(id: "video", kind: .delete, state: .planned, created: Date(), summary: "Delete \(id.prefix(8)) and its local logs", mapping: ["session": id],
                                    steps: [step(1, bucket.appending(path: "\(id).jsonl"), 96_000), step(2, bucket.appending(path: id), 21_000),
                                            step(3, FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Duo/archive/\(id).jsonl"), 96_000)])
        let w = AppModel.deleteWording(name: name, plan: plan, inDuo: false)
        model.confirm(title: w.title, detail: w.detail, button: "Move to Trash") { _ in }
    }

    /// Opens the Bash `python3 eval/score.py` row (else the first tool row): its run, and the step's output.
    static func openScoreRow(_ chat: ChatSession) {
        var first: (run: String?, step: ChatToolStep)?, found: (run: String?, step: ChatToolStep)?
        func see(_ run: String?, _ s: ChatToolStep) {
            if first == nil { first = (run, s) }
            if found == nil, s.name == "Bash", s.object.contains("score.py") { found = (run, s) }
        }
        for case .claude(let turn) in chat.log.items {
            for b in ChatRuns.blocks(turn.segments) {
                switch b {
                case .run(let r): for case .step(let s) in r.entries { see(r.id, s) }
                case .step(let s): see(nil, s)
                default: break
                }
            }
        }
        guard let t = found ?? first else { return }
        if let run = t.run { chat.ui.openRuns.insert(run); chat.ui.toggled.insert(t.step.id) }
        else if t.step.foldsByDefault { chat.ui.toggled.insert(t.step.id) }   // a lone Bash step with output is open already
    }

    // MARK: Actions a state implies

    /// `--then` actions a state brings with it, ahead of the caller's: scene 5's composer states need the window (the composer is
    /// an AppKit field, and pasting goes through ⌘V's real path), so they run after it exists. The caller's own `--then` follows.
    nonisolated public static func impliedActions(for screen: String?, fixturePath: String?) -> [String] {
        guard let screen, screen.hasPrefix("video-s5-"), let fixturePath else { return [] }
        let order = ["video-s5-draft", "video-s5-paste-text", "video-s5-paste-image"]
        guard let step = order.firstIndex(of: screen) else { return [] }
        let dir = URL(fileURLWithPath: fixturePath).deletingLastPathComponent()
        let content = (try? Data(contentsOf: dir.appending(path: "docs/content.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let s5 = content?["s5"] as? [String: String]
        let draft = s5?["draft"] ?? "Here is Denise's feedback from the beta. Can you weigh it against the auto-add question?"
        let select = s5?["select"] ?? "Can you weigh it against the auto-add question?"
        let feedback = dir.appending(path: "docs/research/feedback").path
        var out = ["chat-type:\(draft)"]
        if step >= 1 { out += ["chat-select:end", "chat-paste:textfile=\(feedback)/denise-p3.txt"] }
        if step >= 2 { out += ["chat-select:end", "chat-paste:file=\(feedback)/denise-p3-screenshot.png"] }
        if step == 0 { out += ["chat-select:\(select)"] }
        return out
    }
}
