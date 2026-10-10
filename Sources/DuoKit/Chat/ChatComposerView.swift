import AppKit
import SwiftUI

// The composer (chat-mode-handoff `composer`): Claude's own prompt in a native field. Return sends,
// ⇧Return adds a line; files dropped in go in as their full paths (DL-117) and show by name; `/`
// opens Claude Code's own command list; `@` offers the project's files and folders (DL-133); while Claude works a sent message waits as Queued and Stop
// (esc) sits beside the field. Under it: the mode chip (a click cycles it, as Shift+Tab does), the
// hints and the model.

struct ChatComposerArea: View {
    @Environment(AppModel.self) private var model
    let chat: ChatSession

    var body: some View {
        let s = chat.screen
        VStack(alignment: .leading, spacing: 6) {
            if chat.commandMenuShown {
                ChatCommandMenu(chat: chat, commands: s.commands)
            } else if let m = chat.ui.mention {
                ChatMentionMenu(chat: chat, query: m.query, matches: m.matches)
            }
            HStack(alignment: .bottom, spacing: 10) {
                let focused = chat.ui.composerFocused
                // Pictures sit in a row above the text, inside the field; the text's own inset leaves the 8 between.
                VStack(alignment: .leading, spacing: -2.5) {
                    if !chat.ui.attachedTokens.isEmpty || chat.ui.addingPicture {
                        ChatPictureRow(chat: chat).padding(EdgeInsets(top: 11.5, leading: 15.5, bottom: 0, trailing: 14))
                    }
                    ChatComposerField(chat: chat)
                }
                    .background(RoundedRectangle(cornerRadius: DuoMetric.radiusComposer).fill(DuoColor.pane))
                    .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusComposer)
                        .strokeBorder(focused ? DuoColor.text : DuoColor.controlEdge, lineWidth: focused ? 1.5 : DuoMetric.borderHairline))
                // Stop sits beside the field once a message is waiting on Claude (handoff `composer`); Esc stops any time.
                if s.kind == .busy, chat.log.items.contains(where: { if case .you(let y) = $0 { return y.queued } else { return false } }) {
                    ChatKeyedButton(title: "Stop", key: "esc") { Task { await chat.interrupt() } }  // action: session chat
                        .padding(.bottom, 10)
                }
            }
            if case .answer(let n)? = chat.log.items.last, n.text == "You chose to chat about these questions" {
                Text("Claude is told you want to clarify; it asks again when it’s ready.").duoText(.chatMeta).foregroundStyle(DuoColor.text2)
                    .padding(.horizontal, 4)
            } else {
            HStack(spacing: 8) {
                if let mode = s.mode {
                    HStack(spacing: 4) {
                        ChatModeMark(mode: mode)
                        Text(mode.chip)
                    }
                    .duoText(.chatMeta).foregroundStyle(DuoColor.text2)
                    .padding(.horizontal, 8)
                    .background(Capsule().fill(DuoColor.pane))
                    .overlay(Capsule().strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
                    .onActivate { Task { await chat.cycleMode() } }  // action: session chat
                    .help("Change mode (shift+tab)")
                    .accessibilityLabel("Mode: \(mode.chip). Change mode")
                }
                // Narrow (DL-129): hints drop from the right, ⌘[ ⌘] first, then @ files, then / commands.
                // With the @ menu open, its keys (DL-133).
                // Measured once, not on every pass as ViewThatFits did (F-208, ENH-45).
                let hints = chat.ui.mention?.matches.isEmpty == false ? ["↑↓ choose · ⏎ or tab adds it · esc closes"]
                    : ["⏎ send · ⇧⏎ new line · ⇧⇥ mode · / commands · @ files · ⌘[ ⌘] your messages", "⏎ send · ⇧⏎ new line · ⇧⇥ mode · / commands · @ files",
                       "⏎ send · ⇧⏎ new line · ⇧⇥ mode · / commands", "⏎ send · ⇧⏎ new line · ⇧⇥ mode", "⏎ send · ⇧⏎ new line"]
                if let notice = chat.ui.pasteNotice {
                    ChatPasteNoticeLine(chat: chat, notice: notice)
                } else {
                FirstFit {
                    ForEach(hints, id: \.self) {
                        Text($0).duoText(.chatMeta).foregroundStyle(DuoColor.text2).lineLimit(1).fixedSize()
                            .frame(minWidth: 0, alignment: .leading).clipped()
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(hints[0])
                }
                Spacer(minLength: 8)
                // DL-168: the effort chip, then the model chip: the mode chip mirrored, each asking Claude's own /effort or /model.
                if let e = chat.effort {
                    ChatConfigChip(chat: chat, id: "effort", text: e.text, kind: .effort, working: s.kind == .busy)
                }
                ChatConfigChip(chat: chat, id: "model", text: chat.log.model ?? "Model", kind: .model, working: s.kind == .busy)
            }
            .padding(.horizontal, 4)
            }
        }
        .task(id: chat.ui.composerFocused) { if chat.ui.composerFocused { chat.prefillComposer() } }
    }
}

/// The model chip and the effort chip (DL-168, chat-model-chip-handoff `chip`): the mode chip's look, mirrored at the
/// hint row's right end. A click sends `/model` or `/effort` into Claude's prompt (when it is idle and empty). Under the
/// pointer: `selected`, `controlEdge`, `text`. While Claude works the chip waits: dashed `rule`, no fill, `text2`.
struct ChatConfigChip: View {
    let chat: ChatSession
    let id: String
    let text: String
    let kind: ChatPicker.Kind
    let working: Bool

