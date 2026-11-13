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
    /// Guards `cached` and the lookup: launch resolves off the main thread (F-564), a draw may ask meanwhile.
    private static let lock = NSLock()

    /// How long the login shell may take to say where `claude` is (F-564). A `.zprofile` or `.zshrc` that waits
    /// (on a terminal, a prompt, a keychain, a slow version manager) hung Duo's launch for good: it ran on the main
    /// thread with no limit. Past this the shell is ended and Duo carries on as if no `claude` were found.
    nonisolated(unsafe) public static var shellTimeout: TimeInterval = 3
    /// The places tried before the shell, and the shell. Settable by DuoChecks; the app keeps these.
    nonisolated(unsafe) public static var candidates: () -> [String] = {
        // The release launch matrix (F-580) launches a signed copy with `claude` missing from these places, through
        // LaunchServices, so the login shell runs: `DUO_CLAUDE_CANDIDATES` (colon-separated; empty for none) stands in
        // for them, in an isolated instance only, so the user's Duo always looks in the real places.
        if SupportFolder.isIsolated, let given = ProcessInfo.processInfo.environment["DUO_CLAUDE_CANDIDATES"] {
            return given.split(separator: ":").map(String.init)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
    }
    nonisolated(unsafe) public static var shell = "/bin/zsh"

    /// Look again next time (DB-3's Look Again).
    public static func forget() { lock.lock(); cached = nil; lock.unlock(); ClaudeVersion.forget(); RemoteControl.forget() }

    public static func resolve() -> String? {
        lock.lock(); defer { lock.unlock() }
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
        if let hit = candidates().first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return hit }
        // Fall back to the login shell's PATH (nvm, asdf, custom installs), within `shellTimeout` (F-564).
        let path = loginShellLookUp(timeout: shellTimeout) ?? ""
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    /// `command -v claude` in the user's login shell, or nil if it fails or doesn't answer in `timeout`. Never
    /// waits longer: no terminal on stdin, and the output is read as it comes, so a child the shell left
    /// holding the pipe can't block either.
    public static func loginShellLookUp(timeout: TimeInterval) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-lc", "command -v claude"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0), eof = DispatchSemaphore(value: 0)
        let buffer = LockedData()
        out.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; eof.signal() } else { buffer.append(d) }
        }
        p.terminationHandler = { _ in done.signal() }
        guard (try? p.run()) != nil else { out.fileHandleForReading.readabilityHandler = nil; return nil }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            out.fileHandleForReading.readabilityHandler = nil
            FileHandle.standardError.write(Data("claude: the login shell (\(shell) -lc) didn't answer in \(Int(timeout)) s; Duo carries on without it (F-564)\n".utf8))
            return nil
        }
        // The shell has ended: the rest of its output, unless a child it left still holds the pipe open.
        if eof.wait(timeout: .now() + 0.5) == .timedOut { out.fileHandleForReading.readabilityHandler = nil }
        return String(data: buffer.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Bytes appended from a pipe's handler thread.
final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    func append(_ d: Data) { lock.lock(); bytes.append(d); lock.unlock() }
    var data: Data { lock.lock(); defer { lock.unlock() }; return bytes }
}

/// What a terminal runs.
public enum TerminalCommand: Sendable, Equatable {
    /// A new Claude Code session with a Duo-minted id (DL-14), optionally seeded with a prompt
    /// as its first message.
    /// `remoteControl` names it for the Claude app (`--remote-control <name>`, DL-128).
    /// `name` is given with `-n`: a fixed name survives restarts (a director's, DL-200).
    case newClaude(sessionID: String, prompt: String?, remoteControl: String? = nil, name: String? = nil)
    /// Reopen a session by id. Never `-c` or the picker (DL-14). `prompt` is submitted as its next
    /// message: a director's message to a stopped worker (DL-199).
    case resumeClaude(sessionID: String, remoteControl: String? = nil, prompt: String? = nil)
    /// A new session with the same history: `--resume <from> --fork-session`, under a Duo-minted id.
    case forkClaude(from: String, sessionID: String)
    /// A `/fork` in Claude's background: `claude attach ‹short›` shows the job in a tab (DL-227). Closing the tab detaches;
    /// the fork keeps running. `sessionID` is the fork's id, which keys the tab and sets `DUO_SESSION_ID`.
    case attachClaude(short: String, sessionID: String)
    /// A plain shell (DL-8). Auto-promotion of `claude` typed in it comes later.
    case shell

