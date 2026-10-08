import AppKit
import SwiftUI

/// A Word document in the right pane (DL-162; target docx-viewer-handoff `viewer`, `markup`,
/// `fallback`): the bar under the tabs (Markup ⌄, Convert to Markdown…, Open With ⌄), the document
/// on `ground` at the pane's width, the Markup menu Duo draws; or Quick Look with why under the
/// deck's notice when the document can't be drawn.
struct DocxView: View {
    @Environment(AppModel.self) private var model
    let viewer: DocxViewer
    let path: String
    let file: URL

    var body: some View {
        let _ = model.pickerRevision
        let mine = viewer.url?.standardizedFileURL == file.standardizedFileURL
        VStack(spacing: 0) {
            if mine, case .failed(let why) = viewer.state {
                NoticeBar(text: "Duo can’t draw \(file.lastPathComponent): \(why).",
                          sub: "Quick Look shows what it can, read only." + (viewer.failureExtra.map { " " + $0 } ?? ""), emphasis: true) {
                    OpenWithMenu(path: path, file: file, bordered: true)
                    Button("Show in Finder") { FileActions.reveal(file) }.buttonStyle(.duo)
                }
                QuickLookPane(file: file)
            } else {
                WordDocumentBar(path: path, file: file)   // a conversion's progress, or why it failed
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        DocxBar(viewer: viewer, path: path, file: file)
                        DocxWebHost(viewer: viewer)
                        DocxPickerBar(viewer: viewer)
                    }
                    if model.docxMenuOpen {
                        // A click anywhere else closes the menu, as a menu does.
                        Color.clear.contentShape(Rectangle()).onActivate { model.docxMenuOpen = false }   // not an action: closes the menu
                        MarkupMenu(viewer: viewer, file: file)
                            .padding(.leading, DuoMetric.noticePaddingX)
                            .padding(.top, DuoMetric.docxMenuTop)
                            .transition(.identity)
                    }
                }
            }
        }
        .onAppear { viewer.open(file); viewer.wake() }
        .onDisappear { viewer.sleep(); model.docxMenuOpen = false }
        .onChange(of: file) { _, f in viewer.open(f) }
    }
}

/// The bar: Markup ⌄ at the left (pressed while its menu is open); Convert to Markdown… and Open
/// With ⌄ at the right. 44 high with a `rule` below, as the deck's. 
struct DocxBar: View {
    @Environment(AppModel.self) private var model
    let viewer: DocxViewer
    let path: String
    let file: URL

    var body: some View {
        let _ = model.pickerRevision
        HStack(spacing: DuoSpace.gapButtonToButton) {
            Button { model.docxMenuOpen.toggle() } label: {   // action: doc markup
                HStack(spacing: 1) { Text("Markup"); Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)) }
            }
            .buttonStyle(DuoButtonStyle(on: model.docxMenuOpen)).fixedSize().disabled(viewer.state != .ready)
            Spacer(minLength: 0)
            Button("Select Text") { viewer.picking ? viewer.stopPicking() : viewer.startPicking() }   // action: doc pick
                .buttonStyle(DuoButtonStyle(on: viewer.picking)).fixedSize().disabled(viewer.state != .ready)
            Button("Convert to Markdown…") { model.askConvertToMarkdown(path) }.buttonStyle(.duo).fixedSize()
            OpenWithMenu(path: path, file: file, bordered: true)
        }
        // The board's four buttons run to 10 from the pane's right edge, not 20; Duo's are a little wider, so 6 here: that is what fits them at 460.
        .padding(.leading, DuoMetric.noticePaddingX).padding(.trailing, DuoMetric.docxBarTrailing)
        .frame(height: DuoMetric.deckBarHeight)
        .overlay(alignment: .bottom) { DuoColor.rule.frame(height: DuoMetric.borderHairline) }
    }
}

/// W4: All Markup, Simple Markup, No Markup, Original (one checked); Show Comments, Show Resolved
/// Comments; PEOPLE with a dot and a count each, a click showing only that person's marks.
struct MarkupMenu: View {
    @Environment(AppModel.self) private var model
    let viewer: DocxViewer
    let file: URL

    private static let modes: [(id: String, title: String)] = [("all", "All Markup"), ("simple", "Simple Markup"), ("none", "No Markup"), ("original", "Original")]

