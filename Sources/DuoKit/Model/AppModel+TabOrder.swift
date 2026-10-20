import Foundation
import SwiftUI

/// Moving tabs along their strip (ENH-042, DL-220): a drag, Move Tab Left / Right on the tab's
/// menu, and `duo2 view tab-move`. The console's tabs and the right pane's documents move; the
/// right pane's Project tab (and a group page or read-only session) stays where it is (Q-210).
public enum TabOrder {
    /// `natural` in the user's order: keys the order names first, as it has them, then the rest as
    /// they come (a tab opened after a move goes at the end).
    public static func apply(_ order: [String], to natural: [String]) -> [String] {
        guard !order.isEmpty else { return natural }
        let present = Set(natural)
        var seen = Set<String>()
        let ordered = order.filter { present.contains($0) && seen.insert($0).inserted }
        return ordered + natural.filter { !seen.contains($0) }
    }

    /// The tab to select when `key` closes: its left neighbour in `keys`, the new first tab if it was
    /// first, nil when it was the only one (ENH-144, as a closing document's `PopupPlacement.after`).
    public static func neighbour(closing key: String, in keys: [String]) -> String? {
        guard let i = keys.firstIndex(of: key) else { return keys.first }
        let rest = keys.filter { $0 != key }
        return rest.isEmpty ? nil : rest[max(0, i - 1)]
    }

    /// `key` moved `offset` places (−1 left, +1 right); nil when it can't go that far.
    public static func moved(_ keys: [String], _ key: String, by offset: Int) -> [String]? {
        guard let i = keys.firstIndex(of: key) else { return nil }
        return moved(keys, key, to: i + offset)
    }

    /// `key` moved to `index` (0-based); nil when the index is outside the strip or is where it is.
    public static func moved(_ keys: [String], _ key: String, to index: Int) -> [String]? {
        guard let i = keys.firstIndex(of: key), index >= 0, index < keys.count, index != i else { return nil }
        var out = keys
        out.remove(at: i)
        out.insert(key, at: index)
        return out
    }

    /// Where a dragged tab lands, from the pointer's x and the other tabs' middles on the strip:
    /// before the first tab whose middle is right of the pointer, else after the last one.
    public static func dropped(_ keys: [String], _ key: String, pointerX x: CGFloat, middles: [(key: String, midX: CGFloat)]) -> [String]? {
        let others = middles.filter { $0.key != key && keys.contains($0.key) }
        guard let last = others.last else { return nil }
        var out = keys.filter { $0 != key }
        if let next = others.first(where: { $0.midX > x }), let j = out.firstIndex(of: next.key) {
            out.insert(key, at: j)
        } else if let j = out.firstIndex(of: last.key) {
            out.insert(key, at: j + 1)
        } else {
            return nil
        }
        return out == keys ? nil : out
    }
}

/// A tab under a drag: which, on which strip, and where the pointer is in the strip's space.
public struct TabDrag: Equatable, Sendable {
    public var key: String
    public var pane: DuoPane
    /// The pointer, and how far right of the tab's middle it took hold.
    public var location: CGPoint
    public var grab: CGSize
}

extension AppModel {
    /// The tabs of `pane` that move, in strip order.
    public func movableTabKeys(in pane: DuoPane) -> [String] {
        guard !altitude.isAllProjects, let project = currentProject?.name else { return [] }
        switch pane {
        case .middle: return consoleTabKeys(inProject: project)
        case .right: return rightTabItems().filter { $0.isDocument && openDocuments.contains($0.id) }.map(\.id)
        case .left: return []
        }
    }

    /// Whether Move Tab Left (−1) or Right (+1) can move `key`.
    public func canMoveTab(_ key: String, in pane: DuoPane, by offset: Int) -> Bool {
        TabOrder.moved(movableTabKeys(in: pane), key, by: offset) != nil
    }

    /// Move Tab Left / Right (DL-220). False when the tab is already at that end.
    @discardableResult
    public func moveTab(_ key: String, in pane: DuoPane, by offset: Int) -> Bool {
        guard let keys = TabOrder.moved(movableTabKeys(in: pane), key, by: offset) else { return false }
        setTabOrder(keys, in: pane)
        return true
    }

    /// A tab put at a place among the tabs that move (0-based), as a drag drops it.
    @discardableResult
    public func moveTab(_ key: String, in pane: DuoPane, to index: Int) -> Bool {
        guard let keys = TabOrder.moved(movableTabKeys(in: pane), key, to: index) else { return false }
        setTabOrder(keys, in: pane)
        return true
    }

    func setTabOrder(_ keys: [String], in pane: DuoPane) {
        guard let project = currentProject?.name else { return }
        switch pane {
        case .middle: consoleTabOrder[project] = keys
        case .right: openDocuments = keys + openDocuments.filter { !keys.contains($0) }
        case .left: break
        }
    }

    /// A live session's console tab is dragged as itself, onto a task or a project (DL-147).
    func isSessionDragSource(_ key: String) -> Bool {
        terminalsMode == .live && fixture.sessions.contains { $0.tabKey == key && $0.sessionId != nil }
    }

    /// The pane a tab key is on, if it's one that moves.
    public func paneOfMovableTab(_ key: String) -> DuoPane? {
        [DuoPane.middle, .right].first { movableTabKeys(in: $0).contains(key) }
    }

    // MARK: - Dragging (TabsDrag, ConsoleDrag)

