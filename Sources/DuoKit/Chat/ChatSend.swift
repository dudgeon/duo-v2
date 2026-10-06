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
        guard !text.isEmpty else { return .refused("nothing to send") }
        guard terminal != nil else { return finish(.refused("the terminal isn't running")) }
        let s = reread()
        guard s.kind == .idle || s.kind == .busy else { return finish(.refused("the terminal is showing \(s.kind == .unknown ? "a screen chat mode can’t show" : "a dialog")")) }
        let wasBusy = s.kind == .busy
        sending = true
        defer { sending = false; composing = false }
        if usesExternalEditor, let dir = composeDir {
            // What Claude's prompt really holds: known when the composer opened on it; empty when the
            // screen shows nothing there; otherwise asked (a dim suggestion reads as text, F-108).
            var basis = ui.composerBasis ?? ((s.input ?? "").isEmpty ? "" : nil)
            if basis == nil { basis = await peekPrompt() }
            guard let basis else { return finish(.refused("couldn’t read Claude’s prompt")) }
            do { try ChatCompose.leave(.init(text: text, basis: basis), in: dir, session: key) } catch { return finish(.refused("couldn’t hand the text over (\(error.localizedDescription))")) }
            composing = true
            terminal?.sendKeys(ChatKey.ctrlG.bytes)
            // The TUI runs the editor (its screen goes blank), then redraws with the new input.
            var back = false
            for _ in 0..<50 {
                await pause(100_000_000)
                let gone = !FileManager.default.fileExists(atPath: ChatCompose.handoverFile(dir, key).path)
                let now = reread()
                if gone, now.kind == .idle || now.kind == .busy { back = true; break }
            }
            composing = false
            if let held = try? String(contentsOf: ChatCompose.refusedFile(dir, key), encoding: .utf8) {
                try? FileManager.default.removeItem(at: ChatCompose.refusedFile(dir, key))
                return finish(.refused("Claude’s prompt changed in the terminal (it holds “\(held.prefix(40))”), so your text wasn’t put in"))
            }
            guard back else {
                try? FileManager.default.removeItem(at: ChatCompose.handoverFile(dir, key))
                return finish(.refused("Claude Code didn’t open its editor"))
            }
        } else {
            guard (s.input ?? "").isEmpty else { return finish(.refused("Claude’s prompt already holds “\((s.input ?? "").prefix(40))”")) }
            terminal?.sendKeys("\u{1b}[200~" + text + "\u{1b}[201~")
            await pause(250_000_000)
        }
        let echoed = reread()
        guard echoed.kind == .idle || echoed.kind == .busy, Self.echoMatches(echoed.input ?? "", text) else {
            return finish(.refused("your text didn’t appear in Claude’s prompt as sent"))
        }
        // Shown before Return: the prompt's hook can arrive within the pause after it, and must
        // find this bubble to match.
        log.sent(text, time: now, queued: wasBusy, planMode: s.mode == .plan)
        _ = await press(.enter)
        ui.composer = ""
        ui.composerBasis = nil
        return .done
    }

    /// Claude's real prompt text, through Ctrl+G with nothing changed (the helper copies it out).
    public func peekPrompt() async -> String? {
        guard usesExternalEditor, let dir = composeDir, [.idle, .busy].contains(reread().kind) else { return nil }
        let wasSending = sending
        sending = true; composing = true
        defer { sending = wasSending; composing = false }
        do { try ChatCompose.leave(.init(text: "", basis: "", peek: true), in: dir, session: key) } catch { return nil }
        terminal?.sendKeys(ChatKey.ctrlG.bytes)
        for _ in 0..<50 {
            await pause(100_000_000)
            if let text = try? String(contentsOf: ChatCompose.peekFile(dir, key), encoding: .utf8), [.idle, .busy].contains(reread().kind) {
                try? FileManager.default.removeItem(at: ChatCompose.peekFile(dir, key))
                return text.trimmingCharacters(in: .newlines)
            }
        }
        try? FileManager.default.removeItem(at: ChatCompose.handoverFile(dir, key))
        return nil
    }

    /// The prompt on screen shows the text: whole, or its start (a long input wraps or scrolls), or
    /// the TUI's placeholder for long pasted text.
    static func echoMatches(_ shown: String, _ text: String) -> Bool {
        let a = shown.chatNorm, b = text.chatNorm
        if a.isEmpty { return false }
        if a.contains("[Pasted text") { return true }
        return b.hasPrefix(a) || a.hasPrefix(b) || b.hasPrefix(String(a.prefix(40)))
    }
}
