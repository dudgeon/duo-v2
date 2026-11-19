import AppKit
import Foundation

/// The fallback bar's Debug report as a window to photograph (F-749; Geoff, 2026-11-17: "make the debug window larger
/// and easier to photograph … user generally cannot email the debug payload"). A stand-in for a dev surface (Q-597):
/// the window takes most of the screen, the report sits in two columns (what fired, the evidence and the history on
/// the left; the screen the reader judged on the right) in one monospaced size fitted so the whole report shows at
/// once, text on `ground` for contrast. Copy Report puts the text on the pasteboard; Save to Project writes it into
/// the session's folder, where Claude can read it (`duo2 session chat why --save` does the same).
@MainActor
public final class FallbackReportWindow: NSWindowController, NSWindowDelegate {
    private static var open: [FallbackReportWindow] = []

    /// Shows the report in a window over most of the main screen. `save` writes it and returns where.
    public static func show(report: String, save: (() throws -> URL)?) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = screen.insetBy(dx: screen.width * 0.03, dy: screen.height * 0.03)
        let w = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Why chat mode showed the terminal"
        w.isReleasedWhenClosed = false
        let view = FallbackReportView(report: report, save: save, close: { [weak w] in w?.close() })
        w.contentView = view
        let c = FallbackReportWindow(window: w)
        w.delegate = c
        open.append(c)
        w.setFrame(frame, display: true)
        c.showWindow(nil)
        w.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) { Self.open.removeAll { $0 === self } }
}

/// The report's two columns and its buttons. Public so DuoChecks can draw it to an image off screen.
@MainActor
public final class FallbackReportView: NSView {
    let columns: (summary: String, screen: String)
    private let left = NSTextView(), right = NSTextView()
    private let leftScroll = NSScrollView(), rightScroll = NSScrollView()
    private let status = NSTextField(labelWithString: "")
    private let bar = NSStackView()
    private let report: String
    private let save: (() throws -> URL)?
    private let close: () -> Void
    /// The fitted size, for the checks.
    public private(set) var fontSize: CGFloat = 13