    /// The id the process was started with: its `DUO_SESSION_ID`, whatever the session is now.
    public var launchId: String? {
        switch self {
        case .newClaude(let id, _, _, _), .resumeClaude(let id, _, _), .forkClaude(_, let id), .attachClaude(_, let id): id
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
        // Naming ~/.claude is not naming nothing to Claude: it then reads ~/.claude/.claude.json and starts on the first-run
        // theme screen, never at a prompt (F-646). The default folder is left to the default.
        if let dir = env["CLAUDE_CONFIG_DIR"], ClaudeStorage.isDefaultFolder(dir) { env.removeValue(forKey: "CLAUDE_CONFIG_DIR") }
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
    /// While chat shows, the terminal view is out of the layout: it is sized here to the pane chat fills, as the slot
    /// would size it (inset 12 × 8), so Claude draws at the width the terminal will show (Q-341, F-456). Only a view no
    /// slot on screen holds (two sizers resizing one terminal made Claude redraw by turns, F-208); not mid-slide (DL-129); and once
    /// the pane has settled, so a window being dragged resizes Claude once, not on every frame.
    public func holdHiddenSize(_ pane: CGSize) {
        heldPane = pane
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: Self.holdSettle, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyHeldSize() }
        }
    }

    /// How long the pane must keep a size before the hidden terminal takes it.
    public static let holdSettle: TimeInterval = 0.25
    private var heldPane: CGSize?
    private var holdTimer: Timer?

    func applyHeldSize() {
        guard let pane = heldPane, view.window == nil else { return }
        if PaneMotion.running > 0 { holdHiddenSize(pane); return }
        let f = CGRect(origin: .zero, size: pane).insetBy(dx: 12, dy: 8)
        guard f.width > 0, f.height > 0, view.frame.size != f.size else { return }
        view.frame = f
        hiddenResizes += 1
    }

    /// How many times the hidden view took a new size (the harness's `term-info`).
    public private(set) var hiddenResizes = 0

    public internal(set) var key: String
    public let command: TerminalCommand
    public let cwd: String
    public let view: GuardedTerminalView
    public private(set) var exited = false

    /// A terminal showing recorded text, with no process (the intro video's demo, VideoTargets).
    convenience init(key: String, screen: String) {
        self.init(key: key, command: .shell, cwd: NSTemporaryDirectory(), running: false)
        view.resize(cols: 98, rows: 52)   // the pane's size at the video's window, so no line wraps while it's fed
        view.feed(text: screen.replacingOccurrences(of: "\n", with: "\r\n"))
    }

    init(key: String, command: TerminalCommand, cwd: String, running: Bool = true) {
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
        // Mac editing keys and clean copies in Claude's prompt (DL-274).
        if case .shell = command {} else { view.runsClaude = true; view.installCopyCleaning() }
        if running { start() }
        // A steady block, no blink (DB-2): DECSCUSR 2, as a program would ask for it.
        view.feed(text: "\u{1b}[2 q")
    }

    /// The DB-2 palette of the scheme in force, or its Increase Contrast set when that accessibility setting is on.
    static func applyPalette(_ view: TerminalView) {
        let colors = DuoScheme.resolved(view.effectiveAppearance).terminal
        let set = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? colors.ansiIncreaseContrast : colors.ansi
        view.installColors(set.map { c in
            let s = c.usingColorSpace(.sRGB) ?? c
            return SwiftTerm.Color(red: UInt16(s.redComponent * 65535), green: UInt16(s.greenComponent * 65535), blue: UInt16(s.blueComponent * 65535))
        })
        view.caretColor = colors.cursor
        view.caretTextColor = colors.textUnderCursor
        view.selectedTextBackgroundColor = colors.selection
    }

