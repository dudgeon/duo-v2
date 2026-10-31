import Foundation

/// Which kind of preview a split tab shows beside its source (DL-275). The deck's provider belongs
/// to Duo Decks: until it registers, `deck` is never offered (`PreviewProviders`).
public enum PreviewKind: String, Codable, Sendable, CaseIterable {
    case deck, markdown, html

    /// The preview side's name in the strip: `Slides`, `Preview` or `Page`.
    public var sideName: String {
        switch self {
        case .deck: "Slides"
        case .markdown: "Preview"
        case .html: "Page"
        }
    }
}

/// A side of the split, by place.
public enum SplitSide: String, Codable, Sendable, CaseIterable {
    case left, right
    public var other: SplitSide { self == .left ? .right : .left }
}

/// What a side shows: the source (today's editor) or the provider's preview.
public enum SplitRole: String, Codable, Sendable { case source, preview }

/// One split tab (`split-deck`): one file's source and its preview in one tab of the right pane.
/// The tab's key is the source's path, so a file is still open in one tab only.
public struct SplitTab: Codable, Equatable, Sendable {
    public var source: String
    public var kind: PreviewKind
    /// The left side's share of the right pane, clamped by `SplitGeometry`.
    public var ratio: Double = 0.5
    /// Swap Sides puts the source on the right.
    public var swapped = false
    /// The active side, as the role it plays (it follows a swap).
    public var active: SplitRole = .source
    /// Under 2 × `splitSideMin` + 1 only the active side shows.
    public var folded = false

    public init(source: String, kind: PreviewKind, ratio: Double = 0.5, swapped: Bool = false, active: SplitRole = .source, folded: Bool = false) {
        self.source = source; self.kind = kind; self.ratio = ratio; self.swapped = swapped; self.active = active; self.folded = folded
    }

    public func place(of role: SplitRole) -> SplitSide { (role == .source) == !swapped ? .left : .right }
    public func role(at side: SplitSide) -> SplitRole { place(of: .source) == side ? .source : .preview }
    public var activeSide: SplitSide { place(of: active) }
}

/// The one owner of the divider's ratio and its clamp (legacy rule 5): the drag, double-click, restore
/// and `duo2 split ratio` all go through it, so what was saved is what comes back.
public enum SplitGeometry {
    /// `splitSideMin` (Q-366's stand-in; the handoff's 340).
    public static let sideMin: Double = 340
    public static let divider: Double = 1
    /// `duo2 split ratio` takes 0.2 to 0.8.
    public static let ratioRange: ClosedRange<Double> = 0.2...0.8

    /// Under this the split shows only the active side.
    public static var foldBelow: Double { 2 * sideMin + divider }

    public static func folded(width: Double) -> Bool { width < foldBelow }

    /// The ratio as `duo2 split ratio` and restore accept it: inside the range, and finite.
    public static func clampedRatio(_ r: Double) -> Double {
        guard r.isFinite else { return 0.5 }
        return min(ratioRange.upperBound, max(ratioRange.lowerBound, r))
    }

    /// The left and right widths for a pane `width` wide: the divider's 1 pt comes out, the ratio
    /// splits the rest, and neither side goes under `sideMin`. A folded width gives the whole pane
    /// to each side (only one shows).
    public static func widths(width: Double, ratio: Double) -> (left: Double, right: Double) {
        guard !folded(width: width) else { return (width, width) }
        let room = width - divider
        let left = min(room - sideMin, max(sideMin, (room * clampedRatio(ratio)).rounded()))
        return (left, room - left)
    }

    /// The ratio a left side of `left` pt makes in a pane `width` wide (a drag ends).
    public static func ratio(left: Double, width: Double) -> Double {
        let room = width - divider
        guard room > 0 else { return 0.5 }
        let l = min(room - sideMin, max(sideMin, left))
        return clampedRatio(l / room)
    }
}

/// Geoff's making-room rule (DL-276): opening a split narrows the console to its 480 minimum; if the
/// sidebar, the console and two sides don't fit, the sidebar folds. Closing gives back exactly what
/// was taken.
public enum SplitRoom {
    public static let consoleMin: Double = 480
    public static let sidebarWidth: Double = 300
    /// The folded sidebar's rail (`sidebarRail`), drawn in the console's leading edge.
    public static let railWidth: Double = 16

    /// The window width under which the sidebar must fold: 300 + 480 + two sides + their divider
    /// + the three pane edges (about 1,464 pt).
    public static var foldSidebarBelow: Double { sidebarWidth + consoleMin + SplitGeometry.foldBelow + 3 }

    public struct Plan: Equatable, Sendable {
        /// The right pane's width once the console is at its minimum (this includes its edge).
        public var rightWidth: Double
        public var foldsSidebar: Bool
    }

    /// What opening a split does at `window` wide, with the sidebar `sidebarShown`.
    public static func plan(window: Double, sidebarShown: Bool) -> Plan {
        let folds = sidebarShown && window < foldSidebarBelow
        let sidebar = folds ? railWidth : (sidebarShown ? sidebarWidth : 0)
        return Plan(rightWidth: max(0, window - sidebar - consoleMin), foldsSidebar: folds)
    }

    /// What the split took, to give back on close.
    public struct Taken: Codable, Equatable, Sendable {
        public var rightWidth: Double
        public var sidebarWasShown: Bool
        public var foldedSidebar: Bool
        public init(rightWidth: Double, sidebarWasShown: Bool, foldedSidebar: Bool) {
            self.rightWidth = rightWidth; self.sidebarWasShown = sidebarWasShown; self.foldedSidebar = foldedSidebar
        }
    }
}
