import AppKit
import Foundation
import Observation

/// Everything split view keeps (DL-275 to DL-278): the split tabs per project, what the split took to
/// make room, and the providers and policies that preview each one. One `SplitState` per window.
@MainActor
@Observable
public final class SplitState {
    /// Split tabs by project, then by the source's path (the tab's key).
    public var tabs: [String: [String: SplitTab]] = [:]
    /// What the first split took to make room (DL-276); nil when none is open.
    public var taken: SplitRoom.Taken?
    /// The folded sidebar is peeking over the console.
    public var peek = false
    /// Which rail is under the pointer: "sidebar" or "split" (no `@State` in Duo, ADR-0001).
    public var railHover: String?
    /// Bumped when a tab's source or preview changes, so views that read only the values redraw.
    public var revision = 0

    /// The project layout's AppKit split, to set the right pane's width (registered by `PaneSplit`).
    @ObservationIgnored weak var paneHost: DuoSplitView? {
        didSet { if paneHost != nil, let w = pendingRightWidth { applyRightWidthSoon(w) } }
    }
    /// A restored split's room, applied once the layout exists.
    @ObservationIgnored var pendingRightWidth: Double?
    @ObservationIgnored var policies: [String: PreviewPolicy] = [:]
    @ObservationIgnored var resizeSettle: DispatchWorkItem?
    @ObservationIgnored private var providers: [PreviewKind: PreviewProvider] = [:]

    /// The registered provider for `kind` (one per window), made on first use; nil when none registered.
    func provider(_ kind: PreviewKind) -> PreviewProvider? {
        if let p = providers[kind] { return p }
        guard let make = PreviewProviders.makers[kind] else { return nil }
        let p = make()
        providers[kind] = p
        return p
    }

    public init() {}

    public var sidebarFolded: Bool { taken?.foldedSidebar == true }
    public var any: Bool { tabs.values.contains { !$0.isEmpty } }

    func applyRightWidthSoon(_ w: Double, after delay: Double = 0.4) {
        pendingRightWidth = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.paneHost?.setLastPaneWidth(CGFloat(w)) }
        }
    }

    func policy(_ project: String, _ path: String) -> PreviewPolicy {
        let key = project + "\u{1}" + path
        if let p = policies[key] { return p }
        let p = PreviewPolicy()
        policies[key] = p
        return p
    }

    func dropPolicy(_ project: String, _ path: String) {
        policies[project + "\u{1}" + path]?.cancel()
        policies[project + "\u{1}" + path] = nil
    }
}

extension DuoSplitView {
    /// The last pane's width, as its divider was dragged (the right pane, in a project).
    func setLastPaneWidth(_ w: CGFloat) {
        guard arrangedSubviews.count >= 2, bounds.width > 0 else { return }
        setPosition(bounds.width - w - dividerThickness, ofDividerAt: arrangedSubviews.count - 2)
        adjustSubviews()
    }

    var lastPaneWidth: CGFloat { arrangedSubviews.last?.frame.width ?? 0 }
}
