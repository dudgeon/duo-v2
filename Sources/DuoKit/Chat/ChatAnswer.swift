import Foundation

// Answering the TUI with keys (DL-118 §2, F-104, F-106). A card never sends a key list: it says
// what the human chose (an intent), and this steers the real TUI there one key at a time,
// re-reading the screen after every key, and stops at the first surprise. Before anything is
// sent the screen is re-read: the same dialog must still be up, on a verified CLI, and agree with
// Claude's request. Hooks never answer anything.

/// What the human chose on an AskUserQuestion card (the spike's `ask.mjs` intents).
public enum ChatAskIntent: Equatable, Sendable {
    /// Single-select: move to the option, Enter (moves on or submits).
    case pick(String)
    /// Multi-select: move to the option, Space.
    case toggle(String)
    /// The free-text row: replace its text; Enter on single-select (multi ticks itself).
    case other(String)
    /// Multi-select: Enter on the Next/Submit row under the list.
    case next
    /// Go to question `index` (0-based), or the review page (= the number of questions).
    case tab(Int)
    /// Preview layout: move to the option, n, type, Enter.
    case notes(String, String)
    /// Chat about this.
    case chat
    case submit, cancelReview, decline
}

/// An answer's outcome. A refusal sends nothing more and shows the terminal with `why`.
public struct ChatAnswerResult: Equatable, Sendable {
    public var ok: Bool
    public var why: String?
    public static let done = ChatAnswerResult(ok: true, why: nil)
    public static func refused(_ why: String) -> ChatAnswerResult { ChatAnswerResult(ok: false, why: why) }
}

extension ChatSession {
    /// The pace between keys: 80 ms were all taken in the spike (issue #38299 drops faster keys).
    static var keyPause: UInt64 { 120_000_000 }

    func pause(_ ns: UInt64 = ChatSession.keyPause) async { try? await Task.sleep(nanoseconds: ns) }

    func press(_ k: ChatKey) async -> ChatScreen {
        terminal?.sendKeys(k.bytes)
        await pause()
        return reread()
    }

    /// The re-check every answer starts with.
    func checkBeforeSending(_ sig: String, kinds: Set<ChatScreen.Kind>) -> ChatAnswerResult? {
        guard terminal != nil else { return .refused("the terminal isn't running") }
        let s = reread()
        guard dialogsVerified else { return .refused("chat mode hasn’t been checked with this version of Claude Code’s dialogs") }
        guard kinds.contains(s.kind) else { return .refused("the terminal is showing something else now") }
        guard s.sig == sig else { return .refused("the question changed before your answer arrived") }
        return nil
    }

    /// A permission or plan option, by its number, as the TUI takes it: its digit. The label must
    /// still be the one the card showed.
    public func answerOption(_ n: Int, label: String, sig: String) async -> ChatAnswerResult {
        if let r = checkBeforeSending(sig, kinds: [.permission, .plan]) { return finish(r) }
        guard let o = screen.options.first(where: { $0.n == n }), o.label.chatNorm == label.chatNorm else {
            return finish(.refused("that option isn’t on Claude Code’s screen any more"))
        }
        let what = screen.kind == .plan ? "the plan" : requestSummary
        sending = true
        defer { sending = false }
        terminal?.sendKeys(String(n))
        await pause()
        log.answer("You chose **\(n)** · **\(label)**" + (what.map { " for \($0)" } ?? ""), time: now)
        log.permissionResolved()
        _ = reread()
        return .done
    }

    /// Cancel (esc), or Decline (esc) on a question.
    public func cancelDialog(sig: String) async -> ChatAnswerResult {
        if let r = checkBeforeSending(sig, kinds: [.permission, .plan, .question, .questionReview]) { return finish(r) }
        let wasQuestion = screen.kind == .question || screen.kind == .questionReview
        sending = true
        defer { sending = false }
        _ = await press(.esc)
        if wasQuestion { lastDeclined = "You declined Claude’s questions"; log.answer("You declined Claude’s questions", time: now) }
        log.permissionResolved()
        return .done
    }

