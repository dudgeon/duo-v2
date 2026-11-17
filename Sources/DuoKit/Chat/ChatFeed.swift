import DuoControl
import Foundation

/// Feeds a live session's chat: the transcript for history (the last 50 turns, Q-56c, with
/// Earlier turns on request) and then both files as they grow — Duo's per-session hook events
/// (`events/<id>.jsonl`, F-23) and Claude's transcript. Read-only; whole lines only; lines that
/// don't parse are skipped (two hooks writing at once can merge lines, F-105, C-27).
@MainActor
final class ChatFeed {
    let sessionId: String
    let cwd: String
    /// A fork's parent: its history until the fork writes a transcript of its own (F-367, F-705).
    let historyFrom: String?
    /// The history shown is the parent's. The fork's own file, when it appears, replaces it (it holds a copy of every
    /// parent record, F-292); nothing more is read from the parent's file after the first load.
    private var borrowed = false
    weak var chat: ChatSession?
    private var timer: Timer?
    private var eventsPos: UInt64 = 0
    private var transcript: URL?
    private var transcriptPos: UInt64 = 0
    private var transcriptRest = Data()
    private var eventsRest = Data()
    /// Every transcript record read at attach, for Earlier turns.
    private var history: [ChatJSON] = []
    private(set) var historyStart = 0
    /// How many of your prompts the log was last built to show (a rewind rebuilds the same window).
    private var turnsWindow = ChatFeed.turnsShown
    /// Tells a rewound branch's first prompt as the transcript grows (F-656).
    private var tracker = LiveBranch.Tracker()
    nonisolated static let turnsShown = 50

