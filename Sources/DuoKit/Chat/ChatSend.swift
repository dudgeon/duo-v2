import DuoControl
import Foundation

// Sending from the composer (handoff `composer`, F-104, F-112). The composer is Claude's own
// prompt: Duo hands its text over through Claude Code's external editor (Ctrl+G → `duo2 compose`),
// so the TUI's input is replaced exactly and stays the owner. Below 2.1.269 (a redraw bug) or with
// Ctrl+G rebound, it pastes into an input the screen shows empty instead. Either way the echo is
// checked on screen before Return; anything unexpected sends nothing more and shows the terminal.

extension ChatSession {
    /// Whether Ctrl+G hands over (else paste-on-send).
    public var usesExternalEditor: Bool {
        guard composeDir != nil, ChatComposer.ctrlGIsTheEditor else { return false }
        guard let v = cliVersion.flatMap(ChatVersion.init) else { return false }
        return v >= ChatVersion.externalEditor
    }

    /// Sends the composer's text as your message.
    public func send(_ raw: String) async -> ChatAnswerResult {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Pictures first, then the words, as Claude Code's own prompt reads (F-233).
        let plan = ChatPaste.sendPlan(held: ui.heldTokens, kept: ui.attachedTokens, text: text)
        guard !plan.message.isEmpty else { return .refused("nothing to send") }
        guard terminal != nil else { return finish(.refused("the terminal isn't running")) }
        let s = reread()
        guard s.kind == .idle || s.kind == .busy else { return finish(.refused("the terminal is showing \(s.kind == .unknown ? "a screen chat mode can’t show" : "a dialog")")) }
        let wasBusy = s.kind == .busy
        sending = true
        defer { sending = false; composing = false }
        var echo = plan.message
        var shown = plan.paste   // the words as your bubble shows them: with whatever was carried ahead of them
        let composerShowedPrompt = ui.composerBasis != nil
        if usesExternalEditor, let dir = composeDir {
            // What Claude's prompt really holds: known when the composer opened on it; empty when the
            // screen shows nothing there; otherwise asked (a dim suggestion reads as text, F-108).
            var basis = ui.composerBasis ?? ((s.input ?? "").isEmpty ? "" : nil)
            if basis == nil { basis = await peekPrompt() }
            guard let basis else { return finish(.refused("couldn’t read Claude’s prompt")) }
            // The composer opened on this prompt, or it holds words the composer never showed (the task
            // path drafted into a New Session in Task, DL-112): those stay ahead of the text (F-254).
            let carried = composerShowedPrompt ? "" : ChatPaste.carried(prompt: basis, text: plan.paste)
            if !carried.isEmpty { echo = carried + " " + echo; shown = carried + " " + shown }
            do { try ChatCompose.leave(.init(text: echo, basis: basis), in: dir, session: composeKey) } catch { return finish(.refused("couldn’t hand the text over (\(error.localizedDescription))")) }
            composing = true
            terminal?.sendKeys(ChatKey.ctrlG.bytes)
            // The TUI runs the editor (its screen goes blank), then redraws with the new input.
            var back = false
            for _ in 0..<50 {
                await pause(100_000_000)
                let gone = !FileManager.default.fileExists(atPath: ChatCompose.handoverFile(dir, composeKey).path)
                let now = reread()
                if gone, now.kind == .idle || now.kind == .busy { back = true; break }
            }
            composing = false
            if let held = try? String(contentsOf: ChatCompose.refusedFile(dir, composeKey), encoding: .utf8) {
                try? FileManager.default.removeItem(at: ChatCompose.refusedFile(dir, composeKey))
                return finish(.refused("Claude’s prompt changed in the terminal (it holds “\(held.prefix(40))”), so your text wasn’t put in"))
            }
            guard back else {
                try? FileManager.default.removeItem(at: ChatCompose.handoverFile(dir, composeKey))
                return finish(.refused("Claude Code didn’t open its editor"))
            }
        } else {
            // Pictures this composer attached are in the prompt as tokens: the removed ones are deleted,
            // the rest stay, and the text goes in after them. Other words in the prompt (the drafted
            // task path, DL-112) stay too, ahead of the text (F-254); anything else there is refused.
            let prompt = s.input ?? ""
            guard !prompt.hasPrefix("/"), Set(ChatPaste.tokens(in: prompt)).isSubset(of: Set(ui.heldTokens)) else { return finish(.refused("Claude’s prompt already holds “\(prompt.prefix(40))”")) }
            if !ui.heldTokens.isEmpty, let why = await removeImageTokens(plan.remove, from: prompt) { return finish(.refused(why)) }
            let left = ui.heldTokens.isEmpty ? prompt : reread().input ?? ""
            let carried = ChatPaste.carried(prompt: left, text: "")
            var pasted = plan.paste
            if !carried.isEmpty {
                // The prompt as it will read: what it holds, a space, then the text.
                echo = left + " " + plan.paste
                shown = carried + " " + plan.paste
                pasted = " " + plan.paste
            }
            if !plan.paste.isEmpty { terminal?.sendKeys("\u{1b}[200~" + pasted + "\u{1b}[201~") }
            await pause(250_000_000)
        }
        let echoed = reread()
        guard echoed.kind == .idle || echoed.kind == .busy, Self.echoMatches(echoed.input ?? "", echo) else {
            return finish(.refused("your text didn’t appear in Claude’s prompt as sent"))
        }
        // Shown before Return: the prompt's hook can arrive within the pause after it, and must
        // find this bubble to match.
        log.sent(shown, images: plan.keep.compactMap { ui.images[$0].flatMap(ChatImage.init) }, time: now, queued: wasBusy, planMode: s.mode == .plan)
        lastCommand = text.hasPrefix("/") ? (String(text.prefix { !$0.isWhitespace }), Date()) : nil
        _ = await press(.enter)
        ui.composer = ""
        ui.composerBasis = nil
        forgetImages()
        return .done
    }

