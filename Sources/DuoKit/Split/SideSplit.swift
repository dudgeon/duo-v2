import AppKit
import SwiftUI

/// The split tab's two sides: ordinary subviews of an AppKit split inside the right pane (legacy
/// rule 2: no overlay positioned by hand). The fold is decided here, in `layout()`, from the pane's
/// own width, and reported to the model; the divider's drag and double-click end here too.
@MainActor
final class SideSplitView: NSSplitView {
    var onRatio: ((Double) -> Void)?
    var onFold: ((Bool) -> Void)?
    var onEven: (() -> Void)?
    var onActive: ((SplitRole) -> Void)?
    /// Source and preview hosting views, whichever side they are on.
    var source: NSView?
    var preview: NSView?
    private(set) var swapped = false
    private(set) var ratio = 0.5
    private(set) var activeRole = SplitRole.source
    private(set) var folded = false
    private var applying = false
    private var monitor: Any?

    override var dividerThickness: CGFloat { 1 }
    override var dividerColor: NSColor { DuoNSColor.rule }

    override func drawDivider(in rect: NSRect) {
        DuoNSColor.rule.setFill()
        rect.fill()
    }

    /// Arranges the sides for the model's values; a no-op when nothing changed.
    func apply(swapped: Bool, ratio: Double, active: SplitRole) {
        guard let source, let preview else { return }
        let order = swapped ? [preview, source] : [source, preview]
        if arrangedSubviews != order {
            applying = true
            for v in arrangedSubviews { removeArrangedSubview(v) }
            for v in order { addArrangedSubview(v) }
            applying = false
        }
        self.swapped = swapped; self.ratio = ratio; self.activeRole = active
        needsLayout = true
    }

    override func layout() {
        // The pane's whole width: a folded split gives 16 pt of it to its rail.
        let isFolded = SplitGeometry.folded(width: Double(bounds.width) + (folded ? SplitRoom.railWidth : 0))
        applying = true
        if isFolded {
            // Only the active side shows; the other is kept, hidden (never torn down).
            for (v, role) in [(source, SplitRole.source), (preview, .preview)] { v?.isHidden = role != activeRole }
        } else {
            source?.isHidden = false; preview?.isHidden = false
        }
        super.layout()
        if !isFolded, arrangedSubviews.count == 2, bounds.width > 0 {
            let w = SplitGeometry.widths(width: Double(bounds.width), ratio: ratio)
            if abs(Double(arrangedSubviews[0].frame.width) - w.left) > 0.5 { setPosition(CGFloat(w.left), ofDividerAt: 0) }
        }
        applying = false
        if isFolded != folded {
            folded = isFolded
            DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.onFold?(isFolded) } }
        }
    }

    /// Both sides keep at least `splitSideMin`.
    func constrain(_ position: CGFloat, _ index: Int) -> CGFloat {
        let m = CGFloat(SplitGeometry.sideMin)
        return min(bounds.width - m - dividerThickness, max(m, position))
    }

    func didResize() {
        // Only a drag of the divider changes the ratio; a window or pane resize doesn't.
        guard !applying, !folded, arrangedSubviews.count == 2, bounds.width > 0, NSEvent.pressedMouseButtons & 1 != 0 else { return }
        let r = SplitGeometry.ratio(left: Double(arrangedSubviews[0].frame.width), width: Double(bounds.width))
        if abs(r - ratio) > 0.002 { ratio = r; onRatio?(r) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
            guard let self, e.window === self.window, !self.isHiddenOrHasHiddenAncestor else { return e }
            let p = self.convert(e.locationInWindow, from: nil)
            guard self.bounds.contains(p) else { return e }
            if e.clickCount == 2, self.arrangedSubviews.count == 2, !self.folded {
                let f = self.arrangedSubviews[0].frame
                if abs(p.x - f.maxX - 0.5) <= 3 { self.onEven?(); return nil }
            }
            // A click in a side makes it the active one (model state, never DOM focus).
            for (v, role) in [(self.source, SplitRole.source), (self.preview, .preview)] where v?.isHidden == false {
                if let v, v.frame.contains(p) { self.onActive?(role) }
            }
            return e
        }
    }
}

/// The split's AppKit view, its two sides and the model's callbacks.
struct SideSplit: NSViewRepresentable {
    let model: AppModel
    let path: String
    let tab: SplitTab
    let source: AnyView
    let preview: AnyView

