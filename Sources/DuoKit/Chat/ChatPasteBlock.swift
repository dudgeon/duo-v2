import AppKit

// A long paste in the composer (chat-paste-handoff `text`, DL-161): over 12 lines it folds to a block
// where it was pasted, in the text flow. The block is an attachment that reserves a full-width box;
// a view over that box draws it (folded: chevron, `Pasted text · 42 lines`, ×, the paste's start;
// opened: the text in place, 13/20, editable, eight lines showing). What's sent has each block's
// text, as edited, in its place: byte for byte what a plain paste would have sent.

extension ChatPaste {
    /// A paste of more than this many lines folds (K8's rule for your long messages).
    public static let blockLines = 12
    /// The size is named from here (a stand-in: the board draws it for 1.2 MB, Q-148).
    public static let blockSizeFrom = 100_000

    public static func lineCount(_ s: String) -> Int { s.components(separatedBy: "\n").count }
    public static func isLongPaste(_ s: String) -> Bool { lineCount(s) > blockLines }

    /// `42 lines`, or `12,480 lines · 1.2 MB` once it's big.
    public static func blockLabel(_ s: String) -> String {
        let n = NumberFormatter()
        n.numberStyle = .decimal
        n.locale = Locale(identifier: "en_US")
        var out = (n.string(from: NSNumber(value: lineCount(s))) ?? "\(lineCount(s))") + " lines"
        let bytes = s.utf8.count
        if bytes >= blockSizeFrom {
            let f = ByteCountFormatter()
            f.countStyle = .file
            out += " · " + f.string(fromByteCount: Int64(bytes))
        }
        return out
    }

    /// The start of the paste on one line: its first lines, a full stop added where a line has none.
    public static func blockPreview(_ s: String) -> String {
        var out = "", n = 0
        for raw in s.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            out += (out.isEmpty ? "" : (out.last.map { ".?!:;,…".contains($0) } == true ? " " : ". ")) + line
            n += 1
            if out.count > 400 || n >= 8 || line.hasSuffix("…") { break }
        }
        return out
    }
}

final class ComposerPasteBlock: NSTextAttachment {
    var text = "" { didSet { label = ChatPaste.blockLabel(text) } }
    var label = ""
    var preview = ""
    var isOpen = false
    var view: PasteBlockView?

    static let collapsedHeight: CGFloat = 53, openHeight: CGFloat = 193, margin: CGFloat = 8
    var boxHeight: CGFloat { isOpen ? Self.openHeight : Self.collapsedHeight }

    init(text: String) {
        super.init(data: nil, ofType: nil)
        self.text = text
        label = ChatPaste.blockLabel(text)
        preview = ChatPaste.blockPreview(text)
        image = NSImage(size: NSSize(width: 1, height: 1))   // an attachment needs one to be laid out; nothing is drawn
    }
    required init?(coder: NSCoder) { fatalError() }

    /// The whole line wide, and the box's height with the gap under it.
    override func attachmentBounds(for tc: NSTextContainer?, proposedLineFragment f: CGRect, glyphPosition p: CGPoint, characterIndex i: Int) -> CGRect {
        CGRect(x: 0, y: -4, width: max(40, f.width - 2 * (tc?.lineFragmentPadding ?? 0)), height: boxHeight + Self.margin)
    }
}

/// The block's box: `ground`, a 1 `rule` edge, radius 8, padding 6 10.
final class PasteBlockView: NSView, NSTextViewDelegate {
    let block: ComposerPasteBlock
    weak var host: ComposerTextView?
    private var scroller: NSScrollView?
    private var editor: PasteBlockEditor?
    var editorForChecks: PasteBlockEditor? { editor }
    private let fade = PasteBlockFade()

    override var isFlipped: Bool { true }

    init(block: ComposerPasteBlock, host: ComposerTextView) {
        self.block = block
        self.host = host
        super.init(frame: .zero)
        wantsLayer = true
        syncOpen()
    }
    required init?(coder: NSCoder) { fatalError() }

    static let head = NSFont.systemFont(ofSize: 12, weight: .semibold), meta = NSFont.systemFont(ofSize: 12)
    static let body = NSFont.systemFont(ofSize: DuoTextStyle.body.spec.size)

    /// Builds or drops the editor to match the block's state.
    func syncOpen() {
        if block.isOpen, editor == nil {
            let e = PasteBlockEditor()
            e.owner = self
            e.delegate = self
            e.string = block.text
            let s = NSScrollView()
            s.hasVerticalScroller = false; s.hasHorizontalScroller = false; s.drawsBackground = false; s.borderType = .noBorder
            e.minSize = .zero; e.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            e.isVerticallyResizable = true; e.isHorizontallyResizable = false; e.autoresizingMask = [.width]
            s.documentView = e
            addSubview(s); addSubview(fade)
            scroller = s; editor = e
            needsLayout = true
        } else if !block.isOpen, let s = scroller {
            s.removeFromSuperview(); fade.removeFromSuperview()
            scroller = nil; editor = nil
        }
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        guard let s = scroller, let e = editor else { return }
        s.frame = NSRect(x: 10, y: 25.5, width: bounds.width - 20, height: 160)
        e.textContainer?.containerSize = NSSize(width: s.frame.width, height: .greatestFiniteMagnitude)
        e.frame.size.width = s.frame.width
        fade.frame = NSRect(x: 10, y: 25.5 + 160 - 20, width: bounds.width - 20, height: 20)
        fade.isHidden = !(e.layoutManager.map { $0.usedRect(for: e.textContainer!).height > 160 } ?? false)
    }