    public init(report: String, save: (() throws -> URL)?, close: @escaping () -> Void) {
        self.report = report
        self.save = save
        self.close = close
        let c = ChatFallbackReport.columns(report)
        // Blank rows under the dialog take height and say nothing: the window leaves them out (the text keeps them).
        var rows = c.screen.components(separatedBy: "\n")
        while let last = rows.last, rows.count > 1, last.count > 5, last.dropFirst(3).hasPrefix(" |"), last.dropFirst(5).trimmingCharacters(in: .whitespaces).isEmpty { rows.removeLast() }
        columns = (c.summary, rows.joined(separator: "\n"))
        super.init(frame: NSRect(x: 0, y: 0, width: 1400, height: 860))
        for (tv, sv) in [(left, leftScroll), (right, rightScroll)] {
            tv.isEditable = false
            tv.isSelectable = true
            tv.drawsBackground = false
            tv.textContainerInset = NSSize(width: 0, height: 0)
            tv.textContainer?.lineFragmentPadding = 0
            sv.documentView = tv
            sv.hasVerticalScroller = true
            // Overlay scrollers, hidden until needed: a legacy scroller takes 15 pt of the column, and the text laid
            // out under it was clipped at the edge (the director's review of F-752's capture).
            sv.scrollerStyle = .overlay
            sv.autohidesScrollers = true
            sv.drawsBackground = false
            sv.borderType = .noBorder
            addSubview(sv)
        }
        // The screen rows keep their columns: no wrapping on the right.
        right.textContainer?.widthTracksTextView = false
        right.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        right.isHorizontallyResizable = true
        rightScroll.hasHorizontalScroller = true
        let copy = NSButton(title: "Copy Report", target: self, action: #selector(copyReport))
        copy.keyEquivalent = "\r"
        let saveButton = NSButton(title: "Save to Project", target: self, action: #selector(saveReport))
        saveButton.isEnabled = save != nil
        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeWindow))
        closeButton.keyEquivalent = "\u{1b}"
        status.textColor = DuoNSColor.text2
        status.lineBreakMode = .byTruncatingMiddle
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.setViews([status], in: .leading)
        bar.setViews([closeButton, saveButton, copy], in: .trailing)
        addSubview(bar)
        status.stringValue = "Nothing is sent anywhere. Photograph this window, copy the report, or save it into the project for Claude."
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    /// `ground`, resolved as it draws, so the window follows light and dark.
    public override func draw(_ dirtyRect: NSRect) {
        DuoNSColor.ground.setFill()
        dirtyRect.fill()
    }

    static let margin: CGFloat = 20, gutter: CGFloat = 28, barHeight: CGFloat = 44

    public override func layout() {
        super.layout()
        let m = Self.margin
        let content = NSRect(x: m, y: m, width: bounds.width - 2 * m, height: bounds.height - 2 * m - Self.barHeight)
        bar.frame = NSRect(x: m, y: bounds.height - Self.barHeight - m / 2, width: bounds.width - 2 * m, height: Self.barHeight)
        let fit = Self.fit(columns, in: content.size, gutter: Self.gutter)
        fontSize = fit.size
        let rightWidth = min(fit.rightWidth, content.width * 0.62)
        let leftWidth = content.width - rightWidth - Self.gutter
        leftScroll.frame = NSRect(x: content.minX, y: content.minY, width: leftWidth, height: content.height)
        rightScroll.frame = NSRect(x: content.minX + leftWidth + Self.gutter, y: content.minY, width: rightWidth, height: content.height)
        // Lay the summary out at the width the scroll view actually shows, so a long value wraps inside the column.
        let shown = leftScroll.contentSize.width
        left.frame = NSRect(x: 0, y: 0, width: shown, height: content.height)
        left.textContainer?.widthTracksTextView = true
        left.textContainer?.containerSize = NSSize(width: shown, height: .greatestFiniteMagnitude)
        left.textStorage?.setAttributedString(Self.styled(columns.summary, size: fit.size))
        right.textStorage?.setAttributedString(Self.styled(columns.screen, size: fit.size))
        right.sizeToFit()
        left.sizeToFit()
    }

    /// Key lines and headings in semibold `text`; the rest in regular `text`, row numbers in `text2`.
    static func styled(_ s: String, size: CGFloat) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let regular = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: size, weight: .semibold)
        let cw = ("M" as NSString).size(withAttributes: [.font: regular]).width
        let key = ["rule:", "message:", "request pending:", "hooks:", "verdict:", "when:"]
        for (i, line) in s.components(separatedBy: "\n").enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            // A wrapped line continues under its own text, two in from where it starts.
            let para = NSMutableParagraphStyle()
            para.lineHeightMultiple = 1.08
            para.lineBreakMode = .byWordWrapping
            para.headIndent = CGFloat(line.prefix { $0 == " " }.count + 2) * cw
            let heading = !line.hasPrefix(" ") && !t.isEmpty && !(line.count > 5 && line.dropFirst(3).hasPrefix(" | "))
            let isKey = key.contains { t.hasPrefix($0) }
            var attrs: [NSAttributedString.Key: Any] = [.font: heading || isKey ? bold : regular, .foregroundColor: DuoNSColor.text, .paragraphStyle: para]
            if line.count > 5, line.dropFirst(3).hasPrefix(" | ") {
                // A screen row: its number in text2.
                let n = NSMutableAttributedString(string: String(line.prefix(6)), attributes: [.font: regular, .foregroundColor: DuoNSColor.text2, .paragraphStyle: para])
                n.append(NSAttributedString(string: String(line.dropFirst(6)), attributes: attrs))
                out.append(n)
            } else {
                if i == 0 { attrs[.font] = NSFont.monospacedSystemFont(ofSize: size * 1.15, weight: .semibold) }
                out.append(NSAttributedString(string: line, attributes: attrs))
            }
            out.append(NSAttributedString(string: "\n", attributes: [.font: regular, .paragraphStyle: para]))
        }
        return out
    }

    /// The largest size (1.5 to 0.75 times the `mono` token) at which the screen rows fit unwrapped beside the summary, and both columns fit
    /// the height with the summary wrapped at its width.
    public static func fit(_ c: (summary: String, screen: String), in size: NSSize, gutter: CGFloat) -> (size: CGFloat, rightWidth: CGFloat) {
        let rightLines = c.screen.components(separatedBy: "\n")
        let widest = rightLines.map(\.count).max() ?? 0
        /// The laid-out height of a column at its width, as the text view draws it.
        func height(_ text: String, _ s: CGFloat, _ width: CGFloat) -> CGFloat {
            styled(text, size: s).boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        }
        let base = DuoTextStyle.mono.spec.size
        var s: CGFloat = (base * 1.5).rounded()
        while s > (base * 0.75).rounded() {
            let font = NSFont.monospacedSystemFont(ofSize: s, weight: .regular)
            let cw = ("M" as NSString).size(withAttributes: [.font: font]).width
            let rightWidth = CGFloat(widest) * cw + 24
            let leftWidth = size.width - rightWidth - gutter
            if leftWidth >= 60 * cw, height(c.summary, s, leftWidth) <= size.height, height(c.screen, s, .greatestFiniteMagnitude) <= size.height {
                return (s, rightWidth)
            }
            s -= 0.5
        }
        let font = NSFont.monospacedSystemFont(ofSize: s, weight: .regular)
        return (s, CGFloat(widest) * ("M" as NSString).size(withAttributes: [.font: font]).width + 24)
    }

    /// How far the summary's widest laid-out line runs past the column the scroll view shows (0: none), for the checks.
    public func summaryOverflow() -> CGFloat {
        guard let lm = left.layoutManager, let tc = left.textContainer else { return .infinity }
        lm.ensureLayout(for: tc)
        var widest: CGFloat = 0
        lm.enumerateLineFragments(forGlyphRange: lm.glyphRange(for: tc)) { _, used, _, _, _ in widest = max(widest, used.maxX) }
        return max(0, widest - leftScroll.contentSize.width)
    }

    @objc func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        status.stringValue = "Copied."
    }

    @objc func saveReport() {
        guard let save else { return }
        do {
            let url = try save()
            status.stringValue = "Saved to \(url.path)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            status.stringValue = "Couldn’t save: \(error.localizedDescription)"
        }
    }

    @objc func closeWindow() { close() }

    /// Draws the view at `size` to a PNG, for captures (no window is shown).
    public func png(size: NSSize, scale: CGFloat = 2) -> Data? {
        frame = NSRect(origin: .zero, size: size)
        layoutSubtreeIfNeeded()
        layout()
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        rep.size = bounds.size
        let big = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        guard let big else { return nil }
        big.size = bounds.size
        cacheDisplay(in: bounds, to: big)
        return big.representation(using: .png, properties: [:])
    }
}

extension ChatFallbackReport {
    /// The report in two columns for the window: the screen the reader judged (its heading and rows) on the right,
    /// everything else on the left, in the report's order.
    public static func columns(_ report: String) -> (summary: String, screen: String) {
        let lines = report.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.hasPrefix("Screen the reader judged") }) else { return (report, "") }
        var end = start + 1
        while end < lines.count, !lines[end].isEmpty { end += 1 }
        let screen = Array(lines[start..<end])
        let rest = Array(lines[..<start]) + Array(lines[min(end + 1, lines.count)...])
        return (rest.joined(separator: "\n").trimmingCharacters(in: .newlines), screen.joined(separator: "\n"))
    }

    /// Writes the report into the session's folder (`.duo/chat-reports/`), where Claude can read it, and returns the file.
    public static func save(_ report: String, folder: URL, at date: Date = Date()) throws -> URL {
        let dir = folder.appending(path: ".duo/chat-reports")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmmss"
        let url = dir.appending(path: "chat-fallback-\(f.string(from: date)).txt")
        try (report + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
