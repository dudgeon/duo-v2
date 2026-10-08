import AppKit
import SwiftUI

/// Duo's own sheets (DL-100): drawn in the window, hanging from the toolbar, so they match the
/// targets and never block a scripted run the way a system alert can. The map behind dims to 55%.
struct SheetOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let up = model.sheetIsUp
        ZStack(alignment: .top) {
            if up {
                // Clicks behind a sheet go nowhere, as with a window sheet.
                Color.clear.contentShape(Rectangle())
                    .onActivate {}  // not an action: swallows clicks behind the sheet
                // It hangs down from the toolbar and goes back up, as a window sheet does (DL-130):
                // `sheetIn` 200 ms ease-out, `sheetOut` 150 ms ease-in. The next queued question
                // cross-fades in its place (`sheetSwap`) instead of dropping again.
                ZStack(alignment: .top) {
                    if let m = model.moveIntoHomeForm { MoveIntoHomeSheet(form: m) }
                    else if let n = model.newProjectForm { NewProjectSheet(form: n) }
                    else if let p = model.pushForm { PushSheet(form: p) }
                    else if let q = SheetCenter.shared.current { QuestionSheet(q: q).id(q.id).transition(.opacity) }
                }
                .duoAnimation(.sheetSwap, value: SheetCenter.shared.current?.id)
                // The targets hang the sheet 38 from the window's top, over the toolbar's hairline.
                .offset(y: DuoMetric.sheetTop - FixtureHarness.designContentTop)
                .transition(.move(edge: .top))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Slides from under the toolbar, never over it: clip at the hairline the sheet hangs from.
        .mask(Rectangle().padding(.top, DuoMetric.sheetTop - FixtureHarness.designContentTop))
        .animation((up ? DuoMotionToken.sheetIn : .sheetOut).animation, value: up)
        .allowsHitTesting(up)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(up ? .isModal : [])
        .accessibilityHidden(!up)
    }
}

/// Move into Home… (S2-4): 460 wide on `ground`, open at the top, radius 10 below.
struct MoveIntoHomeSheet: View {
    @Environment(AppModel.self) private var model
    let form: MoveIntoHomeForm

    var body: some View {
        let mono = Font(NSFont.monospacedSystemFont(ofSize: DuoTextStyle.mono.spec.size, weight: .regular))
        let n = form.sessions
        VStack(alignment: .leading, spacing: DuoSpace.gapCardToCard) {
            Text("Move \(form.project) into Home?").duoText(.bodyEmphasis)
            Text("\(Text(AppModel.short(form.from)).font(mono)) moves to \(Text(AppModel.short(form.dest)).font(mono)), with its \(n) session\(n == 1 ? "" : "s"). They stay \(form.project)’s and resume from the new place.")
                .duoText(.body)
                .fixedSize(horizontal: false, vertical: true)
            Text((["Other apps that open the old path (an editor’s recent files, scripts, other clones) won’t find it there. Edit › Undo puts it all back."] + form.warnings).joined(separator: " "))
                .duoText(.body).foregroundStyle(DuoColor.text2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DuoSpace.gapRowItems) {
                Text("Into").duoText(.body).foregroundStyle(DuoColor.text2)
                PlacePopup(places: form.places, selected: form.into, folderMark: false) { form.into = $0 }
            }
            SheetButtons(confirm: "Move", topGap: 6, cancel: model.cancelSheet, ok: model.confirmMoveIntoHome)
        }
        .foregroundStyle(DuoColor.text)
        .padding(DuoMetric.sheetPadding)
        .frame(width: DuoMetric.sheetMoveWidth - 2 * DuoMetric.borderHairline, alignment: .leading)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: DuoMetric.radiusPopover, bottomTrailingRadius: DuoMetric.radiusPopover).fill(DuoColor.ground))
        .padding([.horizontal, .bottom], DuoMetric.borderHairline)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: DuoMetric.radiusPopover, bottomTrailingRadius: DuoMetric.radiusPopover).fill(DuoColor.rule))
        .compositingGroup()
        .duoPopoverShadow()
        .onExitCommand { model.cancelSheet() }
        .accessibilityLabel("Move \(form.project) into Home")
    }
}

