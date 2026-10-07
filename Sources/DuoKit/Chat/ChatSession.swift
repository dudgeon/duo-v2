import AppKit
import Foundation
import Observation

// Chat mode (DL-118 to DL-120): a second, readable view of the real Claude Code TUI a session's
// terminal is already running. Nothing here starts, restarts or answers for Claude: switching
// only changes what the console pane shows, and every answer goes back as the TUI's own keys,
// after re-reading the screen (DL-118 §2). Architecture: docs/plan/spikes/chat-mode.md.

/// What a Claude tab shows.
public enum ChatViewMode: String, Codable, Sendable { case terminal, chat }

/// Chat mode's remembered choices (DL-119 §5): each session's mode, and the one used last, which
/// a new session opens in. Kept in Duo's support folder (`chat.json`).
public struct ChatPrefs: Codable, Sendable, Equatable {
    public var modes: [String: ChatViewMode] = [:]
    /// The mode last chosen, for new sessions; `terminal` until chat is first used (DL-120: a
    /// session changes only when switched to chat).
    public var last: ChatViewMode = .terminal
    /// `--default`: nil follows `last`; otherwise new sessions always open in this mode.
    public var fixedDefault: ChatViewMode?

    public init() {}

    public static var url: URL { DuoPaths.support.appending(path: "chat.json") }

    public static func load(_ url: URL = ChatPrefs.url) -> ChatPrefs {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(ChatPrefs.self, from: $0) } ?? ChatPrefs()
    }

    public func save(_ url: URL = ChatPrefs.url) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// A session's mode: its own once chosen, else the default for new sessions.
    public func mode(for id: String) -> ChatViewMode { modes[id] ?? fixedDefault ?? last }

    public mutating func set(_ mode: ChatViewMode, for id: String) {
        modes[id] = mode
        last = mode
    }
}

/// Why the terminal is showing in a session set to chat (handoff `fallback`). Both kinds come
/// back to chat by themselves once the TUI is back at its prompt; only the toggle stays.
public struct ChatFallback: Equatable, Sendable {
    public enum Kind: Sendable, Equatable { case automatic, handedOver }
    public var kind: Kind
    public var message: String
    /// The command that opened the screen, set in mono at the start of the message (DL-143).
    public var command: String?

    public static let unknownScreen = ChatFallback(kind: .automatic,
        message: "Chat mode can’t show this screen, so here’s the terminal. Chat comes back when it closes.")
    public static func automatic(_ m: String) -> ChatFallback { ChatFallback(kind: .automatic, message: m) }
    public static func handedOver(_ m: String) -> ChatFallback { ChatFallback(kind: .handedOver, message: m) }

    /// A command sent from chat opened a screen of its own (chat-slash-handoff `fallback-named`):
    /// the bar names it and the way out. "Shows" for a screen that only shows, "opens" for one
    /// that takes a choice; `/config` and `/resume` take two Escs (F-173).
    public static func command(_ name: String) -> ChatFallback {
        let shows: Set<String> = ["/usage", "/cost", "/status", "/help", "/skills", "/release-notes"]
        let twoEscs: Set<String> = ["/config", "/resume"]
        let rest = (shows.contains(name) ? " shows" : " opens") + " in Claude Code’s own screen. "
            + (twoEscs.contains(name) ? "Esc clears the search, then closes it." : "Esc closes it and brings chat back.")
        return ChatFallback(kind: .automatic, message: name + rest, command: name)
    }
}

/// The terminal a chat reads and answers: the live SwiftTerm view, or a scripted stand-in.
@MainActor
public protocol ChatTerminal: AnyObject {
    /// The visible rows, as text.
    func screenLines() -> [String]
    var columns: Int { get }
    /// Bytes into the PTY, as if typed.
    func sendKeys(_ text: String)
    /// Called after each batch of output (debounced by the caller).
    func onOutput(_ f: @escaping @MainActor () -> Void)
}

