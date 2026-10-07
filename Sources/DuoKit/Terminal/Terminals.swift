import AppKit
import DuoControl
import SwiftTerm
import SwiftUI

// Terminals (Phase D; stack #3–#4; handoff §3.2, §3.3). Each session owns one terminal view and
// one process for its whole life. Views are re-parented between panes, never recreated, so
// hiding, collapsing or zooming never kills a session (LR-13).

/// Finds the user's `claude` without trusting the GUI PATH (LR-19).
public enum ClaudeLocator {
    /// The last answer: the console asks on every draw, and the PATH lookup starts a login shell.
    nonisolated(unsafe) private static var cached: String??

    /// Look again next time (DB-3's Look Again).
    public static func forget() { cached = nil; ClaudeVersion.forget(); RemoteControl.forget() }

    public static func resolve() -> String? {
        if let c = cached { return c }
        // One the user chose in Settings wins while it runs (LR-19, S3-1).
        let found = chosenRunnable ?? lookUp()
        cached = .some(found)
        return found
    }

    /// The `claude` chosen in Settings, if it's a program Duo can run.
    public static var chosenRunnable: String? {
        guard let p = DuoState.load().claudePath, FileManager.default.isExecutableFile(atPath: p) else { return nil }
        return p
    }

    /// The one Duo finds by itself, ignoring a choice (Settings' "Use Found One").
    public static func found() -> String? { lookUp() }

    private static func lookUp() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude", "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
        ]
        if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return hit }
        // Fall back to the login shell's PATH (nvm, asdf, custom installs).
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v claude"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let path = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }
}

/// What a terminal runs.
public enum TerminalCommand: Sendable, Equatable {
    /// A new Claude Code session with a Duo-minted id (DL-14), optionally seeded with a prompt
    /// as its first message.
    /// `remoteControl` names it for the Claude app (`--remote-control <name>`, DL-128).
    case newClaude(sessionID: String, prompt: String?, remoteControl: String? = nil)
    /// Reopen a session by id. Never `-c` or the picker (DL-14).
    case resumeClaude(sessionID: String, remoteControl: String? = nil)
    /// A new session with the same history: `--resume <from> --fork-session`, under a Duo-minted id.
    case forkClaude(from: String, sessionID: String)
    /// A plain shell (DL-8). Auto-promotion of `claude` typed in it comes later.
    case shell

    /// The id the process was started with: its `DUO_SESSION_ID`, whatever the session is now.
    public var launchId: String? {
        switch self {
        case .newClaude(let id, _, _), .resumeClaude(let id, _), .forkClaude(_, let id): id
        case .shell: nil
        }
    }
}

/// The environment for every child process.
public enum ChildEnvironment {
    /// Set once at launch, before any terminal starts.
    nonisolated(unsafe) public static var control: ControlEndpoint?
    /// The folder holding `duo2` (`Duo.app/Contents/Helpers`).
    nonisolated(unsafe) public static var cliDirectory: String?

    /// Drops what a parent Claude Code session leaks into Duo's environment when Duo was launched
    /// from one (CLAUDECODE, CLAUDE_CODE_SESSION_ID, messaging socket and token, …; findings
    /// F-17): a child inheriting CLAUDE_CODE_SESSION_ID would write into the parent's session.
    /// CLAUDE_CONFIG_DIR is the user's and is kept.
    /// `base` is Duo's own environment; checks pass a fixed one.
    public static func make(sessionID: String?, base: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        var env = base.filter { k, _ in
            !(k == "CLAUDECODE" || (k.hasPrefix("CLAUDE_") && k != "CLAUDE_CONFIG_DIR"))
        }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env.removeValue(forKey: "TERM_PROGRAM")
        // The user's Duo doesn't hand its real support folder down (open-duo.sh sets it): a session
        // that launches a test Duo would otherwise pass it on, and that Duo would count as the
        // user's own, take the shared socket and remove it on quit (C-28, F-113). Without it, a
        // scripted launch gets a temporary folder (F-89); an isolated instance keeps passing its own.
        if !SupportFolder.isIsolated { env.removeValue(forKey: SupportFolder.variable) }
        if let sessionID { env["DUO_SESSION_ID"] = sessionID }  // LR-20
        // Chat mode's composer is Claude's external editor (Ctrl+G, F-104, F-112): `duo2 compose`
        // hands over the composer's text, and opens the user's own editor for anything else.
        if sessionID != nil, let bin = cliDirectory, let editor = ChatComposer.editorCommand(cli: bin + "/duo2") {
            if let e = env["EDITOR"] { env[ChatCompose.userEditor] = e }
            if let v = env["VISUAL"] { env[ChatCompose.userVisual] = v }
            env["EDITOR"] = editor
            env["VISUAL"] = editor
            env[ChatCompose.dirVariable] = ChatComposer.dir.path
        }
        // duo2 and how to reach the app (DL-15): on PATH and in the environment, never installed
        // globally (LR-55).
        if let c = control {
            env[ControlEndpoint.socketVariable] = c.socket
            env[ControlEndpoint.tokenVariable] = c.token
        }
        if let bin = cliDirectory { env["PATH"] = bin + ":" + (env["PATH"] ?? "/usr/bin:/bin") }
        return env.map { "\($0.key)=\($0.value)" }
    }
}

