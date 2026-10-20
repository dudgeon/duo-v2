import AppKit
import SwiftUI

/// The console's tab strip (handoff §3.3, surfaces-handoff DB-4): sessions, then shells, then
/// `+` and the chevron. Titles cap at 24 characters; tabs that don't fit scroll (`ScrollingTabStrip`,
/// DL-225), and the selected tab is always in view. While the selected tab shows chat, the strip is
/// thin and light (DL-136, chat-polish-handoff `bar-thin`).
struct ConsoleTabStrip: View {
    @Environment(AppModel.self) private var model
    let project: String?
    /// `.middle` is the console; `.left` is Home's strip at All projects (same strip, Home's selection and height).
    var pane: DuoPane = .middle
    private var isHome: Bool { pane == .left }
    private var selection: String? { isHome ? model.homeTab : model.consoleTab }

    struct Tab: Identifiable {
        let id: String
        let title: String
        let state: SessionState?   // nil: a shell
        /// The original this tab's session is a fork of (DL-228): the tab wears the fork mark.
        var forkOf: String? = nil
    }

    /// The selected Claude tab is showing chat: the thin light strip.
    var light: Bool { isHome ? model.homeShowsChat : model.consoleShowsChat }
    /// The thin strip's 28 include the rule under it (`bar-thin`).
    var height: CGFloat { light ? DuoMetric.chatStripHeight - DuoMetric.borderHairline : isHome ? DuoMetric.homeSessionTabsHeight : DuoMetric.tabStripHeight }
    var gap: CGFloat { isHome || light ? 16 : 18 }
    var ground: Color { light ? DuoColor.ground : DuoColor.console }
    var dim: Color { light ? DuoColor.text2 : DuoColor.consoleText2 }

    var body: some View {
        let tabs = allTabs
        ScrollingTabStrip(
            pane: pane, space: Self.space, keys: tabs.map(\.id), selected: selection,
            ground: ground, rule: light ? DuoColor.rule : DuoColor.consoleRule, dim: dim, font: light ? .control : .mono,
            needsYou: Set(tabs.filter { $0.state == .needsYou }.map(\.id)), dot: light ? DuoColor.needsYou : DuoColor.needsYouOnConsole,
            rows: { tabs.map { TabMenuRow(key: $0.id, title: $0.title, state: $0.state, isShell: $0.state == nil, selected: $0.id == selection, isFork: $0.forkOf != nil) } },
            choose: { open($0) },  // action: session open
            height: height,
            pinned: { EmptyView() },
            tabs: {
                HStack(spacing: gap) {
                    ForEach(tabs) { t in tab(t, shown: tabs.map(\.id)) }
                }
                .duoAnimation(.tabMove, value: tabs.map(\.id))
            },
            plus: {
                // Home shows the + only with no tabs (home-none); the console always.
                if !isHome || tabs.isEmpty { HStack(spacing: 5) {
                    Text("+").duoText(light ? .control : .mono).foregroundStyle(dim)
                        .onActivate { newSession() }  // action: session new
                        .accessibilityLabel("New Claude session")
                    Chevron(direction: .down, color: dim).frame(width: 8, height: 6).scaleEffect(0.8)
                        .frame(height: 16).contentShape(Rectangle())
                        .onActivate {  // action: session new
                            PopUp.show([("New Claude Session", { newSession() }), ("New Shell", { model.newShell() })],
                                       keys: [("t", [.command]), ("t", [.command, .shift])])
                        }
                        .accessibilityLabel("New session or shell")
                }
                .padding(.leading, tabs.isEmpty ? 0 : gap)
                // Opaque on the strip, so it covers a tab fading out as it slides (DL-130).
                .background(ground) }
            },
            edge: {
                // Terminal / Chat, for the selected Claude tab (chat-mode-handoff `toggle`); 12 from the edge.
                if let key = selection, tabs.contains(where: { $0.id == key && $0.state != nil }),
                   model.chat(for: key) != nil {
                    ChatToggle(key: key, light: light).padding(.trailing, light ? -6 : -4)   // 11 from the edge (bar-thin) on the thin strip
                }
            })
        // A live session's tab is dragged as itself (onto a task or a project, DL-147); along the strip its place moves (DL-220).
        .onDrop(of: [.plainText, .utf8PlainText], delegate: TabStripDrop(model: model, pane: pane))  // action: view tab-move
        .overlay(alignment: .topLeading) {
            // Any other tab, lifted under the pointer (console-drag).
            if let drag = model.tabDrag, drag.pane == pane, let t = tabs.first(where: { $0.id == drag.key }) {
                TabDragGhost(drag: model.stripDrag(drag), onConsole: !light) { label(t) }
            }
        }
        .padding(.horizontal, DuoSpace.panePadding)
        .frame(height: height)
        .id(project)   // another project's tabs replace these at once
        .background(light ? DuoColor.ground : .clear)
    }

    private func open(_ key: String) { if isHome { model.homeTab = key } else { model.openConsoleTab(key) } }  // action: session open
    private func newSession() {  // action: session new
        if isHome { if let h = project { model.homeTab = model.newSession(in: h) } } else { model.newSession() }
    }

