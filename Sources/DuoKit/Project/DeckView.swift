import AppKit
import SwiftUI

/// A PowerPoint deck in the right pane (DL-125; target pptx-handoff): the bar under the tabs (A),
/// the slides, the picker bar at the bottom (B, C), or Quick Look with why when the deck can't be
/// drawn (E).
struct DeckView: View {
    @Environment(AppModel.self) private var model
    let viewer: DeckViewer
    let path: String
    let file: URL

    var body: some View {
        let _ = model.pickerRevision
        VStack(spacing: 0) {
            if case .failed(let why) = viewer.state, viewer.url?.standardizedFileURL == file.standardizedFileURL {
                NoticeBar(text: "Duo can’t draw \(file.lastPathComponent): \(why).",
                          sub: "Quick Look shows what it can, read only. Claude can’t read its slides either.") {
                    OpenWithMenu(path: path, file: file, bordered: true)
                    Button("Show in Finder") { FileActions.reveal(file) }.buttonStyle(.duo)
                }
                QuickLookPane(file: file)
            } else {
                DeckBar(viewer: viewer, path: path, file: file)
                // The slides end where the picker bar starts: nothing draws under it (board C).
                DeckWebHost(viewer: viewer)
                    .overlay { if viewer.state == .loading, viewer.listed > 0 { DeckDrawingFrames(count: viewer.listed) } }
                DeckPickerBar(viewer: viewer)
            }
        }
        .onAppear { viewer.open(file) }
        .onChange(of: file) { _, f in viewer.open(f) }
    }
}

/// A: ‹ › Slide n of N, then Select Shape and Open With; 44 high with a `rule` below.
struct DeckBar: View {
    @Environment(AppModel.self) private var model
    let viewer: DeckViewer
    let path: String
    let file: URL

    var body: some View {
        let _ = model.pickerRevision   // the viewer isn't observable: its changes bump this
        HStack(spacing: DuoSpace.gapButtonToButton) {
            Button { viewer.go(viewer.slide - 1) } label: { Text("‹") }   // action: slide go
                .buttonStyle(.duo).disabled(viewer.slide <= 1).help("Previous Slide").accessibilityLabel("Previous Slide")
            Button { viewer.go(viewer.slide + 1) } label: { Text("›") }   // action: slide go
                .buttonStyle(.duo).disabled(viewer.slide >= viewer.count).help("Next Slide").accessibilityLabel("Next Slide")
            // A pane narrower than the board's 460 shortens the count to "2/5" (DL-132 j, q68-narrow);
            // while drawing, ‹ › and Select Shape are dimmed (q68-drawing).
            ViewThatFits(in: .horizontal) {
                count(viewer.count > 0 ? "Slide \(viewer.slide) of \(viewer.count)" : "Drawing slides…")
                count(viewer.count > 0 ? "\(viewer.slide)/\(viewer.count)" : "…")
            }
            Spacer(minLength: 8)
            Button("Select Shape") { viewer.picking ? viewer.stopPicking() : viewer.startPicking() }
                .buttonStyle(DuoButtonStyle(on: viewer.picking)).disabled(viewer.state != .ready)
            OpenWithMenu(path: path, file: file, bordered: true)
        }
        .padding(.horizontal, DuoMetric.noticePaddingX)
        .frame(height: DuoMetric.deckBarHeight)
        .overlay(alignment: .bottom) { DuoColor.rule.frame(height: DuoMetric.borderHairline) }
    }
}

extension DeckBar {
    func count(_ s: String) -> some View {
        Text(s).duoText(.body).foregroundStyle(viewer.count > 0 ? DuoColor.text : DuoColor.text2).lineLimit(1).fixedSize().padding(.leading, 4)
    }
}

/// B and C: the picker at the bottom of the pane, on `ground` with a `rule` above.
struct DeckPickerBar: View {
    @Environment(AppModel.self) private var model
    let viewer: DeckViewer