/// One terminal: a view and the process it hosts.
@MainActor
public final class TerminalSession {
    public internal(set) var key: String
    public let command: TerminalCommand
    public let cwd: String
    public let view: GuardedTerminalView
    public private(set) var exited = false

    init(key: String, command: TerminalCommand, cwd: String) {
        self.key = key
        self.command = command
        self.cwd = cwd
        self.view = GuardedTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        view.font = .monospacedSystemFont(ofSize: DuoTextStyle.mono.spec.size, weight: .regular)
        // Terminal background and foreground from the tokens (handoff §4.1); the palette, cursor
        // and selection from surfaces-handoff DB-2.
        view.nativeBackgroundColor = DuoNSColor.console
        view.nativeForegroundColor = DuoNSColor.consoleText
        Self.applyPalette(view)
        view.registerForDraggedTypes([.fileURL])  // files dropped in type their paths (DL-117)
        view.processDelegate = ProcessWatcher.shared
        ProcessWatcher.shared.sessions[ObjectIdentifier(view)] = self
        start()
        // A steady block, no blink (DB-2): DECSCUSR 2, as a program would ask for it.
        view.feed(text: "\u{1b}[2 q")
    }

    /// The DB-2 palette, or its Increase Contrast set when that accessibility setting is on.
    static func applyPalette(_ view: TerminalView) {
        let set = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? DuoTerminalPalette.ansiIncreaseContrast : DuoTerminalPalette.ansi
        view.installColors(set.map { c in
            let s = c.usingColorSpace(.sRGB) ?? c
            return SwiftTerm.Color(red: UInt16(s.redComponent * 65535), green: UInt16(s.greenComponent * 65535), blue: UInt16(s.blueComponent * 65535))
        })
        view.caretColor = DuoTerminalPalette.cursor
        view.caretTextColor = DuoTerminalPalette.textUnderCursor
        view.selectedTextBackgroundColor = DuoTerminalPalette.selection
    }

    private func start() {
        try? FileManager.default.createDirectory(atPath: cwd, withIntermediateDirectories: true)
        switch command {
        case .newClaude(let id, let prompt, let remote):
            guard let claude = ClaudeLocator.resolve() else { return showMissingClaude() }
            var args = ["--session-id", id] + Self.hookArgs(id) + RemoteControl.args(remote, claude: claude)
            if let prompt { args.append(prompt) }
            view.startProcess(executable: claude, args: args, environment: ChildEnvironment.make(sessionID: id),
                              execName: nil, currentDirectory: cwd)
        case .resumeClaude(let id, let remote):
            guard let claude = ClaudeLocator.resolve() else { return showMissingClaude() }
            view.startProcess(executable: claude, args: ["--resume", id] + Self.hookArgs(id) + RemoteControl.args(remote, claude: claude), environment: ChildEnvironment.make(sessionID: id),
                              execName: nil, currentDirectory: cwd)
        case .forkClaude(let from, let id):
            guard let claude = ClaudeLocator.resolve() else { return showMissingClaude() }
            view.startProcess(executable: claude, args: ["--resume", from, "--fork-session", "--session-id", id] + Self.hookArgs(id),
                              environment: ChildEnvironment.make(sessionID: id), execName: nil, currentDirectory: cwd)
        case .shell:
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            view.startProcess(executable: shell, args: ["-l"], environment: ChildEnvironment.make(sessionID: nil),
                              execName: "-" + (shell as NSString).lastPathComponent, currentDirectory: cwd)
        }
    }

    /// Per-session hooks (F-23); none if the settings file can't be written.
    private static func hookArgs(_ id: String) -> [String] {
        // DUO_NO_EDIT_HOOK (checks only) leaves the edit hook out, as a managed setting that
        // disables hooks would: the primer and the merge must hold on their own (DL-78).
        let editHook = !Env.isSet("DUO_NO_EDIT_HOOK") ? ChildEnvironment.cliDirectory.map { $0 + "/duo2" } : nil
        // Chat mode's events, for a CLI that has them all (DL-118).
        let chat = ClaudeLocator.resolve().flatMap(ClaudeVersion.known).flatMap(ChatVersion.init).map { $0 >= ChatVersion.messageDisplay } ?? false
        let settings = (try? HookEvents.settingsFile(for: id, cli: editHook, chatEvents: chat)).map { ["--settings", $0.path] } ?? []
        return settings + ["--append-system-prompt", DuoAction.primer()]
    }