    var body: some View {
        let m = viewer.markup
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Self.modes, id: \.id) { mode in
                row(mode.title, checked: m.mode == mode.id, selected: m.mode == mode.id)
                    .onActivate { model.setMarkup(mode: mode.id) }   // action: doc markup
            }
            divider
            row("Show Comments", checked: m.comments).onActivate { model.setMarkup(comments: !m.comments) }   // action: doc markup
            row("Show Resolved Comments", checked: m.resolved).onActivate { model.setMarkup(resolved: !m.resolved) }   // action: doc markup
            if !viewer.people.isEmpty {
                divider
                Text("PEOPLE").duoText(.sectionLabel).foregroundStyle(DuoColor.text2)
                    .padding(.horizontal, DuoMetric.docxMenuRowPaddingX).padding(.vertical, 2)
                ForEach(viewer.people, id: \.name) { p in
                    HStack(spacing: 0) {
                        Circle().fill(Self.colour(p.colour)).frame(width: 9, height: 9).frame(width: 16, alignment: .leading)
                        Text(p.name).duoText(.body).lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(p.count)").duoText(.body).foregroundStyle(DuoColor.text2)
                    }
                    .padding(.horizontal, DuoMetric.docxMenuRowPaddingX).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: DuoMetric.radiusSelection).fill(m.person == p.name ? DuoColor.selected : .clear))
                    .contentShape(Rectangle())
                    .onActivate { model.setMarkup(person: m.person == p.name ? .some(nil) : .some(p.name)) }   // action: doc markup
                    .accessibilityLabel("\(p.name), \(p.count)")
                    .accessibilityAddTraits(m.person == p.name ? .isSelected : [])
                }
            }
        }
        .padding(5)
        .frame(width: DuoMetric.docxMenuWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusPopover).fill(DuoColor.pane))
        // The board's shadow: a soft drop and a hairline edge, both the text colour.
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusPopover).strokeBorder(DuoColor.text.opacity(0.08), lineWidth: DuoMetric.borderHairline))
        .shadow(color: DuoColor.text.opacity(0.18), radius: 12, x: 0, y: 8)
    }

    /// A person's mark colour: `reviewAuthor1…5`.
    static func colour(_ n: Int) -> Color {
        switch n {
        case 1: DuoColor.reviewAuthor1
        case 2: DuoColor.reviewAuthor2
        case 3: DuoColor.reviewAuthor3
        case 4: DuoColor.reviewAuthor4
        default: DuoColor.reviewAuthor5
        }
    }

    private var divider: some View {
        DuoColor.rule.frame(height: DuoMetric.borderHairline).padding(.horizontal, DuoMetric.docxMenuRowPaddingX).padding(.vertical, 5)
    }

    private func row(_ title: String, checked: Bool, selected: Bool = false) -> some View {
        HStack(spacing: 0) {
            Text(checked ? "✓" : "").duoText(.body).frame(width: 16, alignment: .leading)
            Text(title).duoText(.body).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DuoMetric.docxMenuRowPaddingX).padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusSelection).fill(selected ? DuoColor.selected : .clear))
        .contentShape(Rectangle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

/// The document's web view in the pane. Its frame is the pane's: never the document's height.
struct DocxWebHost: NSViewRepresentable {
    let viewer: DocxViewer

    func makeNSView(context: Context) -> DocumentEditorView.EditorHost { DocumentEditorView.EditorHost() }
    func updateNSView(_ host: DocumentEditorView.EditorHost, context: Context) { host.show(viewer.webView) }
}

/// W5: the picker at the bottom of the pane (on `ground`, a `rule` above, padding 10 20 12): what is
/// picked, its changes and comments in `text2`, then the deck's buttons (Send to Claude, Send To ⌄,
/// Pick Another, Cancel).
struct DocxPickerBar: View {
    @Environment(AppModel.self) private var model
    let viewer: DocxViewer

    var body: some View {
        let _ = model.pickerRevision
        if viewer.picking {
            VStack(alignment: .leading, spacing: 8) {
                if let e = viewer.picked {
                    let p = viewer.pickedParagraph
                    let isComment = viewer.pickedKind == "comment"
                    let c = isComment ? p?.comments.first { $0.id == e.attributes["comment"] } : nil
                    let quote = SendFormat.line(isComment ? (c?.text ?? e.text) : (p?.text ?? e.text))
                    let shown = quote.count > 80 ? String(quote.prefix(80)) + "…" : quote
                    let under = p?.heading.map { " under “\(SendFormat.line($0))”" } ?? ""
                    ((isComment ? Text("A comment").fontWeight(.semibold) : Text("A paragraph").fontWeight(.semibold))
                        + Text(isComment ? " by \(c?.author ?? "") on a paragraph\(under)" + (shown.isEmpty ? "" : " · “\(shown)”") : under + (shown.isEmpty ? "" : " · “\(shown)”")))
                        .duoText(.body).lineLimit(2)
                    if let p {
                        Text(isComment ? "In the paragraph “\(String(SendFormat.line(p.text).prefix(60)))”. Its changes and comments go with it." : SendFormat.paragraphSummary(p))
                            .duoText(.control).foregroundStyle(DuoColor.text2).lineLimit(3)
                    }
                    if case .failure(let why) = model.sendTarget {
                        Text("\(why.reason): use Send To.").duoText(.control).foregroundStyle(DuoColor.text2)
                    }
                    PickerButtonRow(viewer: viewer)
                } else {
                    HStack(spacing: DuoSpace.gapButtonToButton) {
                        Text("Click a paragraph or a comment to select it. Esc to stop.").duoText(.body).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("Cancel") { viewer.stopPicking() }.buttonStyle(.duo).keyboardShortcut(.cancelAction)
                    }
                }
            }
            .padding(EdgeInsets(top: 10, leading: DuoMetric.noticePaddingX, bottom: 12, trailing: DuoMetric.noticePaddingX))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DuoColor.ground)
            .overlay(alignment: .top) { DuoColor.rule.frame(height: DuoMetric.borderHairline) }
        }
    }
}