/// New project (S2-6): 520 wide on `ground`, a labelled column of fields.
struct NewProjectSheet: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: NewProjectForm

    var body: some View {
        VStack(alignment: .leading, spacing: DuoMetric.sheetRowGap) {
            Text("New project").duoText(.bodyEmphasis)
            SheetRow("Name") {
                SheetField(text: form.name, focus: true, submit: { model.commitNewProject() }, cancel: model.cancelSheet) { form.name = $0 }
            }
            SheetRow("Goal") {
                VStack(alignment: .leading, spacing: 2) {
                    SheetField(text: form.goal, focus: false, submit: { model.commitNewProject() }, cancel: model.cancelSheet) { form.goal = $0 }
                    Text("One line. It shows on the project’s tile.").duoText(.control, lineHeight: DuoTextStyle.body.spec.lineHeight).foregroundStyle(DuoColor.text2)
                }
            }
            SheetRow("In", center: true) {
                PlacePopup(places: form.places, selected: form.into, folderMark: true) { form.into = $0 }
            }
            SheetRow("") {
                Text(AppModel.short(form.path)).duoText(.mono, lineHeight: DuoTextStyle.body.spec.lineHeight).foregroundStyle(DuoColor.text2)
                    .lineLimit(1).truncationMode(.middle)
            }
            SheetRow("", center: true) {
                Toggle("Start a Claude session in it", isOn: $form.startSession)
                    .toggleStyle(.checkbox).duoText(.body)
            }
            SheetButtons(confirm: "Create Project", topGap: 4, cancel: model.cancelSheet) { model.commitNewProject() }
        }
        .foregroundStyle(DuoColor.text)
        .padding(DuoMetric.sheetPadding)
        .frame(width: DuoMetric.sheetNewProjectWidth - 2 * DuoMetric.borderHairline, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusPopover - DuoMetric.borderHairline).fill(DuoColor.ground))
        .padding(DuoMetric.borderHairline)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusPopover).fill(DuoColor.rule))
        .compositingGroup()
        .duoPopoverShadow()
        .onExitCommand { model.cancelSheet() }
        .accessibilityLabel(form.moving.isEmpty ? "New project" : "Move to a new project")
    }
}

/// A label in a 96 pt right-aligned column, then the control (S2-6).
struct SheetRow<Content: View>: View {
    let label: String
    var center = false
    let content: Content

    init(_ label: String, center: Bool = false, @ViewBuilder content: () -> Content) {
        self.label = label; self.center = center; self.content = content()
    }

    var body: some View {
        HStack(alignment: center ? .center : .top, spacing: DuoSpace.gapCardToCard) {
            Text(label).duoText(.body).foregroundStyle(DuoColor.text2)
                .padding(.top, center ? 0 : 2)
                .frame(width: DuoMetric.sheetLabelColumn, alignment: .trailing)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Cancel, then the default button: `pane` fill, `text` border, semibold (S2-4, S2-6).
struct SheetButtons: View {
    let confirm: String
    let topGap: CGFloat
    let cancel: () -> Void
    let ok: () -> Void

    var body: some View {
        HStack(spacing: DuoSpace.gapButtonToButton) {
            Spacer(minLength: 0)
            Button("Cancel", action: cancel).buttonStyle(.duo).keyboardShortcut(.cancelAction)
            Button(action: ok) { Text(confirm).fontWeight(.semibold) }
                .buttonStyle(DefaultSheetButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(.top, topGap)
    }
}

/// The sheet's default button: the Duo button with a `text` border and a semibold label.
struct DefaultSheetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { DefaultSheetButtonBody(configuration: configuration) }
}

/// Disabled: the label and border at half strength, as DuoButtonStyle (DL-132 j).
private struct DefaultSheetButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        configuration.label
            .duoText(.control, weight: .semibold)
            .foregroundStyle(enabled ? DuoColor.text : DuoColor.text2.opacity(0.5))
            .lineLimit(1)
            .padding(.horizontal, DuoSpace.buttonPadding.leading + DuoMetric.borderHairline)
            .padding(.vertical, DuoSpace.buttonPadding.top + DuoMetric.borderHairline)
            .background(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).fill(configuration.isPressed ? DuoColor.selected : DuoColor.pane))
            .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).strokeBorder(enabled ? DuoColor.text : DuoColor.controlEdge.opacity(0.5), lineWidth: DuoMetric.borderHairline))
            .contentShape(Rectangle())
    }
}

/// Home's top level or a topic folder, as a popup: 24 high, `rule` border, `pane` fill, a down
/// chevron; New project's carries a folder mark (S2-4, S2-6).
struct PlacePopup: View {
    let places: [HomePlace]
    let selected: HomePlace
    let folderMark: Bool
    let choose: (HomePlace) -> Void