    private func start() {
        try? FileManager.default.createDirectory(atPath: cwd, withIntermediateDirectories: true)
        switch command {
        case .newClaude(let id, let prompt, let remote, let name):
            guard let claude = ClaudeLocator.resolve() else { return showMissingClaude() }
            var args = ["--session-id", id] + (name.map { ["-n", $0] } ?? []) + Self.hookArgs(id) + RemoteControl.args(remote, claude: claude)
            if let prompt { args.append(prompt) }
            run(claude, args, environment: Self.environment(id))
        case .resumeClaude(let id, let remote, let prompt):
            guard let claude = ClaudeLocator.resolve() else { return showMissingClaude() }
            var args = ["--resume", id] + Self.hookArgs(id) + RemoteControl.args(remote, claude: claude)
            if let prompt { args += ["--", prompt] }   // `--`: a message starting with "-" is never a flag
            run(claude, args, environment: Self.environment(id))
        case .forkClaude(let from, let id):
            guard let claude = ClaudeLocator.resolve() else { return showMissingClaude() }
            run(claude, ["--resume", from, "--fork-session", "--session-id", id] + Self.hookArgs(id), environment: Self.environment(id))
        case .attachClaude(let short, let id):
            guard let claude = ClaudeLocator.resolve() else { return showMissingClaude() }
            run(claude, ["attach", short], environment: Self.environment(id))
        case .shell:
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            run(shell, ["-l"], argv0: "-" + (shell as NSString).lastPathComponent, environment: ChildEnvironment.make(sessionID: nil))
        }
    }

    /// Every terminal process starts here. Duo stays the responsible process for it (DL-190).
    private func run(_ program: String, _ args: [String], argv0: String? = nil, environment: [String]) {
        view.startProcess(executable: program, args: args, environment: environment, execName: argv0, currentDirectory: cwd)
    }

    /// Per-session hooks (F-23); none if the settings file can't be written.
    private static func hookArgs(_ id: String) -> [String] {
        // DUO_NO_EDIT_HOOK (checks only) leaves the edit hook out, as a managed setting that
        // disables hooks would: the primer and the merge must hold on their own (DL-78).
        let editHook = !Env.isSet("DUO_NO_EDIT_HOOK") ? ChildEnvironment.cliDirectory.map { $0 + "/duo2" } : nil
        // Chat mode's events, for a CLI that has them all (DL-118).
        let claude = ClaudeLocator.resolve(), version = claude.flatMap(ClaudeVersion.known)
        let chat = version.flatMap(ChatVersion.init).map { $0 >= ChatVersion.messageDisplay } ?? false
        let settings = (try? HookEvents.settingsFile(for: id, cli: editHook, chatEvents: chat)).map { ["--settings", $0.path] } ?? []
        // duo-signal (ENH-70 spike): only with DUO_SIGNAL=1, on a CLI with mods that validated it.
        return settings + ["--append-system-prompt", DuoAction.primer(sessionID: id, cli: ChildEnvironment.cliDirectory.map { $0 + "/duo2" })] + DuoSignal.launchArgs(id, claude: claude, cliVersion: version)
    }