    var body: some View {
        let hover = chat.ui.hoverChip == id && !working
        let what = kind == .model ? "model" : "effort"
        Text(text)
            .duoText(.chatMeta).foregroundStyle(hover ? DuoColor.text : DuoColor.text2)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 8)
            .background(Capsule().fill(working ? Color.clear : hover ? DuoColor.selected : DuoColor.pane))
            .overlay {
                if working {
                    Capsule().strokeBorder(DuoColor.rule, style: StrokeStyle(lineWidth: DuoMetric.borderHairline, dash: DuoShadow.dashPattern))
                } else {
                    Capsule().strokeBorder(hover ? DuoColor.controlEdge : DuoColor.rule, lineWidth: DuoMetric.borderHairline)
                }
            }
            .contentShape(Capsule())
            .onHover { inside in
                if inside { chat.ui.hoverChip = id } else if chat.ui.hoverChip == id { chat.ui.hoverChip = nil }
            }
            .onActivate { if !working { Task { _ = await chat.openPicker(kind) } } }  // action: session chat
            .help(working ? "Change the \(what) when Claude finishes" : kind == .model ? "Change model (/model)" : "Change effort (/effort)")
            .accessibilityLabel(kind == .model ? "Model: \(text). Change model" : "Effort: \(text). Change effort")
    }
}

/// `⏸` and `⏵⏵`, as the TUI's footer draws them.
struct ChatModeMark: View {
    let mode: ChatPermissionMode
    var body: some View {
        Text(mode == .manual || mode == .plan ? "⏸" : "⏵⏵").font(.system(size: 9))
    }
}

/// Claude Code's own command list, filtered as you type; a command with its own screen opens in the terminal.
struct ChatCommandMenu: View {
    let chat: ChatSession
    let commands: [(name: String, description: String, selected: Bool)]

    var body: some View {
        let terminal = chat.signatures.terminalCommands
        let rows = Array(commands.prefix(8))
        let column = Self.column(rows.map(\.name))
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, c in
                HStack(spacing: 12) {
                    Self.name(c.name, column: column).duoText(.mono).lineLimit(1).truncationMode(.tail).frame(width: column, alignment: .leading)
                    Text(terminal.contains(c.name) ? "Opens in the terminal" : c.description).duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1)
                    Spacer(minLength: 0)
                    if terminal.contains(c.name) { TerminalMark().stroke(DuoColor.text2, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)).frame(width: 13, height: 10) }
                }
                .padding(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                .background(RoundedRectangle(cornerRadius: DuoMetric.radiusSelection).fill(c.selected ? DuoColor.selected : .clear))
                .contentShape(Rectangle())
                .help(c.name)
                .onActivate { chat.ui.composer = c.name + " "; chat.focusComposer += 1 }  // action: session chat
            }
            // The TUI shows a page of its list; ↑↓ scroll it (F-174). Under a full page, say so.
            if rows.count >= Self.page {
                Text("↑↓ for more · tab completes").duoText(.control).foregroundStyle(DuoColor.text2)
                    .padding(EdgeInsets(top: 3, leading: 10, bottom: 2, trailing: 10))
            }
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusPopover).fill(DuoColor.pane))
        .duoPopoverShadow()
    }

    /// The TUI's page of commands (4 at the sizes measured, F-173): a full one has more under it.
    static let page = 4
    static let font = NSFont.monospacedSystemFont(ofSize: DuoTextStyle.mono.spec.size, weight: .regular)

    static func column(_ names: [String]) -> CGFloat { ChatCommandColumn.width(names) }

    /// A plugin's prefix (`/design:`) in `text2`, the skill's name in `text`. Past 280 the prefix
    /// goes first (`/cowork-plugin-man…:`); the name's tail is cut after it.
    static func name(_ full: String, column: CGFloat) -> Text {
        guard let colon = full.firstIndex(of: ":") else { return Text(full).foregroundStyle(DuoColor.text) }
        var prefix = String(full[...colon])
        let rest = String(full[full.index(after: colon)...])
        if TextWidth.of(full, font: font) > column, prefix.count > 20 { prefix = String(prefix.prefix(18)) + "…:" }
        return Text("\(Text(prefix).foregroundStyle(DuoColor.text2))\(Text(rest).foregroundStyle(DuoColor.text))")
    }
}

