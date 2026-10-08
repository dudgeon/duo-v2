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
    /// Runs opened (DL-135).
    public var openRuns: Set<String> = []
    /// Bash outputs and diffs shown in full.
    public var fullOutput: Set<String> = []
    /// Your long messages shown in full.
    public var fullYou: Set<String> = []
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
    /// `@` in the composer (ENH-3, DL-133): the word after it and its matches (nil: no menu), and
    /// the row selected. Esc closes it until the caret leaves that `@` word.
    public var mention: (query: String, matches: [FileMention.Match])?
    public var mentionSelected = 0
    var mentionDismissedAt: Int?
    /// The link under the pointer, for the status line at the transcript's bottom left (DL-132 g).
    public var hoverLink: URL?
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
                // Only the first offset is SwiftUI's (the end). It no longer re-anchors on size
                // changes: on a lazy stack whose height is an estimate, re-anchoring to the bottom
                // realised other items, their heights moved the estimate, and it re-anchored again,
                // with no Duo code running: 0.2.5 and 0.2.6 froze that way at work (F-225).
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                // A feed shorter than the pane sits at its foot while a card is up (DL-130); this
                // places short content only, so it can't re-anchor a long one.
                .defaultScrollAnchor(chat.cardUp ? .bottom : .top, for: .alignment)
                // New items follow you down only while you're at the bottom; scrolled up, you stay
                // where you are. Only your scrolling decides: the lazy stack re-estimating its height
                // can clamp the offset to the end, which isn't you arriving there. So a change of
                // offset alone decides; one with the height can only say you've left. The history
                // landing (0 → n items) always shows the end. Counted, not compared: comparing every
                // item was a walk of the whole feed per event (F-160).
                .onScrollGeometryChange(for: [CGFloat].self, of: { g in [g.contentOffset.y, g.containerSize.height, g.contentSize.height] }) { old, g in
                    let atBottom = g[0] + g[1] >= g[2] - 60
                    if old.count == 3, old[2] != g[2] || old[1] != g[1] {
                        // Grown or the pane resized while following: back to the end, once, by us
                        // (what the size-change anchor did). Otherwise you've left the end.
                        if chat.followsBottom, !atBottom { follow(proxy) } else if !atBottom { chat.followsBottom = false }
                        return
                    }
                    if old.count == 3, old[0] != g[0] { chat.followsBottom = atBottom }
                }
                .onChange(of: chat.log.items.count) { old, _ in
                    if old == 0 || chat.followsBottom { proxy.scrollTo(ChatPane.bottom, anchor: .bottom) }
                }
                // A card rising in the composer's place (DL-130): the feed gives way, still at its end.
                .onChange(of: chat.cardUp || chat.pickerUp) { if chat.followsBottom { follow(proxy) } }
                .onChange(of: chat.revealRequest) { if let id = chat.revealRequest { withAnimation { proxy.scrollTo(id, anchor: .top) } } }
                // A link's target under the pointer, as Safari shows one (DL-132 g, q57-link-status).
                .background(ChatLinkHover { chat.ui.hoverLink = $0 })
                .overlay(alignment: .bottomLeading) {
                    if let url = chat.ui.hoverLink { ChatLinkStatus(text: ChatLinkWords.words(url)) }
                }
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
            } else if chat.pickerUp, let p = chat.screen.picker {
                // `/model` and `/effort` (DL-143): a card in the composer's place, as a review card.
                ChatPickerCard(chat: chat, picker: p)
                    .padding(EdgeInsets(top: 0, leading: DuoSpace.chatColumnInset, bottom: 14, trailing: DuoSpace.chatColumnInset))
                    .zIndex(1)
                    .transition(.move(edge: .bottom))
            } else {
                ChatComposerArea(chat: chat)
                    .padding(EdgeInsets(top: 0, leading: DuoSpace.chatColumnInset, bottom: 12, trailing: DuoSpace.chatColumnInset))
                    .transition(.opacity)
            }
        }
        .animation((chat.cardUp ? DuoMotionToken.cardIn : .cardOut).animation, value: chat.cardUp)
        .animation((chat.pickerUp ? DuoMotionToken.cardIn : .cardOut).animation, value: chat.pickerUp)
        .background(DuoColor.chatGround)
        .tint(DuoColor.text)
        .onAppear { model.installChatKeys() }
        .environment(\.openURL, OpenURLAction { url in
            model.openChatLink(url, cwd: chat.log.cwd)
            return .handled
        })
    }

    static let bottom = "chat-bottom"

    /// Back to the end of the feed, at most once per turn of the run loop, and never more than 20
    /// times in a second: content that keeps changing size can't scroll it for ever (F-225). Past
    /// that, the feed stops following until you scroll to the end.
    func follow(_ proxy: ScrollViewProxy) {
        guard !chat.followPending else { return }
        let now = Date()
        chat.follows = chat.follows.filter { now.timeIntervalSince($0) < 1 } + [now]
        if chat.follows.count > 20 {
            chat.followsBottom = false
            chat.follows = []
            FileHandle.standardError.write(Data("chat: \(chat.key) kept changing size; stopped following the end (F-225)\n".utf8))
            return
        }
        chat.followPending = true
        DispatchQueue.main.async {
            chat.followPending = false
            proxy.scrollTo(ChatPane.bottom, anchor: .bottom)
        }
    }
}

