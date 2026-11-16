import AppKit
import SwiftUI

// `/btw` in chat (DL-344; docs/design/btw-in-chat-handoff). Claude Code draws its side question as a panel in the
// prompt's place and writes nothing to the transcript. Chat reads the panel (ChatScreen.side), keeps busy or idle
// underneath it (ChatSession.apply), docks a card in the composer's place while it is up, and remembers the exchange
// as a quiet line that reopens the card (Q-551). Fork… is left out until a run shows what Claude Code's `f` does (Q-577).

/// A side question and its answer, as Duo keeps them while it runs.
public struct ChatSideExchange: Equatable, Sendable {
    public var id: String
    public var question: String
    /// The answer as the screen showed it (plain, wrapped into paragraphs).
    public var screenAnswer = ""
    /// The answer as Claude wrote it: the SubagentStop hook's Markdown, when it came.
    public var hookAnswer: String?
    public var answering = true
    public var opened: Date
    public var closed = false

    /// What the card shows and Copy takes: the hook's Markdown when it came, else the screen's words.
    public var answer: String { hookAnswer ?? screenAnswer }
}

extension ChatLog {
    func sideExchange(_ id: String) -> ChatSideExchange? {
        for case .side(let x) in items where x.id == id { return x }
        return nil
    }

    func updateSide(_ id: String, _ change: (inout ChatSideExchange) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }), case .side(let old) = items[i] else { return }
        var x = old
        change(&x)
        if x != old { items[i] = .side(x) }
    }

    /// A panel for this question came up: its exchange (the same question asked again, or browsed back to, is the same one).
    func sideAsked(question: String, answer: String, answering: Bool, time: Date) -> String {
        if let old = items.compactMap({ item -> ChatSideExchange? in if case .side(let x) = item { x } else { nil } }).last(where: { $0.question == question }) {
            updateSide(old.id) { $0.closed = false; $0.screenAnswer = answer; $0.answering = answering }
            return old.id
        }
        let x = ChatSideExchange(id: newID("side"), question: question, screenAnswer: answer, answering: answering, opened: time)
        items.append(.side(x))
        return x.id
    }

    /// The panel's answer was read again.
    func sideSeen(_ id: String, answer: String, answering: Bool) {
        updateSide(id) { $0.screenAnswer = answer; $0.answering = answering }
    }

    /// The panel closed.
    func sideClosed(_ id: String) { updateSide(id) { $0.closed = true; $0.answering = false } }

    /// A SubagentStop with no start and an empty `agent_type` is the side answer (F-689): its Markdown goes to the
    /// exchange still waiting for one (the newest without), never to an Agent card.
    func sideAnswerArrived(_ message: String?, time: Date?) {
        guard let message, !message.isEmpty,
              let x = items.compactMap({ item -> ChatSideExchange? in if case .side(let x) = item { x } else { nil } }).last(where: { $0.hookAnswer == nil })
        else { return }
        updateSide(x.id) { $0.hookAnswer = message; $0.answering = false }
    }
}

/// What the card draws: a live panel's exchange, or one reopened from Duo's memory.
public struct ChatSideCardModel: Equatable, Sendable {
    public var id: String
    public var question: String
    public var answer: String
    public var answering: Bool
    public var opened: Date
    /// The panel is up in Claude Code (its keys work), or the card shows Duo's memory of it.
    public var live: Bool
    public var history: Int
    public var canClear: Bool
    public var canBrowse: Bool
    public var noAnswer: Bool { answer.hasPrefix("(No answer available") }
}

extension ChatSession {
    /// The card, when there is one to draw.
    public var sideCard: ChatSideCardModel? {
        if let s = screen.side, let id = activeSide, let x = log.sideExchange(id) {
            return ChatSideCardModel(id: id, question: x.question, answer: s.answering ? "" : x.answer, answering: s.answering, opened: x.opened,
                                     live: true, history: s.history, canClear: s.canClear, canBrowse: s.canBrowse)
        }
        if let id = reopenedSide, let x = log.sideExchange(id) {
            return ChatSideCardModel(id: id, question: x.question, answer: x.answer, answering: false, opened: x.opened,
                                     live: false, history: 1, canClear: false, canBrowse: false)
        }
        return nil
    }

    /// The side card takes the composer's place (Q-550).
    public var sideUp: Bool { showsChat && sideCard != nil }

    public func sideShowing(_ id: String) -> Bool { sideCard?.id == id }

    /// Called with every new screen: the exchange follows the panel.
    func trackSide(_ new: ChatSide?) {
        guard let n = new else {
            if let id = activeSide { log.sideClosed(id); activeSide = nil }
            return
        }
        if let id = activeSide, let x = log.sideExchange(id), x.question == n.question {
            log.sideSeen(id, answer: n.answer, answering: n.answering)
        } else {
            if let id = activeSide { log.sideClosed(id) }
            activeSide = log.sideAsked(question: n.question, answer: n.answer, answering: n.answering, time: now)
        }
        reopenedSide = nil
    }

    /// Show on the quiet line: the card from Duo's memory, without asking Claude Code again.
    public func reopenSide(_ id: String) {
        guard screen.side == nil, log.sideExchange(id) != nil else { return }
        reopenedSide = id
    }

