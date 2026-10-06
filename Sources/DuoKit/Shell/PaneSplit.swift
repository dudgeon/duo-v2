import AppKit
import SwiftUI

/// A three-pane horizontal split with token-coloured 1 pt dividers (handoff §3, §7).
///
/// AppKit underneath so dividers take the design's colours (`rule`, `consoleRule`), side panes
/// collapse without being torn down (a collapsed pane keeps its view, and later its terminal:
/// LR-13), and the initial widths match the targets exactly. In the targets a pane's border is
/// inside its width, so a 340-wide pane is a 339-wide view plus the 1 pt divider.
struct PaneSplit: NSViewRepresentable {
    struct Pane {
        var view: AnyView
        /// Width including its divider, as drawn in the targets. `nil` for the flexible pane.
        var width: CGFloat?
        var minWidth: CGFloat
        var collapsible: Bool = false
        var collapsed: Bool = false
    }

    var panes: [Pane]
    /// One colour per divider, left to right.
    var dividerColors: [NSColor]
    /// Each pane's background, used to hide a divider beside a collapsed pane.
    var paneBackgrounds: [NSColor]
    var model: AppModel

    func makeNSView(context: Context) -> DuoSplitView {
        let split = DuoSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.delegate = context.coordinator
        for pane in panes {
            let host = NSHostingView(rootView: AnyView(pane.view.environment(model)))
            host.sizingOptions = []
            host.translatesAutoresizingMaskIntoConstraints = true
            split.addArrangedSubview(host)
        }
        apply(to: split, coordinator: context.coordinator)
        return split
    }

    func updateNSView(_ split: DuoSplitView, context: Context) {
        for (pane, host) in zip(panes, split.arrangedSubviews) {
            (host as? NSHostingView<AnyView>)?.rootView = AnyView(pane.view.environment(model))
        }
        apply(to: split, coordinator: context.coordinator)
    }

    private func apply(to split: DuoSplitView, coordinator: Coordinator) {
        coordinator.panes = panes
        split.dividerColors = dividerColors
        split.paneBackgrounds = paneBackgrounds
        split.designWidths = panes.map(\.width)
        for (i, pane) in panes.enumerated() where pane.collapsible {
            split.setCollapsed(pane.collapsed, paneAt: i)
        }
        // Fixed panes hold their width when the window resizes; the flexible pane absorbs it.
        for (i, pane) in panes.enumerated() {
            split.setHoldingPriority(pane.width == nil ? .defaultLow : .defaultHigh + 1, forSubviewAt: i)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        var panes: [Pane] = []

        func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
            guard let i = splitView.arrangedSubviews.firstIndex(of: subview), i < panes.count else { return false }
            return panes[i].collapsible
        }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposed: CGFloat, ofSubviewAt i: Int) -> CGFloat {
            // Divider i sits after subview i: keep subview i at or above its minimum.
            let left = splitView.arrangedSubviews[i].frame.minX
            return max(proposed, left + minWidth(i))
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposed: CGFloat, ofSubviewAt i: Int) -> CGFloat {
            // ...and keep subview i + 1 at or above its minimum.
            let next = i + 1
            guard next < splitView.arrangedSubviews.count else { return proposed }
            let right = splitView.arrangedSubviews[next].frame.maxX
            return min(proposed, right - minWidth(next) - splitView.dividerThickness)
        }

        /// The window resized (DL-129): side panes keep the width they have and the middle pane
        /// takes the change. Under the middle's minimum the right pane gives way first, down to its
        /// own, then the left. A hidden pane stays hidden.
        func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
            guard let split = splitView as? DuoSplitView, !split.isAnimatingPane,
                  let flex = panes.firstIndex(where: { $0.width == nil }), panes.count == splitView.arrangedSubviews.count
            else { splitView.adjustSubviews(); return }
            let views = splitView.arrangedSubviews
            let widths = PaneWidths.resized(
                current: views.map { splitView.isSubviewCollapsed($0) ? 0 : $0.frame.width },
                hidden: views.map { splitView.isSubviewCollapsed($0) },
                total: splitView.bounds.width - CGFloat(views.count - 1) * splitView.dividerThickness,
                flex: flex, minimums: panes.indices.map(minWidth))
            split.place(widths)
        }

        private func minWidth(_ i: Int) -> CGFloat {
            i < panes.count ? max(0, panes[i].minWidth - 1) : 0
        }
    }
}

