import AppKit
import DuoControl
import DuoSearch
import SwiftUI

/// A PDF in the right pane (DL-332): PDFKit's pages under a bar, or Quick Look with why when PDFKit can't open the file.
/// The bar is a stand-in modelled on the deck viewer's (Q-495): ‹ › Page n of N, find, zoom, Add Comment, Comments, Open With.
/// Every control names a `duo2` verb (`pdf page`, `pdf zoom`, `pdf find`, `comment add`, `pdf comments-panel`).
/// The comments are drawn beside the pages as Markdown review's margin (Q-496, built to the markdown-review-handoff screens).
struct PdfView: View {
    @Environment(AppModel.self) private var model
    let viewer: PdfViewer
    let path: String
    let file: URL

    var body: some View {
        VStack(spacing: 0) {
            if case .failed(let why) = viewer.state, viewer.url?.standardizedFileURL == file.standardizedFileURL {
                NoticeBar(text: "Duo can’t draw \(file.lastPathComponent): \(why).",
                          sub: "Quick Look shows what it can, read only. Claude can read the text with doc read when there is any.") {
                    OpenWithMenu(path: path, file: file, bordered: true)
                    Button("Show in Finder") { FileActions.reveal(file) }.buttonStyle(.duo)
                }
                QuickLookPane(file: file)
            } else {
                PdfBar(viewer: viewer, path: path, file: file)
                GeometryReader { geo in
                    // The margin's page says how wide it wants to be and how much the pages give up: a narrow pane's
                    // popover floats over them (the page's own layout, margin.js's).
                    HStack(spacing: 0) {
                        PdfWebHost(viewer: viewer)
                        if viewer.margin.reserve > 0 { DuoColor.ground.frame(width: viewer.margin.reserve) }
                    }
                    .overlay(alignment: .trailing) {
                        if viewer.margin.width > 0 { PdfMarginHost(margin: viewer.margin).frame(width: viewer.margin.width) }
                    }
                    .onChange(of: geo.size.width, initial: true) { _, w in viewer.paneWidth = w }
                }
            }
        }
        .onAppear { viewer.open(file); viewer.wake() }
        .onDisappear { viewer.sleep() }
        .onChange(of: file) { _, f in viewer.open(f) }
    }
}

/// ‹ › Page n of N, then find, zoom, Add Comment, Comments and Open With; 44 high with a `rule` below (the deck bar's height).
struct PdfBar: View {
    @Environment(AppModel.self) private var model
    let viewer: PdfViewer
    let path: String
    let file: URL

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(long: true, find: true, zoom: true)
            bar(long: false, find: true, zoom: true)
            bar(long: false, find: false, zoom: true)
            bar(long: false, find: false, zoom: false)
            bar(long: false, find: false, zoom: false, open: false)
        }
        .padding(.horizontal, DuoMetric.noticePaddingX)
        .frame(height: DuoMetric.deckBarHeight)
        .overlay(alignment: .bottom) { DuoColor.rule.frame(height: DuoMetric.borderHairline) }
    }

    private func bar(long: Bool, find: Bool, zoom: Bool, open: Bool = true) -> some View {
        let ready = viewer.state == .ready
        return HStack(spacing: DuoSpace.gapButtonToButton) {
            Button { viewer.go(viewer.page - 1) } label: { Text("‹") }   // action: pdf page
                .buttonStyle(.duo).disabled(!ready || viewer.page <= 1).help("Previous Page").accessibilityLabel("Previous Page")
            Button { viewer.go(viewer.page + 1) } label: { Text("›") }   // action: pdf page
                .buttonStyle(.duo).disabled(!ready || viewer.page >= viewer.count).help("Next Page").accessibilityLabel("Next Page")
            let words = viewer.count > 0 ? (long ? "Page \(viewer.page) of \(viewer.count)" : "\(viewer.page)/\(viewer.count)") : "…"
            Text(words).duoText(.body).foregroundStyle(viewer.count > 0 ? DuoColor.text : DuoColor.text2).lineLimit(1).fixedSize().padding(.leading, 2)
            Spacer(minLength: 8)
            if find { PdfFindField(viewer: viewer) }
            if zoom {
                Button { viewer.zoomOut() } label: { Text("−") }   // action: pdf zoom
                    .buttonStyle(.duo).disabled(!ready).help("Zoom Out").accessibilityLabel("Zoom Out")
                if long {
                    Text("\(Int((viewer.scale * 100).rounded()))%").duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1).fixedSize()
                        .frame(minWidth: 40)
                }
                Button { viewer.zoomIn() } label: { Text("+") }   // action: pdf zoom
                    .buttonStyle(.duo).disabled(!ready).help("Zoom In").accessibilityLabel("Zoom In")
                if long {
                    Button { viewer.fit() } label: { Text("Fit") }   // action: pdf zoom
                        .buttonStyle(DuoButtonStyle(on: viewer.fitting)).disabled(!ready).help("Fit").accessibilityLabel("Fit")
                }
            }
            Button("Add Comment") { model.composePdfComment(viewer) }   // action: comment add
                .buttonStyle(.duo).disabled(!ready || viewer.selectionText.isEmpty).fixedSize()
                .help(viewer.selectionText.isEmpty ? "Select text to comment on" : "Add a comment on the selection")
            Button("Comments") { viewer.commentsShown.toggle() }   // action: pdf comments-panel
                .buttonStyle(DuoButtonStyle(on: viewer.commentsShown)).disabled(!ready).fixedSize()
                .accessibilityIdentifier("pdf.comments")
            if open, long || !find { OpenWithMenu(path: path, file: file, bordered: true) }
        }
    }
}

/// The find field: Return goes to the next match, ⇧Return the previous, and "n of m" says where it is.
struct PdfFindField: View {
    let viewer: PdfViewer

    var body: some View {
        HStack(spacing: 6) {
            TextField("Find in PDF", text: Binding(get: { viewer.findText }, set: { viewer.findText = $0 }))
                .textFieldStyle(.plain).duoText(.control).foregroundStyle(DuoColor.text)
                .onSubmit {   // action: pdf find
                    let back = NSEvent.modifierFlags.contains(.shift)
                    if viewer.findText.isEmpty { viewer.clearFind() } else { viewer.find(viewer.findText, backwards: back) }
                }
            if viewer.matchCount > 0 {
                Text("\(viewer.matchIndex + 1) of \(viewer.matchCount)").duoText(.control).foregroundStyle(DuoColor.text2).lineLimit(1).fixedSize()
            } else if !viewer.findText.isEmpty, viewer.selectionText.isEmpty {
                EmptyView()
            }
        }
        .padding(.horizontal, 8)
        .frame(width: 170, height: 24)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusField).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusField).strokeBorder(DuoColor.rule, lineWidth: 1))
    }
}

/// The comment margin's page, beside the PDF.
struct PdfMarginHost: NSViewRepresentable {
    let margin: PdfMargin

    func makeNSView(context: Context) -> DocumentEditorView.EditorHost { DocumentEditorView.EditorHost() }
    func updateNSView(_ host: DocumentEditorView.EditorHost, context: Context) { host.show(margin.webView) }
}

/// The PDF's view in the pane.
struct PdfWebHost: NSViewRepresentable {
    let viewer: PdfViewer

    func makeNSView(context: Context) -> DocumentEditorView.EditorHost { DocumentEditorView.EditorHost() }
    func updateNSView(_ host: DocumentEditorView.EditorHost, context: Context) { host.show(viewer.pdfView) }
}