    /// A Claude session's environment: duo-signal's file only when `hookArgs` passed the mod.
    private static func environment(_ id: String) -> [String] {
        ChildEnvironment.make(sessionID: id) + DuoSignal.environment(id).map { "\($0.key)=\($0.value)" }
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

/// The bytes Duo sends for the chords SwiftTerm doesn't (see `GuardedTerminalView.keyDown`).
public enum TerminalKeys {
    /// ⇧↩ sends ESC CR (what iTerm and Terminal send for a soft newline) only while the program has
    /// not asked for the kitty keyboard protocol; with it on, SwiftTerm sends Shift+Enter and Claude
    /// Code (2.1.288+) reads that itself. 2.1.219 doesn't ask, so ⇧↩ would otherwise send. ⌘↩ sends CR
    /// without the protocol (SwiftTerm's `interpretKeyEvents` drops it), so it sends as DL-241 has it. ⌘⌫ sends ^U,
    /// delete to the line start, in both modes: SwiftTerm sends nothing without the protocol (2.1.284 and later read
    /// its Super+Backspace report the same way, F-473). Claude's prompt keys are `PromptKeys` (DL-274).
    public static func bytes(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, enhanced: Bool) -> [UInt8]? {
        let mods = modifiers.intersection([.shift, .control, .option, .command])
        switch (keyCode, mods) {
        case (36, [.shift]), (76, [.shift]): return enhanced ? nil : [0x1b, 0x0d]
        case (36, [.command]), (76, [.command]): return enhanced ? nil : [0x0d]
        case (51, [.command]): return [0x15]
        default: return nil
        }
    }
}

/// SwiftTerm's view, with LR-14's floor: never shrink the terminal below 8 columns by 1 row,
/// whatever its pane does (collapse animations pass through zero width).
public final class GuardedTerminalView: LocalProcessTerminalView {
    /// A ⌘-clicked link: true when Duo opened it (ENH-343 3); set by the slot that shows the view.
    var onOpenLink: ((String) -> Bool)?
    static let minColumns: CGFloat = 8
    static let minRows: CGFloat = 1

    var minimumSize: NSSize {
        let f = font
        let cell = NSAttributedString(string: "W", attributes: [.font: f]).size()
        return NSSize(width: ceil(cell.width * Self.minColumns) + 4,
                      height: ceil((f.ascender - f.descender + f.leading) * Self.minRows) + 4)
    }

    /// The console sinks in dark (DL-224): the background and foreground are resolved again when
    /// the appearance changes, as a colour handed to the renderer is a snapshot of one appearance.
    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            nativeBackgroundColor = DuoNSColor.console
            nativeForegroundColor = DuoNSColor.consoleText
        }
        TerminalSession.applyPalette(self)   // the ANSI set is a snapshot too: a scheme has its own
        needsDisplay = true
    }

    /// Forces a repaint from the current buffer. SwiftTerm's renderer draws from a snapshot, so
    /// `needsDisplay` alone repaints the old frame; a selection change invalidates the snapshot
    /// without resizing the PTY (findings F-20). Used when a terminal is attached to a slot.
    /// For the harness's `term-info`: where the view sits, so a run can tell a terminal drawn in the pane on
    /// screen from one another slot holds (F-640).
    var holderInfo: String {
        var chain: [String] = [], v: NSView? = superview
        while let s = v, chain.count < 40 { chain.append(String(describing: type(of: s)).prefix(24) + "@" + String(UInt(bitPattern: ObjectIdentifier(s).hashValue) % 100000)); v = s.superview }
        let inWin = window.map { convert(bounds, to: nil).intersection($0.contentView?.frame ?? .zero) } ?? .zero
        let place = (superview as? TerminalSlot.SlotView)?.place ?? "none"
        return "place=\(place) frame=\(Int(frame.width))x\(Int(frame.height)) hidden=\(isHiddenOrHasHiddenAncestor) inWindow=\(Int(inWin.minX)),\(Int(inWin.minY)),\(Int(inWin.width))x\(Int(inWin.height)) chain=\(chain.joined(separator: ">"))"
    }

    func repaint() {
        selectAll()
        selectNone()
        needsDisplay = true
    }

    // MARK: Keys SwiftTerm leaves unsent (ENH-67, GitHub #4)

