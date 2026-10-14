import AppKit

// The composer's Markdown look (DL-188, chat-markdown-handoff `composer`): attributes over the typed
// text, never edits to it. ComposerMarkdown says what each range is; this puts the face on it and
// draws what attributes can't (the fence ground, the quote rule, the bullet).

extension ComposerTextView {
    static let line = DuoTextStyle.chatBody.spec.lineHeight
    static let listColumn: CGFloat = 22      // a bullet's column: the text starts this far from the marker
    static let numberColumn: CGFloat = 28    // a numbered item's text, from the start of its line
    static let nestStep: CGFloat = 11        // each leading space of a nested item
    static let quoteColumn: CGFloat = 12     // the rule (2) and the gap (10)
    static let fenceInset: CGFloat = 14      // the fence's own padding, inside its ground
    static let codeFont = NSFont.monospacedSystemFont(ofSize: DuoTextStyle.mono.spec.size, weight: .regular)
    static let inlineCodeFont = NSFont.monospacedSystemFont(ofSize: DuoTextStyle.chatInlineCode.spec.size, weight: .regular)

    static func width(_ s: String, _ f: NSFont) -> CGFloat { (s as NSString).size(withAttributes: [.font: f]).width }

    /// The font with a weight and a slant, in the same family (system or mono) and size.
    static func face(_ f: NSFont, bold: Bool, italic: Bool) -> NSFont {
        let mono = f.fontDescriptor.symbolicTraits.contains(.monoSpace)
        var out = f
        if bold { out = mono ? .monospacedSystemFont(ofSize: f.pointSize, weight: .semibold) : .systemFont(ofSize: f.pointSize, weight: .semibold) }
        if italic, let d = Optional(out.fontDescriptor.withSymbolicTraits(out.fontDescriptor.symbolicTraits.union(.italic))), let i = NSFont(descriptor: d, size: out.pointSize) { out = i }
        return out
    }

