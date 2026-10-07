import AppKit
import SwiftUI

// The chat pane (chat-mode-handoff `window`, `text`, `tools`, `status`): the transcript on
// `chatGround`, your messages on the right in `chatYou`, Claude's replies on white cards with
// their tool steps on a dotted thread, the composer at the bottom (or a review card docked in its
// place while Claude waits on you). Native SwiftUI, not a web view (F-109).

/// What the chat's reader has open or closed: folds, long outputs, thinking.
@MainActor
@Observable
public final class ChatUIState {
    /// Steps opened (folded ones) or closed (open ones) by a click.
    public var toggled: Set<String> = []
    /// Bash outputs shown in full.
    public var fullOutput: Set<String> = []
    public var thinkingOpen: Set<String> = []
    /// Plan option 3's feedback, the free-text answers by question, a preview's notes.
    public var planFeedback = ""
    public var other: [Int: String] = [:]
    public var notes = ""
    /// The composer's text, and what Claude's prompt held when the composer opened on it (nil:
    /// not opened on it yet; the screen's input is the basis).
    public var composer = ""
    public var composerBasis: String?
    public var composerFocused = false
    public init() {}
}

struct ChatPane: View {
    @Environment(AppModel.self) private var model
    let chat: ChatSession

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        // Q-56c's stand-in: the last 50 turns, and more on request.
                        if chat.log.earlierHidden {
                            Text("Earlier turns").duoText(.chatMeta).foregroundStyle(DuoColor.text).underline(color: DuoColor.controlEdge)
                                .frame(maxWidth: .infinity)
                                .onActivate { chat.loadEarlier() }  // not an action: shows more of the transcript
                        }
                        // A new item (your prompt, a tool card, Claude's reply) fades in where it lands
                        // (`messageIn`, DL-130); streaming text grows in place, unanimated.
                        ForEach(chat.log.items) { item in
                            ChatItemView(item: item, chat: chat).id(item.id).transition(.opacity)
                        }
                        ChatWorkingLine(chat: chat)
                    }
                    .duoAnimation(.messageIn, value: chat.log.items.count)
                    .padding(EdgeInsets(top: 18, leading: DuoSpace.chatColumnInset, bottom: 12, trailing: DuoSpace.chatColumnInset))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id(ChatPane.bottom)
                }
                .defaultScrollAnchor(chat.cardUp ? .bottom : .top, for: .alignment)
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
                .onChange(of: chat.log.items) { proxy.scrollTo(ChatPane.bottom, anchor: .bottom) }
                .onChange(of: chat.revealRequest) { if let id = chat.revealRequest { withAnimation { proxy.scrollTo(id, anchor: .top) } } }
            }
            if chat.cardUp {
                // While Claude waits on you, the review card takes the composer's place (DL-119 §3).
                // It rises out of the composer's place (`cardIn`) and sinks back once Claude has the
                // answer (`cardOut`); the feed above gives way and stays pinned to the bottom (DL-130).
                ChatReviewCard(chat: chat)
                    .padding(EdgeInsets(top: 0, leading: 16, bottom: 14, trailing: 16))
                    // Opaque and above the composer while it moves, so their text never overprints.
                    .zIndex(1)
                    .transition(.move(edge: .bottom))
            } else {
                ChatComposerArea(chat: chat)
                    .padding(EdgeInsets(top: 0, leading: DuoSpace.chatColumnInset, bottom: 12, trailing: DuoSpace.chatColumnInset))
                    .transition(.opacity)
            }
        }
        .animation((chat.cardUp ? DuoMotionToken.cardIn : .cardOut).animation, value: chat.cardUp)
        .background(DuoColor.chatGround)
        .tint(DuoColor.text)
        .onAppear { model.installChatKeys() }
        .environment(\.openURL, OpenURLAction { url in
            model.openChatLink(url, cwd: chat.log.cwd)
            return .handled
        })
    }

    static let bottom = "chat-bottom"
}