    /// The model chip and the effort chip (DL-168): `/model` or `/effort` into Claude's own prompt, so DL-143's card docks.
    /// Only at an idle prompt that is empty (text there would turn the command into a message to Claude), on a CLI whose
    /// screens are trusted, and with the echo checked before Return, as a send does. No bubble; the composer's draft stays.
    /// Refusals are reported as a send's are (the terminal, with why), except waiting on Claude: the chip says so itself.
    public func openPicker(_ kind: ChatPicker.Kind) async -> ChatAnswerResult {
        let command = kind == .effort ? "/effort" : "/model"
        guard kind != .confirm else { return .refused("nothing to open") }
        guard !sending, !composing else { return .refused("Duo is sending something to Claude Code") }
        guard terminal != nil else { return finish(.refused("the terminal isn't running")) }
        let s = reread()
        if s.kind == .busy { return .refused("Claude is working; \(command) opens when it finishes") }
        guard s.kind == .idle else { return finish(.refused("the terminal is showing \(s.kind == .unknown ? "a screen chat mode can’t show" : "a dialog")")) }
        guard versionTrust != .unverified else { return finish(.refused("chat mode hasn’t been checked with this version of Claude Code’s screens")) }
        sending = true
        defer { sending = false }
        if !(s.input ?? "").isEmpty {
            // A dim suggestion reads as text on the screen (F-108): only the real buffer says whether the prompt holds any.
            let real = usesExternalEditor ? await peekPrompt() : nil
            guard let real, real.isEmpty else { return finish(.refused("Claude’s prompt holds text, which \(command) would join into a message to Claude")) }
        }
        guard reread().kind == .idle else { return finish(.refused("Claude Code’s screen changed before \(command) was sent")) }
        terminal?.sendKeys("\u{1b}[200~" + command + "\u{1b}[201~")
        await pause(250_000_000)
        let echoed = reread()
        let shown = (echoed.input ?? "").chatNorm
        guard echoed.kind == .idle, !shown.isEmpty, command.hasPrefix(shown) else {
            return finish(.refused("\(command) didn’t appear in Claude’s prompt as sent"))
        }
        lastCommand = (command, Date())
        _ = await press(.enter)
        for _ in 0..<30 {
            if reread().kind == .picker { return .done }
            await pause(100_000_000)
        }
        return .refused("Claude Code didn’t open \(command)")
    }

    /// Claude's real prompt text, through Ctrl+G with nothing changed (the helper copies it out).
    public func peekPrompt() async -> String? {
        guard usesExternalEditor, let dir = composeDir, [.idle, .busy].contains(reread().kind) else { return nil }
        let wasSending = sending
        sending = true; composing = true
        defer { sending = wasSending; composing = false }
        do { try ChatCompose.leave(.init(text: "", basis: "", peek: true), in: dir, session: composeKey) } catch { return nil }
        terminal?.sendKeys(ChatKey.ctrlG.bytes)
        for _ in 0..<50 {
            await pause(100_000_000)
            if let text = try? String(contentsOf: ChatCompose.peekFile(dir, composeKey), encoding: .utf8), [.idle, .busy].contains(reread().kind) {
                try? FileManager.default.removeItem(at: ChatCompose.peekFile(dir, composeKey))
                return text.trimmingCharacters(in: .newlines)
            }
        }
        try? FileManager.default.removeItem(at: ChatCompose.handoverFile(dir, composeKey))
        return nil
    }

    /// The prompt on screen shows the text: whole, or its start, or (a long input scrolls inside the
    /// box, showing only its last lines, F-254) a stretch of it; or the TUI's placeholder for long
    /// pasted text.
    static func echoMatches(_ shown: String, _ text: String) -> Bool {
        let a = shown.chatNorm, b = text.chatNorm
        if a.isEmpty { return false }
        if a.contains("[Pasted text") { return true }
        return b.hasPrefix(a) || a.hasPrefix(b) || b.hasPrefix(String(a.prefix(40))) || (a.count >= 40 && b.contains(a))
    }
}