    private var closeRect: NSRect { NSRect(x: bounds.width - 29, y: 6, width: 20, height: 20) }
    private var chevronRect: NSRect { NSRect(x: 0, y: 0, width: 140, height: 28) }

    override func draw(_ dirty: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: DuoMetric.radiusChatThumb, yRadius: DuoMetric.radiusChatThumb)
        DuoNSColor.ground.setFill(); box.fill()
        DuoNSColor.rule.setStroke(); box.lineWidth = 1; box.stroke()
        // The chevron: › folded, ⌄ opened, 10 wide in text2.
        let c = NSBezierPath()
        if block.isOpen { c.move(to: NSPoint(x: 11, y: 12)); c.line(to: NSPoint(x: 15, y: 16)); c.line(to: NSPoint(x: 19, y: 12)) }
        else { c.move(to: NSPoint(x: 13.5, y: 10)); c.line(to: NSPoint(x: 17.5, y: 14)); c.line(to: NSPoint(x: 13.5, y: 18)) }
        c.lineWidth = 1.3; c.lineCapStyle = .round; c.lineJoinStyle = .round
        DuoNSColor.text2.setStroke(); c.stroke()
        let title = "Pasted text" as NSString
        title.draw(at: NSPoint(x: 26.5, y: 6 + 2), withAttributes: [.font: Self.head, .foregroundColor: DuoNSColor.text])
        let x = 26.5 + ceil(title.size(withAttributes: [.font: Self.head]).width) + 5
        ("· " + block.label as NSString).draw(at: NSPoint(x: x, y: 6 + 2), withAttributes: [.font: Self.meta, .foregroundColor: DuoNSColor.text2])
        guard !block.isOpen else { return }
        let p = NSMutableParagraphStyle(); p.lineBreakMode = .byTruncatingTail
        (block.preview as NSString).draw(in: NSRect(x: 10, y: 27 + 2, width: bounds.width - 20, height: 20),
                                          withAttributes: [.font: Self.body, .foregroundColor: DuoNSColor.text2, .paragraphStyle: p])
        let cx = closeRect.midX, cy = closeRect.midY, x2 = NSBezierPath()
        x2.move(to: NSPoint(x: cx - 3, y: cy - 3)); x2.line(to: NSPoint(x: cx + 3, y: cy + 3))
        x2.move(to: NSPoint(x: cx + 3, y: cy - 3)); x2.line(to: NSPoint(x: cx - 3, y: cy + 3))
        x2.lineWidth = 1.3; x2.lineCapStyle = .round
        DuoNSColor.text2.setStroke(); x2.stroke()
    }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if !block.isOpen, closeRect.contains(p) { host?.remove(block); return }
        if chevronRect.contains(p) || (!block.isOpen && p.y > 27) { host?.toggle(block); return }
    }

    func textDidChange(_ n: Notification) {
        block.text = editor?.string ?? block.text
        host?.blockEdited(block)
        needsLayout = true
    }

    /// Opens with the caret after `line` lines (the fixtures).
    func focusEditor(afterLine line: Int) {
        guard let e = editor else { return }
        let lines = block.text.components(separatedBy: "\n").prefix(line).joined(separator: "\n") as NSString
        e.setSelectedRange(NSRange(location: lines.length, length: 0))
        window?.makeFirstResponder(e)
    }
}

/// The opened block's text: 13/20 in `text`; it tells the composer it has the keyboard.
final class PasteBlockEditor: NSTextView {
    weak var owner: PasteBlockView?

    init() {
        let storage = NSTextStorage(), layout = NSLayoutManager(), container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        super.init(frame: .zero, textContainer: container)
        isRichText = false
        allowsUndo = true
        drawsBackground = false
        textContainerInset = .zero
        font = PasteBlockView.body
        textColor = DuoNSColor.text
        insertionPointColor = DuoNSColor.text
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = 20; p.maximumLineHeight = 20
        defaultParagraphStyle = p
        typingAttributes = [.font: PasteBlockView.body, .foregroundColor: DuoNSColor.text, .paragraphStyle: p]
        setAccessibilityLabel("Pasted text")
    }
    required init?(coder: NSCoder) { fatalError() }
    override init(frame: NSRect, textContainer: NSTextContainer?) { super.init(frame: frame, textContainer: textContainer) }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { owner?.host?.coordinator?.chat.ui.composerFocused = true }
        return ok
    }
    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { owner?.host?.coordinator?.chat.ui.composerFocused = false }
        return ok
    }
    override func setSelectedRange(_ r: NSRange) { super.setSelectedRange(r); scrollRangeToVisible(r) }
}

/// Over the opened text's last line: the text under it dims, saying there is more to scroll to.
final class PasteBlockFade: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ p: NSPoint) -> NSView? { nil }
    override func draw(_ r: NSRect) {
        NSGradient(colors: [DuoNSColor.ground.withAlphaComponent(0), DuoNSColor.ground.withAlphaComponent(0.55)])?.draw(in: bounds, angle: 90)
    }
}