/// The keys chat mode sends, as the TUI reads them.
public enum ChatKey: String, Sendable {
    case enter, esc, up, down, left, right, tab, space, backspace, shiftTab, ctrlG, n

    public var bytes: String {
        switch self {
        case .enter: "\r"
        case .esc: "\u{1b}"
        case .up: "\u{1b}[A"
        case .down: "\u{1b}[B"
        case .right: "\u{1b}[C"
        case .left: "\u{1b}[D"
        case .tab: "\t"
        case .space: " "
        case .backspace: "\u{7f}"
        case .shiftTab: "\u{1b}[Z"
        case .ctrlG: "\u{07}"
        case .n: "n"
        }
    }
}

/// One Claude session's chat: its screen, its log, its mode and fallback.
@MainActor
@Observable
public final class ChatSession {
    /// The console tab key (the session id when live).
    public let key: String
    public var mode: ChatViewMode
    /// Set while a session in chat mode shows the terminal by itself or by a handover.
    public var fallback: ChatFallback?
    public private(set) var screen: ChatScreen = .starting
    /// The installed CLI's version, and the table its screens are read with.
    public private(set) var cliVersion: String?
    public private(set) var signatures: ChatSignatures = .v2_1_291
    /// Dialogs are answered from chat only on a verified CLI (fallback rule 3).
    /// How this CLI's dialogs are trusted (DL-145).
    public private(set) var versionTrust: ChatVersionTrust = .verified
    /// Dialogs are answered from chat: on a verified CLI, or a newer one while the dialog on screen
    /// reads whole by the verified signatures (DL-145).
    public var dialogsVerified: Bool {
        switch versionTrust {
        case .verified: true
        case .newer: ChatScreenReader.wellFormed(screen)
        case .unverified: false
        }
    }
    /// The conversation, from hooks and the transcript.
    public let log: ChatLog = { let l = ChatLog(); l.drawn = true; return l }()
    /// Folds and long outputs the reader opened.
    public let ui = ChatUIState()
    /// Fixture targets: the clock the Writing line counts from.
    public var fixedNow: Date?
    public var now: Date { fixedNow ?? Date() }
    /// Bumped to put the keyboard in the composer (Chat about this).
    public var focusComposer = 0
    /// A click on a row of the composer's `@` menu (DL-133): the field puts that match in.
    public var chooseMention = 0
    /// The plan Claude asks you to approve: the request's text, or its file before 2.1.285.
    public var planPath: String? { pendingRequest?.tool == "ExitPlanMode" ? pendingRequest?.input["planFilePath"] as? String : nil }
    public var planText: String? {
        guard pendingRequest?.tool == "ExitPlanMode" else { return nil }
        let fromHook = pendingRequest?.input["plan"] as? String
        let stale = cliVersion.flatMap(ChatVersion.init).map { $0 < ChatVersion.freshPlanInHook } ?? false
        if (stale || fromHook == nil), let p = planPath, let file = readFile(p) { return file }
        return fromHook
    }
    /// Fixture targets: answers the card wrote, replayed in time order.
    @ObservationIgnored public var answersToReplay: [(at: Date, text: String)] = []
    /// Reads a file for a card (fixture targets stand in their own files).
    @ObservationIgnored public var readFile: (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) }
    /// An edit request's diff with the file's line numbers, when the file can be read.
    public var requestDiff: [ChatDiffLine]? {
        guard let r = pendingRequest, r.tool == "Edit", let path = r.input["file_path"] as? String,
              let old = r.input["old_string"] as? String, let new = r.input["new_string"] as? String,
              let text = readFile(path), let range = text.range(of: old) else { return nil }
        let first = text[..<range.lowerBound].filter { $0 == "\n" }.count + 1
        var lines: [ChatDiffLine] = []
        // One line of context above, as the TUI shows it.
        let before = text[..<range.lowerBound].components(separatedBy: "\n").dropLast()
        if first > 1, let ctx = before.last { lines.append(ChatDiffLine(kind: .context, number: first - 1, text: ctx)) }
        let olds = old.components(separatedBy: "\n"), news = new.components(separatedBy: "\n")
        for (i, l) in olds.enumerated() { lines.append(ChatDiffLine(kind: .del, number: first + i, text: l)) }
        for (i, l) in news.enumerated() { lines.append(ChatDiffLine(kind: .add, number: first + i, text: l)) }
        return lines
    }
    /// A message to scroll to (⌘[ / ⌘]).
    public var revealRequest: String?
    /// The feed is scrolled to its end, so new items keep it there (F-160).
    @ObservationIgnored public var followsBottom = true
    /// Keys are on their way: the screen is expected to change, nothing falls back meanwhile.
    /// Once they've gone, the screen is judged again: a command that opened a screen of its own
    /// (`/help`, `/model`) may not draw again, so nothing else would (F-173).
    public var sending = false { didSet { if oldValue, !sending, !composing { evaluateFallback() } } }
    /// Claude's external editor is open for the composer (F-104): a blank screen is expected.
    public var composing = false { didSet { if oldValue, !composing, !sending { evaluateFallback() } } }
    /// The request Claude is waiting on, from PermissionRequest; cleared by the tool running or Stop.
    @ObservationIgnored public var pendingRequest: ChatRequest?
    /// How the last declined question should read (set when the card declines it).
    @ObservationIgnored public var lastDeclined: String?

    /// Held strongly: the live adapter holds its view weakly, so there's no cycle.
    @ObservationIgnored var terminal: ChatTerminal?
    /// Where `duo2 compose` finds the composer's text; nil: paste instead (no helper in this build).
    @ObservationIgnored public var composeDir: URL?
    /// The id the process was started with (`DUO_SESSION_ID`), which names the hand-over file:
    /// `duo2 compose` knows no other, and keeps it after `/clear`, `/branch` or `/resume` (F-174).
    @ObservationIgnored public var launchId: String?
    var composeKey: String { launchId ?? key }
    /// The hook and transcript reader, for a live session.
    @ObservationIgnored var feed: ChatFeed?
    /// Fixture mode: the screen the stand-in terminal shows.
    public var fixtureScreenText: String?
    @ObservationIgnored private var unknownSince: Date?
    @ObservationIgnored private var unknownTimer: Timer?
    @ObservationIgnored private var readPending = false
    /// Told when chat comes back or leaves by itself, so the store can persist nothing (it isn't a choice).
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    /// How long `unknown` must last before the terminal shows: the screen is blank for a moment at
    /// start and while the external editor runs (F-105).
    public static let grace: TimeInterval = 0.5
    /// How long a dialog may wait for its PermissionRequest before the terminal shows (rule 2).
    public static let requestGrace: TimeInterval = 1.5
    @ObservationIgnored private var disagreeSince: Date?

    /// The dialog on screen and Claude's request tell the same story (fallback rule 2): a
    /// permission for a tool, a plan for ExitPlanMode, a question Claude asked.
    public var requestAgrees: Bool {
        guard let r = pendingRequest else { return false }
        switch screen.kind {
        case .permission: return !["AskUserQuestion", "ExitPlanMode"].contains(r.tool)
        case .plan: return r.tool == "ExitPlanMode"
        case .question, .questionReview: return r.tool == "AskUserQuestion" && questionIndex(screen) != nil
        default: return true
        }
    }

    /// A review card is showing: a verified dialog that agrees with the request.
    /// For the harness: the screen as if Claude's dialog had come up or gone (DL-130's proofs).
    func harnessScreenKind(_ kind: ChatScreen.Kind) { screen.kind = kind }

    /// A screen you opened from chat is up: a picker card, or a command's own screen in the terminal.
    public var ownScreenUp: Bool { pickerUp || (fallback?.command != nil && screen.kind == .unknown) }

    /// `/model` or `/effort` shows as a card in the composer's place (DL-143).
    public var pickerUp: Bool { screen.kind == .picker && screen.picker != nil && dialogsVerified }

    public var cardUp: Bool {
        [.permission, .plan, .question, .questionReview].contains(screen.kind) && dialogsVerified && requestAgrees
    }

    public init(key: String, mode: ChatViewMode) {
        self.key = key
        self.mode = mode
    }

    /// What the console pane shows for this session.
    public var showsChat: Bool { mode == .chat && fallback == nil }

    public func setVersion(_ v: String?) {
        cliVersion = v
        let t = ChatSignatures.table(for: v)
        signatures = t.table
        versionTrust = ChatSignatures.trust(for: v)
        reread()
    }

    /// Attaches the terminal whose screen this chat reads.
    public func attach(_ t: ChatTerminal) {
        guard terminal !== t else { return }
        terminal = t
        t.onOutput { [weak self] in self?.scheduleRead() }
        reread()
    }

    /// Starts reading the session's hooks and transcript (live sessions).
    public func follow(sessionId: String, cwd: String) {
        guard feed?.sessionId != sessionId else { return }
        feed?.stop()
        feed = ChatFeed(sessionId: sessionId, cwd: cwd, chat: self)
    }

    /// Earlier turns (Q-56c).
    public func loadEarlier() { feed?.loadEarlier() }

    /// The TUI repaints in bursts: read once it settles (the spike's 60 ms).
    func scheduleRead() {
        guard !readPending else { return }
        readPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            MainActor.assumeIsolated {
                self?.readPending = false
                self?.reread()
            }
        }
    }

    /// Reads the screen now.
    @discardableResult
    public func reread() -> ChatScreen {
        guard let t = terminal else { return screen }
        let s = ChatScreenReader.read(lines: t.screenLines(), cols: t.columns, table: signatures)
        apply(s)
        return s
    }

    /// A new screen state: fall back, come back, or close a reply the screen says ended.
    public func apply(_ s: ChatScreen) {
        let before = screen
        if s != before { screen = s }
        // An interrupted reply fires no hook: busy → idle ends it (F-105).
        if before.kind == .busy, s.kind == .idle {
            log.endStreaming(interrupted: s.interrupted)
            if s.interrupted { focusComposer += 1 }   // "What should Claude do instead?": the composer is ready
        }
        evaluateFallback()
    }

    /// The fallback rules (spike): unknown for longer than the grace period; a dialog on a CLI
    /// whose dialogs aren't verified; and, once the TUI is back at its prompt, coming back.
    func evaluateFallback() {
        let s = screen
        switch s.kind {
        case .unknown:
            if composing || sending { return }
            if unknownSince == nil {
                unknownSince = Date()
                unknownTimer?.invalidate()
                unknownTimer = Timer.scheduledTimer(withTimeInterval: Self.grace, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.evaluateFallback() }
                }
            } else if Date().timeIntervalSince(unknownSince!) >= Self.grace - 0.01 {
                fallBack(commandScreen() ?? .unknownScreen)
            }
        case .permission, .plan, .question, .questionReview:
            unknownSince = nil; unknownTimer?.invalidate()
            if !dialogsVerified {
                fallBack(versionTrust == .newer
                    ? .automatic("This dialog in Claude Code \(cliVersion ?? "") doesn’t read like the versions chat mode was checked with, so here’s the terminal. Chat comes back when it closes.")
                    : .automatic("Chat mode hasn’t been checked with this version of Claude Code’s dialogs (\(cliVersion ?? "unknown")), so here’s the terminal. Chat comes back when it closes."))
            } else if !requestAgrees {
                // The request comes by hook, a moment after the dialog draws: give it a second.
                if disagreeSince == nil {
                    disagreeSince = now
                    unknownTimer = Timer.scheduledTimer(withTimeInterval: Self.requestGrace, repeats: false) { [weak self] _ in
                        MainActor.assumeIsolated { self?.evaluateFallback() }
                    }
                } else if now.timeIntervalSince(disagreeSince!) >= Self.requestGrace - 0.01 {
                    fallBack(.automatic("Chat mode can’t match this dialog to what Claude asked, so here’s the terminal. Chat comes back when it closes."))
                }
            } else { disagreeSince = nil }
        case .idle, .busy:
            unknownSince = nil; disagreeSince = nil; unknownTimer?.invalidate()
            if fallback != nil { fallback = nil; onChange?() }
        case .picker:
            // `/model` and `/effort` as a card (DL-143), only on a CLI whose screens were checked.
            unknownSince = nil; disagreeSince = nil; unknownTimer?.invalidate()
            if !dialogsVerified {
                fallBack(.automatic("Chat mode hasn’t been checked with this version of Claude Code’s screens (\(cliVersion ?? "unknown")), so here’s the terminal. Chat comes back when it closes."))
            } else if fallback?.kind == .automatic { fallback = nil; onChange?() }
        case .starting:
            break
        }
    }

    /// The last command sent from chat, and when: a screen that comes up just after it is its own.
    @ObservationIgnored var lastCommand: (name: String, at: Date)?

    /// The named bar, when the unknown screen came from a command sent from chat moments ago; the
    /// generic sentence stays for screens chat didn't start (sign-in, folder trust …).
    func commandScreen() -> ChatFallback? {
        guard let c = lastCommand, Date().timeIntervalSince(c.at) < 20 else { return nil }
        return .command(c.name)
    }

    public func fallBack(_ f: ChatFallback) {
        guard mode == .chat, fallback != f else { return }
        fallback = f
        onChange?()
    }

    /// "Back to Chat": shows chat now. If the screen still can't be shown, the terminal returns
    /// after the grace period.
    public func backToChat() {
        fallback = nil
        unknownSince = nil
        evaluateFallback()
    }
}

