import Foundation

// Rewind (DL-338, Q-507): after Duo's sheet, Duo works Claude Code's own `/rewind` menu in the
// session's terminal, reading each screen before each key. The words below were read from the real
// menu on 2.1.284 and 2.1.316 (Fixtures/rewind/screens, F-667). Anything this doesn't recognise
// stops the drive and the terminal is shown (DL-258's fallback); Duo never guesses and never edits a transcript.

/// One screen of Claude Code's rewind menu.
public enum ChatRewindScreen: Equatable, Sendable {
    /// The list of your earlier prompts; `selected` is the row with the cursor (a prompt, or `(current)`).
    case list(selected: String?)
    /// The confirmation: the prompt quoted, whether the files would change, the numbered options.
    case confirm(prompt: String, options: [Option], codeChanges: Bool)

    public struct Option: Equatable, Sendable {
        public var n: Int
        public var label: String
        public var cursor: Bool
    }
}

public enum ChatRewindReader {
    static let listLine = "Restore the code and/or conversation to the point before"
    static let confirmLine = "Confirm you want to restore to the point before you sent this message"

    /// The menu on this screen, nil when it isn't the rewind menu (or isn't one of its two screens).
    public static func read(_ lines: [String]) -> ChatRewindScreen? {
        let rows = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        guard let head = rows.lastIndex(of: "Rewind") else { return nil }
        let body = Array(lines[(head + 1)...])
        let text = Array(rows[(head + 1)...])
        if let at = text.firstIndex(where: { $0.hasPrefix(listLine) }) {
            guard text.contains(where: { $0.hasPrefix("Enter to continue") }) else { return nil }
            // Each entry is a prompt line then a line of what it changed; `(current)` has none. The cursor is `❯`.
            var selected: String?
            for (raw, row) in zip(body[(at + 1)...], text[(at + 1)...]) {
                if row.hasPrefix("Enter to continue") { break }
                if raw.trimmingCharacters(in: .whitespaces).hasPrefix("❯") {
                    selected = String(row.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            return .list(selected: selected)
        }
        if let at = text.firstIndex(where: { $0.hasPrefix(confirmLine) }) {
            var prompt: [String] = []
            var i = at + 1
            while i < text.count, text[i].isEmpty { i += 1 }
            while i < text.count, text[i].hasPrefix("│") {
                let t = String(text[i].dropFirst(1)).trimmingCharacters(in: .whitespaces)
                if t.range(of: #"^\(.* ago\)$"#, options: .regularExpression) == nil { prompt.append(t) }
                i += 1
            }
            var options: [ChatRewindScreen.Option] = []
            var codeChanges = false
            for row in text[i...] {
                if row.hasPrefix("The code will be restored") { codeChanges = true }
                guard let m = row.range(of: #"^[❯↓↑]?\s*(\d)\.\s+(.+)$"#, options: .regularExpression) else { continue }
                let s = String(row[m])
                let cursor = s.hasPrefix("❯")
                let rest = s.drop { !$0.isNumber }
                guard let n = rest.first?.wholeNumberValue else { continue }
                options.append(.init(n: n, label: String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces), cursor: cursor))
            }
            guard !options.isEmpty else { return nil }
            return .confirm(prompt: prompt.joined(separator: "\n"), options: options, codeChanges: codeChanges)
        }
        return nil
    }

    /// Whether the menu's row `shown` is the prompt `wanted`: the menu may cut a long prompt with `…`
    /// and flatten its line breaks.
    public static func same(_ shown: String, _ wanted: String) -> Bool {
        func norm(_ s: String) -> String { s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        var a = norm(shown), b = norm(wanted)
        if a.hasSuffix("…") { a.removeLast(); b = String(b.prefix(a.count)) }
        else if a.hasSuffix("...") { a.removeLast(3); b = String(b.prefix(a.count)) }
        return !a.isEmpty && a == b
    }
}

extension ChatSession {
    /// Your live typed prompts, oldest first (what Claude's list offers).
    var rewindablePrompts: [ChatYou] {
        log.items.compactMap { if case .you(let y) = $0, !y.queued { y } else { nil } }
    }

    /// Rewinds the conversation to before the prompt `uuid` (and the files too, with `code`), by working Claude
    /// Code's `/rewind` menu. The sheet has been answered. On success the prompt is in the composer and the removed turns
    /// have left the log; on a refusal the terminal is showing, with why.
    public func rewind(toPrompt id: String, code: Bool, keepPrompt: Bool = true) async -> ChatAnswerResult {
        let prompts = rewindablePrompts
        guard let index = prompts.firstIndex(where: { $0.id == id }) else { return .refused("that message isn’t in the conversation any more") }
        let target = prompts[index]
        guard !sending, !composing else { return .refused("Duo is sending something to Claude Code") }
        guard terminal != nil else { return finish(.refused("the terminal isn’t running")) }
        let s = reread()
        if s.kind == .busy { return .refused("Claude is working; rewind opens when it finishes") }
        guard s.kind == .idle else { return finish(.refused("the terminal is showing \(s.kind == .unknown ? "a screen chat mode can’t show" : "a dialog")")) }
        guard versionTrust != .unverified else { return finish(.refused("chat mode hasn’t been checked with this version of Claude Code’s screens")) }
        sending = true
        defer { sending = false }
        if !(s.input ?? "").isEmpty {
            let real = usesExternalEditor ? await peekPrompt() : (await promptIsSuggestion()).map { $0 ? "" : "text" }
            guard let real, real.isEmpty else { return finish(.refused("Claude’s prompt holds text, which /rewind would join into a message to Claude")) }
        }
        guard reread().kind == .idle else { return finish(.refused("Claude Code’s screen changed before /rewind was sent")) }
        let command = "/rewind"
        terminal?.sendKeys("\u{1b}[200~" + command + "\u{1b}[201~")
        await pause(250_000_000)
        let echoed = reread()
        guard echoed.kind == .idle, (echoed.input ?? "").chatNorm == command else { return finish(.refused("/rewind didn’t appear in Claude’s prompt as sent")) }
        log.quietCommands.append((command, Date().addingTimeInterval(120)))
        terminal?.sendKeys(ChatKey.enter.bytes)

        // 1. The list, with the cursor on (current): one Up per prompt after the target, plus the target's own row.
        guard case .list = await menu(waitFor: { if case .list = $0 { true } else { false } }) else {
            return finish(.refused("Claude Code’s /rewind list didn’t come up as chat mode knows it"))
        }
        for _ in 0..<(prompts.count - index) {
            terminal?.sendKeys(ChatKey.up.bytes)
            await pause()
        }
        guard case .list(let selected?)? = readMenu(), ChatRewindReader.same(selected, target.text) else {
            return finish(.refused("the /rewind list isn’t on the message chosen"))
        }
        terminal?.sendKeys(ChatKey.enter.bytes)

        // 2. The confirmation: the same prompt quoted, then the option for what was chosen.
        guard case .confirm(let quoted, let options, let hasCode)? = await menu(waitFor: { if case .confirm = $0 { true } else { false } }) else {
            return finish(.refused("Claude Code’s /rewind confirmation didn’t come up as chat mode knows it"))
        }
        guard ChatRewindReader.same(quoted, target.text) || quoted.hasPrefix(String(target.text.prefix(20))) else {
            return finish(.refused("the /rewind confirmation quotes a different message"))
        }
        let want = code ? "Restore code and conversation" : "Restore conversation"
        guard code == false || hasCode else { return finish(.refused("Claude Code has no files to put back for that message")) }
        guard let wanted = options.first(where: { $0.label == want }), let at = options.first(where: \.cursor) else {
            return finish(.refused("Claude Code’s /rewind options aren’t the ones chat mode knows (“\(want)” missing)"))
        }
        let steps = wanted.n - at.n
        for _ in 0..<abs(steps) {
            terminal?.sendKeys((steps > 0 ? ChatKey.down : ChatKey.up).bytes)
            await pause()
        }
        guard case .confirm(_, let now, _)? = readMenu(), now.first(where: \.cursor)?.label == want else {
            return finish(.refused("the /rewind option isn’t on “\(want)”"))
        }
        terminal?.sendKeys(ChatKey.enter.bytes)

        // 3. Back at Claude's prompt with the message in it.
        for _ in 0..<50 {
            await pause(100_000_000)
            let r = reread()
            if r.kind == .idle, readMenu() == nil {
                if ChatRewindReader.same(r.input ?? "", target.text) || (r.input ?? "").chatNorm.hasPrefix(String(target.text.chatNorm.prefix(20))) {
                    land(afterRewindTo: target, code: code, keepPrompt: keepPrompt)
                    if !keepPrompt { await clearPrompt() }
                    return .done
                }
            }
        }
        return finish(.refused("Claude Code didn’t come back to its prompt with the message in it"))
    }

    func readMenu() -> ChatRewindScreen? {
        guard let t = terminal else { return nil }
        return ChatRewindReader.read(t.screenLines())
    }

    /// Waits up to 3 s for a menu screen of the wanted kind.
    private func menu(waitFor wanted: (ChatRewindScreen) -> Bool) async -> ChatRewindScreen? {
        for _ in 0..<30 {
            await pause(100_000_000)
            _ = reread()
            if let m = readMenu(), wanted(m) { return m }
        }
        return nil
    }

    /// The rewind happened: the prompt and everything after it leave the log, and the prompt waits in the composer.
    /// (Claude Code writes nothing to the transcript until the next prompt, F-652, so the log is cut here.)
    func land(afterRewindTo y: ChatYou, code: Bool, keepPrompt: Bool = true) {
        log.cut(from: y.id)
        feedRows = [:]
        if keepPrompt {
            if ui.composer.isEmpty { ui.composer = y.text; ui.composerBasis = y.text }
            let short = y.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? y.text
            let name = short.count > 40 ? String(short.prefix(40)) + "…" : short
            log.append(note: "Rewound to before “\(name)”. \(code ? "Files put back." : "Files are as they were.")", id: "rewound-\(y.id)")
        }
        focusComposer += 1
    }

    /// Esc twice over a prompt that holds text clears it (F-652); used after a rewind whose prompt isn't wanted (a fork
    /// from Claude's reply). If the prompt still holds text, it is left as it is.
    func clearPrompt() async {
        for _ in 0..<2 { terminal?.sendKeys(ChatKey.esc.bytes); await pause(250_000_000) }
        if (reread().input ?? "").isEmpty { ui.composer = ""; ui.composerBasis = nil }
    }
}

/// Fork from a turn (Q-508): a whole fork, then a conversation-only rewind in the copy.
public enum ChatForkPlan: Equatable, Sendable {
    /// From Claude's latest reply: the fork as it is.
    case whole
    /// Rewind the copy to before the prompt with this uuid; `keepPrompt` puts it in the copy's composer (a fork from your message).
    case rewind(promptUuid: String, keepPrompt: Bool)
}

extension ChatSession {
    /// How to fork from the turn `id`, nil when it isn't a turn or the transcript doesn't have what the rewind needs yet.
    /// From your message: the copy rewinds to before it. From Claude's reply: before your next message, and none after the latest.
    public func forkPlan(_ id: String) -> ChatForkPlan? {
        guard let at = log.items.firstIndex(where: { $0.id == id }) else { return nil }
        switch log.items[at] {
        case .you(let y):
            guard !y.queued, let u = y.uuid else { return nil }
            return .rewind(promptUuid: u, keepPrompt: true)
        case .claude:
            for item in log.items[(at + 1)...] {
                if case .you(let y) = item, !y.queued {
                    guard let u = y.uuid else { return nil }
                    return .rewind(promptUuid: u, keepPrompt: false)
                }
            }
            return .whole
        default: return nil
        }
    }

    /// Rewinds to the prompt the transcript calls `uuid` (the fork's log has its own item ids; the uuids are the original's).
    public func rewind(toPromptUuid uuid: String, code: Bool = false, keepPrompt: Bool = true) async -> ChatAnswerResult {
        guard case .you(let y)? = log.items.first(where: { if case .you(let y) = $0 { y.uuid == uuid } else { false } }) else {
            return .refused("the fork doesn’t have that message")
        }
        return await rewind(toPrompt: y.id, code: code, keepPrompt: keepPrompt)
    }
}