    var body: some View {
        Menu {
            ForEach(places, id: \.self) { p in
                Button(p.label) { choose(p) }   // not an action: picks a field's value
            }
        } label: {
            HStack(spacing: DuoSpace.gapGlyphToLabel) {
                if folderMark { FolderMark() }
                Text(selected.label).duoText(.body)
                Chevron(direction: .down)
            }
            .padding(.horizontal, DuoMetric.sheetFieldPaddingX)
            .frame(height: DuoMetric.sheetFieldHeight)
            .background(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).fill(DuoColor.pane))
            .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// A one-line field: 24 high, `rule` border, `pane` fill, 13 pt. Return submits, Escape cancels.
struct SheetField: NSViewRepresentable {
    let text: String
    let focus: Bool
    let submit: () -> Void
    let cancel: () -> Void
    let changed: (String) -> Void

    func makeNSView(context: Context) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = DuoMetric.radiusControl
        box.layer?.borderWidth = DuoMetric.borderHairline
        box.layer?.borderColor = DuoNSColor.rule.cgColor
        box.layer?.backgroundColor = DuoNSColor.pane.cgColor
        let f = FocusingField(string: text)
        f.font = .systemFont(ofSize: DuoTextStyle.body.spec.size)
        f.textColor = DuoNSColor.text
        f.isBezeled = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.cell?.isScrollable = true
        f.cell?.wraps = false
        f.delegate = context.coordinator
        f.wantsFocus = focus
        f.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(f)
        NSLayoutConstraint.activate([
            f.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: DuoMetric.sheetFieldPaddingX),
            f.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -DuoMetric.sheetFieldPaddingX),
            f.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            box.heightAnchor.constraint(equalToConstant: DuoMetric.sheetFieldHeight),
        ])
        return box
    }

    func updateNSView(_ box: NSView, context: Context) {
        context.coordinator.field = self
        if let f = box.subviews.first as? NSTextField, f.currentEditor() == nil, f.stringValue != text { f.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(field: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var field: SheetField
        init(field: SheetField) { self.field = field }

        func controlTextDidChange(_ obj: Notification) {
            if let f = obj.object as? NSTextField { field.changed(f.stringValue) }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) { field.cancel(); return true }
            if selector == #selector(NSResponder.insertNewline(_:)) { field.changed(control.stringValue); field.submit(); return true }
            return false
        }
    }

    /// Takes focus once it's in a window (from makeNSView it could run before SwiftUI attached it).
    final class FocusingField: NSTextField {
        var wantsFocus = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, wantsFocus else { return }
            wantsFocus = false
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
                self.currentEditor()?.selectedRange = NSRange(location: (self.stringValue as NSString).length, length: 0)
            }
        }
    }
}

/// The folder mark before a place's name (12 × 10, `text2`, stroke 1.1), as the New project
/// sheet draws it.
struct FolderMark: View {
    var body: some View {
        FolderMarkShape()
            .stroke(DuoColor.text2, lineWidth: 1.1)
            .frame(width: 12, height: 10)
            .accessibilityHidden(true)
    }
}

/// `M1 2.2c0-.7.5-1.2 1.2-1.2h2.6l1 1.2h4c.7 0 1.2.5 1.2 1.2v4.4c0 .7-.5 1.2-1.2 1.2H2.2C1.5 9 1 8.5 1 7.8z`
struct FolderMarkShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 1, y: 2.2))
        p.addQuadCurve(to: CGPoint(x: 2.2, y: 1), control: CGPoint(x: 1, y: 1))
        p.addLine(to: CGPoint(x: 4.8, y: 1))
        p.addLine(to: CGPoint(x: 5.8, y: 2.2))
        p.addLine(to: CGPoint(x: 9.8, y: 2.2))
        p.addQuadCurve(to: CGPoint(x: 11, y: 3.4), control: CGPoint(x: 11, y: 2.2))
        p.addLine(to: CGPoint(x: 11, y: 7.8))
        p.addQuadCurve(to: CGPoint(x: 9.8, y: 9), control: CGPoint(x: 11, y: 9))
        p.addLine(to: CGPoint(x: 2.2, y: 9))
        p.addQuadCurve(to: CGPoint(x: 1, y: 7.8), control: CGPoint(x: 1, y: 9))
        p.closeSubpath()
        return p
    }
}