/// Every session's chat, and the choices to remember.
@MainActor
@Observable
public final class ChatStore {
    public private(set) var sessions: [String: ChatSession] = [:]
    public var prefs: ChatPrefs
    @ObservationIgnored let persist: Bool

    public init(persist: Bool = true) {
        self.persist = persist
        prefs = persist ? ChatPrefs.load() : ChatPrefs()
    }

    /// A session's chat, made on first use in the mode it should open in.
    public func session(_ key: String) -> ChatSession {
        if let s = sessions[key] { return s }
        let s = ChatSession(key: key, mode: prefs.mode(for: key))
        sessions[key] = s
        return s
    }

    public func existing(_ key: String) -> ChatSession? { sessions[key] }

    /// The user's choice, kept for the session and as the default for new ones (DL-119 §5).
    public func setMode(_ mode: ChatViewMode, for key: String) {
        let s = session(key)
        s.mode = mode
        s.fallback = nil
        if mode == .chat { s.backToChat() }
        prefs.set(mode, for: key)
        if persist { prefs.save() }
    }

    public func setDefault(_ mode: ChatViewMode?) {
        prefs.fixedDefault = mode
        if persist { prefs.save() }
    }

    /// The process now hosts another session (`/clear`, `/resume`, F-29): the chat follows it.
    /// The new session keeps the mode it was in (F-174); its chat starts empty, as the TUI does.
    public func rekey(_ old: String, to new: String) {
        guard old != new else { return }
        if let m = sessions[old]?.mode ?? prefs.modes[old] {
            prefs.modes[new] = m
            if persist { prefs.save() }
        }
        guard let s = sessions.removeValue(forKey: old) else { return }
        s.feed?.stop()
        let moved = ChatSession(key: new, mode: s.mode)
        moved.launchId = s.launchId ?? old
        moved.composeDir = s.composeDir
        if let v = s.cliVersion { moved.setVersion(v) }
        if let t = s.terminal { moved.attach(t) }
        sessions[new] = moved
    }

