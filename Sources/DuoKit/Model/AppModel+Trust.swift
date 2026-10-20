import Foundation
import DuoControl

/// What the bar says about a session's blocked `/fork` (DL-229, trust-notice-handoff).
public struct TrustNotice: Equatable {
    public enum Phase: Equatable {
        /// "Claude Code doesn't trust ‹folder› yet, so /fork couldn't start." with Trust This Folder…
        case offer
        /// Not a folder Duo offers to trust (Q-232's stand-in): OK only.
        case runClaude
        /// Written: "Claude Code now trusts ‹folder›." with Fork Again.
        case trusted
        /// "Couldn't change Claude Code's settings: ‹why›." with Try Again.
        case failed(String)
    }
    public var path: String
    public var forkLine: String?
    public var phase: Phase
    /// Not Now: hidden for this session until the line leaves the screen and comes back. In memory only.
    public var dismissed = false
    /// The real folder of the session, for the "top folder" line of the sheet.
    public var sessionFolder: String
    /// Trust This Folder… or Try Again is on the bar.
    public var canAsk: Bool { switch phase { case .offer, .failed: true; default: false } }
    public var folder: String { (path as NSString).lastPathComponent }

    public init(path: String, forkLine: String?, phase: Phase, sessionFolder: String) {
        self.path = path; self.forkLine = forkLine; self.phase = phase; self.sessionFolder = sessionFolder
    }
}

extension AppModel {
    /// The bar to draw for a tab, or nil.
    public func trustNotice(_ key: String) -> TrustNotice? {
        guard let n = trustNotices[key], !n.dismissed else { return nil }
        return n
    }

    /// Reads every live terminal's screen for Claude Code's "Workspace not trusted" line after a `/fork`. Called on the
    /// refresh tick; cheap when nothing is on screen.
    func scanTrustNotices() {
        guard terminalsMode == .live else { return }
        let file = ClaudeTrust.configFile()
        for t in terminals.all where t.ended == nil && !t.exited && t.command != .shell {
            let term = LiveChatTerminal(t.view)
            let read = TrustLine.read(lines: term.screenLines(), cols: term.columns)
            applyTrustRead(key: t.key, read: read, sessionFolder: t.cwd) { ClaudeTrust.entries(file: file) }
        }
        for k in trustNotices.keys where terminals.existing(k) == nil { trustNotices[k] = nil }
    }

    /// One screen read for one session (also the entry for the checks and fixtures).
    public func applyTrustRead(key: String, read: TrustLine.Read?, sessionFolder: String, entries: () -> [String: Bool?]?) {
        guard let read else {
            // The line scrolled away: a hidden bar is forgotten, so the next such line brings it back.
            if trustNotices[key]?.dismissed == true { trustNotices[key] = nil }
            return
        }
        let path = ClaudeTrust.realPath(read.path)
        if var n = trustNotices[key], n.path == path {
            // Trusted some other way (Claude's own prompt, or another Duo): the bar goes by itself.
            if n.phase == .offer || n.phase == .runClaude, let e = entries(), ClaudeTrust.isTrusted(path, in: e) { trustNotices[key] = nil; return }
            if let f = read.forkLine, f != n.forkLine { n.forkLine = f; trustNotices[key] = n }
            return
        }
        guard let e = entries() else { return }
        let folder = ClaudeTrust.realPath(sessionFolder)
        switch TrustRule.offer(linePath: path, sessionFolder: folder, top: ClaudeTrust.repositoryTop(of: folder), entries: e) {
        case .trusted: trustNotices[key] = nil
        case .trust(let p): trustNotices[key] = TrustNotice(path: p, forkLine: read.forkLine, phase: .offer, sessionFolder: folder)
        case .runClaude(let p): trustNotices[key] = TrustNotice(path: p, forkLine: read.forkLine, phase: .runClaude, sessionFolder: folder)
        }
    }

    /// Not Now.
    public func dismissTrustNotice(_ key: String) { trustNotices[key]?.dismissed = true }

    /// OK on the after-state or the OK-only bar: the bar goes.
    public func closeTrustNotice(_ key: String) { trustNotices[key] = nil }