/// The `/` menu's name column (chat-slash-handoff `menu`, DL-143): the longest name shown and 36
/// to spare, at least the approved 122, at most 280.
public enum ChatCommandColumn {
    public static func width(_ names: [String]) -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: DuoTextStyle.mono.spec.size, weight: .regular)
        let longest = names.map { TextWidth.of($0, font: font) }.max() ?? 0
        return min(280, max(122, ceil(longest + 36)))
    }
}

/// `@`'s menu (DL-133, small-features-handoff `composer-at`): the `/` menu's look; a page or
/// folder mark, the name in mono, its folder at the right.
struct ChatMentionMenu: View {
    let chat: ChatSession
    let query: String
    let matches: [FileMention.Match]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if matches.isEmpty {
                Text("No file or folder in \(((chat.log.cwd ?? "") as NSString).lastPathComponent) matches \u{201C}\(query)\u{201D}")
                    .duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1)
                    .padding(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
            }
            ForEach(Array(matches.enumerated()), id: \.element.path) { i, m in
                HStack(spacing: 8) {
                    Group {
                        if m.isFolder { FolderMarkShape().stroke(DuoColor.text2, lineWidth: 1.1).frame(width: 12, height: 10) }
                        else { PageMarkShape().stroke(DuoColor.text2, style: StrokeStyle(lineWidth: 1.1, lineJoin: .round)).frame(width: 10, height: 12) }
                    }
                    .frame(width: 13)
                    Text(m.name).duoText(.mono).foregroundStyle(DuoColor.text).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(m.folder.isEmpty ? "the project folder" : m.folder).duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1).truncationMode(.head)
                }
                .padding(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                .background(RoundedRectangle(cornerRadius: DuoMetric.radiusSelection).fill(i == chat.ui.mentionSelected ? DuoColor.selected : .clear))
                .contentShape(Rectangle())
                .onActivate { chat.ui.mentionSelected = i; chat.chooseMention += 1 }  // action: session chat
                .accessibilityLabel("\(m.path)\(m.isFolder ? ", folder" : "")")
                .accessibilityAddTraits(i == chat.ui.mentionSelected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(5)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusPopover).fill(DuoColor.pane))
        .duoPopoverShadow()
    }
}

/// A page, 10×12 (the composer's file chip): `M1.5.5h4.5l2.5 2.5v8H1.5Z`.
struct PageMarkShape: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 10, sy = r.height / 12
        var p = Path()
        p.move(to: .init(x: 1.5 * sx, y: 0.5 * sy)); p.addLine(to: .init(x: 6 * sx, y: 0.5 * sy)); p.addLine(to: .init(x: 8.5 * sx, y: 3 * sy))
        p.addLine(to: .init(x: 8.5 * sx, y: 11 * sy)); p.addLine(to: .init(x: 1.5 * sx, y: 11 * sy)); p.closeSubpath()
        return p
    }
}

/// The field itself: an NSTextView, so Return and ⇧Return, file drops and focus behave natively.
struct ChatComposerField: NSViewRepresentable {
    let chat: ChatSession

    func makeCoordinator() -> Coordinator { Coordinator(chat: chat) }

    func makeNSView(context: Context) -> NSScrollView {
        let v = ComposerTextView()
        v.delegate = context.coordinator
        v.coordinator = context.coordinator
        v.isVerticallyResizable = true; v.isHorizontallyResizable = false
        v.autoresizingMask = [.width]
        v.minSize = .zero; v.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        chat.composerView = v
        // The field scrolls past its 8 lines and the caret is followed; no scroller is drawn (Q-148b).
        let s = NSScrollView()
        s.hasVerticalScroller = false; s.hasHorizontalScroller = false; s.drawsBackground = false; s.borderType = .noBorder
        s.automaticallyAdjustsContentInsets = false
        s.documentView = v
        return s
    }