final class DuoSplitView: NSSplitView {
    var dividerColors: [NSColor] = [] { didSet { needsDisplay = true } }
    var paneBackgrounds: [NSColor] = []
    var designWidths: [CGFloat?] = []
    private var placed = false
    /// A side pane is sliding in or out (DL-129): the window's resize rule waits for it.
    private(set) var isAnimatingPane = false
    private var savedWidths: [Int: CGFloat] = [:]
    /// Collapse requests that arrive before the view has a size are applied after first layout;
    /// collapsing a zero-sized split view leaves its panes in an inconsistent order.
    private var pendingCollapse: [Int: Bool] = [:]

    override var dividerThickness: CGFloat { 1 }

    override func drawDivider(in rect: NSRect) {
        // A collapsed subview keeps its old frame (it is hidden, not shrunk), so find the divider
        // by walking visible widths rather than by comparing frames.
        var x: CGFloat = 0, index = 0, best = CGFloat.infinity
        for i in 0..<max(0, arrangedSubviews.count - 1) {
            let v = arrangedSubviews[i]
            x += isSubviewCollapsed(v) ? 0 : v.frame.width
            if abs(x - rect.minX) < best { best = abs(x - rect.minX); index = i }
            x += dividerThickness
        }
        var color = dividerColors.indices.contains(index) ? dividerColors[index] : DuoNSColor.rule
        // Beside a collapsed pane the divider sits at the window edge: paint it as the open
        // neighbour so no stray rule shows.
        let left = index, right = index + 1
        if arrangedSubviews.indices.contains(left), isSubviewCollapsed(arrangedSubviews[left]), paneBackgrounds.indices.contains(right) {
            color = paneBackgrounds[right]
        } else if arrangedSubviews.indices.contains(right), isSubviewCollapsed(arrangedSubviews[right]), paneBackgrounds.indices.contains(left) {
            color = paneBackgrounds[left]
        }
        color.setFill()
        rect.fill()
    }

    override func layout() {
        super.layout()
        if !placed, bounds.width > 0 {
            placed = true
            placeAtDesignWidths()
            for (i, collapsed) in pendingCollapse.sorted(by: { $0.key < $1.key }) where isSubviewCollapsed(arrangedSubviews[i]) != collapsed { snapCollapsed(collapsed, paneAt: i) }   // as restored, no slide
            pendingCollapse.removeAll()
        }
    }

    /// Puts every divider where the targets draw it: fixed panes at their design width from the
    /// nearest window edge, the flexible pane taking the rest.
    func placeAtDesignWidths() {
        guard let flex = designWidths.firstIndex(where: { $0 == nil }) else { return }
        var x: CGFloat = 0
        for i in 0..<flex {
            x += designWidths[i] ?? 0
            if !isSubviewCollapsed(arrangedSubviews[i]) { setPosition(x - 1, ofDividerAt: i) }
        }
        var right = bounds.width
        for i in stride(from: designWidths.count - 1, to: flex, by: -1) {
            right -= designWidths[i] ?? 0
            if !isSubviewCollapsed(arrangedSubviews[i]) { setPosition(right, ofDividerAt: i - 1) }
        }
    }

    /// Sets each pane's frame from left to right; a hidden pane keeps its frame (it's hidden).
    func place(_ widths: [CGFloat]) {
        var x: CGFloat = 0
        for (i, v) in arrangedSubviews.enumerated() {
            if !isSubviewCollapsed(v) {
                v.frame = NSRect(x: x, y: 0, width: max(0, widths[i]), height: bounds.height)
                x += max(0, widths[i])
            }
            x += i < arrangedSubviews.count - 1 ? dividerThickness : 0
        }
        needsDisplay = true
    }

