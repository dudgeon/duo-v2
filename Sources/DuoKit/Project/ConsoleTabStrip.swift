import AppKit
import SwiftUI

/// The console's tab strip (handoff §3.3, surfaces-handoff DB-4): sessions, then shells, then
/// `+` and the chevron. When they don't fit, titles shorten to 24 characters, then the tabs
/// furthest right move into a `» n` menu before `+`; the selected tab is never hidden. While the
/// selected tab shows chat, the strip is thin and light (DL-136, chat-polish-handoff `bar-thin`).
struct ConsoleTabStrip: View {
    @Environment(AppModel.self) private var model
    let project: String?

    struct Tab: Identifiable {
        let id: String
        let title: String
        let state: SessionState?   // nil: a shell
    }

    /// The selected Claude tab is showing chat: the thin light strip.
    var light: Bool { model.consoleShowsChat }
    /// The thin strip's 28 include the rule under it (`bar-thin`).
    var height: CGFloat { light ? DuoMetric.chatStripHeight - DuoMetric.borderHairline : DuoMetric.tabStripHeight }
    var ground: Color { light ? DuoColor.ground : DuoColor.console }
    var dim: Color { light ? DuoColor.text2 : DuoColor.consoleText2 }

    var body: some View {
        let tabs = allTabs
        GeometryReader { box in
            let fit = layout(tabs, width: box.size.width - 2 * DuoSpace.panePadding)
            HStack(spacing: light ? 16 : 18) {
                ForEach(fit.shown) { t in tab(t, short: fit.short) }
                if !fit.hidden.isEmpty {
                    HStack(spacing: 4) {
                        MoreTabsMark(color: dim).frame(width: 11, height: 9)
                        Text("\(fit.hidden.count)").duoText(light ? .control : .mono).foregroundStyle(dim)
                    }
                    .contentShape(Rectangle())
                    .onActivate { PopUp.show(fit.hidden.map { t in (t.title, { model.consoleTab = t.id }) }) }  // action: session open
                    .accessibilityLabel("\(fit.hidden.count) more tabs")
                }
                HStack(spacing: 5) {
                    Text("+").duoText(light ? .control : .mono).foregroundStyle(dim)
                        .onActivate { model.newSession() }  // action: session new
                        .accessibilityLabel("New Claude session")
                    Chevron(direction: .down, color: dim).frame(width: 8, height: 6).scaleEffect(0.8)
                        .frame(height: 16).contentShape(Rectangle())
                        .onActivate {  // action: session new
                            PopUp.show([("New Claude Session", { model.newSession() }), ("New Shell", { model.newShell() })],
                                       keys: [("t", [.command]), ("t", [.command, .shift])])
                        }
                        .accessibilityLabel("New session or shell")
                }
                // Opaque on the strip, so it covers a tab fading out as it slides (DL-130).
                .background(ground)
                Spacer(minLength: 0)
                // Terminal / Chat, for the selected Claude tab (chat-mode-handoff `toggle`); 12 from the edge.
                if let key = model.consoleTab, tabs.contains(where: { $0.id == key && $0.state != nil }),
                   model.chat(for: key) != nil {
                    ChatToggle(key: key, light: light).padding(.trailing, light ? -6 : -4)   // 11 from the edge (bar-thin) on the thin strip
                }
            }
            .padding(.horizontal, DuoSpace.panePadding)
            .frame(height: height)
            .duoAnimation(.tabMove, value: fit.shown.map(\.id))
            .id(project)   // another project's tabs replace these at once
        }
        .frame(height: height)
        .background(light ? DuoColor.ground : .clear)
    }

    var allTabs: [Tab] {
        guard let project else { return [] }
        let sessions = model.tabSessions(inProject: project).map { Tab(id: $0.tabKey, title: $0.name, state: $0.state) }
        return sessions + model.shells(inProject: project).map { Tab(id: $0, title: model.consoleTitle($0), state: nil) }
    }

