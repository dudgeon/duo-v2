import SwiftUI

/// The split mark (`split-deck`): an 11 × 9 outline, radius 2, stroke 1.2, divided at 3.5, in `text2`.
struct SplitMark: View {
    var body: some View {
        Canvas { ctx, _ in
            let w = DuoMetric.splitMarkWidth, h = DuoMetric.splitMarkHeight
            let box = CGRect(x: 0.6, y: 0.6, width: w - 1.2, height: h - 1.2)
            var p = Path(roundedRect: box, cornerRadius: 2)
            p.move(to: CGPoint(x: 3.5, y: 0.6)); p.addLine(to: CGPoint(x: 3.5, y: h - 0.6))
            ctx.stroke(p, with: .color(DuoColor.text2), lineWidth: 1.2)
        }
        .frame(width: DuoMetric.splitMarkWidth, height: DuoMetric.splitMarkHeight)
        .accessibilityHidden(true)
    }
}

/// A split tab's two names joined by the mark: the active side's is semibold in `text`, the other `text2`.
/// Each has its own hover ×; folded, the names are a toggle and the shown one sits on a `selected` fill.
struct SplitTabNames: View {
    @Environment(AppModel.self) private var model
    let split: SplitTab
    let title: String
    let tabActive: Bool

    var body: some View {
        let first = split.role(at: .left), second = split.role(at: .right)
        HStack(spacing: 6) {
            name(first)
            SplitMark()
            name(second)
        }
    }

    @ViewBuilder private func name(_ role: SplitRole) -> some View {
        let on = tabActive && split.active == role
        let hidden = split.folded && split.active != role   // folded, only the active side shows
        let text = role == .source ? title : split.kind.sideName
        HStack(spacing: DuoMetric.tabCloseTitleGap) {
            if role == .preview, model.showsTabClose(split.source) {
                TabCloseButton(key: split.source + "#preview", onConsole: false, active: on) { model.closePreviewSide(split.source) }  // action: split close
            }
            Text(text).duoText(on ? .bodyEmphasis : .body)
                .foregroundStyle(on ? DuoColor.text : hidden ? DuoColor.controlEdge : DuoColor.text2).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture {   // action: split focus
            model.rightTab = split.source
            model.selectedFile = split.source
            if hidden { model.unfoldSplit(role) } else { model.setActiveRole(role, in: split.source) }   // the dimmed name unfolds
        }
        .accessibilityLabel(text)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }
}

/// The folded sidebar's 16 wide rail (DL-276, `making-room`): the sidebar glyph, and the needs-you dot
/// under it while any session needs you. The whole rail is one button; a click peeks.
struct SidebarRail: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let hovering = model.splits.railHover == "sidebar"
        if model.splits.sidebarFolded {
            ZStack(alignment: .top) {
                (hovering ? DuoColor.selected : DuoColor.pane)
                VStack(spacing: 8) {
                    Image(systemName: "sidebar.left").font(.system(size: 12)).foregroundStyle(DuoColor.text2)
                    if !model.needsYouElsewhere.isEmpty {
                        Circle().fill(DuoColor.needsYou).frame(width: DuoMetric.tabNeedsYouDot, height: DuoMetric.tabNeedsYouDot)
                            .accessibilityLabel("needs you")
                    }
                }
                .padding(.top, 10)
                HStack { Spacer(); DuoColor.rule.frame(width: 1) }
            }
            .frame(width: DuoMetric.sidebarRail)
            .contentShape(Rectangle())
            .onHover { model.splits.railHover = $0 ? "sidebar" : nil }
            .onTapGesture { model.setSidebarPeek(!model.splits.peek) }   // action: view sidebar
            .help("Show Sidebar ⌃⌘S")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Show Sidebar")
            .accessibilityAddTraits(.isButton)
        }
    }
}

/// The sidebar peeking over the console from the rail's right edge, at its own width, with the popover
/// shadow. The split does not move. Esc, a click outside or the rail closes it.
struct SidebarPeek: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.splits.sidebarFolded, model.splits.peek {
            ZStack(alignment: .leading) {
                Color.clear.contentShape(Rectangle()).onTapGesture { model.setSidebarPeek(false) }   // action: view sidebar
                ProjectSidebarPane()
                    .frame(width: DuoMetric.paneProjectLeft)
                    .background(DuoColor.pane)
                    .shadow(color: DuoShadow.popoverColor, radius: DuoShadow.popoverRadius, x: DuoShadow.popoverX, y: 0)   // shadowPopover
                    .transition(.move(edge: .leading))
            }
            .onExitCommand { model.setSidebarPeek(false) }
            .duoAnimation(.paneToggle, value: model.splits.peek)
        }
    }
}
