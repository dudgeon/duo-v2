import AppKit
import Foundation

/// The chat-mode-handoff boards as window states (`--state chat-<board>`), each drawn from a
/// recording in `docs/design/chat-mode-handoff/fixture-chat/<board>/` (bundled as
/// `Resources/chat-fixtures`): `meta.json` (mode, fallback, CLI version, tabs), and optionally
/// `events.jsonl` (hook payloads, as Duo's hooks write them), `transcript.jsonl` (Claude's
/// transcript lines) and `screen.txt` (the TUI's screen). The same readers as a live session read
/// them, so the targets exercise the real pipeline. `scripts/check-chat.sh` captures and compares.
@MainActor
public enum ChatTargets {
    nonisolated public static let boards = ["window", "toggle", "text", "tools", "permission-edit", "permission-bash", "plan", "question-multi",
                                            "question-other", "question-review", "question-previews", "question-chat-decline", "composer", "status", "fallback",
                                            // chat-polish-handoff (DL-135): runs folded, and the candidates folded with them.
                                            "polish-collapsed", "polish-expanded", "polish-needs-you", "polish-output", "polish-edits", "polish-thinking",
                                            "polish-agents", "polish-todos", "polish-tools", "polish-failed", "polish-paste",
                                            // DL-136: the thin light strip over chat.
                                            "polish-bar-thin",
                                            // chat-slash-handoff (DL-143): command results, the picker cards, the named bar, the / menu.
                                            "slash-output", "slash-context", "slash-model-card", "slash-effort-card", "slash-fallback-named", "slash-menu",
                                            // chat-paste-handoff (DL-161): pictures in the composer and your bubble, and why one wasn't taken.
                                            "paste-picture", "paste-adding", "paste-sent", "paste-edges", "paste-failed", "paste-keys",
                                            "paste-text", "paste-text-open", "paste-huge"]
    nonisolated public static let screens = boards.map { "chat-" + $0 }