    func paragraph(head: CGFloat = 0, first: CGFloat? = nil, tail: CGFloat = 0) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = Self.line; p.maximumLineHeight = Self.line
        p.headIndent = head; p.firstLineHeadIndent = first ?? 0; p.tailIndent = tail
        return p
    }

    func styleMarkdown() {
        guard let ts = textStorage else { return }
        if hasMarkedText() { return }                       // an IME is composing: style on the next change
        let full = NSRange(location: 0, length: ts.length)
        for key: NSAttributedString.Key in [.underlineStyle, .underlineColor, .strikethroughStyle, .backgroundColor, .kern] { ts.removeAttribute(key, range: full) }
        guard ts.length > 0 else { md = .init(); return }
        let s = ts.string as NSString
        md = ts.length > 30_000 ? .init() : ComposerMarkdown.analyze(ts.string)   // a huge paste stays plain
        ts.beginEditing()
        ts.addAttribute(.foregroundColor, value: DuoNSColor.text, range: full)
        let defaultStyle = defaultParagraphStyle ?? paragraph()

        func plain(_ r: NSRange, _ body: (NSRange) -> Void) {   // the parts of a range that aren't attachments
            ts.enumerateAttribute(.attachment, in: r) { a, sub, _ in if a == nil { body(sub) } }
        }
        func hasBlock(_ r: NSRange) -> Bool {
            var found = false
            ts.enumerateAttribute(.attachment, in: r) { a, _, stop in if a is ComposerPasteBlock { found = true; stop.pointee = true } }
            return found
        }

        // Lines: paragraph shape, and the marks drawn over.
        for line in md.lines {
            let r = line.range
            let para = NSRange(location: r.location, length: min(ts.length - r.location, r.length + 1))
            guard para.length > 0, !hasBlock(para) else { continue }
            var style: NSParagraphStyle = defaultStyle
            switch line.kind {
            case .plain, .heading: break
            case .bullet(let lead, let marker, let gap):
                // Leading spaces step 11 each; the marker is invisible and holds the column; the text starts 22 on.
                let space = Self.width(" ", Self.font)
                if lead > 0 { ts.addAttribute(.kern, value: Self.nestStep - space, range: NSRange(location: r.location, length: lead)) }
                let m = NSRange(location: marker, length: 1)
                let natural = Self.width(s.substring(with: m), Self.font) + Self.width(s.substring(with: NSRange(location: marker + 1, length: gap)), Self.font)
                ts.addAttributes([.foregroundColor: NSColor.clear, .kern: max(0, Self.listColumn - natural)], range: m)
                style = paragraph(head: CGFloat(lead) * Self.nestStep + Self.listColumn)
            case .number(let lead, let mark):
                // As drawn: the number right-aligned in a 22 column, the text 28 from the start (Q-195 stand-in for the indent).
                let space = Self.width(" ", Self.font)
                if lead > 0 { ts.addAttribute(.kern, value: Self.nestStep - space, range: NSRange(location: r.location, length: lead)) }
                var digits = 0
                while lead + digits < mark + lead, !" \t".contains(Character(UnicodeScalar(s.character(at: r.location + lead + digits))!)) { digits += 1 }
                let first = max(0, Self.listColumn - Self.width(s.substring(with: NSRange(location: r.location + lead, length: digits)), Self.font))
                let natural = Self.width(s.substring(with: NSRange(location: r.location + lead, length: mark)), Self.font)
                ts.addAttribute(.kern, value: max(0, Self.numberColumn - first - natural), range: NSRange(location: r.location + lead + mark - 1, length: 1))
                style = paragraph(head: CGFloat(lead) * Self.nestStep + Self.numberColumn, first: first)
            case .quote(let mark):
                let at = s.range(of: ">", range: r).location
                let m = NSRange(location: at, length: mark)
                let natural = Self.width(s.substring(with: m), Self.font)
                ts.addAttribute(.foregroundColor, value: NSColor.clear, range: m)
                ts.addAttribute(.kern, value: max(0, Self.quoteColumn - natural), range: NSRange(location: NSMaxRange(m) - 1, length: 1))
                ts.addAttribute(.foregroundColor, value: DuoNSColor.text2, range: NSRange(location: NSMaxRange(m), length: NSMaxRange(r) - NSMaxRange(m)))
                style = paragraph(head: Self.quoteColumn + Self.width(s.substring(with: NSRange(location: r.location, length: at - r.location)), Self.font))
            case .fenceMark, .fenceBody:
                if r.length > 0 { plain(r) { ts.addAttribute(.font, value: Self.codeFont, range: $0) } }
                style = paragraph(head: Self.fenceInset, first: Self.fenceInset, tail: -Self.fenceInset)
            }
            ts.addAttribute(.paragraphStyle, value: style, range: para)
        }

        // Runs: inline marks, in the order the analysis found them (a mark's dim comes after its span's face).
        for run in md.runs where run.range.length > 0 && NSMaxRange(run.range) <= ts.length {
            let st = run.style
            if st.contains(.dim) { ts.addAttribute(.foregroundColor, value: DuoNSColor.text2, range: run.range) }
            if st.contains(.strike) { ts.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: run.range) }
            if st.contains(.link) { ts.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: DuoNSColor.controlEdge], range: run.range) }
            if st.contains(.code) {
                plain(run.range) { ts.addAttributes([.font: Self.inlineCodeFont, .backgroundColor: DuoNSColor.chatGround], range: $0) }
            }
            if st.contains(.bold) || st.contains(.heading) || st.contains(.italic) {
                plain(run.range) { sub in
                    ts.enumerateAttribute(.font, in: sub) { f, fr, _ in
                        guard let f = f as? NSFont else { return }
                        ts.addAttribute(.font, value: Self.face(f, bold: st.contains(.bold) || st.contains(.heading), italic: st.contains(.italic)), range: fr)
                    }
                }
            }
        }
        ts.endEditing()
        typingAttributes = baseAttributes
        needsDisplay = true
    }

    // MARK: Drawing what attributes can't

    private func fragment(_ charRange: NSRange) -> NSRect? {
        guard let lm = layoutManager, let ts = textStorage, charRange.location < ts.length else { return nil }
        let g = lm.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard g.length > 0, lm.isValidGlyphIndex(g.location), lm.isValidGlyphIndex(NSMaxRange(g) - 1) else { return nil }
        let first = lm.lineFragmentRect(forGlyphAt: g.location, effectiveRange: nil)
        let last = lm.lineFragmentRect(forGlyphAt: NSMaxRange(g) - 1, effectiveRange: nil)
        return first.union(last)
    }

    /// The fences' ground and the quotes' rule, under the text.
    func drawMarkdownBehind() {
        guard let tc = textContainer, let lm = layoutManager, textStorage?.length ?? 0 > 0 else { return }
        let o = textContainerOrigin
        for f in md.fences {
            guard var r = fragment(f) else { continue }
            if NSMaxRange(f) == textStorage?.length, textStorage?.string.hasSuffix("\n") == true, !lm.extraLineFragmentRect.isEmpty { r = r.union(lm.extraLineFragmentRect) }
            let box = NSRect(x: o.x + tc.lineFragmentPadding, y: o.y + r.minY, width: tc.size.width - 2 * tc.lineFragmentPadding, height: r.height)
            DuoNSColor.chatGround.setFill()
            NSBezierPath(roundedRect: box, xRadius: DuoMetric.radiusChatCodeBlock, yRadius: DuoMetric.radiusChatCodeBlock).fill()
        }
        // One rule down each run of quote lines.
        var from: NSRange?, to: NSRange?
        func flush() {
            if let a = from, let b = to, let r = fragment(a)?.union(fragment(b) ?? .zero) {
                DuoNSColor.rule.setFill()
                NSBezierPath(roundedRect: NSRect(x: o.x + tc.lineFragmentPadding, y: o.y + r.minY, width: 2, height: r.height), xRadius: 1, yRadius: 1).fill()
            }
            from = nil; to = nil
        }
        for line in md.lines {
            if case .quote = line.kind { if from == nil { from = line.range }; to = line.range } else { flush() }
        }
        flush()
    }

    /// A bullet where the dash is, over the text.
    func drawMarkdownOver() {
        guard let lm = layoutManager, let ts = textStorage, ts.length > 0 else { return }
        let o = textContainerOrigin
        let dot = NSAttributedString(string: "\u{2022}", attributes: [.font: Self.font, .foregroundColor: DuoNSColor.text])
        let w = dot.size().width
        for line in md.lines {
            guard case .bullet(_, let marker, _) = line.kind, marker < ts.length else { continue }
            let g = lm.glyphIndexForCharacter(at: marker)
            guard lm.isValidGlyphIndex(g) else { continue }
            let rect = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
            let loc = lm.location(forGlyphAt: g)
            dot.draw(at: NSPoint(x: o.x + rect.minX + loc.x + Self.listColumn / 2 - w / 2, y: o.y + rect.minY + loc.y - Self.font.ascender))
        }
    }
}