    public func forget(_ key: String) { sessions.removeValue(forKey: key) }
}

/// The installed CLI's version, asked once per binary (`claude --version`: "2.1.291 (Claude Code)").
public enum ClaudeVersion {
    /// Answers by path; "" records a claude that gave none (failed, hung, or printed no version).
    nonisolated(unsafe) private static var cache: [String: String] = [:]
    private static let lock = NSLock()
    /// How long `claude --version` may take before it's ended and the version taken as unknown
    /// (C-34): a broken install, a first-run prompt or a slow home must never freeze Duo.
    nonisolated(unsafe) public static var timeout: TimeInterval = 2

    static func cached(_ path: String) -> String?? {
        lock.lock(); defer { lock.unlock() }
        return cache[path].map { $0.isEmpty ? nil : $0 }
    }

    /// The version now, for a session starting (it decides chat mode's hooks, F-111). Cached; asked
    /// at most once per binary, for at most `timeout` (Duo also warms the cache at launch with
    /// `warm`, off the main thread). Unknown means chat mode's hooks stay off: the safe default.
    public static func known(_ path: String) -> String? {
        if let hit = cached(path) { return hit }
        return ask(path)
    }

    /// Asks `claude --version` in the background at launch, so a session start finds it cached.
    public static func warm(_ path: String) {
        guard cached(path) == nil else { return }
        DispatchQueue.global(qos: .utility).async { _ = ask(path) }
    }