    var allTabs: [Tab] {
        guard let project else { return [] }
        let sessions = model.tabSessions(inProject: project)
        let tabs = model.consoleTabKeys(inProject: project).map { key -> Tab in
            if let s = sessions.first(where: { $0.tabKey == key }) { return Tab(id: key, title: s.name, state: s.state, forkOf: model.forkParentName(of: key)) }
            return Tab(id: key, title: model.consoleTitle(key), state: nil)
        }
        // Two shells reading the same: the later ones take " 2", " 3", in strip order (DL-225).
        let titles = ShellTitles.numbered(tabs.map { (title: $0.title, isShell: $0.state == nil) })
        return zip(tabs, titles).map { Tab(id: $0.id, title: $1, state: $0.state, forkOf: $0.forkOf) }
    }

    static let space = "duo.tabs.console"

    /// A tab's glyph, name and pin; under the pointer the glyph's place holds the × (DL-126).
    @ViewBuilder func label(_ t: Tab, closable: Bool = false) -> some View {
        let active = t.id == selection
        HStack(spacing: DuoSpace.gapGlyphToLabel) {
            // Under the pointer the glyph's place holds the × (DL-126); nothing moves.
            if closable && model.showsTabClose(t.id) {
                TabCloseButton(key: t.id, onConsole: !light, active: active) { model.closeConsoleTab(t.id) }  // action: session close
                    .frame(width: t.state == nil ? 11 : DuoMetric.glyph, height: t.state == nil ? 9 : DuoMetric.glyph)   // the glyph's own box
            } else if let st = t.state { StateGlyph(st, on: light ? .light : .console(active: active)) }   // light: Q-87's stand-in
            else { ShellPromptMark(active: active, light: light).frame(width: 11, height: 9) }
            // A fork's mark (DL-228 B): after the state glyph, for as long as the tab is open; it stays through a rename.
            if t.forkOf != nil {
                ForkMark(color: light ? (active ? DuoColor.text : DuoColor.text2) : (active ? DuoColor.consoleText : DuoColor.consoleText2))
            }
            if light {
                Text(Self.short(t.title))
                    .duoText(.control, weight: active ? .semibold : nil)
                    .foregroundStyle(active ? DuoColor.text : DuoColor.text2)
                    .lineLimit(1)
            } else {
                Text(Self.short(t.title))
                    .duoText(active ? .monoActiveTab : .mono)
                    .foregroundStyle(active ? DuoColor.consoleText : DuoColor.consoleText2)
                    .lineLimit(1)
            }
            // Keep Running (DL-192): a pin after the name; the state glyph stays where it is.
            if t.state != nil, model.isKeepRunning(t.id) {
                KeepRunningPin(color: light ? (active ? DuoColor.text : DuoColor.text2) : (active ? DuoColor.consoleText : DuoColor.consoleText2))
            }
        }
        .fixedSize()
    }

    @ViewBuilder func tab(_ t: Tab, shown: [String]) -> some View {
        let active = t.id == selection
        label(t, closable: true)
        .modifier(TabHoverFill(key: t.id, onConsole: !light, fill: light ? DuoColor.selected : nil))
        .frame(maxHeight: light ? .infinity : nil)
        // The selected tab is underlined at the strip's foot (DL-136).
        .overlay(alignment: .bottom) { if light && active { DuoColor.text.frame(height: 2) } }
        .contentShape(Rectangle())
        .onActivate { open(t.id) }  // action: session open
        .modifier(SessionOrganizeMenu(sessionKey: t.id, radius: DuoMetric.tabHoverRadius, onConsole: !light, tab: true, pane: pane,
                                      dragImage: { AnyView(TabDragImage(onConsole: !light) { label(t) }.padding(24)) }))   // room for the shadow
        // Dragged along the strip, its place moves (DL-220, console-drag). A live session's tab is a drag source already.
        .modifier(TabDraggable(key: t.id, pane: pane, space: Self.space, enabled: !model.isSessionDragSource(t.id), shown: { shown }))
        .modifier(ShellTabMenu(key: t.id, pane: pane, enabled: t.state == nil))
        .modifier(TabHover(key: t.id) { model.closeConsoleTab(t.id) })
        .accessibilityElement(children: .combine)
        .accessibilityLabel(t.state == nil ? "\(t.title), shell" : t.forkOf.map { "\(t.title), fork of \($0), \(t.state?.spokenName ?? "")" } ?? t.title)
        .modifier(KeepRunningLabel(pinned: t.state != nil && model.isKeepRunning(t.id), name: t.title, state: t.state ?? .idle))
        .accessibilityIdentifier(isHome ? "" : "video.tab.middle.\(allTabs.firstIndex { $0.id == t.id } ?? 0)")   // anchors: the video cursor's target (0-based, strip order)
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
        .overlay(alignment: .leading) {   // anchors (scene 4): the × while the tab shows it (its 16 pt box, centred on the glyph's place), 1-based in strip order; a sibling so the tab's own name stays
            if !isHome, model.videoDemoFolder != nil, model.showsTabClose(t.id) {
                let glyph = t.state == nil ? 11 : DuoMetric.glyph
                Color.clear.frame(width: DuoMetric.tabCloseSize, height: DuoMetric.tabCloseSize).allowsHitTesting(false)
                    .offset(x: (glyph - DuoMetric.tabCloseSize) / 2)
                    .accessibilityElement().accessibilityLabel("Close tab")
                    .accessibilityIdentifier("video.tab.middle.close.\((allTabs.firstIndex { $0.id == t.id } ?? 0) + 1)")
            }
        }
        .background(ground)
        .transition(.tab)
    }