    /// The console says so in Duo's own type (DB-3) instead of printing into the terminal.
    private func showMissingClaude() {
        exited = true
        missingClaude = true
    }

    /// Claude Code wasn't found when this terminal started.
    public private(set) var missingClaude = false
    /// When the process ended by itself, and its exit status (DB-3's bar). Not set by `terminate()`.
    public private(set) var ended: (at: Date, status: Int32?)?
    /// Told when the process ends by itself, so the console can show its bar.
    var onEnded: (@MainActor (TerminalSession) -> Void)?
    /// Told when the process has ended and been reaped, however it ended (the store lets a closed
    /// terminal go then, F-126).
    var onGone: (@MainActor (TerminalSession) -> Void)?

    /// Whether the process is still there: running, or ended and not yet reaped.
    var hasProcess: Bool { view.process?.running == true }

    fileprivate func processEnded(_ status: Int32?) {
        onGone?(self)
        guard !exited else { return }
        exited = true
        ended = (Date(), status)
        onEnded?(self)
    }

    /// Ends the process. Only on explicit close (⌘W) or quit; never on hide (LR-13).
    public func terminate() {
        view.process?.terminate()
        exited = true
    }
}

/// Hears SwiftTerm's process events for every terminal (a weak delegate, so one shared owner).
@MainActor
final class ProcessWatcher: NSObject, LocalProcessTerminalViewDelegate {
    static let shared = ProcessWatcher()
    var sessions: [ObjectIdentifier: TerminalSession] = [:]

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        let id = ObjectIdentifier(source)
        DispatchQueue.main.async { MainActor.assumeIsolated { self.sessions[id]?.processEnded(exitCode) } }
    }
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}

/// SwiftTerm's view, with LR-14's floor: never shrink the terminal below 8 columns by 1 row,
/// whatever its pane does (collapse animations pass through zero width).
public final class GuardedTerminalView: LocalProcessTerminalView {
    static let minColumns: CGFloat = 8
    static let minRows: CGFloat = 1

    var minimumSize: NSSize {
        let f = font
        let cell = NSAttributedString(string: "W", attributes: [.font: f]).size()
        return NSSize(width: ceil(cell.width * Self.minColumns) + 4,
                      height: ceil((f.ascender - f.descender + f.leading) * Self.minRows) + 4)
    }

    /// Forces a repaint from the current buffer. SwiftTerm's renderer draws from a snapshot, so
    /// `needsDisplay` alone repaints the old frame; a selection change invalidates the snapshot
    /// without resizing the PTY (findings F-20). Used when a terminal is attached to a slot.
    func repaint() {
        selectAll()
        selectNone()
        needsDisplay = true
    }

    // MARK: Files dropped in (DL-117)