    /// "Trust This Folder…" and Try Again: Duo's sheet, always (never a system alert; no setting skips it). `source` is
    /// "you" or "duo2", for the log. `done` gets "trusted <path>" or "cancelled" (or why it failed).
    public func askToTrust(_ key: String, source: String = "you", done: ((String) -> Void)? = nil) {
        guard let n = trustNotices[key] else { done?("no folder to trust in that session"); return }
        let config = ClaudeTrust.configFile()
        let configShown = (config.path as NSString).abbreviatingWithTildeInPath
        let isTop = n.sessionFolder != n.path
        let name = n.folder
        var q = DuoQuestion(title: "Trust “\(name)” for Claude Code?", choices: [])
        q.paragraphs = [
            "Claude Code trusts your Home folder, but stops at a git repository when `/fork` starts a background session. \(name) became a repository after this session started, so it needs its own trust.",
            "Duo will change one setting in Claude Code’s file, the one Claude sets when you answer “Yes, I trust this folder”:",
        ]
        let folderLine = isTop ? "\(name) (the repository’s top folder, which holds \((n.sessionFolder as NSString).lastPathComponent)/)" : n.path
        q.items = [
            .init(what: "Folder", path: folderLine, captioned: true),
            .init(what: "In \(configShown)", path: "projects › …/\(name) › hasTrustDialogAccepted: true", captioned: true),
        ]
        q.note = "Only this folder. Claude Code will then use its settings, hooks and tools without asking, as it already does here in this session. Nothing else in the file changes."
        q.choices = [
            .init(label: "Cancel", isCancel: true) { done?("cancelled") },
            .init(label: "Trust Folder", isDefault: true) { [weak self] in self?.writeTrust(key, source: source, done: done) },
        ]
        SheetCenter.shared.ask(q)
    }

    /// The write, after the sheet's yes.
    public func writeTrust(_ key: String, source: String, done: ((String) -> Void)? = nil) {
        guard var n = trustNotices[key] else { return }
        switch ClaudeTrust.trust(n.path) {
        case .success:
            DuoLog.write("trusted \(n.path) for Claude Code (asked by \(source))")
            n.phase = .trusted
            n.dismissed = false
            trustNotices[key] = n
            done?("trusted \(n.path)")
        case .failure(let why):
            let reason = why.reason(path: ClaudeTrust.configFile().path)
            DuoLog.write("couldn't trust \(n.path) for Claude Code: \(reason)")
            n.phase = .failed(reason)
            n.dismissed = false
            trustNotices[key] = n
            done?("couldn't change Claude Code’s settings: \(reason)")
        }
    }

    /// Whether Fork Again can type now: Claude at its prompt with nothing typed.
    public func canForkAgain(_ key: String) -> Bool {
        if fixtureTerminals[key] != nil || fixtureChats[key] != nil { return true }   // a fixture state draws the enabled button
        guard let t = terminals.existing(key), trustNotices[key]?.forkLine != nil else { return false }
        let r = readPrompt(t)
        return r.idle && r.input.isEmpty
    }

    /// Fork Again: the same `/fork` line, read from the screen, text then Return as separate keystrokes (F-45).
    public func forkAgain(_ key: String) {
        guard let n = trustNotices[key], let line = n.forkLine, let t = terminals.existing(key), canForkAgain(key) else { return }
        t.paste(line)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { MainActor.assumeIsolated { t.view.send(txt: "\r") } }
        trustNotices[key] = nil
    }
}

// MARK: - Fixture states (scripts/check-ui.sh, the trust-notice captures)

extension AppModel {
    /// A recorded screen and a notice on the open tab, for the captures: `offer`, `run` (OK only), `trusted`, `failed`, and
    /// `sheet` / `failed-sheet` (the offer with the sheet up). Writes nothing: the fixture's write is never run.
    public func showTrustNoticeFixture(_ what: String) {
        guard let tab = consoleTab ?? fixture.sessions(inProject: currentProject?.name ?? "").first?.tabKey else { return }
        let path = "/Users/you/claude-home/checkout"
        if fixtureChats[tab] == nil, fixtureTerminals[tab] == nil {
            fixtureTerminals[tab] = TerminalSession(key: tab, screen: "> /fork try the annual plan first\n  ⎿  Workspace not trusted. Run `claude` in \(path)\n     once and accept the trust prompt, then retry.\n\n> ")
        }
        consoleTab = tab
        let phase: TrustNotice.Phase = switch what {
        case "run": .runClaude
        case "trusted": .trusted
        case "failed", "failed-sheet": .failed("another Claude is saving them")
        default: .offer
        }
        trustNotices[tab] = TrustNotice(path: path, forkLine: "/fork try the annual plan first", phase: phase, sessionFolder: path)
        if what == "sheet" || what == "failed-sheet" { askToTrust(tab) }
    }
}
