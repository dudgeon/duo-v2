import AppKit

// Keys while a chat shows (DL-119 §3, Q-54): number keys answer a review card, as in the TUI;
// Esc cancels or declines. Return does nothing until an option is chosen. They act only while the
// chat pane is on screen and no text field has the keyboard (a field's own keys win).
extension AppModel {
    /// The chat on screen, when it shows chat (not its terminal).
    public var visibleChat: ChatSession? {
        guard let key = visibleSessionId, let c = chat(for: key), c.showsChat else { return nil }
        return c
    }

    func installChatKeys() {
        guard !ChatKeyMonitor.installed else { return }
        ChatKeyMonitor.installed = true
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            let chars = e.charactersIgnoringModifiers ?? "", escape = e.keyCode == 53
            let mods = e.modifierFlags.intersection([.command, .control, .option, .shift])
            let number = e.windowNumber
            let used = MainActor.assumeIsolated { () -> Bool in
                // ⌘[ / ⌘]: your previous and next message, only while the chat has the keyboard (Q-54).
                if mods == .command, chars == "[" || chars == "]" { return self?.chatStep(chars == "[" ? -1 : 1, window: number) == true }
                return mods.subtracting(.shift).isEmpty && self?.chatKey(chars, escape: escape, window: number) == true
            }
            return used ? nil : e
        }
    }

    /// ⌘[ / ⌘] while the chat pane has the keyboard: the composer, or no field at all.
    func chatStep(_ by: Int, window number: Int) -> Bool {
        guard let chat = visibleChat, let w = NSApp.window(withWindowNumber: number), w.isKeyWindow else { return false }
        let fr = w.firstResponder
        guard fr is ComposerTextView || fr === w || fr == nil || !(fr is NSText || fr is GuardedTerminalView || String(describing: type(of: fr!)).contains("WKWebView")) else { return false }
        chat.stepYourMessages(by)
        return true
    }

    /// Handles a key for the chat on screen; true when it was used.
    func chatKey(_ chars: String, escape: Bool, window number: Int) -> Bool {
        guard let chat = visibleChat, let w = NSApp.window(withWindowNumber: number), w.isKeyWindow else { return false }
        if w.firstResponder is NSText || w.firstResponder is GuardedTerminalView { return false }
        return chat.key(chars, escape: escape)
    }
}

@MainActor enum ChatKeyMonitor { static var installed = false }

extension ChatSession {
    /// A key pressed with the chat in front: a digit answers the card, Esc cancels it.
    public func key(_ chars: String, escape: Bool) -> Bool {
        guard cardUp else {
            if escape, screen.kind == .busy { Task { await interrupt() }; return true }
            return false
        }
        let s = screen
        if escape {
            Task { if s.kind == .question || s.kind == .questionReview { await ask(.decline, sig: s.sig) } else { await cancelDialog(sig: s.sig) } }
            return true
        }
        guard let n = Int(chars), n > 0 else { return false }
        switch s.kind {
        case .permission, .plan:
            guard let o = s.options.first(where: { $0.n == n }) else { return false }
            if o.label.hasPrefix("Tell Claude what to change") { return false }   // its field takes the text
            Task { await answerOption(n, label: o.label, sig: s.sig) }
        case .questionReview:
            guard let o = s.options.first(where: { $0.n == n }) else { return false }
            Task { await ask(o.label == "Cancel" ? .cancelReview : .submit, sig: s.sig) }
        case .question:
            guard let row = s.rows.first(where: { $0.n == n }) else { return false }
            let qs = askedQuestions, qi = questionIndex(s) ?? 0
            let asked = qi < qs.count ? qs[qi]["options"] as? [ChatJSON] ?? [] : []
            switch row.kind {
            case .option:
                let i = s.options.firstIndex(of: row) ?? 0
                let label = i < asked.count ? asked[i]["label"] as? String ?? row.label : row.label
                Task { await ask(s.multi ? .toggle(label) : .pick(label), sig: s.sig) }
            case .chat: Task { await ask(.chat, sig: s.sig); focusComposer += 1 }
            default: return false
            }
        default: return false
        }
        return true
    }

    /// ⌘[ / ⌘]: scrolls to your previous or next message (DL-119 §4).
    public func stepYourMessages(_ by: Int) {
        let ids = log.yourMessageIDs
        guard !ids.isEmpty else { return }
        let here = revealRequest.flatMap { ids.firstIndex(of: $0) } ?? ids.count
        let next = min(max(here + by, 0), ids.count - 1)
        revealRequest = ids[next]
    }

    /// The mode chip: Shift+Tab, as the TUI cycles manual → accept edits → plan (F-104).
    public func cycleMode() async {
        guard [.idle, .busy].contains(reread().kind) else { return }
        _ = await press(.shiftTab)
    }

    /// Stop (esc) while Claude works.
    public func interrupt() async {
        guard reread().kind == .busy else { return }
        _ = await press(.esc)
    }
}