    func updateNSView(_ s: NSScrollView, context: Context) {
        guard let v = s.documentView as? ComposerTextView else { return }
        context.coordinator.chat = chat
        chat.composerView = v
        if let fb = chat.ui.fixtureBlock {
            chat.ui.fixtureBlock = nil
            DispatchQueue.main.async { v.setFixture(fb) }
        } else if v.plainText != chat.ui.composer { v.setPlain(chat.ui.composer) }
        if context.coordinator.chooseSeen != chat.chooseMention {
            context.coordinator.chooseSeen = chat.chooseMention
            context.coordinator.chooseMention(in: v)
        }
        if context.coordinator.focusSeen != chat.focusComposer {
            context.coordinator.focusSeen = chat.focusComposer
            DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
        }
        v.needsDisplay = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView s: NSScrollView, context: Context) -> CGSize? {
        let w = proposal.width ?? 400
        return CGSize(width: w, height: (s.documentView as? ComposerTextView)?.height(for: w) ?? 44)
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var chat: ChatSession
        var focusSeen = 0, chooseSeen = 0
        init(chat: ChatSession) { self.chat = chat }

        func textDidChange(_ n: Notification) {
            guard let v = n.object as? ComposerTextView else { return }
            chat.ui.composer = v.plainText
            chat.ui.pasteNotice = nil
            v.styleMentions()
            v.contentChanged()
            Task { await chat.mirrorSlash(v.plainText) }
            updateMention(v)
        }

        func textViewDidChangeSelection(_ n: Notification) {
            guard let v = n.object as? ComposerTextView else { return }
            updateMention(v)
        }

        /// The `@` word at the caret, matched against Claude's folder (DL-133).
        func updateMention(_ v: ComposerTextView) {
            let sel = v.selectedRange()
            guard sel.length == 0, let cwd = chat.log.cwd, let tok = FileMention.token(in: v.string, caret: sel.location) else {
                chat.ui.mention = nil; chat.ui.mentionDismissedAt = nil; return
            }
            guard chat.ui.mentionDismissedAt != tok.range.location else { chat.ui.mention = nil; return }
            FileMention.paths(in: cwd) { [weak self, weak v] paths in
                guard let self, let v, let now = FileMention.token(in: v.string, caret: v.selectedRange().location), now.query == tok.query,
                      self.chat.ui.mentionDismissedAt != now.range.location else { return }
                if self.chat.ui.mention?.query != now.query { self.chat.ui.mentionSelected = 0 }
                self.chat.ui.mention = (now.query, FileMention.matches(now.query, in: paths))
            }
        }

        /// Esc: closes the menu until the caret leaves this `@` word.
        func dismissMention(_ v: ComposerTextView) {
            chat.ui.mentionDismissedAt = FileMention.token(in: v.string, caret: v.selectedRange().location)?.range.location
            chat.ui.mention = nil
        }

        func moveMention(_ by: Int) {
            guard let n = chat.ui.mention?.matches.count, n > 0 else { return }
            chat.ui.mentionSelected = (chat.ui.mentionSelected + by + n) % n
        }

        /// Puts the selected match in place of the `@` word: `@path ` (Claude Code's own mention).
        func chooseMention(in v: ComposerTextView) {
            guard let m = chat.ui.mention, chat.ui.mentionSelected < m.matches.count,
                  let tok = FileMention.token(in: v.string, caret: v.selectedRange().location) else { return }
            v.insertText(m.matches[chat.ui.mentionSelected].inserted, replacementRange: tok.range)
            chat.ui.mention = nil
            v.window?.makeFirstResponder(v)
        }

        func send() {
            // A part-typed command runs the one the menu has selected, as Return does in the TUI.
            let text = chat.commandMenuShown ? chat.selectedCommand ?? chat.ui.composer : chat.ui.composer
            Task { _ = await chat.send(text) }
        }
    }
}

/// A file dropped into the composer: its full path is what's sent; its name is what shows.
final class ComposerChip: NSTextAttachment {
    var path = ""
}

final class ComposerTextView: NSTextView, @preconcurrency NSLayoutManagerDelegate {
    weak var coordinator: ChatComposerField.Coordinator?
    static let font = NSFont.systemFont(ofSize: DuoTextStyle.chatBody.spec.size)
    static let inset = NSSize(width: 14, height: 11)