    func makeNSView(context: Context) -> SideSplitView {
        let v = SideSplitView()
        v.isVertical = true
        v.dividerStyle = .thin
        v.delegate = context.coordinator
        func host(_ view: AnyView) -> NSHostingView<AnyView> {
            let h = NSHostingView(rootView: AnyView(view.environment(model)))
            h.sizingOptions = []
            h.translatesAutoresizingMaskIntoConstraints = true
            return h
        }
        v.source = host(source)
        v.preview = host(preview)
        let (m, p) = (model, path)
        v.onRatio = { [weak m] r in m?.splitRatioDragged(r, for: p) }
        v.onFold = { [weak m] f in m?.splitFolded(f, for: p) }
        v.onEven = { [weak m] in m?.setSplitRatio(0.5) }
        v.onActive = { [weak m] role in m?.setActiveRole(role, in: p) }
        v.apply(swapped: tab.swapped, ratio: tab.ratio, active: tab.active)
        return v
    }

    func updateNSView(_ v: SideSplitView, context: Context) {
        v.apply(swapped: tab.swapped, ratio: tab.ratio, active: tab.active)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SideSplitView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: nsView.frame.size)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator: NSObject, NSSplitViewDelegate {
        func splitView(_ s: NSSplitView, constrainSplitPosition p: CGFloat, ofSubviewAt i: Int) -> CGFloat {
            (s as? SideSplitView)?.constrain(p, i) ?? p
        }
        func splitViewDidResizeSubviews(_ n: Notification) { (n.object as? SideSplitView)?.didResize() }
        func splitView(_ s: NSSplitView, shouldAdjustSizeOfSubview v: NSView) -> Bool { true }
    }
}

extension AppModel {
    /// A drag of the divider ended at `r`: saved with the split (one SplitGeometry owns the clamp).
    func splitRatioDragged(_ r: Double, for path: String) {
        guard var t = splitTabs[path] else { return }
        let c = SplitGeometry.clampedRatio(r)
        guard abs(t.ratio - c) > 0.001 else { return }
        t.ratio = c
        splitTabs[path] = t
    }
}

/// The right pane's body for a split tab: source and preview in one AppKit split.
struct SplitBody: View {
    @Environment(AppModel.self) private var model
    let path: String
    let file: URL

    var body: some View {
        if let tab = model.splitTab(path) {
            SideSplit(model: model, path: path, tab: tab,
                      source: AnyView(SplitSourceSide(path: path, file: file)),
                      preview: AnyView(SplitPreviewSide(path: path, kind: tab.kind, file: file)))
                .id(path)
                .padding(.trailing, tab.folded ? DuoMetric.sidebarRail : 0)   // the active side fills the rest
                .overlay(alignment: .trailing) { if tab.folded { SplitRail(tab: tab) } }
                .onAppear { if !tab.isDocPair { model.startPreview(path) } }
                .accessibilityIdentifier("video.right.document")
        }
    }
}

/// The source side: today's editor with its bars, in the main editor (C-135).
struct SplitSourceSide: View {
    @Environment(AppModel.self) private var model
    let path: String
    let file: URL

    var body: some View { DocumentStack(file: file, ref: .main) }
}

/// The preview side: the provider's view (no bar of its own for Markdown).
struct SplitPreviewSide: View {
    @Environment(AppModel.self) private var model
    let path: String
    let kind: PreviewKind
    let file: URL

    var body: some View {
        Group {
            switch kind {
            case .markdown: WebPreviewView(web: model.splits.markdown.webView).background(DuoColor.pane)
            case .html:
                ZStack(alignment: .bottom) {
                    WebPreviewView(web: model.htmlViewer.webView)
                    PickerBar()
                }
            case .document:
                // Slice 2 (DL-278): the other document, in the second editor with its own bars.
                if let w = model.splitTab(path)?.with, let f = model.liveFile(w) ?? model.keptFile(w) {
                    DocumentStack(file: f, ref: .second)
                } else { DuoColor.pane }
            case .deck: DuoColor.pane   // Duo Decks' provider fills this (preview-provider)
            }
        }
    }
}

/// The folded split's rail (`fold`): 16 wide at the right pane's far right, the other side's way back.
/// The whole rail is one button; a click unfolds (the console narrows just enough for two sides).
struct SplitRail: View {
    @Environment(AppModel.self) private var model
    let tab: SplitTab

    var body: some View {
        let hovering = model.splits.railHover == "split"
        let hiddenRole: SplitRole = tab.active == .source ? .preview : .source
        let name = model.splitSideName(tab, hiddenRole)
        ZStack(alignment: .top) {
            (hovering ? DuoColor.selected : DuoColor.pane)
            SplitMark().padding(.top, 10)
            HStack { DuoColor.rule.frame(width: 1); Spacer() }
        }
        .frame(width: DuoMetric.sidebarRail)
        .contentShape(Rectangle())
        .onHover { model.splits.railHover = $0 ? "split" : nil }
        .onTapGesture { model.unfoldSplit(hiddenRole) }   // action: split unfold
        .help("Show \(name) in Split View")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Show \(name) in Split View")
        .accessibilityAddTraits(.isButton)
    }
}
