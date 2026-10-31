import AppKit
import SwiftUI

/// The first row of All projects › List (DL-262): `New session in [★ home ⌄]  ⌘T`. Dashed, because in this
/// header dashed means "make something" (as on `+ New project`). The row starts a session in the default;
/// the popup picks another place. Metrics are the handoff's: 28 high, the popup 20 high, radius 5.
struct NewSessionRow: View {
    @Environment(AppModel.self) private var model

    private static let height: CGFloat = 28
    private static let popupHeight: CGFloat = 20
    private static let popupRadius: CGFloat = 5

    var body: some View {
        let place = model.startDefault
        let hover = model.newSessionRowHover, pressed = model.newSessionRowPressed
        HStack(spacing: 8) {
            RobotMark().fill(hover ? DuoColor.text : DuoColor.text2).frame(width: 12, height: 8)
            Text("New session").duoText(.body).foregroundStyle(DuoColor.text)
            Text("in").duoText(.body).foregroundStyle(DuoColor.text2)
            popup(place)
            Spacer(minLength: 0)
            Text("⌘T").duoText(.control).foregroundStyle(DuoColor.text2)
        }
        .padding(.leading, 10).padding(.trailing, 6)
        .frame(height: Self.height)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).fill(pressed ? DuoColor.menuTarget : hover ? DuoColor.selected : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusControl)
            .strokeBorder(DuoColor.controlEdge, style: StrokeStyle(lineWidth: DuoMetric.borderHairline, dash: DuoShadow.dashPattern)))
        .contentShape(Rectangle())
        .onHover { model.newSessionRowHover = $0 }
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in model.newSessionRowPressed = true }.onEnded { _ in model.newSessionRowPressed = false })
        .onActivate { model.pressNewSessionRow() }  // action: session new
        .focusable().focusEffectDisabled()
        .onKeyPress(.return) { model.pressNewSessionRow(); return .handled }
        .help("New Claude session ⌘T · in \(place?.label ?? "…choose a folder")")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New session in \(place?.label ?? "a folder you choose")")
        .accessibilityIdentifier("new-session-row")
    }

    /// The popup: a system menu under it (the default ticked, the others, Choose Another Folder…).
    private func popup(_ place: StartPlace?) -> some View {
        HStack(spacing: 5) {
            if let place {
                if place.kind == .home {
                    Text("★").font(.system(size: 11)).foregroundStyle(DuoColor.text)
                    Text("home").duoText(.control, lineHeight: 16).foregroundStyle(DuoColor.text)
                } else {
                    Text(place.label).duoText(.control, lineHeight: 16).foregroundStyle(DuoColor.text).lineLimit(1).truncationMode(.middle)
                }
            } else {
                Text("Choose…").duoText(.control, lineHeight: 16).foregroundStyle(DuoColor.text2)
            }
            Image(systemName: "chevron.up.chevron.down").font(.system(size: DuoSymbolSize.chevronSmall, weight: .semibold)).foregroundStyle(DuoColor.text2)
        }
        .padding(.leading, 7).padding(.trailing, 6)
        .frame(height: Self.popupHeight)
        .background(RoundedRectangle(cornerRadius: Self.popupRadius).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: Self.popupRadius).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
        .contentShape(Rectangle())
        .onActivate { NewSessionPopup.show(model) }  // action: session new
        .accessibilityLabel("Where to start")
    }
}