    init() {
        let storage = NSTextStorage(), layout = NSLayoutManager(), container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        super.init(frame: .zero, textContainer: container)
        layout.delegate = self
        isRichText = true
        importsGraphics = false
        allowsUndo = true
        drawsBackground = false
        font = Self.font
        textColor = DuoNSColor.text
        insertionPointColor = DuoNSColor.text
        textContainerInset = Self.inset
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = DuoTextStyle.chatBody.spec.lineHeight
        p.maximumLineHeight = DuoTextStyle.chatBody.spec.lineHeight
        defaultParagraphStyle = p
        typingAttributes = [.font: Self.font, .foregroundColor: DuoNSColor.text, .paragraphStyle: p,
                            .baselineOffset: (DuoTextStyle.chatBody.spec.lineHeight - Self.font.ascender + Self.font.descender) / 4]
        registerForDraggedTypes([.fileURL])
        setAccessibilityLabel("Reply to Claude")
    }

    required init?(coder: NSCoder) { fatalError() }
    override init(frame: NSRect, textContainer: NSTextContainer?) { super.init(frame: frame, textContainer: textContainer) }

    /// What's sent: the text, with each chip as its full path.
    var plainText: String {
        var out = ""
        textStorage?.enumerateAttributes(in: NSRange(location: 0, length: textStorage?.length ?? 0)) { attrs, range, _ in
            if let block = attrs[.attachment] as? ComposerPasteBlock { out += block.text }
            else if let chip = attrs[.attachment] as? ComposerChip { out += FileDrop.terminalText([URL(fileURLWithPath: chip.path)]).trimmingCharacters(in: .whitespaces) }
            else { out += (string as NSString).substring(with: range) }
        }
        return out
    }

    func setPlain(_ s: String) {
        textStorage?.setAttributedString(NSAttributedString(string: s, attributes: typingAttributes))
        setSelectedRange(NSRange(location: (s as NSString).length, length: 0))
        styleMentions()
    }

    static let mentionFont = NSFont.monospacedSystemFont(ofSize: DuoTextStyle.mono.spec.size, weight: .regular)
    static let mentionPattern = try! NSRegularExpression(pattern: "(?<![^\\s\u{FFFC}])@[^\\s\u{FFFC}]+")

    /// `@` mentions in mono, the rest in the body face (small-features-handoff `composer-at`, DL-133).
    func styleMentions() {
        guard let ts = textStorage, ts.length > 0 else { return }
        ts.beginEditing()
        ts.enumerateAttribute(.attachment, in: NSRange(location: 0, length: ts.length)) { a, r, _ in
            if a == nil { ts.addAttribute(.font, value: Self.font, range: r) }
        }
        for m in Self.mentionPattern.matches(in: ts.string, range: NSRange(location: 0, length: ts.length)) {
            ts.addAttribute(.font, value: Self.mentionFont, range: m.range)
        }
        ts.endEditing()
        typingAttributes[.font] = Self.font
    }

    func height(for width: CGFloat) -> CGFloat {
        guard let lm = layoutManager, let tc = textContainer else { return 44 }
        tc.containerSize = NSSize(width: max(40, width - Self.inset.width * 2), height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: tc)
        let lines = max(DuoTextStyle.chatBody.spec.lineHeight, ceil(lm.usedRect(for: tc).height))
        // Eight lines, past which the field scrolls; an opened block shows whole (chat-paste-handoff `text`).
        let cap = DuoTextStyle.chatBody.spec.lineHeight * 8 + (hasOpenBlock ? 64 : 0)
        return min(lines, cap) + Self.inset.height * 2
    }

