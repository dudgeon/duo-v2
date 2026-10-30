import AppKit

// Dictation in the composer's text view (voice-input-handoff `composer`).

extension ComposerTextView {
    /// The words dictated so far go in at the caret: settled text in `text`, the volatile tail in `text2`, replaced
    /// in place as it changes. The whole dictation is one undo group.
    func dictate(_ t: VoiceTranscript, final: Bool) {
        guard let ts = textStorage else { return }
        if dictation == nil {
            let at = min(selectedRange().location + selectedRange().length, ts.length)
            // A space between what's there and the first word, unless it already ends in space or a new line.
            var lead = ""
            if at > 0, let c = (ts.string as NSString).substring(with: NSRange(location: at - 1, length: 1)).first, !c.isWhitespace { lead = " " }
            dictation = (at, 0)
            leading = lead
            undoManager?.groupsByEvent = false
            undoManager?.beginUndoGrouping()
        }
        guard let d = dictation else { return }
        let tail = final ? "" : t.volatile
        let body = [t.settledText, tail].filter { !$0.isEmpty }.joined(separator: " ")
        let text = body.isEmpty ? "" : leading + body
        let range = NSRange(location: d.start, length: d.length)
        if shouldChangeText(in: range, replacementString: text) {
            ts.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: baseAttributes))
            didChangeText()
        }
        let length = (text as NSString).length
        dictation = (d.start, length)
        // The styling pass after each change restores the base colour; the tail goes back to `text2`.
        if !tail.isEmpty {
            let n = (tail as NSString).length
            ts.addAttribute(.foregroundColor, value: DuoNSColor.text2, range: NSRange(location: d.start + length - n, length: n))
        }
        setSelectedRange(NSRange(location: d.start + length, length: 0))
        scrollRangeToVisible(selectedRange())
    }

    /// The dictation is over: kept (its words stay, all in `text`) or discarded (Esc takes them out). Keys typed
    /// while it finished are played now.
    func endDictation(keep: Bool) {
        if let d = dictation, let ts = textStorage {
            let range = NSRange(location: d.start, length: d.length)
            if range.length > 0, NSMaxRange(range) <= ts.length { ts.addAttribute(.foregroundColor, value: DuoNSColor.text, range: range) }
            undoManager?.endUndoGrouping()
            undoManager?.groupsByEvent = true
            if !keep, d.length > 0 {
                // One ⌘Z's worth: the whole dictation comes out.
                if undoManager?.canUndo == true { undoManager?.undo() }
                else if NSMaxRange(range) <= ts.length, shouldChangeText(in: range, replacementString: "") {
                    ts.replaceCharacters(in: range, with: ""); didChangeText()
                }
            }
        }
        dictation = nil
        let keys = heldKeys
        heldKeys = []
        for e in keys { keyDown(with: e) }
    }

    /// Voice input's keys while it listens: Esc discards, Return finishes and keeps the text (never sends), anything
    /// typed finishes first, then types. True when it took the key.
    func voiceKey(_ e: NSEvent) -> Bool {
        guard let v = VoiceInput.current, let chat = coordinator?.chat, v.target == .chat(chat.key) else { return false }
        let mods = e.modifierFlags.intersection([.shift, .command, .option, .control])
        switch v.state {
        case .listening:
            if e.keyCode == 53 { v.discard(); return true }
            if e.keyCode == 36 || e.keyCode == 76, mods.isEmpty { v.finish(); return true }
            if mods.contains(.command) { return false }
            if let c = e.characters, !c.isEmpty { heldKeys.append(e); v.finish(); return true }
            return false
        case .finishing:
            if e.keyCode == 53 || mods.contains(.command) { return false }
            if e.keyCode == 36 || e.keyCode == 76, mods.isEmpty { return true }
            if let c = e.characters, !c.isEmpty { heldKeys.append(e); return true }
            return false
        case .denied, .restricted, .unavailable, .failed:
            if e.characters?.isEmpty == false, !mods.contains(.command) { v.dismissLine() }
            return false
        default:
            return false
        }
    }
}