    /// Plan option 3, "Tell Claude what to change": arrows to it one at a time, the feedback typed, Enter.
    public func planFeedback(_ text: String, sig: String) async -> ChatAnswerResult {
        if let r = checkBeforeSending(sig, kinds: [.plan]) { return finish(r) }
        guard let target = screen.options.firstIndex(where: { $0.label.hasPrefix("Tell Claude what to change") }) else {
            return finish(.refused("Claude Code’s plan dialog has no “Tell Claude what to change” here"))
        }
        sending = true
        defer { sending = false }
        var s = screen
        for _ in 0..<8 {
            guard s.kind == .plan, let cur = s.options.firstIndex(where: { $0.cursor }) else { return finish(.refused("lost the plan dialog's cursor")) }
            if cur == target { break }
            s = await press(cur < target ? .down : .up)
        }
        guard s.options.firstIndex(where: { $0.cursor }) == target else { return finish(.refused("couldn’t reach “Tell Claude what to change”")) }
        terminal?.sendKeys(text)
        await pause(200_000_000)
        _ = await press(.enter)
        log.answer("You asked Claude to change the plan: \(text)", time: now)
        return .done
    }

    /// The pending request in words, for `You chose …` (`the edit to prd-v2.md`).
    var requestSummary: String? {
        guard let r = pendingRequest else { return nil }
        let file = (r.input["file_path"] as? String).map { ($0 as NSString).lastPathComponent }
        switch r.tool {
        case "Edit", "MultiEdit": return file.map { "the edit to \($0)" }
        case "Write": return file.map { "writing \($0)" }
        case "Bash": return (r.input["command"] as? String).map { "`\($0.count > 60 ? String($0.prefix(59)) + "…" : $0)`" }
        default: return r.tool.isEmpty ? nil : r.tool
        }
    }

    /// A refusal shows the terminal and says why (fallback rule 4).
    @discardableResult
    func finish(_ r: ChatAnswerResult) -> ChatAnswerResult {
        if !r.ok, let why = r.why {
            fallBack(.automatic("Chat mode didn’t send your answer: \(why). Here’s the terminal; chat comes back when it’s done."))
        }
        return r
    }

    // MARK: AskUserQuestion (F-106; the spike's ask.mjs)

    /// The asked questions, from the PermissionRequest.
    public var askedQuestions: [ChatJSON] {
        guard let r = pendingRequest, r.tool == "AskUserQuestion" else { return [] }
        return r.input["questions"] as? [ChatJSON] ?? []
    }

    /// Which asked question the screen shows: its visible text must be the end of exactly one of
    /// them (a short terminal scrolls a long question's top away).
    public func questionIndex(_ s: ChatScreen) -> Int? {
        if s.kind == .questionReview { return askedQuestions.count }
        guard s.kind == .question, let shown = s.question?.chatNorm else { return nil }
        let hits = askedQuestions.enumerated().filter { _, q in
            let asked = (q["question"] as? String ?? "").chatNorm
            return asked == shown || (shown.count >= 20 && asked.hasSuffix(shown))
        }
        return hits.count == 1 ? hits[0].offset : nil
    }

    public func ask(_ intent: ChatAskIntent, sig: String?) async -> ChatAnswerResult {
        finish(await runAsk(intent, sig: sig))
    }

