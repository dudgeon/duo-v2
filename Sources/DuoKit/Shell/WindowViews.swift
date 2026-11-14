import SwiftUI

// Multi-window slice 1's views (DL-311, DL-312, DL-314; docs/design/multi-window-handoff): the toolbar swatch
// and its popover (boards 4b A, 4b′ A), Window › Window Colour (4b, 4c′ A under Classic), and Home's pane in
// a window that doesn't hold it (10 B, 10′ A).

/// The swatch that ends the breadcrumb (DL-314, 4b″ A): after the project's name, or after "All projects".
/// Hidden under Classic (board 4c A). Opens the colours and the switch.
struct WindowSwatch: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.core.classicOn {
            Button {
                model.colourPopoverOpen.toggle()   // action: window color
            } label: {
                HStack(spacing: 3) {
                    Circle()
                        .fill(model.swatchColor)
                        .overlay(Circle().strokeBorder(DuoColor.controlEdge, lineWidth: DuoMetric.borderHairline))
                        .frame(width: 11, height: 11)
                    Image(systemName: "chevron.down")
                        .font(.system(size: DuoSymbolSize.swatchChevron, weight: .semibold))
                        .foregroundStyle(model.toolbarText2)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                // Outlined while its popover is open (4b′); bare at rest (4b, 4b″).
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(model.colourPopoverOpen ? DuoColor.controlEdge : .clear, lineWidth: DuoMetric.borderHairline))
                .contentShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Window Color")
            .accessibilityLabel("Window Color")
            .accessibilityValue(model.windowColour?.name ?? "None")
            .popover(isPresented: Binding(get: { model.colourPopoverOpen }, set: { model.colourPopoverOpen = $0 }), arrowEdge: .bottom) {
                WindowColourPopover().environment(model)
            }
        }
    }
}

/// The swatch's popover (DL-314, board 4b′ A): "Window Color"; None on its own row, naming the window's
/// colour at the right; one column per hue, named once on top, with Light and Deep rows; then the switch.
struct WindowColourPopover: View {
    @Environment(AppModel.self) private var model

    static var lightRow: [DuoWindowColour.Colour] { DuoWindowColour.all.filter { !$0.deep }.sorted { $0.hue < $1.hue } }
    static var deepRow: [DuoWindowColour.Colour] { DuoWindowColour.all.filter(\.deep).sorted { $0.hue < $1.hue } }
    private static let column: CGFloat = 46
    private static let label: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Window Color").duoText(.bodyEmphasis).foregroundStyle(DuoColor.text)
            HStack(spacing: 8) {
                dot(nil)
                Text("None").duoText(.body).foregroundStyle(DuoColor.text)
                Spacer(minLength: 16)
                Text(model.windowColour?.name ?? "None").duoText(.pill).foregroundStyle(DuoColor.text2)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: Self.label, height: 1)
                    ForEach(Self.lightRow) { c in
                        Text(c.name).duoText(.pill).foregroundStyle(DuoColor.text2).frame(width: Self.column)
                    }
                }
                row("Light", Self.lightRow)
                row("Deep", Self.deepRow)
            }
            Divider()
            Toggle(isOn: Binding(get: { model.core.colourNewWindows }, set: { model.core.colourNewWindows = $0 })) {   // action: window color
                Text("Color new windows automatically").duoText(.body).foregroundStyle(DuoColor.text)
            }
            .toggleStyle(.checkbox)
        }
        .padding(DuoSpace.popoverPadding)
        .frame(width: Self.label + 6 * Self.column + DuoSpace.popoverPadding.leading + DuoSpace.popoverPadding.trailing)
    }

    private func row(_ name: String, _ colours: [DuoWindowColour.Colour]) -> some View {
        HStack(spacing: 0) {
            Text(name).duoText(.pill).foregroundStyle(DuoColor.text2).frame(width: Self.label, alignment: .leading)
            ForEach(colours) { c in dot(c).frame(width: Self.column) }
        }
    }

    private func dot(_ c: DuoWindowColour.Colour?) -> some View {
        let own = model.windowColourID == c?.id
        return Button {
            model.setWindowColour(c?.id)   // action: window color
        } label: {
            Circle()
                .fill(Color(nsColor: WindowTint.nsColor(.swatch, c)))
                .overlay(Circle().strokeBorder(own ? DuoColor.text : DuoColor.controlEdge, lineWidth: own ? 2 : DuoMetric.borderHairline))
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(c?.name ?? "None")
        .accessibilityLabel(c?.name ?? "None")
        .accessibilityAddTraits(own ? .isSelected : [])
    }
}

/// Window › Window Colour ▸ (DL-314): None, the six light, the six deep in 4a′'s hue order, ticked on the
/// window's own. Under Classic (4c′ A) it stays enabled: 4c's line at the top, every colour dimmed with the
/// window's own still ticked, then Appearance Settings….
struct WindowColourMenu: View {
    let model: AppModel

    var body: some View {
        let classic = model.core.classicOn
        Menu("Window Color") {   // action: window color
            if classic {
                Text("Window colors are off while Classic is on. Each window gets its color back when you choose another appearance.")
                Divider()
            }
            item(nil).disabled(classic)
            Divider()
            ForEach(WindowColourPopover.lightRow) { item($0).disabled(classic) }
            Divider()
            ForEach(WindowColourPopover.deepRow) { item($0).disabled(classic) }
            if classic {
                Divider()
                Button("Appearance Settings…") { WindowColourMenu.openSettings() }   // action: settings
            }
        }
    }

    /// Settings › General, where Appearance is (the Settings scene's own action).
    @MainActor static func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func item(_ c: DuoWindowColour.Colour?) -> some View {
        Toggle(isOn: Binding(get: { model.windowColourID == c?.id }, set: { if $0 { model.setWindowColour(c?.id) } })) {
            Label {
                Text(c?.name ?? "None")
            } icon: {
                Image(nsImage: WindowSwatchImage.make(c))
            }
        }
    }
}

/// A 12 pt swatch for a menu item (menus draw images, not shapes).
enum WindowSwatchImage {
    @MainActor static func make(_ c: DuoWindowColour.Colour?) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let img = NSImage(size: size, flipped: false) { r in
            let path = NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5))
            WindowTint.nsColor(.swatch, c).setFill(); path.fill()
            DuoNSColor.controlEdge.setStroke(); path.lineWidth = 1; path.stroke()
            return true
        }
        return img
    }
}