    /// Runs `claude --version`, ending it after `timeout`, and caches the answer (or its absence).
    @discardableResult
    static func ask(_ path: String) -> String? {
        let v = output(path, ["--version"])?.split(separator: " ").first.map(String.init).flatMap { ChatVersion($0) != nil ? $0 : nil }
        lock.lock(); cache[path] = v ?? ""; lock.unlock()
        return v
    }

    /// What `claude <args>` prints, or nil if it can't run or takes longer than `timeout` (it's ended).
    static func output(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        // Read as it comes: a long answer (`--help`) would otherwise fill the pipe and never exit.
        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }
        guard (try? p.run()) != nil else { return nil }
        nonisolated(unsafe) var data = Data()
        let read = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async { data = out.fileHandleForReading.readDataToEndOfFile(); read.signal() }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            if exited.wait(timeout: .now() + 0.5) == .timedOut { kill(p.processIdentifier, SIGKILL) }
            return nil
        }
        guard read.wait(timeout: .now() + 0.5) == .success else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    @MainActor public static func of(_ path: String, done: @escaping @MainActor (String?) -> Void) {
        if let hit = cached(path) { return done(hit) }
        nonisolated(unsafe) let done = done
        DispatchQueue.global(qos: .utility).async {
            let found = ask(path)
            DispatchQueue.main.async { MainActor.assumeIsolated { done(found) } }
        }
    }

    /// Forgets every answer (a different claude chosen in Settings, and the checks).
    public static func forget() { lock.lock(); cache = [:]; lock.unlock() }
}

/// The live terminal, read and typed into for chat mode.
@MainActor
final class LiveChatTerminal: ChatTerminal {
    weak var view: GuardedTerminalView?
    init(_ view: GuardedTerminalView) { self.view = view }

    func screenLines() -> [String] {
        guard let v = view else { return [] }
        let rows = v.terminalStateSnapshot().dimensions.rows
        return v.visibleRowsText(0..<rows)
    }
    var columns: Int { view?.terminalStateSnapshot().dimensions.cols ?? 80 }
    func sendKeys(_ text: String) { view?.send(txt: text) }
    func onOutput(_ f: @escaping @MainActor () -> Void) {
        view?.setProcessOutputHandler {
            DispatchQueue.main.async { MainActor.assumeIsolated { f() } }
        }
    }
}
