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
    private var savedPositions: [Int: CGFloat] = [:]
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
            for (i, collapsed) in pendingCollapse.sorted(by: { $0.key < $1.key }) { setCollapsed(collapsed, paneAt: i) }
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

    /// Collapses or restores a side pane. The pane's view is kept, never torn down.
    func setCollapsed(_ collapsed: Bool, paneAt i: Int) {
        guard placed else { pendingCollapse[i] = collapsed; return }
        guard arrangedSubviews.indices.contains(i), isSubviewCollapsed(arrangedSubviews[i]) != collapsed else { return }
        let isLeading = i == 0
        let divider = isLeading ? 0 : i - 1
        if collapsed {
            savedPositions[i] = isLeading ? arrangedSubviews[i].frame.maxX : arrangedSubviews[i].frame.minX - 1
            setPosition(isLeading ? minPossiblePositionOfDivider(at: divider) : maxPossiblePositionOfDivider(at: divider), ofDividerAt: divider)
        } else {
            let fallback: CGFloat = isLeading ? (designWidths[i] ?? 300) - 1 : bounds.width - (designWidths[i] ?? 300)
            setPosition(savedPositions[i] ?? fallback, ofDividerAt: divider)
        }
    }
}
