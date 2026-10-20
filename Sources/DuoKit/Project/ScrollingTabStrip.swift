import AppKit
import SwiftUI

// The scrolling tab strip (DL-225, docs/design/tabs-handoff): the console, the right pane, Home and
// the thin strip over chat all use it. Tabs keep their looks and widths; when they don't fit they
// scroll sideways under edge fades, `n ⌄` lists them all, and the selected tab is always in view.

/// The pure rules, apart from the views so DuoChecks can check them.
public enum TabScroll {
    /// The offset that shows the selected tab whole, or nil when it's already shown. A tab with a
    /// neighbour on a side keeps that side's fade and `peek` of the neighbour clear; with none it
    /// shows to the edge. The least distance; a tab wider than the viewport starts at its own start.
    public static func offsetToReveal(tab: ClosedRange<CGFloat>, offset: CGFloat, viewport: CGFloat, content: CGFloat,
                                      hasPrevious: Bool, hasNext: Bool,
                                      fade: CGFloat = DuoMetric.tabFade, peek: CGFloat = DuoMetric.tabPeek) -> CGFloat? {
        guard viewport > 0, content > viewport else { return offset == 0 ? nil : 0 }
        let left = tab.lowerBound - (hasPrevious ? fade + peek : 0)
        let right = tab.upperBound + (hasNext ? fade + peek : 0)
        var target = offset
        if right - left > viewport { target = tab.lowerBound - (hasPrevious ? fade : 0) }
        else if left < offset { target = left }
        else if right > offset + viewport { target = right - viewport }
        target = min(max(0, target), content - viewport)
        return abs(target - offset) < 0.5 ? nil : target
    }

    /// Which way a pointer at `x` in the viewport pushes the strip: −1 at the start, 1 at the end, 0 elsewhere or
    /// when there's nothing more that way.
    public static func edgeDirection(pointerX x: CGFloat, viewport: CGFloat, offset: CGFloat, content: CGFloat,
                                     edge: CGFloat = DuoMetric.tabEdgeScroll) -> Int {
        if x < edge, offset > 0.5 { return -1 }
        if x > viewport - edge, offset + viewport < content - 0.5 { return 1 }
        return 0
    }

    /// The tabs (indexes) out of view at each end: wholly under the fade or beyond it.
    public static func hidden(frames: [ClosedRange<CGFloat>], offset: CGFloat, viewport: CGFloat, content: CGFloat,
                              fade: CGFloat = DuoMetric.tabFade) -> (before: [Int], after: [Int]) {
        var before: [Int] = [], after: [Int] = []
        let showsStart = offset > 0.5, showsEnd = offset + viewport < content - 0.5
        for (i, f) in frames.enumerated() {
            if showsStart, f.upperBound <= offset + fade { before.append(i) }
            else if showsEnd, f.lowerBound >= offset + viewport - fade { after.append(i) }
        }
        return (before, after)
    }

    /// Edge scroll's pace: one tab every 0.3 s, for tabs `tabWidth` wide on average.
    public static func edgeSpeed(tabWidth: CGFloat) -> CGFloat { min(max(tabWidth, 60), 260) / 0.3 }
}

/// A strip's scroll offset and measures, kept in the model (no view state, DL-30).
@MainActor @Observable public final class TabStripState {
    public var offset: CGFloat = 0
    /// The scrolling part's width, and the width of everything in it.
    public var viewport: CGFloat = 0
    public var content: CGFloat = 0
    /// The strip's whole width, and what sits beside the scrolling part.
    public var stripWidth: CGFloat = 0
    public var pinnedWidth: CGFloat = 0
    public var trailingWidth: CGFloat = 0
    public var edgeWidth: CGFloat = 0
    public var position = ScrollPosition(edge: .leading)
    /// A trackpad swipe is moving the strip: nothing scrolls it meanwhile.
    public var userScrolling = false

    /// Everything fits beside the pinned tabs and the controls: no fades, no all-tabs button.
    public var overflows: Bool { content > 0 && pinnedWidth + content + trailingWidth + edgeWidth > stripWidth + 0.5 }

    public func scroll(to x: CGFloat, animated: Bool) {
        let x = min(max(0, x), max(0, content - viewport))
        if animated, let a = DuoMotionToken.tabMove.animation { withAnimation(a) { position.scrollTo(x: x) } } else { position.scrollTo(x: x) }
    }
}