    /// The pointer moved with a tab held: it follows, and the tab's place moves to where it would land.
    /// `shown` is the strip's tabs on screen, left to right, with their middles in the strip's space.
    func dragTab(_ key: String, in pane: DuoPane, start: CGPoint, location: CGPoint, middle: CGPoint, shown: [(key: String, midX: CGFloat)]) {
        if tabDrag?.key != key {
            tabDrag = TabDrag(key: key, pane: pane, location: location, grab: CGSize(width: start.x - middle.x, height: start.y - middle.y))
        } else {
            tabDrag?.location = location
        }
        if let keys = TabOrder.dropped(movableTabKeys(in: pane), key, pointerX: location.x, middles: shown) {
            setTabOrder(keys, in: pane)
        }
    }

    /// The tab let go: it settles in its place.
    func endTabDrag() { tabDrag = nil }
}

/// Makes a tab draggable along its strip (ENH-042). The tab keeps its place, emptied, while a
/// lifted copy follows the pointer (`TabDragGhost`); the place moves as the pointer passes a
/// neighbour's middle, and the strip's `tabMove` animation slides the neighbours.
struct TabDraggable: ViewModifier {
    @Environment(AppModel.self) private var model
    let key: String
    let pane: DuoPane
    let space: String
    /// False where the tab is a drag source of its own (a live session's console tab: `TabStripDrop`).
    let enabled: Bool
    /// What's before the label inside the tab (a document tab's × slot), so the lifted copy sits on the label.
    var lead: CGFloat = 0
    /// The strip's tabs on screen, left to right, for where a drag lands.
    let shown: () -> [String]

    func body(content: Content) -> some View {
        let dragged = model.tabDrag?.key == key
        content
            .opacity(dragged ? 0 : 1)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(space)) }) { model.tabFrames[key] = $0 }
            .gesture(enabled ? DragGesture(minimumDistance: 4, coordinateSpace: .named(space))
                .onChanged { v in
                    let frames = model.tabFrames
                    guard let own = frames[key] else { return }
                    let middles = shown().compactMap { k in frames[k].map { (key: k, midX: $0.midX) } }
                    model.dragTab(key, in: pane, start: v.startLocation, location: v.location, middle: CGPoint(x: own.midX + lead / 2, y: own.midY), shown: middles)
                }
                .onEnded { _ in model.endTabDrag() } : nil)   // action: view tab-move
    }
}

/// A lifted tab: its name on its strip's ground, a hairline, radius 5, 24 high, and the popover
/// shadow (TabsDrag, ConsoleDrag). The system's drag image for a session tab, and `TabDragGhost`.
struct TabDragImage<Label: View>: View {
    let onConsole: Bool
    @ViewBuilder let label: () -> Label

    var body: some View {
        label()
            .padding(.horizontal, DuoMetric.tabDragPaddingX)
            .frame(height: DuoMetric.tabHoverHeight)
            .background(RoundedRectangle(cornerRadius: DuoMetric.tabHoverRadius).fill(onConsole ? DuoColor.console : DuoColor.pane))
            .overlay(RoundedRectangle(cornerRadius: DuoMetric.tabHoverRadius).strokeBorder(onConsole ? DuoColor.consoleRule : DuoColor.rule, lineWidth: DuoMetric.borderHairline))
            .modifier(TabDragShadow(onConsole: onConsole))
            .fixedSize()
    }
}

/// The dragged tab under the pointer, drawn over its strip.
struct TabDragGhost<Label: View>: View {
    let drag: TabDrag
    let onConsole: Bool
    @ViewBuilder let label: () -> Label

    var body: some View {
        TabDragImage(onConsole: onConsole, label: label)
            .position(x: drag.location.x - drag.grab.width, y: drag.location.y - drag.grab.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The popover shadow; on the console its own, black at 50% (ConsoleDrag).
struct TabDragShadow: ViewModifier {
    let onConsole: Bool
    func body(content: Content) -> some View {
        if onConsole { content.shadow(color: DuoShadow.consoleLiftColor, radius: DuoShadow.consoleLiftRadius, y: DuoShadow.consoleLiftY) } else { content.duoPopoverShadow() }
    }
}

/// The console's strip under a session tab's own drag (it is a drag source already, so a session can
/// go onto a task or a project, DL-147): passing along the strip moves its place, as `TabDraggable` does.
struct TabStripDrop: DropDelegate {
    let model: AppModel
    let pane: DuoPane
    /// The strip's tabs on screen, left to right.
    let shown: [String]

    @MainActor func key() -> String? {
        guard let payload = model.dragging, payload.hasPrefix("duo-session:") else { return nil }
        let id = String(payload.dropFirst("duo-session:".count))
        return model.movableTabKeys(in: pane).contains(id) ? id : nil
    }

    @MainActor func validateDrop(info: DropInfo) -> Bool { key() != nil }

    @MainActor func dropUpdated(info: DropInfo) -> DropProposal? {
        guard let key = key() else { return nil }
        let frames = model.tabFrames
        let middles = shown.compactMap { k in frames[k].map { (key: k, midX: $0.midX) } }
        if let keys = TabOrder.dropped(model.movableTabKeys(in: pane), key, pointerX: info.location.x, middles: middles) {
            model.setTabOrder(keys, in: pane)
        }
        return DropProposal(operation: .move)
    }

    @MainActor func performDrop(info: DropInfo) -> Bool {
        guard key() != nil else { return false }
        model.dragging = nil
        return true
    }
}
