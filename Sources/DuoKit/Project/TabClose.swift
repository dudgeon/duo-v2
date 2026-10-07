import SwiftUI

/// The close button a tab shows under the pointer (DL-126, canvas
/// https://claude.ai/artifact/BcUBs8KZcpEpPF3EhHt6GT): a 7 pt × in a 10 pt box, in place of a
/// console tab's state glyph or in the gap before a right-pane tab's title. On the × a 16 pt
/// square, radius 4, shows behind it; pressed, a stronger one. It runs exactly what ⌘W or the
/// tab's Close Tab runs, so it adds no behaviour of its own.
struct TabCloseButton: View {
    @Environment(AppModel.self) private var model
    let key: String
    let onConsole: Bool
    let active: Bool
    let close: () -> Void

    var body: some View {
        Button {
            model.hoveredTab = nil; model.hoveredTabClose = nil; model.pressedTabClose = nil
            close()
        } label: { EmptyView() }
            .buttonStyle(Style(on: model.hoveredTabClose == key, held: model.pressedTabClose == key,
                               onConsole: onConsole, active: active))
            .frame(width: DuoMetric.tabCloseSize, height: DuoMetric.tabCloseSize)
            .contentShape(RoundedRectangle(cornerRadius: DuoMetric.tabCloseRadius))
            .onHover { inside in
                if inside { model.hoveredTabClose = key } else if model.hoveredTabClose == key { model.hoveredTabClose = nil }
            }
            .help("Close Tab")
            .accessibilityHidden(true)   // the tab itself offers Close Tab (TabHover)
    }

    struct Style: ButtonStyle {
        let on: Bool
        let held: Bool
        let onConsole: Bool
        let active: Bool

        func makeBody(configuration: Configuration) -> some View {
            let pressed = configuration.isPressed || held
            let fill: Color = pressed ? (onConsole ? DuoColor.tuiInputBorder : DuoColor.rule)
                : on ? (onConsole ? DuoColor.consoleRule : DuoColor.selected) : .clear
            let strong = on || pressed || active
            let ink: Color = onConsole ? (strong ? DuoColor.consoleText : DuoColor.consoleText2)
                : (strong ? DuoColor.text : DuoColor.text2)
            ZStack {
                RoundedRectangle(cornerRadius: DuoMetric.tabCloseRadius).fill(fill)
                TabCloseMark(color: ink).frame(width: DuoMetric.tabCloseGlyph, height: DuoMetric.tabCloseGlyph)
            }
            .frame(width: DuoMetric.tabCloseSize, height: DuoMetric.tabCloseSize)
        }
    }
}

/// The × itself: two strokes, round caps, 7 pt across in a 10 pt box.
struct TabCloseMark: View {
    let color: Color
    var body: some View {
        Canvas { ctx, box in
            ctx.scaleBy(x: box.width / 10, y: box.height / 10)
            var p = Path()
            p.move(to: .init(x: 1.5, y: 1.5)); p.addLine(to: .init(x: 8.5, y: 8.5))
            p.move(to: .init(x: 8.5, y: 1.5)); p.addLine(to: .init(x: 1.5, y: 8.5))
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: DuoMetric.tabCloseStroke, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Tracks which tab is under the pointer, in the model (no view state, DL-30), and gives the tab
/// a Close Tab action for VoiceOver and Full Keyboard Access, since the × shows only on hover.
struct TabHover: ViewModifier {
    @Environment(AppModel.self) private var model
    let key: String
    var enabled = true   // a tab with no Close Tab (Project, a group page) gets nothing
    let close: () -> Void

    func body(content: Content) -> some View {
        if enabled { hovering(content) } else { content }
    }

    func hovering(_ content: Content) -> some View {
        content
            .onHover { inside in
                if inside { model.hoveredTab = key } else if model.hoveredTab == key { model.hoveredTab = nil }
            }
            .accessibilityAction(named: "Close Tab", close)
    }
}

/// The fill behind a closable tab while it shows its × (DL-134, canvas
/// https://claude.ai/artifact/PEPNt2XyjyuWxYjG3ZofKN, A): radius 5, 24 high, `consoleHover` on
/// the console and `ground` on the right pane, reaching 7 past the glyph or × and the name.
/// Drawn behind the tab, so nothing moves; it comes and goes with the ×, without a fade (DL-130).
struct TabHoverFill: ViewModifier {
    @Environment(AppModel.self) private var model
    let key: String
    let onConsole: Bool
    var leading = DuoMetric.tabHoverInset

    func body(content: Content) -> some View {
        content.background {
            if model.showsTabClose(key) {
                RoundedRectangle(cornerRadius: DuoMetric.tabHoverRadius)
                    .fill(onConsole ? DuoColor.consoleHover : DuoColor.ground)
                    .padding(.leading, -leading)
                    .padding(.trailing, -DuoMetric.tabHoverInset)
                    .frame(height: DuoMetric.tabHoverHeight)
            }
        }
    }
}

extension AppModel {
    /// Whether a tab shows its × now: under the pointer, or the pointer is on the × itself.
    func showsTabClose(_ key: String) -> Bool { hoveredTab == key || hoveredTabClose == key || pressedTabClose == key }

    /// A console or Home tab's ×: what ⌘W does for that tab when it's the one showing
    /// (`closeVisibleSession`), for any tab: a shell's process ends and its tab goes; a
    /// session's process ends, it stays filed and resumable, and the next tab is selected.
    /// Asks first when Claude is working there or the shell is running a command (Q-71).
    public func closeConsoleTab(_ key: String) {
        confirmClose(key) { [weak self] in
            guard let self else { return }
            if self.isShell(key) { self.closeShell(key) } else { self.closeSession(key) }
        }
    }
}
