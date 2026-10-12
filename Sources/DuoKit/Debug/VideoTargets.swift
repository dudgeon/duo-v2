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
                                             "video-s4-resumed", "video-s4-tab-hover", "video-s4-tab-closed", "video-s4-menu", "video-s4-archived", "video-s4-delete-ask", "video-s4-deleted",
                                             "video-s5-chat", "video-s5-chat-open", "video-s5-draft", "video-s5-paste-text", "video-s5-paste-image",
                                             // Scene 6: chat mode, turn by turn (the recordings video/fixture/chat-s5-*).
                                             "video-s6-answered", "video-s6-open", "video-s6-typed", "video-s6-draft", "video-s6-paste-text", "video-s6-paste-image",
                                             "video-s6-turn1", "video-s6-slash", "video-s6-turn2", "video-s6-model", "video-s6-model-picked", "video-s6-final",
                                             // Scene 7: the editor pane (the right pane's tabs, the PRD's hand edits, Send Selection, the pickers).
                                             "video-s7-tab-md", "video-s7-tab-html", "video-s7-tab-pptx", "video-s7-tab-docx",
                                             "video-s7-bold-sel", "video-s7-bold", "video-s7-link-sel", "video-s7-link", "video-s7-typed", "video-s7-bullet",
                                             "video-s7-md-sel", "video-s7-md-composer", "video-s7-md-sent", "video-s7-md-after",
                                             "video-s7-html-pick", "video-s7-html-sent", "video-s7-html-after",
                                             "video-s7-pptx-slide3", "video-s7-pptx-pick", "video-s7-pptx-sent", "video-s7-pptx-after"]
                                            + s9s10Screens

    public static func apply(_ screen: String, to model: AppModel) {
        if screen == "video-s3-list" { return applyS3(model) }
        if screen == "video-s9-board" || screen == "video-s9-list" { return applyS9Home(screen, model) }
        if screen.hasPrefix("video-s4-") || screen.hasPrefix("video-s5-") || screen.hasPrefix("video-s6-") || screen.hasPrefix("video-s7-")
            || screen.hasPrefix("video-s9-") || screen.hasPrefix("video-s10-") { return applyS4S5(screen, to: model) }
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
    static let scanReview = "Prototype scan review"   // the tab the story closes ("Close one and come back to it later")

    static func applyS4S5(_ requested: String, to model: AppModel) {
        let screen = s9s10Base(requested)   // scenes 9 and 10's project states stand on scene 7's last one
        TargetState.project.apply(to: model)
        guard let v = model.fixture.videoS2, let base = model.fixture.baseDir else { return }
        let dir = URL(fileURLWithPath: base)
        let project = v.project ?? "checkout-redesign"
        if requested.hasPrefix("video-s10-") { assignSessionIds(model, dir: dir) }   // scene 10's tasks link sessions by id
        // A session's tab key: its id when it has one (scene 10), else its name, as the tabs of scenes 2 to 9 are keyed.
        func key(_ name: String) -> String { model.fixture.sessions.first { $0.project == project && $0.name == name }?.tabKey ?? name }
        model.altitude = .project(project)
        var folder = dir.appending(path: v.folder).standardizedFileURL
        // Scene 7 edits files (the editor saves them): its states work on a copy of the project's folder, never the fixture's.
        if screen.hasPrefix("video-s7-"), let scratch = s7Scratch(copyOf: folder, dir: dir, screen: screen) { folder = scratch }
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
            model.fixtureTerminals[key(t.name)] = TerminalSession(key: key(t.name), screen: text)
        }
        let screenText = v.s4Terminal.flatMap { try? String(contentsOf: dir.appending(path: $0), encoding: .utf8) } ?? ""
        model.fixtureTerminals[key(autoAdd)] = TerminalSession(key: key(autoAdd), screen: screenText)
        model.parkedTabs = Set((v.terminals.map(\.name) + [autoAdd]).map(key))
        model.openDocuments = v.tabs
        if let prd = v.tabs.first { model.rightTab = prd; model.selectedFile = prd } else { model.rightTab = "Project" }
        model.consoleTab = key(autoAdd)

        // The chat of the same session: terminal mode in scene 4 (it makes the toggle show), chat in scenes 5 and 6.
        if screen.hasPrefix("video-s7-") {
            let spec = S7.of(screen)
            let chat = s6Chat(dir.appending(path: spec.chat), cwd: v.cwd, picked: false, key: key(autoAdd))
            if spec.composer, let text = try? String(contentsOf: dir.appending(path: "chat-s7-md/composer.txt"), encoding: .utf8) {
                chat.ui.composer = text   // Duo's payload, then Sam's words: what the composer holds just before Send
                chat.focusComposer += 1
            }
            model.fixtureChats[key(autoAdd)] = chat
            model.rightTab = spec.tab; model.selectedFile = spec.tab
        } else if screen.hasPrefix("video-s6-") {
            if let folder = s6Folders[String(screen.dropFirst("video-s6-".count))] {
                let chat = s6Chat(dir.appending(path: folder), cwd: v.cwd, picked: screen == "video-s6-model-picked")
                model.fixtureChats[autoAdd] = chat
                if screen == "video-s6-open" { openLastToolRow(chat) }
            }
        } else if let rec = v.s5Chat {
            let chat = ChatSession(key: autoAdd, mode: screen.hasPrefix("video-s5-") ? .chat : .terminal)
            chat.log.cwd = v.cwd ?? "/Users/pm/work/payments/checkout-redesign"
            chat.videoAnchors = true
            ChatRecording.play(dir.appending(path: rec), into: chat)
            if chat.fixtureScreenText == nil { chat.fixtureScreenText = "" }   // a fixture chat has no TUI: a picture paste takes the next number
            model.fixtureChats[autoAdd] = chat
            if screen == "video-s5-chat-open" { openScoreRow(chat) }
        }

        if requested.hasPrefix("video-s9-") { applyS9Project(requested, model) }
        if requested.hasPrefix("video-s10-") { applyS10(requested, model: model, dir: dir, video: v, project: project) }

        // Scene 4 closes "Prototype scan review" with its ×, before the context menu; the states after it keep it closed. The pointer
        // over the tab shows the ×; closing goes through the tab's own close path, so the session stays filed in the list.
        if screen == "video-s4-tab-hover" { model.hoveredTab = key(scanReview) }
        if closedScanReview.contains(screen) || screen.hasPrefix("video-s5-") || screen.hasPrefix("video-s6-") { model.closeConsoleTab(key(scanReview)) }

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

    /// The scene 4 states after the tab was closed (scenes 5 and 6, which follow, close it too).
    static let closedScanReview: Set<String> = ["video-s4-tab-closed", "video-s4-menu", "video-s4-archived", "video-s4-delete-ask", "video-s4-deleted"]

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

    // MARK: Scene 6: the chat's turns

    /// Each scene 6 state's recording folder, beside the fixture (video/fixture/): what Sam has said and Claude has done so far.
    static let s6Folders = ["answered": "chat-s5-answered", "open": "chat-s5-answered", "typed": "chat-s5-answered", "draft": "chat-s5-answered",
                            "paste-text": "chat-s5-answered", "paste-image": "chat-s5-answered", "turn1": "chat-s5-turn1",
                            "slash": "chat-s5-slash", "turn2": "chat-s5-turn2", "model": "chat-s5-model",
                            "model-picked": "chat-s5-model", "final": "chat-s5"]

    /// A scene 6 chat from its recording folder, set up as the chat boards are (`ChatTargets.apply`): its `meta.json` brings the
    /// composer's draft and focus and the CLI version, its `screen.txt` the `/` menu or the `/model` picker. `picked`: the moment
    /// after Sonnet was chosen in the picker (Claude Code's own line in the transcript, and the prompt idle again).
    static func s6Chat(_ dir: URL, cwd: String?, picked: Bool, key: String = autoAdd) -> ChatSession {
        let meta = (try? Data(contentsOf: dir.appending(path: "meta.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let chat = ChatSession(key: key, mode: ChatViewMode(rawValue: meta["mode"] as? String ?? "chat") ?? .chat)
        chat.videoAnchors = true
        chat.setVersion(meta["version"] as? String ?? "2.1.296")
        if meta["focusComposer"] as? Bool == true { chat.focusComposer += 1 }
        ChatRecording.play(dir, into: chat)
        chat.log.cwd = cwd ?? "/Users/pm/work/payments/checkout-redesign"
        if let d = meta["drafts"] as? [String: String] { chat.ui.composer = d["composer"] ?? "" }
        if chat.fixtureScreenText == nil { chat.fixtureScreenText = "" }   // no TUI behind a fixture chat: a picture paste takes the next number
        if picked {
            // The picker's answer as the TUI prints it, then its prompt as it was: the slash recording's screen without the menu.
            let line: ChatJSON = ["type": "user", "message": ["role": "user", "content": "<local-command-stdout>Set model to `Sonnet 5.5` for this session only</local-command-stdout>"],
                                  "timestamp": "2026-10-12T16:20:00.000Z", "cwd": chat.log.cwd ?? ""]
            ChatIngest.record(line, into: chat.log, chat: chat)
            let idle = ((try? String(contentsOf: dir.deletingLastPathComponent().appending(path: "chat-s5-slash/screen.txt"), encoding: .utf8)) ?? "")
                .components(separatedBy: "\n").filter { !$0.hasPrefix("  ❯ /") && !$0.hasPrefix("    /") }
                .map { $0.hasPrefix("❯ /") ? "❯ " : $0 }.joined(separator: "\n")
            chat.fixtureScreenText = idle
            chat.apply(ChatScreenReader.read(idle, table: chat.signatures))
        }
        return chat
    }

    /// Opens the newest tool row in the chat (its run, and the step inside): whatever is last on the page, not a particular one.
    static func openLastToolRow(_ chat: ChatSession) {
        var last: (run: String?, step: ChatToolStep)?
        for case .claude(let turn) in chat.log.items {
            for b in ChatRuns.blocks(turn.segments) {
                switch b {
                case .run(let r): for case .step(let s) in r.entries { last = (r.id, s) }
                case .step(let s): last = (nil, s)
                default: break
                }
            }
        }
        guard let t = last else { return }
        if let run = t.run { chat.ui.openRuns.insert(run); chat.ui.toggled.insert(t.step.id) }
        else if t.step.foldsByDefault { chat.ui.toggled.insert(t.step.id) }
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
        if let screen, screen.hasPrefix("video-s9-") || screen.hasPrefix("video-s10-"), let fixturePath { return s9s10Actions(screen, dir: URL(fileURLWithPath: fixturePath).deletingLastPathComponent()) }
        if let screen, screen.hasPrefix("video-s7-"), let fixturePath { return s7Actions(screen, dir: URL(fileURLWithPath: fixturePath).deletingLastPathComponent()) }
        guard let screen, screen.hasPrefix("video-s5-") || screen.hasPrefix("video-s6-"), let fixturePath else { return [] }
        let order = screen.hasPrefix("video-s5-") ? ["video-s5-draft", "video-s5-paste-text", "video-s5-paste-image"]
                                                   : ["video-s6-draft", "video-s6-paste-text", "video-s6-paste-image"]
        // video-s6-typed: the draft as typed, before the drag selects part of it (the drag reveals video-s6-draft's selection).
        let typed = screen == "video-s6-typed"
        guard let step = typed ? 0 : order.firstIndex(of: screen) else { return [] }
        let dir = URL(fileURLWithPath: fixturePath).deletingLastPathComponent()
        let content = (try? Data(contentsOf: dir.appending(path: "docs/content.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let s5 = content?["s5"] as? [String: String]
        let draft = s5?["draft"] ?? "Here is Denise's feedback from the beta. Can you weigh it against the auto-add question?"
        let select = s5?["select"] ?? "Can you weigh it against the auto-add question?"
        let feedback = dir.appending(path: "docs/research/feedback").path
        var out = ["chat-type:\(draft)"]
        if step >= 1 { out += ["chat-select:end", "chat-paste:textfile=\(feedback)/denise-p3.txt"] }
        if step >= 2 { out += ["chat-select:end", "chat-paste:file=\(feedback)/denise-p3-screenshot.png"] }
        if step == 0 { out += [typed ? "chat-select:end" : "chat-select:\(select)"] }
        return out
    }
}
