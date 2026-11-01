import Foundation

// The composer's unsent words follow the session into the terminal (ENH-292, F-485). Every way chat stops showing
// (the tab's toggle, its key, `duo2 session chat off`, any fallback rule, a refused send or hand-over) changes `mode`
// or `fallback`, so the carry starts there: the words go into Claude's own prompt as a send puts them (the hand-over
// through Ctrl+G, or a bracketed paste below 2.1.269), and Return is never pressed. With a question, a picker or a
// screen chat can't read up, nothing is typed: the words wait in the composer and go in when the prompt is back.
// Coming back to chat, the composer opens on Claude's prompt again (prefillComposer), so the words return with any
// edits made in the terminal. A dictation running at the switch keeps listening into the terminal (Q-374): its words so
// far go with the composer's, and its next phrases go in after them, phrase at a time, as the terminal mic's do.

extension ChatSession {
    /// `showsChat` may have changed (a `mode` or `fallback` was set).
    func shownChanged() {
        let shows = showsChat
        guard shows != wasShowingChat else { return }
        wasShowingChat = shows
        if shows {
            carryPending = false
            let moved = movedVoice
            movedVoice = false
            if moved, let v = VoiceInput.current, v.target == .terminal(key), v.state.isActive || v.isHeldForCarry {
                if v.isHeldForCarry {
                    // Back before the carry was made: the composer still has its words, and gets the held phrases after them.
                    takeBack(v.endMoved())
                } else {
                    // Still landing in Claude's prompt: the composer opens on it once the last phrase is in.
                    carried = false
                    v.finishWhenDone { [weak self] _ in self?.prefillComposer() }
                    return
                }
            }
            if carried { carried = false; prefillComposer() }
        } else {
            // The composer is going: its dictation range closes with its words as they stand (V-6, V-8), and the
            // dictation itself follows the session into the terminal (Q-374). Its volatile tail stays out of the carry:
            // it settles into a phrase of its own, which goes in after the carried words.
            composerView?.dropDictation()
            if let v = VoiceInput.current, v.target == .chat(key), v.state.isActive {
                let tail = v.transcript.volatile
                if !tail.isEmpty, ui.composer.hasSuffix(tail) {
                    ui.composer = String(ui.composer.dropLast(tail.count)).replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
                }
                v.moveToTerminal(key, joins: !ui.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                movedVoice = true
            }
            carryPending = carryPlan != nil
            if !carryPending { releaseVoice() }
            carryWhenReady()
        }
    }

    /// What a carry would put in: nil when the composer holds nothing Claude's prompt lacks.
    var carryPlan: ChatPaste.SendPlan? {
        let plan = ChatPaste.sendPlan(held: ui.heldTokens, kept: ui.attachedTokens, text: ui.composer)
        return plan.paste.isEmpty && plan.remove.isEmpty ? nil : plan
    }

    /// Carries now if Claude's prompt was on screen at the last read and nothing else is typing into it; otherwise the next screen
    /// change, or the end of a send, calls again.
    func carryWhenReady() {
        guard carryPending, !carrying, !showsChat else { return }
        guard terminal != nil else { carryPending = false; return releaseVoice() }
        guard !sending, !composing, [.idle, .busy].contains(screen.kind) else { return }
        carrying = true
        carryPending = false
        Task {
            await carry()
            carrying = false
        }
    }

    func carry() async {
        guard !showsChat else { return }
        guard let plan = carryPlan else { return releaseVoice() }
        let s = reread()
        guard s.kind == .idle || s.kind == .busy else { carryPending = true; return }
        let words = ui.composer
        sending = true
        let placed = await place(plan, on: s, carry: true)
        sending = false
        composing = false
        if let why = placed.refused {
            noteTransition("carry", "the composer's words stayed in chat: \(why)")
            // The dictation's later words join them there rather than land in the terminal on their own.
            if movedVoice, let v = VoiceInput.current, v.isHeldForCarry { movedVoice = false; takeBack(v.endMoved()) }
            return
        }
        noteTransition("carry", "the composer's words went into Claude's prompt (\(plan.paste.count) characters)")
        // Claude's prompt holds them now; the composer takes them back from it when chat shows again.
        if ui.composer == words { ui.composer = "" }
        ui.composerBasis = nil
        ui.heldTokens = ui.attachedTokens
        carried = true
        releaseVoice()
    }

    /// A dictation moved to the terminal sends the phrases it held while the carry ran, and its next ones as they come.
    func releaseVoice() {
        guard movedVoice, let v = VoiceInput.current, v.target == .terminal(key) else { return }
        v.releaseMoved()
    }

    /// Words a moved dictation held, back in the composer after what it has.
    func takeBack(_ words: String) {
        guard !words.isEmpty else { return }
        ui.composer += (ui.composer.isEmpty || ui.composer.hasSuffix(" ") || ui.composer.hasSuffix("\n") ? "" : " ") + words
    }
}