/// One transcript entry.
struct ChatItemView: View {
    let item: ChatItem
    let chat: ChatSession

    var body: some View {
        switch item {
        case .you(let y): ChatYouBubble(you: y, chat: chat)
        case .claude(let t): ChatClaudeCard(turn: t, chat: chat)
        case .answer(let n): ChatAnswerReply(note: n)
        case .note(let n): ChatQuietLine(text: n.text)
        case .divider(let n): ChatDivider(text: n.text)
        case .interrupted(let n): ChatInterruptedLine(text: n.text)
        case .result(let r): ChatResultView(result: r, chat: chat)
        }
    }
}

// MARK: - Yours

/// Your message: right-aligned, `chatYou`, at most 440 wide, its bottom-right corner sharp. Your
/// Markdown is rendered.
struct ChatYouBubble: View {
    let you: ChatYou
    let chat: ChatSession
    /// Over 12 lines, the first 8 and `Show all n lines` (DL-135, handoff `paste`).
    static let longer = 12, shown = 8

    var body: some View {
        let lines = you.text.components(separatedBy: "\n")
        let cut = lines.count > Self.longer && !chat.ui.fullYou.contains(you.id)
        VStack(alignment: .trailing, spacing: 4) {
            if !you.queued { ChatWho(who: "You", time: you.time, tag: you.planMode ? "plan mode" : nil) }
            // The bubble hugs its text, at most 440 (chat-mode-handoff `text`, `composer`; F-184).
            ChatHug(maxWidth: DuoSpace.chatBubbleMax, content: you.text.hashValue ^ (cut ? 1 : 0)) {
                VStack(alignment: .leading, spacing: 6) {
                    ChatMarkdownView(blocks: ChatMarkdown.parse(cut ? lines.prefix(Self.shown).joined(separator: "\n") : you.text), streaming: false)
                    if cut {
                        Text("Show all \(lines.count) lines").duoText(.chatMeta).foregroundStyle(DuoColor.text).underline(color: DuoColor.controlEdge)
                            .onActivate { chat.ui.fullYou.insert(you.id) }  // not an action: shows more of what's drawn
                    }
                }
                .padding(EdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 14))
                .background(UnevenRoundedRectangle(cornerRadii: DuoMetric.radiusChatBubble).fill(DuoColor.chatYou))
            }
            .opacity(you.queued ? 0.6 : 1)
            if you.queued { Text("Queued · Claude reads it when it’s ready").duoText(.chatMeta).foregroundStyle(DuoColor.text2) }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You: \(you.text)")
    }
}

/// Its content at its own width, at most `maxWidth` (and what's offered): a bubble that hugs short
/// text and wraps long text at the cap. Markdown's views take all the width offered, so the
/// content is asked its ideal width first, then offered just that (F-184).
struct ChatHug: Layout {
    var maxWidth: CGFloat
    /// What the bubble shows (its text, and whether it is cut): a change re-measures (F-208).
    var content: Int

