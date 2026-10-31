import AppKit
import DuoControl
import SwiftUI

/// The terminal mic (voice-input-handoff `terminal`, DL-261): a 24 × 18 patch on Claude's input box's bottom
/// rule, its right edge 2 columns in from the corner. It is the one thing Duo draws over the terminal, so it
/// is careful: it sits only where every cell under it is a rule character, and hides on any frame where that
/// isn't so, where no box is found, where a question is up, or where the view is scrolled back. It re-anchors
/// on every poll of the screen (20 a second: SwiftTerm has one output hook, which chat mode owns). Only its own
/// rect takes clicks.
/// Design studies for the mic's look (`MicFix.dc.html`, after Geoff rejected the thin outline in a gap of the rule):
/// `a` a 30 × 20 capsule on the rule, `b` the same with words, `c` a round button in a margin Duo keeps beside the
/// terminal. Only an isolated Duo honours `DUO_VOICE_MIC_STYLE`; a release draws `today`.
enum VoiceMicStyle {
    case today, a, b, c
    static let current: VoiceMicStyle = {
        guard SupportFolder.isIsolated else { return .today }
        switch ProcessInfo.processInfo.environment["DUO_VOICE_MIC_STYLE"] { case "a": return .a; case "b": return .b; case "c": return .c; default: return .today }
    }()
}

@MainActor
final class TerminalMicView: NSView {
    static let size = NSSize(width: 24, height: 18)
    static let chip = NSSize(width: 30, height: 20)
    static let round: CGFloat = 28
    /// A harness switch: draw the hover look.
    var forceHover = false
    private var cellH: CGFloat = 15
    private var chipWidth: CGFloat = 30
    weak var session: TerminalSession?
    weak var voice: VoiceInput?
    var onClick: (() -> Void)?
    /// Where the terminal sits in the slot (its frame).
    var terminalFrame: () -> NSRect = { .zero }
    private var timer: Timer?
    private var hovering = false
    private var lastRows: [String] = []
    private var bottomRow = 0
    private var lastDims = ""
    private var lastAnchor: VoiceMicAnchor?
    private var notice: NSHostingView<VoiceNoticeBox>?
    /// Where the mic last was in the slot, for the notice.
    private var lastFrame: NSRect?

    /// `DUO_VOICE_MIC_ON_SHELL=1` draws the mic on a shell tab too, so a scripted run can feed recorded Claude screens
    /// to a shell and watch the finder. Only an isolated Duo honours it: a release never does.
    static let onShellForProofs = SupportFolder.isIsolated && ProcessInfo.processInfo.environment["DUO_VOICE_MIC_ON_SHELL"] == "1"