    var hasOpenBlock: Bool {
        var open = false
        textStorage?.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage?.length ?? 0)) { a, _, stop in
            if (a as? ComposerPasteBlock)?.isOpen == true { open = true; stop.pointee = true }
        }
        return open
    }

    /// The text changed, or a block did: the field's height is asked again.
    func contentChanged() {
        invalidateIntrinsicContentSize()
        enclosingScrollView?.invalidateIntrinsicContentSize()
        syncBlocks()
    }

    // MARK: Pasted-text blocks

    /// A paste over 12 lines, folded where the caret is.
    /// A fixture board's composer: a block, then the words after it.
    func setFixture(_ fb: ChatUIState.FixtureBlock) {
        window?.makeFirstResponder(self)
        insertBlock(fb.text)
        insertText(fb.typed, replacementRange: selectedRange())
        guard fb.open, let b = (textStorage?.attribute(.attachment, at: 0, effectiveRange: nil)) as? ComposerPasteBlock else { return }
        toggle(b)
        if let line = fb.caretLine { DispatchQueue.main.async { b.view?.focusEditor(afterLine: line) } }
    }

    func insertBlock(_ text: String) {
        // The block is a line of its own, as drawn: what's before it and what you type after it are
        // on other lines, so a line break is sent where the box shows one.
        let sel = selectedRange(), all = (textStorage?.string ?? "") as NSString
        let before = sel.location > 0 && all.character(at: sel.location - 1) != 10
        let after = NSMaxRange(sel) >= all.length || all.character(at: NSMaxRange(sel)) != 10
        let s = NSMutableAttributedString(string: before ? "\n" : "", attributes: typingAttributes)
        let blockAt = sel.location + s.length
        s.append(NSAttributedString(attachment: ComposerPasteBlock(text: text)))
        if after { s.append(NSAttributedString(string: "\n", attributes: typingAttributes)) }
        insertText(s, replacementRange: sel)
        // The paragraph holding it has no maximum line height: the box is taller than a line.
        if let ts = textStorage {
            let para = (ts.string as NSString).paragraphRange(for: NSRange(location: blockAt, length: 0))
            let ps = NSMutableParagraphStyle()
            ps.minimumLineHeight = DuoTextStyle.chatBody.spec.lineHeight
            ts.addAttribute(.paragraphStyle, value: ps, range: para)
        }
        contentChanged()
    }

    func blockRange(_ b: ComposerPasteBlock) -> NSRange? {
        var found: NSRange?
        textStorage?.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage?.length ?? 0)) { a, r, stop in
            if a as AnyObject === b { found = r; stop.pointee = true }
        }
        return found
    }

    func remove(_ b: ComposerPasteBlock) {
        guard let r = blockRange(b) else { return }
        insertText("", replacementRange: r)
        window?.makeFirstResponder(self)
        contentChanged()
    }

    func toggle(_ b: ComposerPasteBlock) {
        b.isOpen.toggle()
        b.view?.syncOpen()
        if let r = blockRange(b) { layoutManager?.invalidateLayout(forCharacterRange: r, actualCharacterRange: nil) }
        contentChanged()
        needsDisplay = true
    }

    /// Its text was edited in place: what's sent follows.
    func blockEdited(_ b: ComposerPasteBlock) {
        b.preview = ChatPaste.blockPreview(b.text)
        b.view?.needsDisplay = true
        coordinator?.chat.ui.composer = plainText
        coordinator?.chat.ui.pasteNotice = nil
        contentChanged()
    }

    /// Puts each block's view over the box its attachment reserved; drops the views of blocks that are gone.
    func syncBlocks() {
        guard let ts = textStorage, let lm = layoutManager, let tc = textContainer else { return }
        var seen = Set<ObjectIdentifier>()
        ts.enumerateAttribute(.attachment, in: NSRange(location: 0, length: ts.length)) { a, r, _ in
            guard let b = a as? ComposerPasteBlock else { return }
            seen.insert(ObjectIdentifier(b))
            let v = b.view ?? PasteBlockView(block: b, host: self)
            b.view = v
            if v.superview !== self { addSubview(v) }
            let g = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            guard g.length > 0, lm.isValidGlyphIndex(g.location) else { return }
            let line = lm.lineFragmentRect(forGlyphAt: g.location, effectiveRange: nil)
            let x = lm.location(forGlyphAt: g.location).x
            v.frame = NSRect(x: textContainerOrigin.x + line.minX + x, y: textContainerOrigin.y + line.minY,
                             width: max(40, tc.size.width - 2 * tc.lineFragmentPadding), height: b.boxHeight)
        }
        for v in subviews.compactMap({ $0 as? PasteBlockView }) where !seen.contains(ObjectIdentifier(v.block)) { v.removeFromSuperview() }
    }

    func layoutManager(_ lm: NSLayoutManager, didCompleteLayoutFor tc: NSTextContainer?, atEnd: Bool) {
        if tc != nil, atEnd { syncBlocks() }
    }

    override func setFrameSize(_ size: NSSize) {
        super.setFrameSize(size)
        syncBlocks()
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { coordinator?.chat.ui.composerFocused = true }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { coordinator?.chat.ui.composerFocused = false }
        return ok
    }

    override func keyDown(with e: NSEvent) {
        // ⇧⇥: Claude Code's own mode cycle (manual, accept edits, plan, auto …, whatever this claude
        // offers); the chip follows its footer (F-179).
        if e.keyCode == 48, e.modifierFlags.intersection([.shift, .command, .option, .control]) == .shift, let c = coordinator?.chat {
            Task { await c.cycleMode() }
            return
        }
        // The @ menu takes ↑↓, ⏎ and tab while it has matches, and esc while it's open (DL-133).
        if let c = coordinator, let m = c.chat.ui.mention {
            let any = !m.matches.isEmpty
            switch e.keyCode {
            case 126 where any: c.moveMention(-1); return
            case 125 where any: c.moveMention(1); return
            case 36, 76, 48:
                if any, !e.modifierFlags.contains(.shift) { c.chooseMention(in: self); return }
            case 53: c.dismissMention(self); return
            default: break
            }
        }
        // The `/` menu is Claude Code's own: ↑↓ move its selection and tab completes, as in the
        // TUI; ⏎ runs the selected command (F-173).
        if let c = coordinator?.chat, c.commandMenuShown, e.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty {
            switch e.keyCode {
            case 126: Task { await c.moveCommandMenu(.up) }; return
            case 125: Task { await c.moveCommandMenu(.down) }; return
            case 48:
                if let n = c.selectedCommand { c.ui.composer = n + " "; Task { await c.mirrorSlash(n + " ") } }
                return
            default: break
            }
        }
        // Backspace in an empty field takes the last picture off (chat-paste-handoff `picture`).
        if e.keyCode == 51, e.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty, string.isEmpty, let c = coordinator?.chat, let last = c.ui.attachedTokens.last {
            c.removePicture(last)
            return
        }
        switch e.keyCode {
        case 36, 76:   // Return: send; ⇧Return: a new line
            if e.modifierFlags.contains(.shift) { insertNewlineIgnoringFieldEditor(nil) } else { coordinator?.send() }
        case 53:       // Esc: Stop while Claude works
            if let c = coordinator?.chat, c.screen.kind == .busy { Task { await c.interrupt() } } else { super.keyDown(with: e) }
        default: super.keyDown(with: e)
        }
    }

    /// Text pastes; a copied file becomes a chip; an image goes into Claude's prompt through Claude
    /// Code's own image paste and shows as a chip (ChatPaste).
    override func paste(_ sender: Any?) {
        for route in ChatPaste.routes(NSPasteboard.general) {
            switch route {
            case .chip(let u): insertChip(u)
            case .text:
                if let t = NSPasteboard.general.string(forType: .string), ChatPaste.isLongPaste(t) { insertBlock(t) } else { pasteAsPlainText(sender) }
            case .image(let image):
                guard let chat = coordinator?.chat else { break }
                Task { if await !chat.attachClipboardImage(image).ok { NSSound.beep() } }
            }
        }
    }

    /// Paste is on for text, an image or a file (an image alone would leave it off: no graphics).
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)) || item.action == #selector(pasteAsPlainText(_:)) { return ChatPaste.canPaste(NSPasteboard.general) }
        return super.validateUserInterfaceItem(item)
    }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(paste(_:)) || item.action == #selector(pasteAsPlainText(_:)) { return ChatPaste.canPaste(NSPasteboard.general) }
        return super.validateMenuItem(item)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { GuardedTerminalView.fileURLs(sender.draggingPasteboard).isEmpty ? super.draggingEntered(sender) : .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = GuardedTerminalView.fileURLs(sender.draggingPasteboard)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        for u in urls { insertChip(u) }
        window?.makeFirstResponder(self)
        return true
    }

    func insertChip(_ url: URL) {
        let chip = ComposerChip()
        chip.path = url.path
        chip.image = Self.chipImage(url.lastPathComponent)
        chip.bounds = NSRect(x: 0, y: -6, width: chip.image!.size.width, height: chip.image!.size.height)
        let s = NSMutableAttributedString(attachment: chip)
        s.append(NSAttributedString(string: " ", attributes: typingAttributes))
        insertText(s, replacementRange: selectedRange())
    }

    /// A file's chip: a page mark and its name, on `ground` with a `rule` edge (handoff `composer`).
    static func chipImage(_ name: String) -> NSImage {
        let f = NSFont.systemFont(ofSize: DuoTextStyle.body.spec.size)
        let tw = ceil((name as NSString).size(withAttributes: [.font: f]).width)
        let size = NSSize(width: tw + 34, height: 22)
        return NSImage(size: size, flipped: true) { r in
            let box = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: DuoMetric.radiusChatStepBody, yRadius: DuoMetric.radiusChatStepBody)
            DuoNSColor.ground.setFill(); box.fill()
            DuoNSColor.rule.setStroke(); box.lineWidth = 1; box.stroke()
            let page = NSBezierPath()
            page.move(to: NSPoint(x: 10, y: 5)); page.line(to: NSPoint(x: 16, y: 5)); page.line(to: NSPoint(x: 19, y: 8))
            page.line(to: NSPoint(x: 19, y: 17)); page.line(to: NSPoint(x: 10, y: 17)); page.close()
            DuoNSColor.text.setStroke(); page.lineWidth = 1.1; page.stroke()
            (name as NSString).draw(at: NSPoint(x: 25, y: 2.5), withAttributes: [.font: f, .foregroundColor: DuoNSColor.text])
            return true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            ("Reply to Claude" as NSString).draw(at: NSPoint(x: Self.inset.width + 5, y: Self.inset.height + 1.5),
                                                 withAttributes: [.font: Self.font, .foregroundColor: DuoNSColor.text2])
        }
    }
}

