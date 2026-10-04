import AppKit
import SwiftUI

/// The console's tab strip (handoff §3.3, surfaces-handoff DB-4): sessions, then shells, then
/// `+` and the chevron. When they don't fit, titles shorten to 24 characters, then the tabs
/// furthest right move into a `» n` menu before `+`; the selected tab is never hidden.
struct ConsoleTabStrip: View {
    @Environment(AppModel.self) private var model
    let project: String?

    struct Tab: Identifiable {
        let id: String
        let title: String
        let state: SessionState?   // nil: a shell
    }

    var body: some View {
        let tabs = allTabs
        GeometryReader { box in
            let fit = layout(tabs, width: box.size.width - 2 * DuoSpace.panePadding)
            HStack(spacing: 18) {
                ForEach(fit.shown) { t in tab(t, short: fit.short) }
                if !fit.hidden.isEmpty {
                    HStack(spacing: 4) {
                        MoreTabsMark().frame(width: 11, height: 9)
                        Text("\(fit.hidden.count)").duoText(.mono).foregroundStyle(DuoColor.consoleText2)
                    }
                    .contentShape(Rectangle())
                    .onActivate { PopUp.show(fit.hidden.map { t in (t.title, { model.consoleTab = t.id }) }) }  // action: session open
                    .accessibilityLabel("\(fit.hidden.count) more tabs")
                }
                HStack(spacing: 5) {
                    Text("+").duoText(.mono).foregroundStyle(DuoColor.consoleText2)
                        .onActivate { model.newSession() }  // action: session new
                        .accessibilityLabel("New Claude session")
                    Chevron(direction: .down, color: DuoColor.consoleText2).frame(width: 8, height: 6).scaleEffect(0.8)
                        .frame(height: 16).contentShape(Rectangle())
                        .onActivate {  // action: session new
                            PopUp.show([("New Claude Session", { model.newSession() }), ("New Shell", { model.newShell() })],
                                       keys: [("t", [.command]), ("t", [.command, .shift])])
                        }
                        .accessibilityLabel("New session or shell")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DuoSpace.panePadding)
            .frame(height: DuoMetric.tabStripHeight)
        }
        .frame(height: DuoMetric.tabStripHeight)
    }

    var allTabs: [Tab] {
        guard let project else { return [] }
        let sessions = model.tabSessions(inProject: project).map { Tab(id: $0.tabKey, title: $0.name, state: $0.state) }
        return sessions + model.shells(inProject: project).map { Tab(id: $0, title: model.consoleTitle($0), state: nil) }
    }

    @ViewBuilder func tab(_ t: Tab, short: Bool) -> some View {
        let active = t.id == model.consoleTab
        HStack(spacing: DuoSpace.gapGlyphToLabel) {
            if let st = t.state { StateGlyph(st, on: .console(active: active)) }
            else { ShellPromptMark(active: active).frame(width: 11, height: 9) }
            Text(short ? Self.short(t.title) : t.title)
                .duoText(active ? .monoActiveTab : .mono)
                .foregroundStyle(active ? DuoColor.consoleText : DuoColor.consoleText2)
                .lineLimit(1)
        }
        .fixedSize()
        .contentShape(Rectangle())
        .onActivate { model.openConsoleTab(t.id) }  // action: session open
        .accessibilityElement(children: .combine)
        .accessibilityLabel(t.state == nil ? "\(t.title), shell" : t.title)
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
    }

    static func short(_ s: String) -> String {
        s.count > DuoMetric.consoleTabTitleMax ? String(s.prefix(DuoMetric.consoleTabTitleMax - 1)) + "…" : s
    }

    /// Which tabs show, and whether titles are shortened, for the strip's width.
    func layout(_ tabs: [Tab], width: CGFloat) -> (shown: [Tab], hidden: [Tab], short: Bool) {
        let font = DuoTextStyle.mono.spec.nsFont
        func w(_ t: Tab, _ short: Bool) -> CGFloat {
            (t.state == nil ? 11 : 9) + DuoSpace.gapGlyphToLabel
                + ceil(((short ? Self.short(t.title) : t.title) as NSString).size(withAttributes: [.font: font]).width)
        }
        let controls: CGFloat = 5 + 8 + 10 + 18          // + , chevron, and the gap before them
        let more: CGFloat = 11 + 4 + 16 + 18             // » n, when needed
        func total(_ ts: [Tab], _ short: Bool, _ withMore: Bool) -> CGFloat {
            ts.map { w($0, short) }.reduce(0, +) + CGFloat(max(0, ts.count - 1)) * 18 + controls + (withMore ? more : 0)
        }
        if total(tabs, false, false) <= width { return (tabs, [], false) }
        if total(tabs, true, false) <= width { return (tabs, [], true) }
        var shown = tabs
        var hidden: [Tab] = []
        while total(shown, true, true) > width, let i = shown.lastIndex(where: { $0.id != model.consoleTab }) {
            hidden.insert(shown.remove(at: i), at: 0)
        }
        return (shown, hidden, true)
    }
}

/// tokens.json `icon.shellPrompt`: a prompt mark, 11×9 (DB-4).
struct ShellPromptMark: View {
    let active: Bool
    var body: some View {
        Canvas { ctx, box in
            ctx.scaleBy(x: box.width / 12, y: box.height / 10)
            var p = Path()
            p.move(to: .init(x: 1.5, y: 2)); p.addLine(to: .init(x: 5, y: 5)); p.addLine(to: .init(x: 1.5, y: 8))
            p.move(to: .init(x: 6.5, y: 8.5)); p.addLine(to: .init(x: 10.5, y: 8.5))
            ctx.stroke(p, with: .color(active ? DuoColor.consoleText : DuoColor.consoleText2),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// tokens.json `icon.moreTabs`: »
struct MoreTabsMark: View {
    var body: some View {
        Canvas { ctx, box in
            ctx.scaleBy(x: box.width / 12, y: box.height / 10)
            var p = Path()
            p.move(to: .init(x: 2, y: 1.5)); p.addLine(to: .init(x: 5.5, y: 5)); p.addLine(to: .init(x: 2, y: 8.5))
            p.move(to: .init(x: 6.5, y: 1.5)); p.addLine(to: .init(x: 10, y: 5)); p.addLine(to: .init(x: 6.5, y: 8.5))
            ctx.stroke(p, with: .color(DuoColor.consoleText2), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
