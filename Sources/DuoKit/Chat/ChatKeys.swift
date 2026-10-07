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
    /// A picker card's keys (DL-143): a number or ↑↓ moves the TUI's cursor, ←/→ its marker; ⏎, s and
    /// Esc finish. Each goes after the same check as the card's buttons.
    func pickerKey(_ p: ChatPicker, _ chars: String, escape: Bool) -> Bool {
        let up = String(UnicodeScalar(NSUpArrowFunctionKey)!), down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!), right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        if escape { Task { await pickerFinish(.cancel) }; return true }
        switch chars {
        case "\r": Task { await pickerFinish(.confirm) }
        case "s": Task { await pickerFinish(.sessionOnly) }
        case up, down:
            guard p.kind == .model, let at = p.cursor else { return false }
            let to = min(max(at + (chars == up ? -1 : 1), 0), p.rows.count - 1)
            Task { await pickerMove(to: p.rows[to].n) }
        case left, right:
            guard p.kind == .effort, let at = p.level else { return false }
            Task { await pickerLevel(to: min(max(at + (chars == left ? -1 : 1), 0), p.levels.count - 1)) }
        default:
            guard p.kind == .model, let n = Int(chars), p.rows.contains(where: { $0.n == n }) else { return false }
            Task { await pickerMove(to: n) }
        }
        return true
    }

    /// A key pressed with the chat in front: a digit answers the card, Esc cancels it.
    public func key(_ chars: String, escape: Bool) -> Bool {
        if pickerUp, let p = screen.picker { return pickerKey(p, chars, escape: escape) }
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

    /// A mode by name (`duo2 session chat mode plan`): ⇧⇥ until the TUI's footer shows it, re-reading
    /// after each press, at most once round the cycle. Nil when this claude's cycle hasn't got it.
    public func cycleMode(to target: ChatPermissionMode) async -> ChatPermissionMode? {
        for _ in 0..<6 {
            let s = reread()
            if s.mode == target { return target }
            guard [.idle, .busy].contains(s.kind) else { return nil }
            _ = await press(.shiftTab)
            await pause(200_000_000)
        }
        return reread().mode == target ? target : nil
    }

    // MARK: `/model` and `/effort` (DL-143)

    /// The same picker is still up, or nothing is sent and the terminal shows (as review cards do).
    func pickerCheck(_ kind: ChatPicker.Kind) -> ChatPicker? {
        let s = reread()
        guard dialogsVerified, s.kind == .picker, let p = s.picker, p.kind == kind else { return nil }
        return p
    }

    /// Moves the TUI's own cursor to row `n` (↑↓, re-reading after each key). Nothing is chosen.
    public func pickerMove(to n: Int) async -> ChatAnswerResult {
        for _ in 0..<12 {
            guard let p = pickerCheck(.model), let at = p.cursor else { return finish(.refused("the model picker isn’t up any more")) }
            guard let want = p.rows.firstIndex(where: { $0.n == n }) else { return .refused("there's no option \(n)") }
            if at == want { return .done }
            _ = await press(want > at ? .down : .up)
        }
        return finish(.refused("the picker's cursor didn't move"))
    }

    /// Moves `/effort`'s marker to a level (←/→, re-reading after each key). Nothing is chosen.
    public func pickerLevel(to i: Int) async -> ChatAnswerResult {
        for _ in 0..<8 {
            guard let p = pickerCheck(.effort), let at = p.level else { return finish(.refused("the effort picker isn’t up any more")) }
            guard p.levels.indices.contains(i) else { return .refused("there's no level \(i + 1)") }
            if at == i { return .done }
            _ = await press(i > at ? .right : .left)
        }
        return finish(.refused("the marker didn't move"))
    }

    /// ⏎ (set as default, confirm), s (this session only) or Esc, on the picker that's up.
    public func pickerFinish(_ how: PickerFinish) async -> ChatAnswerResult {
        guard let p = reread().picker, pickerCheck(p.kind) != nil else { return finish(.refused("the picker isn’t up any more")) }
        switch how {
        case .confirm: _ = await press(.enter)
        case .sessionOnly: terminal?.sendKeys("s"); await pause(); _ = reread()
        case .cancel: _ = await press(.esc)
        }
        return .done
    }

    public enum PickerFinish: Sendable { case confirm, sessionOnly, cancel }

    /// Stop (esc) while Claude works.
    public func interrupt() async {
        guard reread().kind == .busy else { return }
        _ = await press(.esc)
    }
}