/// For DuoChecks: a real composer in an offscreen window, driven by the same paths as the keyboard.
@MainActor public final class ComposerMarkdownProbe {
    public struct Look: Equatable {
        public var bold = false, italic = false, mono = false, dim = false, struck = false, underlined = false, hidden = false, grounded = false
    }
    let view = ComposerTextView()
    let window: NSWindow

    public init(_ text: String, width: CGFloat = 632) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 300), styleMask: [.borderless], backing: .buffered, defer: true)
        let host = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: 300))
        host.documentView = view
        view.frame = NSRect(x: 0, y: 0, width: width, height: 300)
        window.contentView = host
        window.makeFirstResponder(view)
        view.delegate = ChatComposerField.Coordinator(chat: ChatSession(key: "probe", mode: .chat))
        view.setPlain("")
        view.insertText(text, replacementRange: view.selectedRange())
        view.undoManager?.groupsByEvent = false   // no run loop here: a key is the group
        view.undoManager?.removeAllActions()
    }

    /// What would be sent, and what the storage holds.
    public var plain: String { view.plainText }
    public var storage: String { view.textStorage?.string ?? "" }
    public var selection: NSRange { get { view.selectedRange() } set { view.setSelectedRange(newValue) } }
    public var undoManager: UndoManager? { view.undoManager }
    public func type(_ s: String) { view.insertText(s, replacementRange: view.selectedRange()) }
    /// A chord: "b", "i", "x", "e" or "k". Returns whether the composer took it.
    public func key(_ k: String) -> Bool {
        let shift = k == "x"
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? [.command, .shift] : .command, timestamp: 0, windowNumber: window.windowNumber,
                                 context: nil, characters: k, charactersIgnoringModifiers: k, isARepeat: false, keyCode: 0)
        view.undoManager?.beginUndoGrouping()
        defer { view.undoManager?.endUndoGrouping() }
        return e.map { view.performKeyEquivalent(with: $0) } ?? false
    }
    public var lineHeights: Set<CGFloat> {
        var out = Set<CGFloat>()
        view.textStorage?.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: view.textStorage?.length ?? 0)) { p, _, _ in
            if let p = p as? NSParagraphStyle { out.insert(p.minimumLineHeight); out.insert(p.maximumLineHeight) }
        }
        return out
    }
    public var typing: Bool { view.typingAttributes[.foregroundColor] as? NSColor == DuoNSColor.text }
    public func look(at i: Int) -> Look {
        guard let ts = view.textStorage, i < ts.length else { return Look() }
        let a = ts.attributes(at: i, effectiveRange: nil)
        let f = a[.font] as? NSFont
        var l = Look()
        l.mono = f?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true
        l.italic = f?.fontDescriptor.symbolicTraits.contains(.italic) == true
        l.bold = f.map { NSFontManager.shared.weight(of: $0) >= 8 } ?? false
        l.dim = (a[.foregroundColor] as? NSColor) == DuoNSColor.text2
        l.hidden = (a[.foregroundColor] as? NSColor) == NSColor.clear
        l.struck = (a[.strikethroughStyle] as? Int ?? 0) != 0
        l.underlined = (a[.underlineStyle] as? Int ?? 0) != 0
        l.grounded = (a[.backgroundColor] as? NSColor) == DuoNSColor.chatGround
        return l
    }
}