    func runAsk(_ intent: ChatAskIntent, sig: String?) async -> ChatAnswerResult {
        guard terminal != nil else { return .refused("the terminal isn't running") }
        var s = reread()
        guard dialogsVerified else { return .refused("chat mode hasn’t been checked with this version of Claude Code’s dialogs") }
        if let sig, s.sig != sig { return .refused("the question changed before your answer arrived") }
        guard s.kind == .question || s.kind == .questionReview else { return .refused("the terminal shows \(s.kind.rawValue), not a question") }
        let qs = askedQuestions
        guard !qs.isEmpty else { return .refused("no question is pending from Claude") }
        // The screen and the request tell the same story: the question is one Claude asked, and
        // each visible label is the start of the asked label in the same place.
        guard let qIndex = questionIndex(s) else { return .refused("the question on screen is not the one Claude asked") }
        if s.kind == .question {
            let asked = (qs[qIndex]["options"] as? [ChatJSON] ?? []).map { ($0["label"] as? String ?? "").chatNorm }
            let shown = s.options.map { $0.label.chatNorm }
            guard asked.count == shown.count, zip(asked, shown).allSatisfy({ $0.hasPrefix($1) && !$1.isEmpty }) else {
                return .refused("the options on screen differ from what Claude asked")
            }
        }
        sending = true
        defer { sending = false }
        // The review page reads as its own kind; give it rows so moving works there too.
        func rows(_ s: ChatScreen) -> [ChatScreenRow] { s.rows }
        let step: (ChatKey) async -> Void = { k in s = await self.press(k) }
        func optionRow(_ label: String) -> (ChatScreenRow) -> Bool {
            let i = (qs[self.questionIndex(s) ?? qIndex]["options"] as? [ChatJSON] ?? []).firstIndex { ($0["label"] as? String ?? "").chatNorm == label.chatNorm }
            return { r in r.kind == .option && s.options.firstIndex(of: r) == i }
        }
        // Moves the cursor to the first row matching `want`, one arrow at a time.
        func goTo(_ want: (ChatScreenRow) -> Bool) async -> Bool {
            for _ in 0..<16 {
                guard s.kind == .question || s.kind == .questionReview else { return false }
                guard let target = rows(s).firstIndex(where: want) else { return false }
                let cur = s.cursor
                if cur == target { return true }
                if cur < 0 { return false }
                await step(target > cur ? .down : .up)
            }
            return false
        }
        switch intent {
        case .pick(let label), .toggle(let label):
            let toggling: Bool = { if case .toggle = intent { return true }; return false }()
            guard s.kind == .question else { return .refused("not on a question") }
            guard toggling == s.multi else { return .refused(s.multi ? "this question takes several answers" : "this question takes one answer") }
            guard await goTo(optionRow(label)) else { return .refused("couldn’t reach “\(label)”") }
            await step(toggling ? .space : .enter)
            return .done
        case .other(let text):
            guard s.kind == .question, let other = s.other else { return .refused("this question has no free-text answer") }
            guard await goTo({ $0.kind == .other }) else { return .refused("couldn’t reach the free-text row") }
            for _ in (other.value ?? "") { terminal?.sendKeys(ChatKey.backspace.bytes); await pause(40_000_000) }
            terminal?.sendKeys(text)
            await pause(200_000_000)
            s = reread()
            guard s.kind == .question, s.other?.value?.chatNorm == text.chatNorm else { return .refused("the typed answer did not appear as sent") }
            if !s.multi { await step(.enter) }
            return .done
        case .next:
            guard s.kind == .question, s.multi else { return .refused("Next is for multi-select questions") }
            guard await goTo({ $0.kind == .next || $0.kind == .submit }) else { return .refused("couldn’t reach Next") }
            await step(.enter)
            return .done
        case .tab(let index):
            // ← and → move between questions, but not from inside the free-text row (they move its caret).
            for _ in 0..<10 {
                guard let here = questionIndex(s) else { return .refused("lost track of the questions") }
                if here == index { return .done }
                if s.kind == .question, s.cursor >= 0, s.rows[s.cursor].kind == .other { await step(.up) }
                await step(index > here ? .right : .left)
            }
            return .refused("couldn’t reach that question")
        case .notes(let label, let text):
            guard s.kind == .question, s.preview else { return .refused("notes are for questions with previews") }
            guard await goTo(optionRow(label)) else { return .refused("couldn’t reach “\(label)”") }
            await step(.n)
            terminal?.sendKeys(text)
            await pause(200_000_000)
            s = reread()
            guard s.notes?.chatNorm == text.chatNorm else { return .refused("the notes did not appear as typed") }
            // Return inside the notes field sends them with no option on 2.1.219 ("(notes only)"). Esc leaves the
            // field with the notes kept and the cursor on the option; Return there sends both (same on 2.1.296).
            await step(.esc)
            guard s.kind == .question, s.preview, s.notes?.chatNorm == text.chatNorm, await goTo(optionRow(label)) else { return .refused("couldn’t leave the notes on “\(label)”") }
            await step(.enter)
            return .done
        case .chat:
            guard await goTo({ $0.kind == .chat }) else { return .refused("no “Chat about this” here") }
            await step(.enter)
            lastDeclined = "You chose to chat about these questions"
            log.answer("You chose to chat about these questions", time: now)
            return .done
        case .submit, .cancelReview:
            guard s.kind == .questionReview else { return .refused("not on the review page") }
            let label = intent == .submit ? "Submit answers" : "Cancel"
            guard await goTo({ $0.label == label }) else { return .refused("couldn’t reach “\(label)”") }
            await step(.enter)
            if intent == .cancelReview { lastDeclined = "You declined Claude’s questions"; log.answer("You declined Claude’s questions", time: now) }
            return .done
        case .decline:
            await step(.esc)
            lastDeclined = "You declined Claude’s questions"
            log.answer("You declined Claude’s questions", time: now)
            return .done
        }
    }
}