    override var isFlipped: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); isHidden = true; setAccessibilityLabel("Voice input"); setAccessibilityRole(.button) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate(); timer = nil
        guard window != nil else { return }
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with e: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with e: NSEvent) { hovering = false; needsDisplay = true }
    override func mouseDown(with e: NSEvent) { onClick?() }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }

    /// No input device and nothing running: options 1 and 2 of NoMic.dc.html change the look.
    private var noMic: Bool { !(voice?.microphoneAvailable ?? true) && !state.isActive }

    private var state: VoiceState {
        guard let v = voice, let s = session, v.target == .terminal(s.key) else { return .idle }
        return v.state
    }

    func tick() {
        guard let s = session, let sv = superview, s.isClaude || Self.onShellForProofs, !s.exited, s.view.superview === sv, !s.view.isHidden else { return hide() }
        let snap = s.view.terminalStateSnapshot()
        let rows = s.view.visibleRowsText(0..<snap.dimensions.rows)
        let cell = s.cellSize
        guard cell.width > 0, cell.height > 0 else { return hide() }
        let style = VoiceMicStyle.current
        cellH = cell.height
        // B's chip is as wide as its words; A's and the old patch are fixed. A and B keep 6 pt clear each side of the chip.
        if style == .b { chipWidth = Self.wordsChipWidth(listening: state == .listening) }
        let wanted: CGFloat = switch style {
        case .today: Self.size.width
        case .a: Self.chip.width + 12
        case .b: chipWidth + 12
        case .c: 1
        }
        let cells = Int(ceil(wanted / cell.width))
        // Scrolled back: the viewport's top row (SwiftTerm's yDisp) is below the highest it has been. The scroller's own
        // position isn't kept up to date while output arrives, so it can't say (F-441).
        let dims = "\(snap.dimensions.cols)x\(snap.dimensions.rows)"
        if dims != lastDims { lastDims = dims; bottomRow = 0 }
        if snap.viewportRow >= bottomRow { bottomRow = snap.viewportRow }
        let scrolled = snap.viewportRow < bottomRow
        let cursor = (row: snap.cursor.row, col: snap.cursor.col)
        guard let a = InputBoxFinder.find(rows: rows, cursor: cursor, scrolledBack: scrolled, micCells: cells) else {
            updateNotice(); return hide()
        }
        // The patch covers cells that are all rule characters (the finder checked), so it breaks the rule and nothing else.
        let tf = s.view.frame
        // Right edge on the grid: 2 columns in from the rule's last character, which is the corner (DL-261).
        let f: NSRect
        switch style {
        case .today:
            let x = tf.minX + CGFloat(a.lastCol + 1) * cell.width - Self.size.width
            let y = tf.minY + CGFloat(a.row) * cell.height + (cell.height - Self.size.height) / 2
            f = NSRect(x: x.rounded(), y: y.rounded(), width: Self.size.width, height: Self.size.height)
        case .a, .b:
            // The overlay is the cells' width, `console` where the rule is hidden; the chip sits in its middle, centred on the rule's row.
            let w = CGFloat(a.lastCol - a.firstCol + 1) * cell.width
            let x = tf.minX + CGFloat(a.firstCol) * cell.width
            let h = Self.chip.height
            let y = tf.minY + (CGFloat(a.row) + 0.5) * cell.height - h / 2
            f = NSRect(x: x.rounded(), y: y.rounded(), width: w, height: h)
        case .c:
            // Beside the box, in the margin Duo keeps: centred on the prompt row the finder reports.
            let y = tf.minY + (CGFloat(a.promptRow) + 0.5) * cell.height - Self.round / 2
            f = NSRect(x: (sv.bounds.width - 10 - Self.round).rounded(), y: y.rounded(), width: Self.round, height: Self.round)
        }
        if frame != f { frame = f }
        lastFrame = f
        // No microphone, option 2 (NoMic.dc.html): no chip until there is one; the notice still has its place.
        if noMic, VoiceNoMicStyle.current == .hidden { updateNotice(); return hide() }
        if isHidden { isHidden = false }
        needsDisplay = true
        updateNotice()
    }

    private func hide() {
        if !isHidden { isHidden = true }
    }

    /// "Voice input stopped: Claude asked a question…" at the mic's last place, 6 s.
    private func updateNotice() {
        guard let sv = superview, let s = session, let n = voice?.notice, n.target == .terminal(s.key), let at = lastFrame else {
            notice?.removeFromSuperview(); notice = nil; return
        }
        if notice == nil {
            let h = NSHostingView(rootView: VoiceNoticeBox(text: n.text))
            sv.addSubview(h)
            notice = h
        }
        guard let h = notice else { return }
        let size = h.fittingSize
        h.frame = NSRect(x: max(0, min(at.maxX - size.width, sv.bounds.width - size.width)), y: max(0, at.minY - size.height - 4), width: size.width, height: size.height)
    }

    // MARK: The design studies (MicFix.dc.html)

    static func wordsChipWidth(listening: Bool) -> CGFloat {
        let f = NSFont.systemFont(ofSize: DuoTextStyle.control.spec.size)
        let w = listening ? ("Listening" as NSString).size(withAttributes: [.font: f]).width
                          : ("Voice" as NSString).size(withAttributes: [.font: f]).width + 5 + ("⇧⌘D" as NSString).size(withAttributes: [.font: f]).width
        return ceil(7 + 11 + 5 + w + 7)
    }

    /// The mic mark of the board's SVG (16-unit box), stroked at 1.6 units.
    static func micPath(size: CGFloat, slash: Bool = false) -> NSBezierPath {
        let k = size / 16
        let p = NSBezierPath(roundedRect: NSRect(x: 5.5 * k, y: 1.5 * k, width: 5 * k, height: 8.5 * k), xRadius: 2.5 * k, yRadius: 2.5 * k)
        p.move(to: NSPoint(x: 3 * k, y: 7.8 * k))
        for deg in stride(from: 0, through: 180, by: 10) {
            let t = Double(deg) * .pi / 180
            // From the left end round the bottom to the right end (y grows downward in this flipped view).
            p.line(to: NSPoint(x: (8 - 5 * cos(t)) * k, y: (7.8 + 5 * sin(t)) * k))
        }
        p.move(to: NSPoint(x: 8 * k, y: 12.8 * k)); p.line(to: NSPoint(x: 8 * k, y: 14.7 * k))
        if slash { p.move(to: NSPoint(x: 2 * k, y: 1.5 * k)); p.line(to: NSPoint(x: 14 * k, y: 14.5 * k)) }
        p.lineWidth = 1.6 * k; p.lineCapStyle = .round; p.lineJoinStyle = .round
        return p
    }

    private func drawChip(_ r: NSRect, round: Bool) {
        let st = state
        let listening = st == .listening
        let dashed: Bool = { if case .preparing = st { return true }; return st == .restricted }()
        let radius = r.height / 2
        let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        // Option 1 with no microphone: the chip keeps its edge, loses its fill, and its mark is slashed in a dimmer step.
        let slashed = noMic && VoiceNoMicStyle.current == .slashed
        (listening ? DuoNSColor.consoleText : slashed ? DuoNSColor.console : (hovering || forceHover) ? DuoNSColor.consoleMenuTarget : DuoNSColor.consoleRule).setFill()
        path.fill()
        (listening ? DuoNSColor.consoleText : DuoNSColor.tuiInputBorder).setStroke()
        if dashed { path.setLineDash([2, 2], count: 2, phase: 0) }
        path.lineWidth = 1; path.stroke()
        let ink = listening ? DuoNSColor.console : slashed ? DuoNSColor.consoleText2 : DuoNSColor.consoleText
        let slash = slashed
        let words = VoiceMicStyle.current == .b
        let markSize: CGFloat = round ? 13 : words ? 11 : 12
        let mark = Self.micPath(size: markSize, slash: slash)
        let f = NSFont.systemFont(ofSize: DuoTextStyle.control.spec.size)
        if words {
            let label = listening ? "Listening" : "Voice"
            let hint = listening ? "" : "⇧⌘D"
            let lw = (label as NSString).size(withAttributes: [.font: f]).width
            let hw = hint.isEmpty ? 0 : (hint as NSString).size(withAttributes: [.font: f]).width
            let total = markSize + 5 + lw + (hint.isEmpty ? 0 : 5 + hw)
            var x = r.minX + (r.width - total) / 2
            let t = NSAffineTransform(); t.translateX(by: x, yBy: r.minY + (r.height - markSize) / 2); ink.setStroke()
            let m = mark.copy() as! NSBezierPath; m.transform(using: t as AffineTransform); m.stroke()
            x += markSize + 5
            let ly = r.minY + (r.height - f.boundingRectForFont.height) / 2
            (label as NSString).draw(at: NSPoint(x: x, y: ly), withAttributes: [.font: f, .foregroundColor: listening ? DuoNSColor.console : DuoNSColor.consoleText])
            if !hint.isEmpty { (hint as NSString).draw(at: NSPoint(x: x + lw + 5, y: ly), withAttributes: [.font: f, .foregroundColor: DuoNSColor.consoleText2]) }
        } else {
            let t = NSAffineTransform(); t.translateX(by: r.minX + (r.width - markSize) / 2, yBy: r.minY + (r.height - markSize) / 2); ink.setStroke()
            let m = mark.copy() as! NSBezierPath; m.transform(using: t as AffineTransform); m.stroke()
        }
    }

    override func draw(_ dirty: NSRect) {
        switch VoiceMicStyle.current {
        case .today: drawToday()
        case .c: drawChip(bounds, round: true)
        case .a, .b:
            // `console` over the cells' row, so the rule isn't seen beside the chip; the chip centred on it.
            DuoNSColor.console.setFill()
            NSRect(x: 0, y: (bounds.height - cellH) / 2, width: bounds.width, height: cellH).fill()
            let w = VoiceMicStyle.current == .a ? Self.chip.width : chipWidth
            drawChip(NSRect(x: (bounds.width - w) / 2, y: 0, width: w, height: bounds.height), round: false)
        }
    }

    private func drawToday() {
        let st = state
        let listening = st == .listening
        let dashed: Bool = { if case .preparing = st { return true }; return st == .restricted }()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5)
        // The patch is `console`; hovered, `consoleRule`; listening, `consoleText`.
        (listening ? DuoNSColor.consoleText : hovering ? DuoNSColor.consoleRule : DuoNSColor.console).setFill()
        path.fill()
        if dashed {
            DuoNSColor.consoleRule.setStroke()
            let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
            p.setLineDash([2, 2], count: 2, phase: 0); p.lineWidth = 1; p.stroke()
        }
        let tint = listening ? DuoNSColor.console : hovering ? DuoNSColor.consoleText : DuoNSColor.consoleText2
        let cfg = NSImage.SymbolConfiguration(pointSize: DuoSymbolSize.barIcon, weight: .regular)
        if let img = NSImage(systemSymbolName: "mic", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
            let tinted = NSImage(size: img.size, flipped: false) { r in
                img.draw(in: r); tint.set(); r.fill(using: .sourceAtop); return true
            }
            tinted.draw(in: NSRect(x: (bounds.width - img.size.width) / 2, y: (bounds.height - img.size.height) / 2, width: img.size.width, height: img.size.height),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}
