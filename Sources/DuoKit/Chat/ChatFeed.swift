import Foundation

/// Feeds a live session's chat: the transcript for history (the last 50 turns, Q-56c, with
/// Earlier turns on request) and then both files as they grow — Duo's per-session hook events
/// (`events/<id>.jsonl`, F-23) and Claude's transcript. Read-only; whole lines only; lines that
/// don't parse are skipped (two hooks writing at once can merge lines, F-105, C-27).
@MainActor
final class ChatFeed {
    let sessionId: String
    let cwd: String
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
    static let turnsShown = 50

    init(sessionId: String, cwd: String, chat: ChatSession) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.chat = chat
        chat.log.cwd = cwd
        loadHistory()
        startEvents()
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
    }

    func stop() { timer?.invalidate(); timer = nil }

    var eventsURL: URL { HookEvents.file(for: sessionId) }

    /// The transcript so far, read off the main thread; the last 50 turns go into the log.
    private func loadHistory() {
        guard let url = ClaudeStorage.transcript(sessionId: sessionId, cwd: cwd) else { return }
        transcript = url
        let data = (try? Data(contentsOf: url)) ?? Data()
        let cut = data.lastIndex(of: UInt8(ascii: "\n")).map { $0 + 1 } ?? 0
        transcriptPos = UInt64(cut)
        history = ChatIngest.lines(data.prefix(cut))
        historyStart = Self.start(of: history, turns: Self.turnsShown)
        replayHistory()
    }

    /// Where the last `turns` of your prompts begin.
    static func start(of records: [ChatJSON], turns: Int) -> Int {
        var n = 0
        for i in records.indices.reversed() {
            let r = records[i]
            if r["type"] as? String == "user", (r["message"] as? ChatJSON)?["content"] is String, r["isMeta"] as? Bool != true {
                n += 1
                if n == turns { return i }
            }
        }
        return 0
    }

    private func replayHistory() {
        guard let chat else { return }
        chat.log.reset()
        chat.log.earlierHidden = historyStart > 0
        for r in history[historyStart...] { ChatIngest.record(r, into: chat.log, chat: chat) }
    }

    /// Earlier turns: 50 more.
    func loadEarlier() {
        guard historyStart > 0 else { return }
        let shown = history[historyStart...].filter { $0["type"] as? String == "user" && ($0["message"] as? ChatJSON)?["content"] is String }.count
        historyStart = Self.start(of: Array(history), turns: shown + Self.turnsShown)
        replayHistory()
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
        for (i, l) in lines.enumerated() {
            if i == 0, start > 0 { offset += UInt64(l.count + 1); continue }
            if let obj = try? JSONSerialization.jsonObject(with: Data(l)) as? ChatJSON, let e = obj["e"] as? ChatJSON {
                let name = e["hook_event_name"] as? String
                if name == "UserPromptSubmit" { from = offset; openTurn = true }
                if name == "Stop" || name == "SessionStart" { openTurn = false }
            }
            offset += UInt64(l.count + 1)
        }
        eventsPos = openTurn ? from : size
    }

    private func tick() {
        guard let chat else { return stop() }
        for e in read(eventsURL, &eventsPos, &eventsRest) {
            if let p = e["e"] as? ChatJSON {
                if p["hook_event_name"] as? String == "SessionStart", let t = p["transcript_path"] as? String, transcript == nil {
                    transcript = URL(fileURLWithPath: t)
                }
                ChatIngest.hook(p, at: (e["at"] as? NSNumber)?.doubleValue, into: chat.log, chat: chat)
            }
        }
        if transcript == nil { transcript = ClaudeStorage.transcript(sessionId: sessionId, cwd: cwd) }
        if let t = transcript {
            for r in read(t, &transcriptPos, &transcriptRest) { ChatIngest.record(r, into: chat.log, chat: chat) }
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
}
