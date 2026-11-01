import Foundation

// The composer's unsent words follow the session into the terminal (ENH-292, F-485). Every way chat stops showing
// (the tab's toggle, its key, `duo2 session chat off`, any fallback rule, a refused send or hand-over) changes `mode`
// or `fallback`, so the carry starts there: the words go into Claude's own prompt as a send puts them (the hand-over
// through Ctrl+G, or a bracketed paste below 2.1.269), and Return is never pressed. With a question, a picker or a
// screen chat can't read up, nothing is typed: the words wait in the composer and go in when the prompt is back.
// Coming back to chat, the composer opens on Claude's prompt again (prefillComposer), so the words return with any
// edits made in the terminal.

extension ChatSession {
    /// `showsChat` may have changed (a `mode` or `fallback` was set).
    func shownChanged() {
        let shows = showsChat
        guard shows != wasShowingChat else { return }
        wasShowingChat = shows
        if shows {
            carryPending = false
            if carried { carried = false; prefillComposer() }
        } else {
            // The composer is going: a dictation into it stops, its words kept as they stand (V-6, V-8), and they go with it.
            composerView?.dropDictation()
            if let v = VoiceInput.current, v.target == .chat(key), v.state.isActive { v.discard() }
            carryPending = carryPlan != nil
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
        guard terminal != nil else { carryPending = false; return }
        guard !sending, !composing, [.idle, .busy].contains(screen.kind) else { return }
        carrying = true
        carryPending = false
        Task {
            await carry()
            carrying = false
        }
    }

    func carry() async {
        guard let plan = carryPlan, !showsChat else { return }
        let s = reread()
        guard s.kind == .idle || s.kind == .busy else { carryPending = true; return }
        let words = ui.composer
        sending = true
        let placed = await place(plan, on: s, carry: true)
        sending = false
        composing = false
        if let why = placed.refused {
            noteTransition("carry", "the composer's words stayed in chat: \(why)")
            return
        }
        noteTransition("carry", "the composer's words went into Claude's prompt (\(plan.paste.count) characters)")
        // Claude's prompt holds them now; the composer takes them back from it when chat shows again.
        if ui.composer == words { ui.composer = "" }
        ui.composerBasis = nil
        ui.heldTokens = ui.attachedTokens
        carried = true
    }
}
