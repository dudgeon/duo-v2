import AppKit
import SwiftUI

// The composer (chat-mode-handoff `composer`): Claude's own prompt in a native field. Return sends,
// ⇧Return adds a line; files dropped in go in as their full paths (DL-117) and show by name; `/`
// opens Claude Code's own command list; while Claude works a sent message waits as Queued and Stop
// (esc) sits beside the field. Under it: the mode chip (a click cycles it, as Shift+Tab does), the
// hints and the model.

struct ChatComposerArea: View {
    @Environment(AppModel.self) private var model
    let chat: ChatSession

    var body: some View {
        let s = chat.screen
        VStack(alignment: .leading, spacing: 6) {
            if chat.ui.composer.hasPrefix("/"), !chat.ui.composer.contains(" "), !s.commands.isEmpty {
                ChatCommandMenu(chat: chat, commands: s.commands)
            }
            HStack(alignment: .bottom, spacing: 10) {
                let focused = chat.ui.composerFocused
                ChatComposerField(chat: chat)
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
                // Narrow (DL-129): hints drop from the right, ⌘[ ⌘] first, then / commands.
                ViewThatFits(in: .horizontal) {
                    ForEach(["⏎ send · ⇧⏎ new line · / commands · ⌘[ ⌘] your messages", "⏎ send · ⇧⏎ new line · / commands", "⏎ send · ⇧⏎ new line"], id: \.self) {
                        Text($0).duoText(.chatMeta).foregroundStyle(DuoColor.text2).lineLimit(1).fixedSize()
                    }
                }
                Spacer(minLength: 8)
                if let m = chat.log.model { Text(m).duoText(.chatMeta).foregroundStyle(DuoColor.text2) }
            }
            .padding(.horizontal, 4)
            }
        }
        .task(id: chat.ui.composerFocused) { if chat.ui.composerFocused { chat.prefillComposer() } }
    }
}

/// `⏸` and `⏵⏵`, as the TUI's footer draws them.
struct ChatModeMark: View {
    let mode: ChatPermissionMode
    var body: some View {
        Text(mode == .manual ? "⏸" : mode == .plan ? "⏸" : "⏵⏵").font(.system(size: 9))
    }
}

/// Claude Code's own command list, filtered as you type; a command with its own screen opens in the terminal.
struct ChatCommandMenu: View {
    let chat: ChatSession
    let commands: [(name: String, description: String, selected: Bool)]

    var body: some View {
        let terminal = chat.signatures.terminalCommands
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(commands.prefix(8).enumerated()), id: \.offset) { _, c in
                HStack(spacing: 0) {
                    Text(c.name).duoText(.mono).foregroundStyle(DuoColor.text).frame(width: 122, alignment: .leading)
                    Text(terminal.contains(c.name) ? "Opens in the terminal" : c.description).duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1)
                    Spacer(minLength: 8)
                    if terminal.contains(c.name) { TerminalMark().stroke(DuoColor.text, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)).frame(width: 13, height: 10) }
                }
                .padding(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                .background(RoundedRectangle(cornerRadius: DuoMetric.radiusSelection).fill(c.selected ? DuoColor.selected : .clear))
                .contentShape(Rectangle())
                .onActivate { chat.ui.composer = c.name + " "; chat.focusComposer += 1 }  // action: session chat
            }
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusPopover).fill(DuoColor.pane))
        .duoPopoverShadow()
    }
}

/// The field itself: an NSTextView, so Return and ⇧Return, file drops and focus behave natively.
struct ChatComposerField: NSViewRepresentable {
    let chat: ChatSession

    func makeCoordinator() -> Coordinator { Coordinator(chat: chat) }

    func makeNSView(context: Context) -> ComposerTextView {
        let v = ComposerTextView()
        v.delegate = context.coordinator
        v.coordinator = context.coordinator
        return v
    }

    func updateNSView(_ v: ComposerTextView, context: Context) {
        context.coordinator.chat = chat
        if v.plainText != chat.ui.composer { v.setPlain(chat.ui.composer) }
        if context.coordinator.focusSeen != chat.focusComposer {
            context.coordinator.focusSeen = chat.focusComposer
            DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
        }
        v.needsDisplay = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView v: ComposerTextView, context: Context) -> CGSize? {
        let w = proposal.width ?? 400
        return CGSize(width: w, height: v.height(for: w))
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var chat: ChatSession
        var focusSeen = 0
        init(chat: ChatSession) { self.chat = chat }

        func textDidChange(_ n: Notification) {
            guard let v = n.object as? ComposerTextView else { return }
            chat.ui.composer = v.plainText
            v.invalidateIntrinsicContentSize()
            Task { await chat.mirrorSlash(v.plainText) }
        }

        func send() {
            let text = chat.ui.composer
            Task { _ = await chat.send(text) }
        }
    }
}

/// A file dropped into the composer: its full path is what's sent; its name is what shows.
final class ComposerChip: NSTextAttachment {
    var path = ""
}

final class ComposerTextView: NSTextView {
    weak var coordinator: ChatComposerField.Coordinator?
    static let font = NSFont.systemFont(ofSize: DuoTextStyle.chatBody.spec.size)
    static let inset = NSSize(width: 14, height: 11)

    init() {
        let storage = NSTextStorage(), layout = NSLayoutManager(), container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        super.init(frame: .zero, textContainer: container)
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
            if let chip = attrs[.attachment] as? ComposerChip { out += FileDrop.terminalText([URL(fileURLWithPath: chip.path)]).trimmingCharacters(in: .whitespaces) }
            else { out += (string as NSString).substring(with: range) }
        }
        return out
    }

    func setPlain(_ s: String) {
        textStorage?.setAttributedString(NSAttributedString(string: s, attributes: typingAttributes))
        setSelectedRange(NSRange(location: (s as NSString).length, length: 0))
    }

    func height(for width: CGFloat) -> CGFloat {
        guard let lm = layoutManager, let tc = textContainer else { return 44 }
        tc.containerSize = NSSize(width: max(40, width - Self.inset.width * 2), height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: tc)
        let lines = max(DuoTextStyle.chatBody.spec.lineHeight, ceil(lm.usedRect(for: tc).height))
        return min(lines, DuoTextStyle.chatBody.spec.lineHeight * 8) + Self.inset.height * 2
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
        switch e.keyCode {
        case 36, 76:   // Return: send; ⇧Return: a new line
            if e.modifierFlags.contains(.shift) { insertNewlineIgnoringFieldEditor(nil) } else { coordinator?.send() }
        case 53:       // Esc: Stop while Claude works
            if let c = coordinator?.chat, c.screen.kind == .busy { Task { await c.interrupt() } } else { super.keyDown(with: e) }
        default: super.keyDown(with: e)
        }
    }

    /// Text only; an image pasted goes to the terminal, as chat mode can't send one (Q-56e).
    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if pb.string(forType: .string) == nil, pb.canReadObject(forClasses: [NSImage.self], options: nil), let c = coordinator?.chat {
            c.fallBack(.handedOver("Paste images into Claude’s prompt here; chat mode can’t send them yet. Chat comes back after."))
            return
        }
        pasteAsPlainText(sender)
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
        guard let input = screen.input, ui.composer.isEmpty, ui.composerBasis == nil, !input.isEmpty, !input.hasPrefix("/"), !sending else { return }
        guard usesExternalEditor else { return }   // pasting needs an empty prompt anyway
        Task {
            guard let real = await peekPrompt(), ui.composer.isEmpty else { return }
            ui.composer = real
            ui.composerBasis = real
        }
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