/// One transcript entry.
struct ChatItemView: View {
    let item: ChatItem
    let chat: ChatSession

    var body: some View {
        switch item {
        case .you(let y): ChatYouBubble(you: y)
        case .claude(let t): ChatClaudeCard(turn: t, chat: chat)
        case .answer(let n): ChatAnswerReply(note: n)
        case .note(let n): ChatQuietLine(text: n.text)
        case .divider(let n): ChatDivider(text: n.text)
        case .interrupted(let n): ChatInterruptedLine(text: n.text)
        }
    }
}

// MARK: - Yours

/// Your message: right-aligned, `chatYou`, at most 440 wide, its bottom-right corner sharp. Your
/// Markdown is rendered.
struct ChatYouBubble: View {
    let you: ChatYou

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if !you.queued { ChatWho(who: "You", time: you.time, tag: you.planMode ? "plan mode" : nil) }
            ChatMarkdownView(blocks: ChatMarkdown.parse(you.text), streaming: false)
                .padding(EdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 14))
                .background(UnevenRoundedRectangle(cornerRadii: DuoMetric.radiusChatBubble).fill(DuoColor.chatYou))
                .opacity(you.queued ? 0.6 : 1)
                .frame(maxWidth: DuoSpace.chatBubbleMax, alignment: .trailing)
                .fixedSize(horizontal: false, vertical: true)
            if you.queued { Text("Queued · Claude reads it when it’s ready").duoText(.chatMeta).foregroundStyle(DuoColor.text2) }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You: \(you.text)")
    }
}

/// The questions Claude asked, in its card: `Platforms · Which platforms …?`.
struct ChatAskedBox: View {
    let questions: [ChatAsked]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(questions.enumerated()), id: \.offset) { _, q in
                Text("\(Text(q.header).fontWeight(.semibold).foregroundStyle(DuoColor.text))\(Text(" · " + q.question).foregroundStyle(DuoColor.text2))")
                    .duoText(.body).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody).strokeBorder(DuoColor.selected, lineWidth: DuoMetric.borderHairline))
    }
}

/// Your answer to a review card, as a small reply of yours (`✓ You chose 1 · Yes for …`).
struct ChatAnswerReply: View {
    let note: ChatNote
    var body: some View {
        HStack(spacing: 8) {
            if note.text.hasPrefix("You chose **") {
                Checkmark().stroke(DuoColor.text, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)).frame(width: 10, height: 8)
            }
            Text(ChatInlineText.styled(note.text, style: .body)).duoText(.body).foregroundStyle(DuoColor.text)
        }
            .padding(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
            .background(UnevenRoundedRectangle(cornerRadii: DuoMetric.radiusChatBubble).fill(DuoColor.chatYou))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// `You · 9:41`, `Claude · 9:42`.
struct ChatWho: View {
    let who: String
    let time: Date?
    var tag: String?

    var body: some View {
        Text([who, time.map { ChatWho.clock.string(from: $0) }, tag].compactMap { $0 }.joined(separator: " · "))
            .duoText(.chatMeta).foregroundStyle(DuoColor.text2)
    }

    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f
    }()
}

// MARK: - Status lines (handoff `status`)

struct ChatQuietLine: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Checkmark().stroke(DuoColor.text2, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)).frame(width: 10, height: 8)
            Text(text).duoText(.chatMeta).foregroundStyle(DuoColor.text2)
        }
        .frame(maxWidth: .infinity)
    }
}

struct Checkmark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: r.minX, y: r.midY)); p.addLine(to: .init(x: r.minX + r.width * 0.38, y: r.maxY)); p.addLine(to: .init(x: r.maxX, y: r.minY))
        return p
    }
}

struct ChatDivider: View {
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            DuoColor.rule.frame(height: DuoMetric.borderHairline)
            Text(text).duoText(.chatMeta).foregroundStyle(DuoColor.text2).fixedSize()
            DuoColor.rule.frame(height: DuoMetric.borderHairline)
        }
    }
}

