import AppKit
import DuoControl
import SwiftTerm
import SwiftUI

// Terminals (Phase D; stack #3–#4; handoff §3.2, §3.3). Each session owns one terminal view and
// one process for its whole life. Views are re-parented between panes, never recreated, so
// hiding, collapsing or zooming never kills a session (LR-13).

/// Finds the user's `claude` without trusting the GUI PATH (LR-19).
public enum ClaudeLocator {
    public static func resolve() -> String? {
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
    case newClaude(sessionID: String, prompt: String?)
    /// Reopen a session by id. Never `-c` or the picker (DL-14).
    case resumeClaude(sessionID: String)
    /// A plain shell (DL-8). Auto-promotion of `claude` typed in it comes later.
    case shell
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
    public static func make(sessionID: String?) -> [String] {
        var env = ProcessInfo.processInfo.environment.filter { k, _ in
            !(k == "CLAUDECODE" || (k.hasPrefix("CLAUDE_") && k != "CLAUDE_CONFIG_DIR"))
        }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env.removeValue(forKey: "TERM_PROGRAM")
        if let sessionID { env["DUO_SESSION_ID"] = sessionID }  // LR-20
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
        // Terminal background and foreground from the tokens (handoff §4.1). The ANSI palette is
        // SwiftTerm's default until one is designed (handoff §13).
        view.nativeBackgroundColor = DuoNSColor.console
        view.nativeForegroundColor = DuoNSColor.consoleText
        start()
    }

    private func start() {
        try? FileManager.default.createDirectory(atPath: cwd, withIntermediateDirectories: true)
        switch command {
        case .newClaude(let id, let prompt):
            guard let claude = ClaudeLocator.resolve() else { return showMissingClaude() }
            var args = ["--session-id", id] + Self.hookArgs(id)
            if let prompt { args.append(prompt) }
            view.startProcess(executable: claude, args: args, environment: ChildEnvironment.make(sessionID: id),
                              execName: nil, currentDirectory: cwd)
        case .resumeClaude(let id):
            guard let claude = ClaudeLocator.resolve() else { return showMissingClaude() }
            view.startProcess(executable: claude, args: ["--resume", id] + Self.hookArgs(id), environment: ChildEnvironment.make(sessionID: id),
                              execName: nil, currentDirectory: cwd)
        case .shell:
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            view.startProcess(executable: shell, args: ["-l"], environment: ChildEnvironment.make(sessionID: nil),
                              execName: "-" + (shell as NSString).lastPathComponent, currentDirectory: cwd)
        }
    }

    /// Per-session hooks (F-23); none if the settings file can't be written.
    private static func hookArgs(_ id: String) -> [String] {
        let settings = (try? HookEvents.settingsFile(for: id)).map { ["--settings", $0.path] } ?? []
        return settings + ["--append-system-prompt", ControlCommand.sessionGuidance()]
    }

    private func showMissingClaude() {
        exited = true
        view.feed(text: "Claude Code isn't installed, or Duo couldn't find it.\r\nInstall it, then start a new session.\r\n")
    }

    /// Ends the process. Only on explicit close (⌘W) or quit; never on hide (LR-13).
    public func terminate() {
        view.process?.terminate()
        exited = true
    }
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

    public init() {}

    public func session(_ key: String, command: @autoclosure () -> TerminalCommand, cwd: @autoclosure () -> String) -> TerminalSession {
        if let s = sessions[key] { return s }
        let s = TerminalSession(key: key, command: command(), cwd: cwd())
        sessions[key] = s
        return s
    }

    public func existing(_ key: String) -> TerminalSession? { sessions[key] }
    public var all: [TerminalSession] { Array(sessions.values) }

    public func terminateAll() { sessions.values.forEach { $0.terminate() } }

    /// The process now hosts another session (`/clear`, `/resume` in the TUI): same terminal,
    /// new key (F-29).
    public func rekey(_ old: String, to new: String) {
        guard old != new, let s = sessions.removeValue(forKey: old) else { return }
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
            // enforces the 8×1 floor if the slot gets smaller (LR-14).
            current?.frame = bounds.insetBy(dx: 12, dy: 8)
        }
    }
}