extension ChatSession {
    /// Text typed in the terminal is Claude's prompt: the composer opens on it (handoff `composer`).
    /// The screen can't tell typed text from a dim suggestion (F-108), so the real buffer is asked.
    func prefillComposer() {
        guard let input = screen.input, ui.composer.isEmpty, ui.composerBasis == nil, ui.heldTokens.isEmpty, !input.isEmpty, !input.hasPrefix("/"), !sending else { return }
        guard usesExternalEditor else { return }   // pasting needs an empty prompt anyway
        Task {
            guard let real = await peekPrompt(), ui.composer.isEmpty else { return }
            ui.composer = real
            ui.composerBasis = real
        }
    }

    /// The composer holds a part-typed command and Claude Code's `/` menu is up under it.
    public var commandMenuShown: Bool {
        ui.composer.hasPrefix("/") && !ui.composer.contains(" ") && !ui.composer.contains("\n") && !screen.commands.isEmpty
    }

    /// The command the TUI's menu has selected.
    public var selectedCommand: String? { screen.commands.first { $0.selected }?.name }

    /// ↑ or ↓ in the composer moves the TUI's own menu selection.
    public func moveCommandMenu(_ k: ChatKey) async {
        guard commandMenuShown, !sending, screen.kind == .idle else { return }
        _ = await press(k)
    }