    /// Close (Esc): Claude Code's panel, or Duo's reopened card.
    @discardableResult
    public func closeSide() async -> ChatAnswerResult {
        if screen.side == nil { reopenedSide = nil; return .done }
        _ = await press(.esc)
        await pause()
        _ = reread()
        return .done
    }

    /// Typing with the card up closes it and starts your message with what you typed (Q-552).
    public func sideTyped(_ chars: String) {
        Task {
            await closeSide()
            ui.composer += chars
            focusComposer += 1
        }
    }

    /// Copy: the answer's Markdown on Duo's clipboard (Claude Code's own `c` copies its plain text).
    @discardableResult
    public func copySide() -> Bool {
        guard let c = sideCard, !c.answer.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(c.answer, forType: .string)
        return true
    }

    /// `x` on the panel at the prompt: Claude Code forgets this session's side questions.
    public func clearSideHistory() async -> ChatAnswerResult {
        guard reread().side?.canClear == true else { return .refused("Claude Code’s side-question history isn’t up") }
        terminal?.sendKeys("x")
        await pause()
        _ = reread()
        return .done
    }

    /// ⇧← or ⇧→ on the panel at the prompt: an earlier or later side question.
    public func browseSide(by step: Int) async -> ChatAnswerResult {
        guard reread().side?.canBrowse == true else { return .refused("Claude Code’s side-question history isn’t up") }
        terminal?.sendKeys(step < 0 ? "\u{1b}[1;2D" : "\u{1b}[1;2C")
        await pause()
        _ = reread()
        return .done
    }

    /// Asks a side question: `/btw` into Claude Code's prompt, which answers at once, even mid-turn.
    public func askSide(_ question: String) async -> ChatAnswerResult {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return .refused("nothing to ask") }
        return await send("/btw " + q)
    }
}

// MARK: - Views

/// The card in the composer's place (btw-in-chat-handoff `01-where` A, `02-states`).
struct ChatSideCard: View {
    let chat: ChatSession
    let card: ChatSideCardModel
    var copied: Bool { chat.sideCopied }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("SIDE QUESTION · NOT PART OF THE CONVERSATION").duoText(.sectionLabel).foregroundStyle(DuoColor.text2)
                Spacer(minLength: 8)
                if card.live, card.history > 1 { pager }
            }
            Text(card.question).duoText(.bodyEmphasis).foregroundStyle(DuoColor.text).fixedSize(horizontal: false, vertical: true)
            if card.answering {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    HStack(spacing: 8) {
                        StateGlyph(.working)
                        Text("Answering · \(max(0, Int(ctx.date.timeIntervalSince(card.opened))))s").duoText(.chatMeta).foregroundStyle(DuoColor.text2)
                    }
                }
            } else if card.noAnswer {
                Text(card.answer).duoText(.body).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    ChatMarkdownView(blocks: ChatMarkdown.parse(card.answer), streaming: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                if !card.answering, !card.answer.isEmpty, !card.noAnswer {
                    ChatKeyedButton(title: copied ? "Copied" : "Copy", key: copied ? "✓" : "c") {  // action: session chat
                        if chat.copySide() {
                            chat.sideCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { chat.sideCopied = false }
                        }
                    }
                }
                if card.canClear { ChatKeyedButton(title: "Clear history", key: "x") { Task { _ = await chat.clearSideHistory() } } }  // action: session chat
                ChatKeyedButton(title: "Close", key: "esc") { Task { await chat.closeSide() } }  // action: session chat
                Spacer(minLength: 8)
                if card.live { Text("Claude keeps working above").duoText(.control).foregroundStyle(DuoColor.text2).lineLimit(1) }
            }
        }
        .padding(EdgeInsets(top: 15, leading: 17, bottom: 15, trailing: 17))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusReviewCard).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusReviewCard).strokeBorder(DuoColor.controlEdge, lineWidth: DuoMetric.borderHairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Side question: \(card.question)")
    }

    var pager: some View {
        HStack(spacing: 6) {
            Button("‹") { Task { _ = await chat.browseSide(by: -1) } }.buttonStyle(.duo).disabled(!card.canBrowse)  // action: session chat
            Text("\(card.history) of \(card.history)").duoText(.control).foregroundStyle(DuoColor.text2)
            Button("›") { Task { _ = await chat.browseSide(by: 1) } }.buttonStyle(.duo).disabled(!card.canBrowse)  // action: session chat
        }
    }
}

/// The quiet line where you asked: "Side question: … · Show" (btw-in-chat-handoff `03-after`, Q-551 A).
struct ChatSideLine: View {
    let exchange: ChatSideExchange
    let chat: ChatSession

    var body: some View {
        if !chat.sideShowing(exchange.id), !exchange.answering || exchange.closed {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left").font(.system(size: 10)).foregroundStyle(DuoColor.text2)
                Text("Side question: \(exchange.question)").duoText(.chatMeta).foregroundStyle(DuoColor.text2).lineLimit(1).truncationMode(.tail)
                Text("Show").duoText(.chatMeta).underline().foregroundStyle(DuoColor.text2)
                    .onActivate { chat.reopenSide(exchange.id) }  // action: session chat
                    .accessibilityLabel("Show side question")
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
        }
    }
}