    @ViewBuilder func tab(_ t: Tab, short: Bool) -> some View {
        let active = t.id == model.consoleTab
        HStack(spacing: DuoSpace.gapGlyphToLabel) {
            // Under the pointer the glyph's place holds the × (DL-126); nothing moves.
            if model.showsTabClose(t.id) {
                TabCloseButton(key: t.id, onConsole: !light, active: active) { model.closeConsoleTab(t.id) }  // action: session close
                    .frame(width: t.state == nil ? 11 : DuoMetric.glyph, height: t.state == nil ? 9 : DuoMetric.glyph)   // the glyph's own box
            } else if let st = t.state { StateGlyph(st, on: light ? .light : .console(active: active)) }   // light: Q-87's stand-in
            else { ShellPromptMark(active: active, light: light).frame(width: 11, height: 9) }
            if light {
                Text(short ? Self.short(t.title) : t.title)
                    .duoText(.control, weight: active ? .semibold : nil)
                    .foregroundStyle(active ? DuoColor.text : DuoColor.text2)
                    .lineLimit(1)
            } else {
                Text(short ? Self.short(t.title) : t.title)
                    .duoText(active ? .monoActiveTab : .mono)
                    .foregroundStyle(active ? DuoColor.consoleText : DuoColor.consoleText2)
                    .lineLimit(1)
            }
        }
        .fixedSize()
        .modifier(TabHoverFill(key: t.id, onConsole: !light, fill: light ? DuoColor.selected : nil))
        .frame(maxHeight: light ? .infinity : nil)
        // The selected tab is underlined at the strip's foot (DL-136).
        .overlay(alignment: .bottom) { if light && active { DuoColor.text.frame(height: 2) } }
        .contentShape(Rectangle())
        .onActivate { model.openConsoleTab(t.id) }  // action: session open
        .modifier(SessionOrganizeMenu(sessionKey: t.id))
        .modifier(TabHover(key: t.id) { model.closeConsoleTab(t.id) })
        .accessibilityElement(children: .combine)
        .accessibilityLabel(t.state == nil ? "\(t.title), shell" : t.title)
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
        .background(ground)
        .transition(.tab)
    }

    static func short(_ s: String) -> String {
        s.count > DuoMetric.consoleTabTitleMax ? String(s.prefix(DuoMetric.consoleTabTitleMax - 1)) + "…" : s
    }

    /// Which tabs show, and whether titles are shortened, for the strip's width. Runs on every pass
    /// of the strip's body: each title is measured once (`TextWidth`, F-224), and the fit is one walk.
    func layout(_ tabs: [Tab], width: CGFloat) -> (shown: [Tab], hidden: [Tab], short: Bool) {
        let font = (light ? DuoTextStyle.control : DuoTextStyle.mono).spec.nsFont
        func w(_ t: Tab, _ short: Bool) -> CGFloat {
            (t.state == nil ? 11 : 9) + DuoSpace.gapGlyphToLabel + TextWidth.of(short ? Self.short(t.title) : t.title, font: font)
        }
        var controls: CGFloat = 5 + 8 + 10 + 18          // + , chevron, and the gap before them
        if let key = model.consoleTab, model.chat(for: key) != nil { controls += light ? 46 + 16 - 6 : 52 + 18 - 4 }   // the chat toggle
        let more: CGFloat = 11 + 4 + 16 + 18             // » n, when needed
        let r = TabStripFit.fit(full: tabs.map { w($0, false) }, short: tabs.map { w($0, true) }, selected: tabs.firstIndex { $0.id == model.consoleTab },
                         width: width, controls: controls, more: more)
        return (tabs.indices.filter { r.keep[$0] }.map { tabs[$0] }, tabs.indices.filter { !r.keep[$0] }.map { tabs[$0] }, r.short)
    }

}

public enum TabStripFit {
    /// The fit, from each tab's width full and shortened: all full, all short, or short with tabs
    /// dropped from the right (never the selected one) until the rest and `» n` fit. One walk.
    public static func fit(full: [CGFloat], short: [CGFloat], selected: Int?, width: CGFloat, controls: CGFloat, more: CGFloat) -> (keep: [Bool], short: Bool) {
        func total(_ ws: [CGFloat]) -> CGFloat { ws.reduce(0, +) + CGFloat(max(0, ws.count - 1)) * 18 + controls }
        if total(full) <= width { return (Array(repeating: true, count: full.count), false) }
        if total(short) <= width { return (Array(repeating: true, count: full.count), true) }
        var keep = Array(repeating: true, count: full.count)
        var sum = short.reduce(0, +), count = full.count
        var i = full.count - 1
        while i >= 0, sum + CGFloat(max(0, count - 1)) * 18 + controls + more > width {
            if i != selected { keep[i] = false; sum -= short[i]; count -= 1 }
            i -= 1
        }
        return (keep, true)
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
        let w = ceil((s as NSString).size(withAttributes: [.font: font]).width)
        cache[key] = w
        return w
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

/// tokens.json `icon.moreTabs`: »
struct MoreTabsMark: View {
    var color = DuoColor.consoleText2
    var body: some View {
        Canvas { ctx, box in
            ctx.scaleBy(x: box.width / 12, y: box.height / 10)
            var p = Path()
            p.move(to: .init(x: 2, y: 1.5)); p.addLine(to: .init(x: 5.5, y: 5)); p.addLine(to: .init(x: 2, y: 8.5))
            p.move(to: .init(x: 6.5, y: 1.5)); p.addLine(to: .init(x: 10, y: 5)); p.addLine(to: .init(x: 6.5, y: 8.5))
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
