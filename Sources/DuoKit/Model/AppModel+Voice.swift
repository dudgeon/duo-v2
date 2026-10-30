import AppKit
import DuoControl
import Foundation

/// Voice input's wiring (DL-260, DL-261): which session a dictation goes to, how its words reach a chat
/// composer or a terminal's prompt, and the ⇧⌘D key (tap toggles, held past 0.3 s is hold-to-talk).
extension AppModel {
    /// The session showing, as chat (its composer) or as a terminal; nil when there is none to speak to.
    public var voiceFocusTarget: VoiceTarget? {
        if let t = voice.target, voice.state.isActive { return t }
        guard let key = visibleSessionId else { return nil }
        if let c = chats.existing(key) ?? fixtureChats[key], c.showsChat { return .chat(key) }
        if terminals.existing(key) != nil { return .terminal(key) }
        return nil
    }

    /// The mic, ⇧⌘D's menu item and `duo2 voice start|stop`: starts a dictation, or finishes the running one.
    public func toggleVoice(_ target: VoiceTarget? = nil) {
        guard let target = target ?? voiceFocusTarget else { return }
        voice.toggle(target)
    }

    /// The terminal's visible rows, as chat mode reads them.
    func voiceRows(_ t: TerminalSession) -> [String] {
        let rows = t.view.terminalStateSnapshot().dimensions.rows
        return t.view.visibleRowsText(0..<rows)
    }

    /// One settled phrase into a terminal's prompt: a bracketed paste, a space between phrases, never a Return.
    /// Claude's own prompt must be on screen and no question or picker may be: a paste could answer one.
    func voicePaste(_ target: VoiceTarget, _ phrase: String, first: Bool) -> VoicePasteResult {
        guard let t = terminals.existing(target.key), !t.exited else { return .blocked("The session isn't running") }
        if t.isClaude {
            guard t.isLiveClaude else { return .blocked("The session has ended") }
            if let why = t.notReadyReason { return .blocked(why) }
            let rows = voiceRows(t)
            if InputBoxFinder.questionShowing(rows) { return .blocked("Claude asked a question") }
            if !InputBoxFinder.hasInputBox(rows: rows) { return .blocked("Claude's input box isn't on screen") }
        }
        // A shell has no input box: the words go in at its prompt, bracketed if the shell turned that on.
        let bytes = VoiceTerminalText.paste(phrase, first: first)
        if t.isClaude || t.view.terminalStateSnapshot().bracketedPasteMode {
            t.view.send(txt: bytes)
        } else {
            t.view.send(txt: SendFormat.line((first ? "" : " ") + phrase))
        }
        return .sent
    }

    func wireVoice(_ v: VoiceInput) {
        VoiceInput.current = v
        v.host = VoiceInput.Host(
            update: { [weak self] target, transcript, final in
                guard let self, let chat = self.chats.existing(target.key) ?? self.fixtureChats[target.key] else { return }
                if let field = chat.composerView { field.dictate(transcript, final: final) }
                else if final, !transcript.settledText.isEmpty { chat.ui.composer += (chat.ui.composer.isEmpty ? "" : " ") + transcript.settledText }
            },
            paste: { [weak self] target, phrase, first in self?.voicePaste(target, phrase, first: first) ?? .blocked("Duo isn't ready") },
            ended: { [weak self] target, kept in
                guard let self, let chat = self.chats.existing(target.key) ?? self.fixtureChats[target.key] else { return }
                chat.composerView?.endDictation(keep: kept)
            })
        installVoiceKeys()
    }

    /// ⇧⌘D: key down starts or finishes, key up ends a hold. A local monitor, since a menu's key equivalent
    /// has no key-up.
    func installVoiceKeys() {
        guard VoiceKeys.monitors.isEmpty else { return }
        let chord: NSEvent.ModifierFlags = [.command, .shift]
        let down = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard e.keyCode == 2, e.modifierFlags.intersection([.command, .shift, .option, .control]) == chord else { return e }
            let (isRepeat, flags) = (e.isARepeat, e.modifierFlags)
            _ = flags
            let took = MainActor.assumeIsolated { () -> Bool in
                guard let self, let target = self.voiceFocusTarget else { return false }
                if !isRepeat {
                    self.voice.keyDown(target)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.31) { MainActor.assumeIsolated { self.voice.noteHolding() } }
                }
                return true
            }
            return took ? nil : e
        }
        let up = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] e in
            guard e.keyCode == 2 else { return e }
            MainActor.assumeIsolated { self?.voice.keyUp() }
            return e
        }
        VoiceKeys.monitors = [down, up].compactMap { $0 }
    }

    /// The Edit menu item's title.
    public var voiceMenuTitle: String { voice.state.isActive ? "Stop Voice Input" : "Start Voice Input" }
}