    init(sessionId: String, cwd: String, chat: ChatSession, historyFrom: String? = nil) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.historyFrom = historyFrom
        self.chat = chat
        chat.log.cwd = cwd
        loadHistory()
        startEvents()
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }.loose()
    }

    func stop() { timer?.invalidate(); timer = nil }
    var isRunning: Bool { timer != nil }

    var eventsURL: URL { HookEvents.file(for: sessionId) }

    /// The transcript so far: read, parsed and replayed off the main thread (a long session's is
    /// 100 MB and more, seconds of work, F-160); the last 50 turns go into the log. Until it's in,
    /// the tick reads nothing, so hooks and the transcript resume where the history ends.
    private func loadHistory() {
        // A `--fork-session` fork has no file under its id until its first message (F-292): show its parent's meanwhile,
        // or chat is a blank pane while the terminal draws the history (F-367).
        let own = ClaudeStorage.transcript(sessionId: sessionId, cwd: cwd)
        guard let url = own ?? historyFrom.flatMap({ ClaudeStorage.transcript(sessionId: $0, cwd: cwd) }) else { return }
        borrowed = own == nil
        if !borrowed { transcript = url }
        let borrowing = borrowed
        loading = true
        let cwd = cwd, declined = chat?.lastDeclined
        Task.detached(priority: .userInitiated) { [weak self] in
            let data = (try? Data(contentsOf: url)) ?? Data()
            let cut = data.lastIndex(of: UInt8(ascii: "\n")).map { $0 + 1 } ?? 0
            // Turns /rewind removed stay in the file as a dead branch: follow the live one (F-656).
            let records = ChatFeed.liveRecords(data.prefix(cut))
            let start = ChatFeed.start(of: records, turns: ChatFeed.turnsShown)
            let built = Built(records: records, start: start, turns: ChatFeed.turnsShown, log: ChatFeed.replay(records, from: start, cwd: cwd, lastDeclined: declined))
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.transcriptPos = borrowing ? 0 : UInt64(cut)   // the fork's own file is read from its start
                self.land(built)
            }
        }
    }

    private struct Records: @unchecked Sendable { let all: [ChatJSON] }
    private struct Built: @unchecked Sendable {
        let records: [ChatJSON]; let start: Int; let turns: Int; let log: ChatLog; let tracker: LiveBranch.Tracker
        init(records: [ChatJSON], start: Int, turns: Int, log: ChatLog) {
            self.records = records; self.start = start; self.turns = turns; self.log = log
            tracker = LiveBranch.Tracker(records)   // built where the Built is: off the main thread
        }
    }
    private var loading = false

    /// A transcript's records on its live branch (F-656).
    nonisolated static func liveRecords(_ data: Data) -> [ChatJSON] { LiveBranch.filter(ChatIngest.lines(data)) }

    /// A scratch log of the records from `start` on, built wherever it's called.
    nonisolated static func replay(_ records: [ChatJSON], from start: Int, cwd: String?, lastDeclined: String?) -> ChatLog {
        let log = ChatLog()
        log.cwd = cwd
        log.earlierHidden = start > 0
        for r in records[start...] { ChatIngest.record(r, into: log, lastDeclined: lastDeclined) }
        return log
    }

    private func land(_ built: Built) {
        history = built.records
        historyStart = built.start
        turnsWindow = built.turns
        tracker = built.tracker
        chat?.log.adopt(built.log)
        loading = false
    }

    /// Where the last `turns` of your prompts begin.
    nonisolated static func start(of records: [ChatJSON], turns: Int) -> Int {
        var n = 0
        for i in records.indices.reversed() {
            let r = records[i]
            if (r["type"] as? String == "user" && (r["message"] as? ChatJSON)?["content"] is String && r["isMeta"] as? Bool != true) || MidTurnPrompt.text(r) != nil {
                n += 1
                if n == turns { return i }
            }
        }
        return 0
    }

    /// Earlier turns: 50 more, replayed off the main thread like the first 50.
    func loadEarlier() {
        guard historyStart > 0, !loading else { return }
        let shown = history[historyStart...].filter { ($0["type"] as? String == "user" && ($0["message"] as? ChatJSON)?["content"] is String) || MidTurnPrompt.text($0) != nil }.count
        let held = Records(all: history), cwd = cwd, declined = chat?.lastDeclined
        loading = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let records = held.all
            let start = ChatFeed.start(of: records, turns: shown + ChatFeed.turnsShown)
            let built = Built(records: records, start: start, turns: shown + ChatFeed.turnsShown, log: ChatFeed.replay(records, from: start, cwd: cwd, lastDeclined: declined))
            await MainActor.run { [weak self] in self?.land(built) }
        }
    }

    /// A rewind showed up in the transcript (a prompt on a branch that already has a live prompt):
    /// the removed turns leave the log. `history` is the live branch plus what just arrived; the
    /// filter drops the prompts the new branch replaced, and the same window is replayed.
    private func rewound() {
        let held = Records(all: history), cwd = cwd, declined = chat?.lastDeclined, turns = turnsWindow
        loading = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let records = LiveBranch.filter(held.all)
            let start = ChatFeed.start(of: records, turns: turns)
            let built = Built(records: records, start: start, turns: turns, log: ChatFeed.replay(records, from: start, cwd: cwd, lastDeclined: declined))
            await MainActor.run { [weak self] in self?.land(built) }
        }
    }

    /// Hook events from the start of the turn in progress (after the last Stop), so a reply already
    /// streaming when chat opens isn't missed; matching drops what the transcript already showed.
    private func startEvents() {
        guard let h = try? FileHandle(forReadingFrom: eventsURL) else { return }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let start = size > 256 * 1024 ? size - 256 * 1024 : 0
        try? h.seek(toOffset: start)
        let data = (try? h.readToEnd()) ?? Data()
        let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        var offset = start, from = size
        var openTurn = false
        var asking: (e: ChatJSON, at: Double?)?
        for (i, l) in lines.enumerated() {
            if i == 0, start > 0 { offset += UInt64(l.count + 1); continue }
            if let obj = try? JSONSerialization.jsonObject(with: Data(l)) as? ChatJSON, let e = obj["e"] as? ChatJSON {
                let name = e["hook_event_name"] as? String
                if name == "UserPromptSubmit" { from = offset; openTurn = true }
                if name == "Stop" || name == "SessionStart" { openTurn = false; asking = nil }
                if name == "PermissionRequest" { asking = (e, (obj["at"] as? NSNumber)?.doubleValue) }
                if name == "PostToolUse" || name == "PostToolUseFailure", e["tool_name"] as? String == asking?.e["tool_name"] as? String { asking = nil }
            }
            offset += UInt64(l.count + 1)
        }
        eventsPos = openTurn ? from : size
        // A long turn's events (MessageDisplay above all) can push its prompt out of the window: the
        // dialog Claude is waiting on is still owed its request, or chat falls back (F-419).
        if !openTurn, let a = asking, let tool = a.e["tool_name"] as? String {
            chat?.pendingRequest = ChatRequest(tool: tool, input: a.e["tool_input"] as? ChatJSON ?? [:], at: a.at.map { Date(timeIntervalSince1970: $0) } ?? Date())
        }
    }

    /// The events file's state, for the report when no hook was read (F-749): missing, or how big and how fresh.
    var eventsFileState: String {
        guard let a = try? FileManager.default.attributesOfItem(atPath: eventsURL.path) else { return "no events file" }
        let size = (a[.size] as? NSNumber)?.intValue ?? 0
        let age = (a[.modificationDate] as? Date).map { String(format: "%.0f s", Date().timeIntervalSince($0)) } ?? "?"
        return "events file \(size) bytes, written \(age) ago"
    }

    /// The question on screen, asked in another session's events (F-749). `/clear`, `/resume` and plan approval's
    /// "clear context" start another session in the same process, and its hooks write under the new id from then on;
    /// until Duo's refresh sees the beacon move (F-29), or if it never does, this feed reads a file nothing writes.
    /// So when a question has no request here, the events files written in the last two minutes are searched for an
    /// unanswered AskUserQuestion, asked in this session's folder, whose questions include the one on screen. The
    /// match is by the question's text, the same test `questionIndex` makes, so the request found agrees with the
    /// screen or isn't taken.
    @discardableResult
    func adoptMovedQuestion(shown: String) -> String? {
        guard let chat else { return nil }
        let want = shown.chatNorm
        guard !want.isEmpty else { return nil }
        // Only a session in this folder: the same question asked elsewhere at the same time is someone else's.
        let here = URL(fileURLWithPath: cwd).resolvingSymlinksInPath().path
        let dir = eventsURL.deletingLastPathComponent()
        let recent = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "jsonl" && $0.lastPathComponent != eventsURL.lastPathComponent }
            .compactMap { u -> (URL, Date)? in
                guard let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                      Date().timeIntervalSince(d) < 120 else { return nil }
                return (u, d)
            }
            .sorted { $0.1 > $1.1 }
        for (url, _) in recent.prefix(16) {
            guard let h = try? FileHandle(forReadingFrom: url) else { continue }
            let size = (try? h.seekToEnd()) ?? 0
            try? h.seek(toOffset: size > 512 * 1024 ? size - 512 * 1024 : 0)
            let data = (try? h.readToEnd()) ?? Data()
            try? h.close()
            var open: (input: ChatJSON, at: Double?)?
            for e in ChatIngest.lines(data) {
                guard let p = e["e"] as? ChatJSON, let name = p["hook_event_name"] as? String else { continue }
                let tool = p["tool_name"] as? String
                if (name == "PermissionRequest" || name == "PreToolUse"), tool == "AskUserQuestion", let input = p["tool_input"] as? ChatJSON,
                   (p["cwd"] as? String).map({ URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }) == here {
                    open = (input, (e["at"] as? NSNumber)?.doubleValue)
                } else if name == "Stop" || name == "SessionStart" || ((name == "PostToolUse" || name == "PostToolUseFailure") && tool == "AskUserQuestion") {
                    open = nil
                }
            }
            guard let o = open else { continue }
            let qs = (o.input["questions"] as? [ChatJSON]) ?? []
            let hits = qs.filter { q in
                let asked = (q["question"] as? String ?? "").chatNorm
                return asked == want || (want.count >= 20 && asked.hasSuffix(want))
            }
            guard hits.count == 1 else { continue }
            let id = url.deletingPathExtension().lastPathComponent
            chat.pendingRequest = ChatRequest(tool: "AskUserQuestion", input: o.input, at: o.at.map { Date(timeIntervalSince1970: $0) } ?? Date(),
                                              source: "events of \(id.prefix(8))")
            return id
        }
        return nil
    }

    /// When the feed last read a hook event, and which: the Debug report's evidence (F-419).
    private(set) var lastEvent: (name: String, at: Date)?
    var isLoading: Bool { loading }

    /// Reads the hooks now, shown or not (a dialog's request is due). While the transcript loads,
    /// only the request is taken: the rest waits for the log the load builds (F-419).
    func catchUp() {
        guard let chat else { return }
        if loading { peekRequest(); return }
        readEvents(chat)
    }

    /// The newest unanswered request among the events not yet read, without reading them.
    private func peekRequest() {
        guard let chat, let h = try? FileHandle(forReadingFrom: eventsURL) else { return }
        defer { try? h.close() }
        try? h.seek(toOffset: eventsPos)
        let data = (try? h.read(upToCount: 4 << 20)) ?? Data()
        for e in ChatIngest.lines(eventsRest + data) {
            guard let p = e["e"] as? ChatJSON, let name = p["hook_event_name"] as? String else { continue }
            if name == "PermissionRequest", let tool = p["tool_name"] as? String {
                chat.pendingRequest = ChatRequest(tool: tool, input: p["tool_input"] as? ChatJSON ?? [:],
                                                  at: (e["at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? Date())
            } else if name == "Stop" { chat.pendingRequest = nil }
        }
    }

    private func readEvents(_ chat: ChatSession) {
        for e in read(eventsURL, &eventsPos, &eventsRest) {
            if let p = e["e"] as? ChatJSON {
                if p["hook_event_name"] as? String == "SessionStart", let t = p["transcript_path"] as? String, transcript == nil {
                    transcript = URL(fileURLWithPath: t)
                }
                ChatIngest.hook(p, at: (e["at"] as? NSNumber)?.doubleValue, into: chat.log, chat: chat)
                if let n = p["hook_event_name"] as? String { lastEvent = (n, Date()) }
            }
        }
    }

    private var ticks = 0

    private func tick() {
        guard let chat else { return stop() }
        // Off screen, every 2 s (ENH-45); on screen, every tick, after reading what it skipped.
        ticks += 1
        // A long transcript loads for seconds (F-160): the request a dialog waits on can't wait that long (F-419).
        if loading { if chat.isShown(), chat.dialogUp { peekRequest() }; return }
        if chat.isShown() { chat.wake() } else if ticks % 13 != 0 { return }
        readEvents(chat)
        if transcript == nil { transcript = ClaudeStorage.transcript(sessionId: sessionId, cwd: cwd) }
        // The fork's first message wrote its own file, every parent record copied into it: rebuild from that file.
        if borrowed, let t = transcript, FileManager.default.fileExists(atPath: t.path) {
            borrowed = false
            transcript = nil
            transcriptPos = 0; transcriptRest = Data()
            return loadHistory()
        }
        if borrowed { return }
        if let t = transcript {
            let fresh = read(t, &transcriptPos, &transcriptRest)
            var branched = false
            for r in fresh where tracker.add(r) { branched = true }
            history.append(contentsOf: fresh)
            if branched { rewound(); return }
            for r in fresh { ChatIngest.record(r, into: chat.log, chat: chat) }
        }
    }

    /// New whole lines since `pos` (at most 4 MB a tick).
    private func read(_ url: URL, _ pos: inout UInt64, _ rest: inout Data) -> [ChatJSON] {
        guard let h = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        if size < pos { pos = 0; rest = Data() }   // replaced
        guard size > pos else { return [] }
        try? h.seek(toOffset: pos)
        let data = (try? h.read(upToCount: Int(min(size - pos, 4 << 20)))) ?? Data()
        pos += UInt64(data.count)
        var all = rest + data
        guard let last = all.lastIndex(of: UInt8(ascii: "\n")) else { rest = all; return [] }
        rest = all.suffix(from: last + 1)
        all = all.prefix(upTo: last + 1)
        return ChatIngest.lines(all)
    }
}

/// For the checks: where the last `turns` prompts begin.
public enum ChatFeedProbe {
    @MainActor public static func start(_ records: [ChatJSON], turns: Int) -> Int { ChatFeed.start(of: records, turns: turns) }
    /// A replay built off the main thread, as opening a chat builds it (F-160).
    public static func replayOffMain(_ transcript: Data) async -> ChatLog {
        await Task.detached { Held(log: ChatFeed.replay(ChatFeed.liveRecords(transcript), from: 0, cwd: nil, lastDeclined: nil)) }.value.log!
    }
    /// A transcript timestamp, read as the replay reads it.
    public static func date(_ s: String) -> Date? { ChatIngest.date(s) }
    private struct Held: @unchecked Sendable {
        let log: ChatLog?
    }
}