    /// The content's ideal width, measured once and kept until the content or the layout changes:
    /// it was measured afresh on every pass, twice per bubble (F-208).
    struct Cache { var ideal: CGFloat? }
    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func width(_ proposal: ProposedViewSize, _ s: Subviews, _ cache: inout Cache) -> CGFloat {
        let ideal = cache.ideal ?? s.first?.sizeThatFits(.unspecified).width ?? 0
        cache.ideal = ideal
        return ceil(min(ideal, maxWidth, proposal.width ?? .infinity))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews s: Subviews, cache: inout Cache) -> CGSize {
        let w = width(proposal, s, &cache)
        return CGSize(width: w, height: s.first?.sizeThatFits(ProposedViewSize(width: w, height: nil)).height ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews s: Subviews, cache: inout Cache) {
        s.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
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
                // Runs fold to one line (DL-135); consecutive thread rows share one dotted thread.
                let blocks = ChatRuns.blocks(turn.segments)
                let lastAsked = blocks.last { if case .asked = $0 { return true } else { return false } }?.id
                ForEach(Self.sections(blocks), id: \.first!.id) { section in
                    if section.first!.onThread {
                        ChatThread(blocks: section, chat: chat)
                    } else {
                        switch section.first! {
                        case .thinking(let id, let secs): ChatThinkingRow(id: id, seconds: secs, chat: chat)
                        case .text(let t): ChatMarkdownView(blocks: ChatMarkdown.parse(t.markdown), streaming: t.streaming, faded: t.cut)
                        case .asked(let id, let qs):
                            // While the question is up, its card shows it; the list stays once it closes.
                            if !(chat.cardUp && [.question, .questionReview].contains(chat.screen.kind) && id == lastAsked) {
                                ChatAskedBox(questions: qs)
                            }
                        default: EmptyView()
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

    /// Thread rows in a row go together; everything else stands alone.
    static func sections(_ blocks: [ChatCardRow]) -> [[ChatCardRow]] {
        var out: [[ChatCardRow]] = []
        for b in blocks {
            if b.onThread, let last = out.last?.last, last.onThread { out[out.count - 1].append(b) } else { out.append([b]) }
        }
        return out
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

/// The status line for a link under the pointer (DL-132 g, q57-link-status): `pane` with a `rule`
/// on its top and right, 12/16, at the transcript's bottom left. No fade (as the hover × and +).
struct ChatLinkStatus: View {
    let text: String
    var body: some View {
        Text(text).duoText(.control).foregroundStyle(DuoColor.text).lineLimit(1).truncationMode(.middle)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(UnevenRoundedRectangle(topTrailingRadius: DuoMetric.radiusControl).fill(DuoColor.pane))
            .overlay(UnevenRoundedRectangle(topTrailingRadius: DuoMetric.radiusControl).stroke(DuoColor.rule, lineWidth: DuoMetric.borderHairline).padding(.leading, -2).padding(.bottom, -2))
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Finds the link under the pointer in the transcript. Selectable `Text` is an AppKit text field
/// (F-159) and SwiftUI says nothing about which run is hovered, so a mouse-moved monitor finds the
/// field under the pointer, lays its string out as the field draws it and reads `.link` there.
struct ChatLinkHover: NSViewRepresentable {
    let changed: @MainActor (URL?) -> Void

    func makeNSView(context: Context) -> Probe { let v = Probe(); v.changed = changed; return v }
    func updateNSView(_ v: Probe, context: Context) { v.changed = changed }
    static func dismantleNSView(_ v: Probe, coordinator: ()) { v.stop() }

    final class Probe: NSView {
        var changed: (@MainActor (URL?) -> Void)?
        private var monitor: Any?
        private var last: URL?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            window.acceptsMouseMovedEvents = true
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseExited, .scrollWheel]) { [weak self] e in
                MainActor.assumeIsolated { self?.look(e) }
                return e
            }
        }

        func stop() { if let m = monitor { NSEvent.removeMonitor(m) }; monitor = nil }

        private func look(_ e: NSEvent) {
            guard let window, e.window === window else { return }
            let p = e.locationInWindow
            var url: URL?
            if bounds.contains(convert(p, from: nil)) { url = Self.link(in: window, at: p) }
            if url != last { last = url; changed?(url) }
        }

        /// The link under a point of the window (in window coordinates), if any.
        static func link(in window: NSWindow, at p: NSPoint) -> URL? {
            guard let hit = window.contentView?.hitTest(p) else { return nil }
            var v: NSView? = hit
            while let x = v, !(x is NSTextField) { v = x.superview }
            guard let field = v as? NSTextField else { return nil }
            return link(in: field, at: field.convert(p, from: nil))
        }

        /// The `.link` at a point in a text field, laid out at the field's width.
        static func link(in field: NSTextField, at p: NSPoint) -> URL? {
            let s = field.attributedStringValue
            guard s.length > 0 else { return nil }
            let storage = NSTextStorage(attributedString: s)
            let layout = NSLayoutManager()
            let container = NSTextContainer(size: NSSize(width: field.bounds.width, height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            storage.addLayoutManager(layout)
            let y = field.isFlipped ? p.y : field.bounds.height - p.y
            var fraction: CGFloat = 0
            let i = layout.characterIndex(for: NSPoint(x: p.x, y: y), in: container, fractionOfDistanceBetweenInsertionPoints: &fraction)
            guard i < s.length else { return nil }
            let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: i, length: 1), actualCharacterRange: nil)
            guard layout.boundingRect(forGlyphRange: glyphs, in: container).insetBy(dx: -1, dy: -1).contains(NSPoint(x: p.x, y: y)) else { return nil }
            switch s.attribute(.link, at: i, effectiveRange: nil) {
            case let u as URL: return u
            case let t as String: return URL(string: t)
            default: return nil
            }
        }
    }
}

/// The status line's words for a link (DL-132 g).
public enum ChatLinkWords {
    /// "Open flows.md at line 42 in Duo" for a file link; a web link's address.
    public static func words(_ url: URL) -> String {
        guard url.scheme == "duo-file" else { return url.absoluteString }
        let c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let line = c?.queryItems?.first { $0.name == "line" }?.value
        let name = ((c?.path ?? url.path) as NSString).lastPathComponent   // duo-file:docs/x.md is opaque: url.path is empty
        return "Open \(name)\(line.map { " at line \($0)" } ?? "") in Duo"
    }
}