    /// Hides or shows a side pane: its width slides over `motion.paneToggle` (200 ms, ease-in-out),
    /// at once with Reduce Motion (DL-129). Terminals keep their size until it ends, so a PTY is
    /// resized once (LR-14).
    func setCollapsed(_ collapsed: Bool, paneAt i: Int) {
        guard placed else { pendingCollapse[i] = collapsed; return }
        guard !isAnimatingPane, arrangedSubviews.indices.contains(i), isSubviewCollapsed(arrangedSubviews[i]) != collapsed,
              let flex = designWidths.firstIndex(where: { $0 == nil }) else { return }
        guard window != nil, !MotionSettings.shared.reduce, PaneMotion.enabled else {
            snapCollapsed(collapsed, paneAt: i); return
        }
        let views = arrangedSubviews
        let pane = views[i]
        let open = collapsed ? pane.frame.width : openWidth(i)
        if collapsed { savedWidths[i] = open }
        if !collapsed { snapCollapsed(false, paneAt: i) }   // back in the split, then slide from nothing
        let start = views.map { isSubviewCollapsed($0) ? 0 : $0.frame.width }
        let duration = DuoMotionToken.paneToggle.duration
        isAnimatingPane = true
        PaneMotion.began()
        let began = CACurrentMediaTime()
        func step(_ t: CGFloat) {
            let e = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2   // ease-in-out
            var w = start
            w[i] = collapsed ? open * (1 - e) : open * e
            w[flex] = start[flex] + (start[i] - w[i])
            place(w)
        }
        func tick() {
            let t = min(1, CGFloat((CACurrentMediaTime() - began) / duration))
            step(t)
            if t < 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { MainActor.assumeIsolated { tick() } }
                return
            }
            isAnimatingPane = false
            if collapsed { snapCollapsed(true, paneAt: i, saving: false) }
            PaneMotion.ended()
        }
        tick()
    }

    /// The width a hidden pane comes back at: where it was, else its design width.
    private func openWidth(_ i: Int) -> CGFloat {
        return savedWidths[i] ?? (designWidths[i] ?? 300) - 1
    }

    /// Collapses or restores a side pane at once. The pane's view is kept, never torn down.
    /// `saving: false` when a slide already noted the width (the frame is nearly 0 by then).
    private func snapCollapsed(_ collapsed: Bool, paneAt i: Int, saving: Bool = true) {
        let isLeading = i == 0
        let divider = isLeading ? 0 : i - 1
        if collapsed {
            if saving { savedWidths[i] = arrangedSubviews[i].frame.width }
            setPosition(isLeading ? minPossiblePositionOfDivider(at: divider) : maxPossiblePositionOfDivider(at: divider), ofDividerAt: divider)
        } else {
            // Back at the width it had, kept as a width so a window resized meanwhile still fits it.
            let w = openWidth(i)
            setPosition(isLeading ? w : bounds.width - w - dividerThickness, ofDividerAt: divider)
        }
    }
}

/// The window's resize rule (DL-129), apart from AppKit so DuoChecks can check it.
public enum PaneWidths {
    /// New widths for `total` (dividers taken out): side panes keep `current`, the `flex` pane takes
    /// the rest; under its minimum the last pane gives way first, then the first, each down to its
    /// own. Hidden panes stay 0.
    public static func resized(current: [CGFloat], hidden: [Bool], total: CGFloat, flex: Int, minimums: [CGFloat]) -> [CGFloat] {
        var w = current.enumerated().map { hidden[$0.offset] ? 0 : $0.element }
        w[flex] = total - w.indices.filter { $0 != flex }.map { w[$0] }.reduce(0, +)
        for i in [w.count - 1, 0] where i != flex && !hidden[i] && w[flex] < minimums[flex] {
            let give = min(minimums[flex] - w[flex], max(0, w[i] - minimums[i]))
            w[i] -= give; w[flex] += give
        }
        return w
    }
}

/// A pane sliding in or out (DL-129). Terminals hold their size while it runs and take the new one
/// when it ends, so a PTY is resized once (LR-14).
@MainActor public enum PaneMotion {
    public static let endedNotification = Notification.Name("DuoPaneMotionEnded")
    /// Off for captures, which must not catch a pane mid-slide.
    public static var enabled = true
    public private(set) static var running = 0
    static func began() { running += 1 }
    static func ended() {
        running = max(0, running - 1)
        if running == 0 { NotificationCenter.default.post(name: endedNotification, object: nil) }
    }
}