    static func short(_ s: String) -> String {
        s.count > DuoMetric.consoleTabTitleMax ? String(s.prefix(DuoMetric.consoleTabTitleMax - 1)) + "…" : s
    }
}

/// A string's width in a font, measured once and kept (F-224). Measuring a title with glyphs the
/// font lacks (emoji, CJK, symbols) builds CoreText's fallback cascade, which on a cold cache opened
/// font files from disk: 905 ms on the work Mac, from a tab strip measuring every title on every pass.
public enum TextWidth {
    nonisolated(unsafe) private static var cache: [String: CGFloat] = [:]
    /// Measurements made (for the checks).
    nonisolated(unsafe) public private(set) static var measured = 0
    private static let lock = NSLock()

    public static func of(_ s: String, font: NSFont) -> CGFloat {
        let key = "\(font.fontName)\u{1}\(font.pointSize)\u{1}\(s)"
        lock.lock(); defer { lock.unlock() }
        if let w = cache[key] { return w }
        if cache.count > 4000 { cache.removeAll() }
        measured += 1
        let w = (s as NSString).size(withAttributes: [.font: font]).width
        cache[key] = w
        return w
    }
}

/// The fork mark (DL-228 B, fork-thread-handoff `canvas/Strip.dc.html`): three small circles joined as a branch, 10 × 10,
/// stroke 1.3, round caps and joins, in the tab's text colour.
struct ForkMark: View {
    let color: Color
    var body: some View {
        Canvas { ctx, box in
            ctx.scaleBy(x: box.width / 10, y: box.height / 10)
            var p = Path()
            for c in [CGPoint(x: 2.6, y: 2), CGPoint(x: 2.6, y: 8.2), CGPoint(x: 7.6, y: 2)] {
                p.addEllipse(in: CGRect(x: c.x - 1.2, y: c.y - 1.2, width: 2.4, height: 2.4))
            }
            p.move(to: .init(x: 2.6, y: 3.2)); p.addLine(to: .init(x: 2.6, y: 7))
            p.move(to: .init(x: 7.6, y: 3.2)); p.addCurve(to: .init(x: 2.6, y: 7), control1: .init(x: 7.6, y: 5.4), control2: .init(x: 2.6, y: 4.8))
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 10, height: 10)
        .accessibilityHidden(true)
    }
}

/// tokens.json `icon.shellPrompt`: a prompt mark, 11×9 (DB-4).
struct ShellPromptMark: View {
    let active: Bool
    var light = false
    var body: some View {
        Canvas { ctx, box in
            ctx.scaleBy(x: box.width / 12, y: box.height / 10)
            var p = Path()
            p.move(to: .init(x: 1.5, y: 2)); p.addLine(to: .init(x: 5, y: 5)); p.addLine(to: .init(x: 1.5, y: 8))
            p.move(to: .init(x: 6.5, y: 8.5)); p.addLine(to: .init(x: 10.5, y: 8.5))
            ctx.stroke(p, with: .color(light ? (active ? DuoColor.text : DuoColor.text2) : active ? DuoColor.consoleText : DuoColor.consoleText2),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// A shell tab's menu (DL-225): Close Tab, then Move Tab Left / Right, dimmed at the ends.
struct ShellTabMenu: ViewModifier {
    @Environment(AppModel.self) private var model
    let key: String
    let pane: DuoPane
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.contextMenu {
                Button("Close Tab") { model.closeConsoleTab(key) }  // action: session close
                Divider()
                Button("Move Tab Left") { model.moveTab(key, in: pane, by: -1) }  // action: view tab-move
                    .disabled(!model.canMoveTab(key, in: pane, by: -1))
                Button("Move Tab Right") { model.moveTab(key, in: pane, by: 1) }  // action: view tab-move
                    .disabled(!model.canMoveTab(key, in: pane, by: 1))
            }
        } else { content }
    }
}

public enum ShellTitles {
    /// `titles` in strip order, each with whether it's a shell: shells that read the same take " 2", " 3" after the first.
    public static func numbered(_ titles: [(title: String, isShell: Bool)]) -> [String] {
        var seen: [String: Int] = [:]
        return titles.map { t in
            guard t.isShell else { return t.title }
            let n = (seen[t.title] ?? 0) + 1
            seen[t.title] = n
            return n == 1 ? t.title : "\(t.title) \(n)"
        }
    }
}
