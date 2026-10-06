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
                ZStack(alignment: .bottom) {
                    DeckWebHost(viewer: viewer)
                    DeckPickerBar(viewer: viewer)
                }
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
            Text(viewer.count > 0 ? "Slide \(viewer.slide) of \(viewer.count)" : "Drawing…")
                .duoText(.body).foregroundStyle(viewer.count > 0 ? DuoColor.text : DuoColor.text2).padding(.leading, 4)
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
                    HStack(spacing: DuoSpace.gapButtonToButton) {
                        switch model.sendTarget {
                        case .success(let t):
                            Button("Send to Claude") { model.sendPickedElement(to: t.key) }
                                .buttonStyle(DefaultSheetButtonStyle()).keyboardShortcut(.defaultAction)
                        case .failure(let why):
                            Button("Send to Claude") {}.buttonStyle(DefaultSheetButtonStyle()).disabled(true).help(why.reason)
                        }
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
                        .menuStyle(.button).buttonStyle(.duo).fixedSize()
                        Button("Pick Another") { viewer.pickAgain() }.buttonStyle(.duo)
                        Spacer(minLength: 0)
                        Button("Cancel") { viewer.stopPicking() }.buttonStyle(.duo).keyboardShortcut(.cancelAction)
                    }
                    if case .failure(let why) = model.sendTarget {
                        Text("\(why.reason): use Send To.").duoText(.control).foregroundStyle(DuoColor.text2)
                    }
                } else {
                    HStack(spacing: DuoSpace.gapButtonToButton) {
                        Text("Click a shape on a slide to select it. Esc to stop.").duoText(.body)
                        Spacer(minLength: 8)
                        Button("Cancel") { viewer.stopPicking() }.buttonStyle(.duo).keyboardShortcut(.cancelAction)
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
}

/// The deck's web view in the pane.
struct DeckWebHost: NSViewRepresentable {
    let viewer: DeckViewer

    func makeNSView(context: Context) -> DocumentEditorView.EditorHost { DocumentEditorView.EditorHost() }
    func updateNSView(_ host: DocumentEditorView.EditorHost, context: Context) { host.show(viewer.webView) }
}
