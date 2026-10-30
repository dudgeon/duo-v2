import AppKit
import DuoControl
import SwiftUI

/// The terminal mic (voice-input-handoff `terminal`, DL-261): a 24 × 18 patch on Claude's input box's bottom
/// rule, its right edge 2 columns in from the corner. It is the one thing Duo draws over the terminal, so it
/// is careful: it sits only where every cell under it is a rule character, and hides on any frame where that
/// isn't so, where no box is found, where a question is up, or where the view is scrolled back. It re-anchors
/// on every poll of the screen (20 a second: SwiftTerm has one output hook, which chat mode owns). Only its own
/// rect takes clicks.
@MainActor
final class TerminalMicView: NSView {
    static let size = NSSize(width: 24, height: 18)
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
        let cells = Int(ceil(Self.size.width / cell.width))
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
        let x = tf.minX + CGFloat(a.lastCol + 1) * cell.width - Self.size.width
        let y = tf.minY + CGFloat(a.row) * cell.height + (cell.height - Self.size.height) / 2
        let f = NSRect(x: x.rounded(), y: y.rounded(), width: Self.size.width, height: Self.size.height)
        if frame != f { frame = f }
        lastFrame = f
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

    override func draw(_ dirty: NSRect) {
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
