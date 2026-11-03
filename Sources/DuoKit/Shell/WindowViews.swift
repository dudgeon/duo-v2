import SwiftUI

// Multi-window slice 1's views (DL-311, DL-312; docs/design/multi-window-handoff): the toolbar swatch and
// its popover (board 4b A; twelve colours are the Q-444 stand-in), Window › Window Colour (board 4b; Q-446
// under Classic), and Home's stand-in in a window that doesn't hold it (board 10 B; Q-447). Each stand-in is
// one view here, so the approved drawing replaces it in one place.

/// The swatch after the project's name (board 4b), or after "All projects" (Q-445). Hidden under Classic
/// (board 4c A). Opens the colours and the switch.
struct WindowSwatch: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.core.classicOn {
            Button {
                model.colourPopoverOpen.toggle()   // action: window colour
            } label: {
                HStack(spacing: 2) {
                    Circle()
                        .fill(model.swatchColor)
                        .overlay(Circle().strokeBorder(DuoColor.controlEdge, lineWidth: DuoMetric.borderHairline))
                        .frame(width: 8, height: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 5, weight: .bold))
                        .foregroundStyle(model.toolbarText2)
                }
                .padding(.vertical, 1)
                .padding(.horizontal, 3)
                .contentShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Window Colour")
            .accessibilityLabel("Window Colour")
            .accessibilityValue(model.windowColour?.name ?? "None")
            .popover(isPresented: Binding(get: { model.colourPopoverOpen }, set: { model.colourPopoverOpen = $0 }), arrowEdge: .bottom) {
                WindowColourPopover().environment(model)
            }
        }
    }
}

/// The swatch's popover (board 4b, middle; Q-444 stand-in for twelve): "Window Colour", None, the six light
/// steps over the six deep ones in hue order, then "Colour new windows automatically".
struct WindowColourPopover: View {
    @Environment(AppModel.self) private var model

    static var lightRow: [DuoWindowColour.Colour] { DuoWindowColour.all.filter { !$0.deep }.sorted { $0.hue < $1.hue } }
    static var deepRow: [DuoWindowColour.Colour] { DuoWindowColour.all.filter(\.deep).sorted { $0.hue < $1.hue } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Window Colour").duoText(.bodyEmphasis).foregroundStyle(DuoColor.text)
            HStack(spacing: 8) { cell(nil) }
            HStack(spacing: 8) { ForEach(Self.lightRow) { cell($0) } }
            HStack(spacing: 8) { ForEach(Self.deepRow) { cell($0) } }
            Toggle(isOn: Binding(get: { model.core.colourNewWindows }, set: { model.core.colourNewWindows = $0 })) {   // action: window colour
                Text("Colour new windows automatically").duoText(.body).foregroundStyle(DuoColor.text)
            }
            .toggleStyle(.checkbox)
        }
        .padding(DuoSpace.popoverPadding)
    }

    private func cell(_ c: DuoWindowColour.Colour?) -> some View {
        let own = model.windowColourID == c?.id
        return Button {
            model.setWindowColour(c?.id)   // action: window colour
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(Color(nsColor: WindowTint.nsColor(.swatch, c)))
                    .overlay(Circle().strokeBorder(own ? DuoColor.text : DuoColor.controlEdge, lineWidth: own ? DuoMetric.borderEmphasis : DuoMetric.borderHairline))
                    .frame(width: 22, height: 22)
                Text(c?.name ?? "None").duoText(.pill).foregroundStyle(DuoColor.text2).lineLimit(1).fixedSize()
            }
            .frame(minWidth: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(c?.name ?? "None")
        .accessibilityAddTraits(own ? .isSelected : [])
    }
}

/// Window › Window Colour ▸ (board 4b; Q-444): None, the light six, the deep six, ticked on the window's own.
/// Dimmed under Classic with 4c's line as its tooltip (Q-446).
struct WindowColourMenu: View {
    let model: AppModel

    var body: some View {
        if model.core.classicOn {
            Button("Window Colour") {}   // action: window colour
                .disabled(true)
                .help("Window colours are off while Classic is on.")
        } else {
            Menu("Window Colour") {   // action: window colour
                item(nil)
                Divider()
                ForEach(WindowColourPopover.lightRow) { item($0) }
                Divider()
                ForEach(WindowColourPopover.deepRow) { item($0) }
            }
        }
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

/// Home's pane in a window that doesn't hold Home (board 10 B, Q-431; Q-447 stand-in): the dark pane says
/// where Home is, and Show Here moves its terminal to this window.
struct HomeElsewhere: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Text("Home is showing in window \(model.core.homeOwner?.windowNumber ?? 1)")
                .duoText(.body)
                .foregroundStyle(DuoColor.consoleText)
                .multilineTextAlignment(.center)
            Button("Show Here") { model.core.showHome(in: model) }   // action: window home
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, DuoSpace.panePadding)
        .background(DuoColor.console)
        .environment(\.colorScheme, .dark)   // the console is dark in every appearance
    }
}