@MainActor enum VoiceKeys {
    static var monitors: [Any] = []
}

extension TerminalSession {
    /// The cell size the renderer uses (SwiftTerm: the font's "W" advance and its ceiled line height).
    var cellSize: CGSize {
        let f = view.font
        let w = f.advancement(forGlyph: f.glyph(withName: "W")).width
        let h = ceil(f.ascender - f.descender + f.leading)
        return CGSize(width: w, height: h)
    }
}

// MARK: - duo2 voice

extension AppModel {
    /// `duo2 voice start|stop|status [id]` and `duo2 voice file <audio> [id]` (DL-71): what the mic does, and its
    /// scripted twin that feeds a file through the same path.
    func voiceVerb(_ id: ActionID, _ inv: Invocation, _ req: ControlRequest, _ done: @escaping @MainActor (Reply) -> Void) {
        let idWord = id == .voiceFile ? (inv.positional.count > 1 ? inv.positional[1] : nil) : inv.positional.first
        var key = visibleSessionId
        if idWord == "shell" {
            // The shell opened last: a shell has no session id (`duo2 shell new`).
            guard let k = shellTabs.values.flatMap({ $0 }).last(where: { terminals.existing($0) != nil }) else { return done(.fail("no shell is open; `duo2 shell new` opens one")) }
            key = k
        } else if let w = idWord {
            guard let s = findSession(w, in: nil) else { return done(.fail("no session '\(w)'")) }
            key = s.tabKey
        }
        guard let key else { return done(.fail("no session is showing; name one: \(id.action.usage)")) }
        let name = consoleTitle(key)
        let target: VoiceTarget = (chats.existing(key) ?? fixtureChats[key])?.showsChat == true ? .chat(key) : .terminal(key)
        guard target.isChat || terminals.existing(key) != nil else { return done(.fail("\(name) isn't running in Duo; open it first")) }
        switch id {
        case .voiceStatus:
            let mine = voice.target == target
            // For a terminal, the line the words land on: what its prompt holds now (scripted checks read it).
            var prompt = ""
            if case .terminal = target, let t = terminals.existing(key) {
                prompt = " Its last screen line: \"" + (voiceRows(t).last { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "").trimmingCharacters(in: .whitespaces) + "\""
            }
            if let u = voice.unsentWords { prompt += " Unsent words (a question stopped it): \"\(u)\"" }
            done(.ok((mine || voice.state.isActive ? VoiceCopy.line(voice.state) : "Voice input is off.") + prompt,
                     ["state": String(describing: voice.state), "session": voice.target?.key ?? ""]))
        case .voiceStop:
            guard voice.state.isActive else { return done(.ok("Voice input wasn't on.")) }
            voice.finishWhenDone { state in done(.ok("Stopped. \(self.voice.transcript.settledText.isEmpty ? "Nothing was heard." : "Said: \(self.voice.transcript.settledText)")", ["state": String(describing: state)])) }
        case .voiceStart:
            voice.start(target)
            switch voice.state {
            case .unavailable, .denied, .restricted, .failed: done(.fail(VoiceCopy.line(voice.state)))
            default: done(.ok("Voice input is on for \(name)." + (voice.state == .asking ? " Duo is asking the user first." : "")))
            }
        case .voiceFile:
            guard let path = inv.positional.first else { return done(.fail("usage: \(id.action.usage)")) }
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else { return done(.fail("no audio file at \(url.path) (give an absolute path)")) }
            guard !voice.state.isActive else { return done(.fail("voice input is already on; stop it first")) }
            voice.start(target, source: .file(url)) { state in
                switch state {
                case .idle where self.voice.notice != nil: done(.fail("\(self.voice.notice?.text ?? "") (\(name))"))
                case .idle: done(.ok("Said into \(name): \(self.voice.transcript.settledText.isEmpty ? "(nothing recognised)" : self.voice.transcript.settledText). Nothing was sent.",
                                     ["said": self.voice.transcript.settledText]))
                default: done(.fail(VoiceCopy.line(state)))
                }
            }
        default: done(.fail("not a voice verb"))
        }
    }
}

extension VoiceTarget {
    var isChat: Bool { if case .chat = self { true } else { false } }
}