/// One row of the all-tabs menu.
struct TabMenuRow {
    let key: String
    let title: String
    let state: SessionState?
    let isShell: Bool
    let selected: Bool
}

extension PopUp {
    /// The all-tabs menu: a pop-up of every scrolling tab in strip order, the selected one checked; console
    /// and Home rows carry the state glyph in light colours, or the prompt mark for a shell.
    @MainActor static func showTabs(_ rows: [TabMenuRow], glyphs: Bool, choose: @escaping (String) -> Void) {
        let menu = NSMenu()
        for r in rows {
            let i = Item(title: r.title, action: #selector(Item.fire), keyEquivalent: "")
            i.run = { choose(r.key) }; i.target = i
            i.state = r.selected ? .on : .off
            if glyphs {
                let glyph: AnyView = r.isShell ? AnyView(ShellPromptMark(active: false, light: true).frame(width: 11, height: 9))
                    : AnyView(StateGlyph(r.state ?? .idle, on: .light).frame(width: DuoMetric.glyph, height: DuoMetric.glyph))
                let render = ImageRenderer(content: glyph)
                render.scale = NSScreen.main?.backingScaleFactor ?? 2
                i.image = render.nsImage
            }
            menu.addItem(i)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

struct ScrollingTabStrip<Pinned: View, Tabs: View, Plus: View, Edge: View>: View {
    @Environment(AppModel.self) private var model
    let pane: DuoPane
    /// The named space the tabs' frames are written in (`TabDraggable`); it spans the scrolling content.
    let space: String
    /// The scrolling tabs, in strip order, and the selected one.
    let keys: [String]
    let selected: String?
    /// The strip's ground, for the fades; its rule and its dim text.
    let ground: Color
    let rule: Color
    let dim: Color
    let font: DuoTextStyle
    /// Tabs that need you (the dot in the fade), and its colour.
    var needsYou: Set<String> = []
    let dot: Color
    /// Rows of the all-tabs menu and whether they carry glyphs; choosing one selects the tab.
    let rows: () -> [TabMenuRow]
    var glyphs = true
    let choose: (String) -> Void
    /// The strip's height less its border: the all-tabs button's rule.
    let height: CGFloat
    @ViewBuilder let pinned: () -> Pinned
    @ViewBuilder let tabs: () -> Tabs
    @ViewBuilder let plus: () -> Plus
    @ViewBuilder let edge: () -> Edge

    var body: some View {
        let st = model.tabStrips[pane]!
        HStack(spacing: 0) {
            pinned().onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { st.pinnedWidth = $0 }
            scrollArea(st)
            if st.overflows { allTabs(st) }
            plus().onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { st.trailingWidth = $0 }
            Spacer(minLength: 0)
            edge().onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { st.edgeWidth = $0 }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { st.stripWidth = $0 }
        .task(id: Reveal(selected: selected, content: st.content, viewport: st.viewport, count: keys.count)) { reveal(st) }
        .task(id: dragging) { await edgeScroll(st) }
    }

    private var dragging: Bool { model.tabDrag?.pane == pane || model.draggedSessionKey(in: pane) != nil }

    private struct Reveal: Hashable { let selected: String?; let content: CGFloat; let viewport: CGFloat; let count: Int }

    private func scrollArea(_ st: TabStripState) -> some View {
        @Bindable var b = st
        return ScrollView(.horizontal, showsIndicators: false) {
            tabs()
                .coordinateSpace(.named(space))
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { st.content = $0 }
        }
        .scrollPosition($b.position)
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x }) { _, x in st.offset = x }
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.containerSize.width }) { _, w in st.viewport = w }
        .onScrollPhaseChange { _, phase in st.userScrolling = phase == .interacting }
        .frame(maxWidth: st.content > 0 ? st.content : .infinity)
        .frame(height: height)
        .overlay(alignment: .leading) { fade(st, leading: true) }
        .overlay(alignment: .trailing) { fade(st, leading: false) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs")
        .accessibilityScrollAction { edge in
            switch edge {
            case .leading: st.scroll(to: st.offset - st.viewport * 0.8, animated: true)
            case .trailing: st.scroll(to: st.offset + st.viewport * 0.8, animated: true)
            default: break
            }
        }
    }

    /// The tabs out of view at one end, with a needs-you dot for the first that needs you.
    @ViewBuilder private func fade(_ st: TabStripState, leading: Bool) -> some View {
        let more = leading ? st.offset > 0.5 : st.offset + st.viewport < st.content - 0.5
        if st.overflows, more {
            let hidden = hiddenKeys(st, leading: leading)
            let needy = hidden.filter(needsYou.contains)
            ZStack(alignment: leading ? .leading : .trailing) {
                LinearGradient(colors: leading ? [ground, ground.opacity(0)] : [ground.opacity(0), ground],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: DuoMetric.tabFade).allowsHitTesting(false)
                if let first = leading ? needy.last : needy.first {
                    Circle().fill(dot).frame(width: DuoMetric.tabNeedsYouDot, height: DuoMetric.tabNeedsYouDot)
                        .frame(width: 16, height: 16).contentShape(Rectangle())
                        .padding(leading ? .leading : .trailing, 5 - (16 - DuoMetric.tabNeedsYouDot) / 2)
                        .onActivate { scrollTo(first, st) }  // action: view tab
                        .accessibilityLabel("\(hidden.count) more tab\(hidden.count == 1 ? "" : "s") to the \(leading ? "left" : "right"), \(needy.count == 1 ? "one needs you" : "\(needy.count) need you")")
                }
            }
            .frame(width: DuoMetric.tabFade)
            .transition(.opacity)
        }
    }

    private func frames(_ st: TabStripState) -> [ClosedRange<CGFloat>] {
        keys.map { k in model.tabFrames[k].map { $0.minX...$0.maxX } ?? 0...0 }
    }

    private func hiddenKeys(_ st: TabStripState, leading: Bool) -> [String] {
        let h = TabScroll.hidden(frames: frames(st), offset: st.offset, viewport: st.viewport, content: st.content)
        return (leading ? h.before : h.after).map { keys[$0] }
    }

    /// Scrolls to a tab without selecting it.
    private func scrollTo(_ key: String, _ st: TabStripState) {
        guard let i = keys.firstIndex(of: key), let target = target(i, st) else { return }
        st.scroll(to: target, animated: true)
    }

    private func target(_ i: Int, _ st: TabStripState) -> CGFloat? {
        guard let f = model.tabFrames[keys[i]] else { return nil }
        return TabScroll.offsetToReveal(tab: f.minX...f.maxX, offset: st.offset, viewport: st.viewport, content: st.content,
                                        hasPrevious: i > 0, hasNext: i < keys.count - 1)
    }

    /// The selected tab is always in view, whole (a click, ⌃Tab, a choice, a close, a move, a drag, a resize).
    private func reveal(_ st: TabStripState) {
        guard let selected, let i = keys.firstIndex(of: selected), !st.userScrolling, st.viewport > 0 else { return }
        guard let t = target(i, st) else { return }
        st.scroll(to: t, animated: true)
    }

    /// A tab held within `tabEdgeScroll` of an end scrolls the strip that way, steadily; its place keeps moving.
    private func edgeScroll(_ st: TabStripState) async {
        guard dragging else { return }
        let dt: CGFloat = 1.0 / 60
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            guard let p = model.tabDragPointer, p.pane == pane else { continue }
            let dir = TabScroll.edgeDirection(pointerX: p.x, viewport: st.viewport, offset: st.offset, content: st.content)
            guard dir != 0 else { continue }
            let speed = TabScroll.edgeSpeed(tabWidth: st.content / CGFloat(max(1, keys.count)))
            let before = st.offset
            let next = min(max(0, before + CGFloat(dir) * speed * dt), max(0, st.content - st.viewport))
            guard next != before else { continue }
            st.scroll(to: next, animated: false)
            st.offset = next
            model.advanceTabDrag(in: pane, by: next - before)
        }
    }

    private func allTabs(_ st: TabStripState) -> some View {
        HStack(spacing: 0) {
            rule.frame(width: DuoMetric.borderHairline, height: height)
            HStack(spacing: 4) {
                Text("\(keys.count)").duoText(font).foregroundStyle(dim)
                Chevron(direction: .down, color: dim).frame(width: 8, height: 6).scaleEffect(0.8)
            }
            .padding(.leading, 12).padding(.trailing, 10)
            .frame(height: height).contentShape(Rectangle())
            .onActivate { PopUp.showTabs(rows(), glyphs: glyphs, choose: { k in choose(k) }) }  // action: view tab
            .accessibilityLabel("All tabs, \(keys.count)")
        }
        .background(ground)
    }
}