struct ChatInterruptedLine: View {
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Text("Interrupted").duoText(.chatMeta, weight: .semibold).foregroundStyle(DuoColor.text)
            Text("· " + text).duoText(.chatMeta).foregroundStyle(DuoColor.text2)
        }
    }
}

/// Under the last card while Claude works: `○ Writing · 14s · Esc to interrupt`, or Claude Code's
/// own retry status (`529 Overloaded · Retrying in 2s · attempt 4/10`).
struct ChatWorkingLine: View {
    let chat: ChatSession

    var body: some View {
        if currentText != nil {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack(spacing: 8) {
                    StateGlyph(.working)
                    Text(currentText ?? "").duoText(.chatMeta).foregroundStyle(DuoColor.text2)
                }
                .padding(.leading, 4)
            }
        }
    }

    var currentText: String? {
        let s = chat.screen
        if let status = s.status, s.kind == .busy, status.contains("Retrying") {
            return status.replacingOccurrences(of: #"^[✻✽✶✳✢·*]\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: " (mock)", with: "")
        }
        guard s.kind == .busy || chat.log.writing else { return nil }
        let secs = chat.log.turnStarted.map { max(0, Int(chat.now.timeIntervalSince($0))) }
        let verb = chat.log.writing ? "Writing" : "Working"
        return [verb, secs.map { "\($0)s" }, "Esc to interrupt"].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Claude's card

struct ChatClaudeCard: View {
    let turn: ChatTurn
    let chat: ChatSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ChatWho(who: "Claude", time: turn.time)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(turn.segments) { seg in
                    switch seg {
                    case .thinking(let id, let secs, _): ChatThinkingRow(id: id, seconds: secs, chat: chat)
                    case .tools(_, let steps): ChatToolThread(steps: steps, chat: chat)
                    case .text(let t): ChatMarkdownView(blocks: ChatMarkdown.parse(t.markdown), streaming: t.streaming, faded: t.cut)
                    case .asked(_, let qs):
                        // While the question is up, its card shows it; the list stays once it closes.
                        if !(chat.cardUp && [.question, .questionReview].contains(chat.screen.kind) && seg.id == turn.segments.last(where: { if case .asked = $0 { return true }; return false })?.id) {
                            ChatAskedBox(questions: qs)
                        }
                    }
                }
            }
            .padding(EdgeInsets(top: 14, leading: 18, bottom: 16, trailing: 18))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(UnevenRoundedRectangle(cornerRadii: DuoMetric.radiusChatCard).fill(DuoColor.pane))
        }
        .padding(.trailing, DuoSpace.chatCardTrailing)
    }
}

/// `› Thought for 6s`, folded; a click shows what's there (often redacted).
struct ChatThinkingRow: View {
    let id: String
    let seconds: Int?
    let chat: ChatSession

    var body: some View {
        HStack(spacing: 6) {
            Text(chat.ui.thinkingOpen.contains(id) ? "⌄" : "›")
            Text(seconds.map { "Thought for \($0)s" } ?? "Thought")
        }
        .duoText(.chatMeta).foregroundStyle(DuoColor.text2)
        .contentShape(Rectangle())
        .onActivate { chat.ui.thinkingOpen.formSymmetricDifference([id]) }  // not an action: a fold
        .accessibilityLabel(seconds.map { "Thought for \($0) seconds" } ?? "Thought")
    }
}

/// The composer's look until it works (phase 4): Claude's prompt as a field.
struct ChatComposerStandIn: View {
    var body: some View {
        Text("Reply to Claude").duoText(.chatBody).foregroundStyle(DuoColor.text2)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
            .background(RoundedRectangle(cornerRadius: DuoMetric.radiusComposer).fill(DuoColor.pane))
            .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusComposer).strokeBorder(DuoColor.controlEdge, lineWidth: DuoMetric.borderHairline))
    }
}