    /// Dropped files and folders type their paths at the cursor, as Terminal.app does: absolute,
    /// shell-escaped, space-separated, a trailing space, never a Return. From Finder or Duo's tree.
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { dropOperation(sender) }
    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { dropOperation(sender) }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = Self.fileURLs(sender.draggingPasteboard)
        guard !urls.isEmpty, process?.running == true else { return false }
        insertPaths(urls)
        window?.makeFirstResponder(self)
        return true
    }

    private func dropOperation(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.fileURLs(sender.draggingPasteboard).isEmpty || process?.running != true ? [] : .copy
    }

    static func fileURLs(_ pb: NSPasteboard) -> [URL] {
        (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    /// Types the paths in. Bracketed when the program asked for it (zsh, Claude Code), so it reads
    /// as a paste: Claude Code takes a dropped image path as the image.
    func insertPaths(_ urls: [URL]) {
        let text = FileDrop.terminalText(urls)
        send(txt: terminalStateSnapshot().bracketedPasteMode ? "\u{1b}[200~" + text + "\u{1b}[201~" : text)
    }

    public override func setFrameSize(_ newSize: NSSize) {
        let m = minimumSize
        super.setFrameSize(NSSize(width: max(newSize.width, m.width), height: max(newSize.height, m.height)))
    }
}

/// Owns every terminal for the window. Keyed by session (`project/session-name` in fixture mode,
/// the session id once state is live).
@MainActor
public final class TerminalStore {
    private var sessions: [String: TerminalSession] = [:]

    public init() {
        // Increase Contrast switched on or off: every open terminal takes the matching palette (DB-2).
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.all.forEach { TerminalSession.applyPalette($0.view) } }
        }
    }

    /// Closed terminals whose process hasn't ended yet. Each is kept, and its terminal still read,
    /// until it has: SwiftTerm stops reading a terminal it lets go of, and a Claude that exits with
    /// output nobody reads waits in the kernel (state E) for good, never reaped (C-30, F-126).
    private var closing: [ObjectIdentifier: TerminalSession] = [:]
    /// How long a closed process has to end after SIGTERM before it gets SIGKILL.
    nonisolated(unsafe) public static var killAfter: TimeInterval = 3

    public func session(_ key: String, command: @autoclosure () -> TerminalCommand, cwd: @autoclosure () -> String) -> TerminalSession {
        if let s = sessions[key] { return s }
        let s = TerminalSession(key: key, command: command(), cwd: cwd())
        s.onEnded = { [weak self] t in self?.onEnded?(t) }
        sessions[key] = s
        return s
    }

    public func existing(_ key: String) -> TerminalSession? { sessions[key] }

    /// Any terminal's process ended by itself (DB-3).
    public var onEnded: (@MainActor (TerminalSession) -> Void)?

    /// Forgets an ended terminal without ending anything, so the next open starts it afresh.
    public func forget(_ key: String) {
        if let s = sessions.removeValue(forKey: key) { release(s, ending: false) }
    }

    /// Ends one session's process and forgets its terminal (explicit close only, LR-13).
    public func close(_ key: String) {
        if let s = sessions.removeValue(forKey: key) { release(s, ending: true) }
    }

    /// Lets a terminal go once its process has ended and been reaped, never before (F-126).
    private func release(_ s: TerminalSession, ending: Bool) {
        let id = ObjectIdentifier(s.view)
        if ending { s.terminate() }
        guard s.hasProcess else { ProcessWatcher.shared.sessions[id] = nil; return }
        closing[id] = s
        s.onGone = { [weak self] t in
            self?.closing[ObjectIdentifier(t.view)] = nil
            ProcessWatcher.shared.sessions[ObjectIdentifier(t.view)] = nil
        }
        guard ending else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.killAfter) { [weak self] in
            MainActor.assumeIsolated {
                guard self?.closing[id] != nil, let pid = s.view.process?.shellPid, pid > 0 else { return }
                kill(pid, SIGKILL)
            }
        }
    }

    /// Closed terminals still waiting for their process to end.
    public var closingCount: Int { closing.count }
    /// Their processes: still Duo's while they end, never "running elsewhere".
    public var closingPids: [Int32] { closing.values.compactMap { $0.view.process?.shellPid }.filter { $0 > 0 } }

    public var all: [TerminalSession] { Array(sessions.values) }

    public func terminateAll() { sessions.values.forEach { $0.terminate() } }

    /// The process now hosts another session (`/clear`, `/resume` in the TUI): same terminal,
    /// new key (F-29).
    public func rekey(_ old: String, to new: String) {
        guard old != new, let s = sessions.removeValue(forKey: old) else { return }
        // A terminal already under the new key is closed properly, not dropped (F-126).
        if let displaced = sessions.removeValue(forKey: new) { release(displaced, ending: true) }
        s.key = new
        sessions[new] = s
    }
}

/// Shows one session's terminal in a pane. The same view moves between slots (Home pane,
/// console, later the peek), so it is re-parented, not recreated.
struct TerminalSlot: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> SlotView { SlotView() }

    func updateNSView(_ slot: SlotView, context: Context) {
        slot.show(session.view)
    }

    final class SlotView: NSView {
        private weak var current: NSView?

        override var isFlipped: Bool { true }

        override init(frame: NSRect) {
            super.init(frame: frame)
            clipsToBounds = true   // a terminal held at its size while a pane slides (DL-129)
            NotificationCenter.default.addObserver(self, selector: #selector(paneMotionEnded), name: PaneMotion.endedNotification, object: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        @objc private func paneMotionEnded() { needsLayout = true }

        func show(_ view: NSView) {
            guard view !== current else { return }
            current?.removeFromSuperview()
            view.removeFromSuperview()
            addSubview(view)
            current = view
            needsLayout = true
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, view.superview === self else { return }
                self.window?.makeFirstResponder(view)
                (view as? GuardedTerminalView)?.repaint()
            }
        }

        override func layout() {
            super.layout()
            // The terminal fills the slot, inset like the targets' console body. GuardedTerminalView
            // enforces the 8×1 floor if the slot gets smaller (LR-14). While a pane slides (DL-129)
            // it keeps its size, clipped, and takes the new one when the slide ends.
            guard PaneMotion.running == 0 || current?.frame.isEmpty != false else { return }
            current?.frame = bounds.insetBy(dx: 12, dy: 8)
        }
    }
}