    /// ⇧↩ adds a line, ⌘↩ sends (DL-241) and ⌘⌫ deletes to the line start. Plain Return is never remapped (LR-16).
    /// SwiftTerm's `keyDown` isn't open to override, so a local monitor sees the key first, while
    /// this terminal is the window's first responder.
    private var keyMonitor: Any?

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        guard window != nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let (code, mods, win) = (event.keyCode, event.modifierFlags, event.window)
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.window === win, self.window?.firstResponder === self else { return false }
                // Seen here, before the menus: ⌘↑ (All Projects) and ⌘Z (Undo) are theirs everywhere else.
                if self.runsClaude, self.process?.running == true, let k = PromptKey.chord(keyCode: code, modifiers: mods) {
                    return self.promptKey(k)
                }
                guard let bytes = TerminalKeys.bytes(keyCode: code, modifiers: mods,
                                                     enhanced: !self.keyboardEnhancementFlags.isEmpty) else { return false }
                self.send(bytes)
                return true
            }
            return handled ? nil : event
        }
    }

    // MARK: Mac editing keys in Claude's prompt (DL-274)

    /// Set by the session: this terminal runs Claude Code, not a shell.
    public var runsClaude = false
    /// A ⌘↑ or ⌘↓ still stepping through a full box.
    private var promptJump: Task<Void, Never>?

    /// The box as drawn now, if the caret is in it and no question is up.
    public func promptBox() -> PromptBox? {
        let snap = terminalStateSnapshot()
        return PromptBox.find(rows: visibleRowsText(0..<snap.dimensions.rows), cursor: (snap.cursor.row, snap.cursor.col))
    }

    /// Whether the key was taken (nothing else sees it).
    public func promptKey(_ k: PromptKey) -> Bool {
        if promptJump != nil, k == .toStart || k == .toEnd { return true }   // one jump at a time
        let box = promptBox()
        guard let bytes = PromptKeys.bytes(k, box: box, enhanced: !keyboardEnhancementFlags.isEmpty) else { return false }
        if !bytes.isEmpty { send(bytes) }
        // A full box may hold more than it shows: go on a row at a time until Claude has nothing more that way.
        if let b = box, b.full, k == .toStart || k == .toEnd {
            let toStart = k == .toStart
            promptJump = Task { @MainActor [weak self] in
                await self?.stepThroughFullBox(toStart: toStart)
                self?.promptJump = nil
            }
        }
        return true
    }

    /// With the caret on the box's first (last) row: one ↑ (↓) at a time, read back, until `PromptKeys.next` says done.
    private func stepThroughFullBox(toStart: Bool) async {
        guard var before = await settledBox(from: nil) else { return }
        for _ in 0..<2000 {
            // Claude re-centres a scrolled box on the caret: back to its edge row first, then probe.
            let edge = toStart ? before.above : before.below
            if edge > 0 {
                send(Array(repeating: toStart ? PromptKeys.up : PromptKeys.down, count: edge).flatMap { $0 })
                guard let b = await settledBox(from: before) else { return }
                before = b
                continue
            }
            send(toStart ? PromptKeys.up : PromptKeys.down)
            let after = await settledBox(from: before)
            switch PromptKeys.next(toStart: toStart, before: before, after: after) {
            case .done(let keys), .history(let keys): send(keys); return
            case .stop: return
            case .more(let keys):
                if !keys.isEmpty { send(keys) }
                guard let b = await settledBox(from: after) else { return }
                before = b
            }
        }
    }

    /// The box once Claude has drawn the keys sent: it differs from `old`, or has held still for 250 ms.
    private func settledBox(from old: PromptBox?) async -> PromptBox? {
        var last = promptBox(), still = 0
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 15_000_000)
            let now = promptBox()
            if let o = old, let n = now, n != o, n == last { return n }   // changed, and drawn twice the same
            still = now == last ? still + 1 : 0
            last = now
            if still >= 16 { return now }
        }
        return last
    }

    // MARK: Copying from Claude's prompt (DL-274)

    /// Claude copies its own selections twice on a Mac: OSC 52 through the terminal and `pbcopy`, whichever lands last
    /// (F-504). Its text is screen text, so the clean text goes on the pasteboard, and again for a moment if the raw
    /// text arrives after it. `pasteboard` is a private one in DuoChecks.
    public var pasteboard = NSPasteboard.general
    private var copyCleaner: CopyCleaningDelegate?
    private var copyGeneration = 0

    /// Puts Duo between SwiftTerm and this view for OSC 52 (`clipboardCopy` isn't open to override).
    public func installCopyCleaning() {
        let d = CopyCleaningDelegate(base: self)
        copyCleaner = d
        terminalDelegate = d
    }

    /// The prompt text a copy holds, cleaned (`PromptCopy`), from the screen as it is now.
    func cleanedCopy(_ text: String) -> String {
        guard runsClaude else { return text }
        let snap = terminalStateSnapshot()
        return PromptCopy.clean(text, rows: visibleRowsText(0..<snap.dimensions.rows), cols: snap.dimensions.cols)
    }

    /// OSC 52 from the program.
    func programCopied(_ text: String) {
        copyGeneration &+= 1   // a newer copy retires every repair still waiting on an older one (F-568)
        let generation = copyGeneration
        let clean = cleanedCopy(text)
        put(clean)
        guard clean != text else { return }
        // `pbcopy` may land after the OSC 52: put the clean text back whenever the raw text shows up in the next 1.5 s.
        for ms in [60, 150, 300, 600, 1000, 1500] {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) { [weak self] in
                // At fire time, not just when armed: still this copy, still a Claude terminal, raw text back (F-568).
                guard let self, self.copyGeneration == generation, self.runsClaude,
                      self.pasteboard.string(forType: .string) == text else { return }
                self.put(clean)
            }
        }
    }

    private func put(_ s: String) {
        pasteboard.clearContents()
        pasteboard.setString(s, forType: .string)
    }

    /// Edit ▸ Copy on SwiftTerm's own selection (⇧-drag, Select All): cleaned the same way when it is the prompt's.
    public override func copy(_ sender: Any) {
        copyGeneration &+= 1
        guard runsClaude, let s = getSelection(), !s.isEmpty else { return super.copy(sender) }
        put(cleanedCopy(s))
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
    @Environment(AppModel.self) private var model
    let session: TerminalSession
    /// Whether this slot's pane is the one on screen. Both layouts stay in the window (RootView), so Home's column is
    /// still there, out of sight, under a project: its slot must not take Home's terminal from the console (F-640).
    var shown = true
    /// Named in the harness's `term-info`.
    var place = "console"

    func makeNSView(context: Context) -> SlotView { SlotView() }

    func updateNSView(_ slot: SlotView, context: Context) {
        slot.place = place
        slot.show(session.view, shown: shown)
        // Voice input's mic on Claude's input box (DL-261): a sibling above the terminal, never inside it.
        let key = session.key
        slot.mic.session = session
        slot.mic.voice = model.voice
        slot.mic.onClick = { [weak model] in model?.toggleVoice(.terminal(key)) }  // action: voice start
        let cwd = session.cwd
        session.view.onOpenLink = { [weak model] link in model?.openTerminalLink(link, cwd: cwd) ?? false }
    }

    final class SlotView: NSView {
        private weak var current: NSView?
        private(set) var shown = true
        var place = "console"
        let mic = TerminalMicView(frame: NSRect(origin: .zero, size: TerminalMicView.size))

        override var isFlipped: Bool { true }

        override init(frame: NSRect) {
            super.init(frame: frame)
            clipsToBounds = true   // a terminal held at its size while a pane slides (DL-129)
            NotificationCenter.default.addObserver(self, selector: #selector(paneMotionEnded(_:)), name: PaneMotion.endedNotification, object: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        /// A slide ended: in this slot's window (C-44), or with no window named.
        @objc private func paneMotionEnded(_ note: Notification) {
            guard note.object == nil || note.object as AnyObject? === window else { return }
            needsLayout = true
        }

        func show(_ view: NSView, shown: Bool = true, old: Bool = oldRule) {
            self.shown = shown
            guard Self.takes(holds: view.superview === self, had: view === current, shown: shown,
                             holder: (view.superview as? SlotView).map { (shown: $0.shown, elsewhere: $0.window != nil && $0.window !== window) }, old: old) else { return }
            // Only a view this slot still holds (C-43): one another slot (another window's) took stays where it is.
            if let current, current.superview === self { current.removeFromSuperview() }
            view.removeFromSuperview()
            addSubview(view)
            addSubview(mic, positioned: .above, relativeTo: view)
            current = view
            needsLayout = true
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, view.superview === self else { return }
                self.window?.makeFirstResponder(view)
                (view as? GuardedTerminalView)?.repaint()
            }
        }

        /// Whether a slot takes the terminal's view when SwiftUI updates it (F-640). One view, several slots: Home's
        /// column and the console both show Home's session, and each window has its own console (C-43).
        /// - A slot out of sight never takes the view. Whichever slot SwiftUI updates last must not win: both are
        ///   made in one pass when chat falls back, and a slot just made isn't in the window yet.
        /// - A slot on screen that had the view and lost it to a slot on screen in another window (`elsewhere`) leaves
        ///   it there (C-43). Lost to this window's other pane, it takes it back: only one of the two is on screen,
        ///   and a console slot about to be removed gets no last update to say it is out of sight.
        /// - Otherwise (a slot on screen, new to the view) it takes it, as before.
        /// `DUO_SLOT_RULE=old` is the rule before F-640 (a slot new to the view always takes it, and never takes it
        /// back), kept so `scripts/check-chat-fallback-slot-live.sh` can show the failure.
        nonisolated static func takes(holds: Bool, had: Bool, shown: Bool, holder: (shown: Bool, elsewhere: Bool)?, old: Bool = oldRule) -> Bool {
            if old { return !had }
            if holds || !shown { return false }
            if had, let holder, holder.shown, holder.elsewhere { return false }
            return true
        }
        nonisolated static let oldRule = ProcessInfo.processInfo.environment["DUO_SLOT_RULE"] == "old"

        override func layout() {
            super.layout()
            // The terminal fills the slot, inset like the targets' console body. GuardedTerminalView
            // enforces the 8×1 floor if the slot gets smaller (LR-14). While a pane slides (DL-129)
            // it keeps its size, clipped, and takes the new one when the slide ends.
            guard PaneMotion.running(in: window) == 0 || current?.frame.isEmpty != false else { return }
            // Only a terminal this slot still holds: one another slot took keeps that slot's size.
            // Sizing it from here too made two slots resize one terminal by turns, and each size
            // made Claude Code redraw (F-208).
            guard let current, current.superview === self else { return }
            current.frame = bounds.insetBy(dx: 12, dy: 8)
            // DL-264: a Claude terminal gives up 4 columns for a margin Duo keeps, where the mic sits beside the prompt row,
            // so nothing is drawn over Claude's TUI (study C keeps the same margin).
            if VoiceMicStyle.current.keepsMargin, let s = mic.session, s.isClaude || TerminalMicView.onShellForProofs {
                current.frame.size.width = max(0, current.frame.width - 4 * s.cellSize.width)
            }
        }
    }
}

/// The slots' rule replayed on real slot views, for DuoChecks (F-640): which slot holds a terminal's view after each
/// move, with SwiftUI's updates in either order. `old` is the rule before F-640.
@MainActor
public enum TerminalSlotProof {
    /// Home's session on Home's own page: chat falls back (the console's slot and Home's column's are made in one
    /// pass), then All projects (the console's slot is removed with no last update), then Home's page again.
    /// The holder after each: "console", "home", or "none" (in no slot, or in one out of the window).
    public static func homePage(homeFirst: Bool, old: Bool) -> [String] {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let view = NSView()
        let home = TerminalSlot.SlotView(); home.place = "home"
        window.contentView?.addSubview(home)
        var out: [String] = []
        func holder() -> String { (view.superview as? TerminalSlot.SlotView).flatMap { $0.window != nil ? $0.place : nil } ?? "none" }
        func enterPage() -> TerminalSlot.SlotView {
            let console = TerminalSlot.SlotView()   // updated before it is in the window, as SwiftUI does
            if homeFirst { home.show(view, shown: false, old: old); console.show(view, shown: true, old: old) }
            else { console.show(view, shown: true, old: old); home.show(view, shown: false, old: old) }
            window.contentView?.addSubview(console)
            return console
        }
        let first = enterPage(); out.append(holder())
        if homeFirst { home.show(view, shown: true, old: old); first.removeFromSuperview() }
        else { first.removeFromSuperview(); home.show(view, shown: true, old: old) }
        out.append(holder())
        _ = enterPage(); out.append(holder())
        return out
    }

    /// Two windows' consoles on one session (C-43): the second takes the view, and the first, updated again, leaves it there.
    public static func twoWindows(old: Bool) -> Bool {
        let make = { () -> (NSWindow, TerminalSlot.SlotView) in
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
            w.isReleasedWhenClosed = false
            let s = TerminalSlot.SlotView(); w.contentView?.addSubview(s)
            return (w, s)
        }
        let (a, b) = (make(), make()), view = NSView()
        a.1.show(view, old: old); b.1.show(view, old: old); a.1.show(view, old: old)
        return view.superview === b.1
    }
}

/// Stands between SwiftTerm and a Claude terminal so Duo sees the program's OSC 52 copies (DL-274); every other call
/// goes on to the view, which is its own delegate otherwise.
@MainActor
final class CopyCleaningDelegate: TerminalViewDelegate {
    unowned let base: GuardedTerminalView
    init(base: GuardedTerminalView) { self.base = base }

    func clipboardCopy(source: TerminalView, content: Data) {
        guard let text = String(data: content, encoding: .utf8) else { return base.clipboardCopy(source: source, content: content) }
        base.programCopied(text)
    }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { base.sizeChanged(source: source, newCols: newCols, newRows: newRows) }
    func setTerminalTitle(source: TerminalView, title: String) { base.setTerminalTitle(source: source, title: title) }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) { base.hostCurrentDirectoryUpdate(source: source, directory: directory) }
    func send(source: TerminalView, data: ArraySlice<UInt8>) { base.send(source: source, data: data) }
    func scrolled(source: TerminalView, position: Double) { base.scrolled(source: source, position: position) }
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        // ⌘-click goes through Duo's own link rule (ENH-343 3), not the Mac's default app.
        if base.onOpenLink?(link) == true { return }
        base.requestOpenLink(source: source, link: link, params: params)
    }
    func bell(source: TerminalView) { base.bell(source: source) }
    func clipboardRead(source: TerminalView) -> Data? { base.clipboardRead(source: source) }
    func kittyClipboardCapabilities(source: TerminalView) -> KittyClipboardCapabilities { base.kittyClipboardCapabilities(source: source) }
    func kittyClipboardAvailableMimeTypes(source: TerminalView, location: KittyClipboardLocation) -> [String]? {
        base.kittyClipboardAvailableMimeTypes(source: source, location: location)
    }
    func kittyClipboardRead(source: TerminalView, location: KittyClipboardLocation, mimeType: String) -> KittyClipboardReadResult? {
        base.kittyClipboardRead(source: source, location: location, mimeType: mimeType)
    }
    func kittyClipboardWrite(source: TerminalView, location: KittyClipboardLocation, content: KittyClipboardWriteContent) -> KittyClipboardWriteResult {
        base.kittyClipboardWrite(source: source, location: location, content: content)
    }
    func kittyClipboardRequestPermission(source: TerminalView, request: KittyClipboardPermissionRequest) -> KittyClipboardPermissionResult {
        base.kittyClipboardRequestPermission(source: source, request: request)
    }
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) { base.iTermContent(source: source, content: content) }
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) { base.rangeChanged(source: source, startY: startY, endY: endY) }
}