    var body: some View {
        let _ = model.pickerRevision
        if viewer.picking {
            VStack(alignment: .leading, spacing: DuoSpace.gapGlyphToLabel) {
                if let s = viewer.pickedShape {
                    (Text(s.name).fontWeight(.semibold) + Text(" on slide \(s.slide)" + (s.text.isEmpty ? "" : " · “\(SendFormat.line(s.text).prefix(80))”")))
                        .duoText(.body).lineLimit(2)
                    if !s.groups.isEmpty {
                        Text("In " + s.groups.joined(separator: " › ")).duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1)
                    }
                    // Only when no session can take it (DL-132 j, q68-no-session): why, and use Send To.
                    if case .failure(let why) = model.sendTarget {
                        Text("\(why.reason): use Send To.").duoText(.body).foregroundStyle(DuoColor.text2)
                    }
                    // One row as drawn; two in a pane too narrow for it (DL-132 j, q68-narrow).
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: DuoSpace.gapButtonToButton) { send; another; Spacer(minLength: 0); cancel }
                        VStack(alignment: .leading, spacing: DuoSpace.gapButtonToButton) {
                            HStack(spacing: DuoSpace.gapButtonToButton) { send }
                            HStack(spacing: DuoSpace.gapButtonToButton) { another; Spacer(minLength: 0); cancel }
                        }
                    }
                } else {
                    HStack(spacing: DuoSpace.gapButtonToButton) {
                        Text("Click a shape on a slide to select it. Esc to stop.").duoText(.body).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        cancel
                    }
                }
            }
            .padding(.vertical, DuoMetric.noticePaddingY)
            .padding(.horizontal, DuoMetric.noticePaddingX)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DuoColor.ground)
            .overlay(alignment: .top) { DuoColor.rule.frame(height: DuoMetric.borderHairline) }
        }
    }

    /// Send to Claude (default) and Send To ⌄.
    @ViewBuilder private var send: some View {
        switch model.sendTarget {
        case .success(let t):
            Button("Send to Claude") { model.sendPickedElement(to: t.key) }
                .buttonStyle(DefaultSheetButtonStyle()).keyboardShortcut(.defaultAction)
        case .failure(let why):
            Button("Send to Claude") {}.buttonStyle(DefaultSheetButtonStyle()).disabled(true).help(why.reason)
        }
        let sendToDefault = (try? model.sendTarget.get()) == nil   // with no session, Send To is the way (q68-no-session)
        Menu {
            let visible = (try? model.sendTarget.get())?.key
            ForEach(model.sendTargets.filter { $0.key != visible }) { t in
                Button(t.project.isEmpty ? t.title : "\(t.title) — \(t.project)") { model.sendPickedElement(to: t.key) }
            }
            Divider()
            Button("New Session") { model.sendPickedElement(to: nil) }
        } label: {
            HStack(spacing: 4) { Text("Send To"); Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)) }
        }
        .menuStyle(.button).fixedSize()
        .modifier(SendToStyle(isDefault: sendToDefault))
    }

    private var another: some View { Button("Pick Another") { viewer.pickAgain() }.buttonStyle(.duo) }
    private var cancel: some View { Button("Cancel") { viewer.stopPicking() }.buttonStyle(.duo).keyboardShortcut(.cancelAction) }
}

/// Send To ⌄ takes the default look when Send to Claude can't send (q68-no-session).
struct SendToStyle: ViewModifier {
    let isDefault: Bool
    func body(content: Content) -> some View {
        if isDefault { content.buttonStyle(DefaultSheetButtonStyle()) } else { content.buttonStyle(.duo) }
    }
}

/// While a deck draws (DL-132 j, q68-drawing): an empty numbered frame per slide on `ground`, at
/// the slides' place and size, so nothing jumps when they arrive.
struct DeckDrawingFrames: View {
    let count: Int
    var body: some View {
        GeometryReader { g in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(1...max(1, count), id: \.self) { n in
                        Text("\(n)").duoText(.pill).foregroundStyle(DuoColor.text2).padding(.top, n == 1 ? 0 : 10).padding(.bottom, 6)
                        Rectangle().fill(DuoColor.pane)
                            .overlay(Rectangle().strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
                            .frame(width: g.size.width - 2 * DuoMetric.noticePaddingX, height: (g.size.width - 2 * DuoMetric.noticePaddingX) * 9 / 16)
                    }
                }
                .padding(.horizontal, DuoMetric.noticePaddingX)
                .padding(.top, 16)
            }
            .scrollDisabled(true)
        }
        .background(DuoColor.ground)
        .accessibilityLabel("Drawing \(count) slides")
    }
}

/// The deck's web view in the pane.
struct DeckWebHost: NSViewRepresentable {
    let viewer: DeckViewer

    func makeNSView(context: Context) -> DocumentEditorView.EditorHost { DocumentEditorView.EditorHost() }
    func updateNSView(_ host: DocumentEditorView.EditorHost, context: Context) { host.show(viewer.webView) }
}