    /// `/` in the composer: the same prefix in Claude's prompt, so its menu shows its own commands.
    /// Only over an empty prompt or one this already typed; the hand-over replaces it on send.
    public func mirrorSlash(_ text: String) async {
        let s = reread()
        guard s.kind == .idle, !sending else { return }
        let current = s.input ?? ""
        let want = text.hasPrefix("/") && !text.contains(" ") && !text.contains("\n") ? text : ""
        guard current != want, current.isEmpty || current.hasPrefix("/") else { return }
        for _ in current { terminal?.sendKeys(ChatKey.backspace.bytes) }
        if !want.isEmpty { terminal?.sendKeys(want) }
        ui.composerBasis = want
        await pause(150_000_000)
        _ = reread()
    }
}

/// The first of its subviews that fits the width offered, as `ViewThatFits(in: .horizontal)` picks,
/// but each subview's own width is measured once and kept until the subviews change: ViewThatFits
/// measured every candidate on every layout pass, and with many composers on screen that was most of
/// a frame (F-208). The others are placed at no width (each clips itself).
struct FirstFit: Layout {
    struct Cache { var widths: [CGFloat]?; var height: CGFloat = 0 }
    func makeCache(subviews: Subviews) -> Cache { Cache() }

    private func measure(_ s: Subviews, _ cache: inout Cache) -> [CGFloat] {
        if let w = cache.widths { return w }
        let sizes = s.map { $0.sizeThatFits(.unspecified) }
        cache.widths = sizes.map(\.width)
        cache.height = sizes.map(\.height).max() ?? 0
        return cache.widths!
    }

    private func chosen(_ width: CGFloat?, _ widths: [CGFloat]) -> Int? {
        guard !widths.isEmpty else { return nil }
        guard let width else { return 0 }
        return widths.firstIndex { $0 <= width } ?? widths.count - 1
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews s: Subviews, cache: inout Cache) -> CGSize {
        let widths = measure(s, &cache)
        guard let i = chosen(proposal.width, widths) else { return .zero }
        return CGSize(width: min(widths[i], proposal.width ?? widths[i]), height: cache.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews s: Subviews, cache: inout Cache) {
        let widths = measure(s, &cache)
        let pick = chosen(bounds.width, widths)
        for (i, v) in s.enumerated() {
            v.place(at: bounds.origin, anchor: .topLeading,
                    proposal: i == pick ? ProposedViewSize(width: bounds.width, height: bounds.height) : ProposedViewSize(width: 0, height: bounds.height))
        }
    }
}