    public static func folder(_ board: String) -> URL? {
        if let r = Bundle.main.url(forResource: "chat-fixtures", withExtension: nil) { return r.appending(path: board) }
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let handoff = board.hasPrefix("polish-") ? "chat-polish-handoff" : board.hasPrefix("slash-") ? "chat-slash-handoff" : board.hasPrefix("paste-") ? "chat-paste-handoff" : "chat-mode-handoff"
        for _ in 0..<6 {
            let c = dir.appending(path: "docs/design/\(handoff)/fixture-chat/\(board)")
            if FileManager.default.fileExists(atPath: c.path) { return c }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    public static func apply(_ screen: String, to model: AppModel) {
        let board = String(screen.dropFirst("chat-".count))
        TargetState.project.apply(to: model)
        guard let dir = folder(board) else { return }
        let meta = (try? Data(contentsOf: dir.appending(path: "meta.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let tab = meta["tab"] as? String ?? "PRD v2 edits"
        model.consoleTab = tab
        // Tabs the board draws: its sessions' states, and any shells.
        for (name, state) in meta["states"] as? [String: String] ?? [:] {
            if let i = model.fixture.sessions.firstIndex(where: { $0.name == name }), let st = SessionState(rawValue: state) { model.fixture.sessions[i].state = st }
        }
        if let shells = meta["shells"] as? [String], let project = model.currentProject?.name {
            let keys = shells.map { AppModel.shellPrefix + $0 }
            for (k, n) in zip(keys, shells) { model.shellTitles[k] = n }
            model.shellTabs[project] = keys
        }
        let chat = ChatSession(key: tab, mode: ChatViewMode(rawValue: meta["mode"] as? String ?? "chat") ?? .chat)
        chat.lastDeclined = meta["lastDeclined"] as? String
        if meta["focusComposer"] as? Bool == true { chat.focusComposer += 1 }
        // Files a card reads (an edit's line numbers, a plan), as the board's project has them.
        let files = meta["files"] as? [String: String] ?? [:]
        chat.readFile = { files[$0] }
        chat.answersToReplay = (meta["answers"] as? [[String: String]] ?? []).compactMap { a in
            guard let at = a["at"].flatMap({ ChatIngest.iso.date(from: $0) }), let text = a["text"] else { return nil }
            return (at, text)
        }
        chat.setVersion(meta["version"] as? String ?? "2.1.291")
        // A command sent from chat a moment ago (DL-143): its screen's bar names it.
        if let c = (meta["fallback"] as? [String: String])?["command"] { chat.lastCommand = (c, Date()) }
        ChatRecording.play(dir, into: chat, now: meta["now"] as? String)
        for id in meta["toggled"] as? [String] ?? [] { chat.ui.toggled.insert(id) }
        for id in meta["openRuns"] as? [String] ?? [] { chat.ui.openRuns.insert(id) }
        if let d = meta["drafts"] as? [String: String] {
            chat.ui.planFeedback = d["plan"] ?? ""
            chat.ui.notes = d["notes"] ?? ""
            chat.ui.composer = d["composer"] ?? ""
        }
        // Pictures (chat-paste-handoff): in the composer's row, on your last bubble, the dashed tile, the failure line.
        for (i, spec) in (meta["pictures"] as? [[String: Any]] ?? []).enumerated() {
            let token = "[Image #\(i + 1)]"
            chat.ui.images[token] = ChatTargetPicture.draw(spec)
            chat.ui.attachedTokens.append(token)
            chat.ui.heldTokens.append(token)
        }
        if let h = meta["hoverPicture"] as? Int, h < chat.ui.attachedTokens.count { chat.ui.hoveredPicture = chat.ui.attachedTokens[h] }
        chat.ui.addingPicture = meta["adding"] as? Bool == true
        chat.ui.pasteNotice = (meta["notice"] as? String).flatMap { $0 == "keysMoved" ? .keysMoved : .notTaken }
        for spec in meta["bubblePictures"] as? [[String: Any]] ?? [] {
            if let png = ChatImage(ChatTargetPicture.draw(spec)) { chat.log.addImage(png) }
        }
        if let b = meta["block"] as? [String: Any] {
            chat.ui.fixtureBlock = ChatUIState.FixtureBlock(text: ChatTargetPicture.pasted(b["kind"] as? String ?? "review"), open: b["open"] as? Bool == true,
                                                            caretLine: b["caretLine"] as? Int, typed: chat.ui.composer)
            chat.ui.composer = ""
        }
        // An interrupted reply ends on the screen, not a hook (F-105): the busy → idle the TUI drew.
        if meta["interruptAfterPlay"] as? Bool == true { chat.log.endStreaming(interrupted: true) }
        if let f = meta["fallback"] as? [String: String] {
            chat.fallback = ChatFallback(kind: f["kind"] == "handedOver" ? .handedOver : .automatic, message: f["message"] ?? ChatFallback.unknownScreen.message, command: f["command"])
        }
        model.fixtureChats[tab] = chat
    }
}

/// Plays a recording into a chat: the transcript, then the hooks, then the screen.
@MainActor
public enum ChatRecording {
    public static func play(_ dir: URL, into chat: ChatSession, now: String? = nil) {
        // Board times are the boards' own (9:41): read and shown in UTC, whatever the Mac's zone.
        ChatWho.clock.timeZone = TimeZone(identifier: "UTC")
        if let now, let d = ChatIngest.iso.date(from: now) ?? ISO8601DateFormatter().date(from: now) { chat.fixedNow = d }
        chat.log.cwd = "/Users/pm/work/payments/checkout-redesign"
        // Both sources, in the order things happened (a transcript line before a hook at the same moment).
        let t = (try? Data(contentsOf: dir.appending(path: "transcript.jsonl"))).map(ChatIngest.lines) ?? []
        let e = (try? Data(contentsOf: dir.appending(path: "events.jsonl"))).map(ChatIngest.lines) ?? []
        var all: [(at: Double, n: Int, hook: Bool, obj: ChatJSON)] = []
        for (n, r) in t.enumerated() {
            all.append(((r["timestamp"] as? String).flatMap { ChatIngest.iso.date(from: $0) }?.timeIntervalSince1970 ?? 0, n, false, r))
        }
        for (n, r) in e.enumerated() { all.append(((r["at"] as? NSNumber)?.doubleValue ?? 0, t.count + n, true, r)) }
        // Answers the card itself writes (`You chose …`), at the moment they were given.
        for (n, a) in chat.answersToReplay.enumerated() { all.append((a.at.timeIntervalSince1970, t.count + e.count + n, true, ["answer": a.text])) }
        for x in all.sorted(by: { ($0.at, $0.n) < ($1.at, $1.n) }) {
            if let text = x.obj["answer"] as? String { chat.log.answer(text, time: Date(timeIntervalSince1970: x.at)); continue }
            if x.hook, let p = x.obj["e"] as? ChatJSON { ChatIngest.hook(p, at: x.at, into: chat.log, chat: chat) }
            else if !x.hook { ChatIngest.record(x.obj, into: chat.log, chat: chat) }
        }
        if let text = try? String(contentsOf: dir.appending(path: "screen.txt"), encoding: .utf8) {
            chat.fixtureScreenText = text
            chat.apply(ChatScreenReader.read(text, table: chat.signatures))
        }
    }
}

/// Stand-in pictures for the paste boards, drawn from the tokens in the shapes the boards show.
@MainActor
enum ChatTargetPicture {
    static func draw(_ spec: [String: Any]) -> NSImage {
        let w = CGFloat(spec["w"] as? Int ?? 128), h = CGFloat(spec["h"] as? Int ?? 128)
        let fill: NSColor = switch spec["fill"] as? String {
        case "chatYou": DuoNSColor.chatYou
        case "ground": DuoNSColor.ground
        case "selected": DuoNSColor.selected
        default: DuoNSColor.pane
        }
        let kind = spec["kind"] as? String ?? "plain"
        return NSImage(size: NSSize(width: w, height: h), flipped: true) { r in
            let u = (kind == "chart" || kind == "phone" ? r.height : r.width) / 64   // the boards' 64-point square, scaled
            func bar(_ x: CGFloat, _ y: CGFloat, _ bw: CGFloat, _ bh: CGFloat, _ c: NSColor) { c.setFill(); NSBezierPath(roundedRect: NSRect(x: x * u, y: y * u, width: bw * u, height: bh * u), xRadius: 1.5 * u, yRadius: 1.5 * u).fill() }
            fill.setFill(); r.fill()
            switch kind {
            case "chart":
                let top = CGFloat(0), left = CGFloat(0)
                bar(left + 7.5, top + 7.5, 30, 6, DuoNSColor.text)
                bar(left + 7.5, top + 17.5, 46, 4, DuoNSColor.rule)
                bar(left + 7.5, top + 25.5, 36, 4, DuoNSColor.rule)
                bar(left + 7.5, top + 45.5, 7, 9, DuoNSColor.controlEdge); bar(left + 17.5, top + 39.5, 7, 15, DuoNSColor.controlEdge)
                bar(left + 27.5, top + 33.5, 7, 21, DuoNSColor.text); bar(left + 37.5, top + 42.5, 7, 12, DuoNSColor.controlEdge)
            case "phone":
                DuoNSColor.controlEdge.setFill()
                let cx = r.midX, rad = 20 * u
                NSBezierPath(ovalIn: NSRect(x: cx - rad, y: r.maxY - rad * 1.2, width: rad * 2, height: rad * 2)).fill()
            case "frame":
                let f = NSRect(x: r.midX - r.width * 0.34, y: r.midY - r.height * 0.28, width: r.width * 0.68, height: r.height * 0.56)
                let box = NSBezierPath(roundedRect: f, xRadius: 3 * u, yRadius: 3 * u)
                DuoNSColor.ground.setFill(); box.fill()
                DuoNSColor.rule.setStroke(); box.lineWidth = u; box.stroke()
            default: break
            }
            return true
        }
    }
}

extension ChatTargetPicture {
    /// A long paste for the boards: the review notes (42 lines), or a 12,480-line log of about 1.2 MB.
    static func pasted(_ kind: String) -> String {
        if kind == "log" {
            let pad = String(repeating: "x", count: 40)
            return (0..<12_480).map { i in i == 0 ? "2026-10-08T09:14:02Z INFO checkout: session started id=8f1c…" : String(format: "2026-10-08T09:14:%02dZ INFO checkout: step %05d ok id=8f1c %@", i % 60, i, pad) }.joined(separator: "\n")
        }
        let notes = ["Review notes, 8 October", "1. Guest checkout keeps the card form on one page.", "2. Saved cards need an account; no guest vault in v1.",
                     "3. Apple Pay ships with the redesign, Google Pay after.", "4. Address autocomplete stays behind the flag.", "5. Error copy goes to content design by Friday.",
                     "6. Refund flows are out of scope; see flows.md.", "7. Open: who owns the fraud rules in the new flow…"]
        return (notes + (8..<42).map { "\($0). Follow-up note \($0)." }).joined(separator: "\n")
    }
}
