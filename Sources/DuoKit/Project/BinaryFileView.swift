import AppKit
import DuoSearch
import Quartz
import SwiftUI

/// A file that isn't text (C-26, F-102), as `standins2-handoff/q52-preview` and `q52-none` draw it
/// (DL-132 e): a quiet strip under the tabs (the kind in plain words, "read only", Open With,
/// Show in Finder) over Quick Look's own preview, or, when Quick Look can't show it, the name,
/// a line and the two buttons, centred. Word documents keep their own bars (DL-123). Duo never
/// puts the bytes in its editor.
struct BinaryFileView: View {
    @Environment(AppModel.self) private var model
    let path: String
    let file: URL

    var body: some View {
        let word = AppModel.isWordDocument(file) || AppModel.isOldWordDocument(file)
        VStack(spacing: 0) {
            if AppModel.isWordDocument(file) {
                WordDocumentBar(path: path, file: file)
            } else if AppModel.isOldWordDocument(file) {
                // F2: the older format can't be converted; say how to get a .docx.
                NoticeBar(text: "Read only: Duo can’t edit a Word 97–2004 document, or convert one.",
                          sub: "Save it as .docx in Word or Pages, and Duo can make a Markdown copy.") {
                    OpenWithMenu(path: path, file: file)
                    Button("Show in Finder") { FileActions.reveal(file) }.buttonStyle(.duo)
                }
            }
            // Quick Look can't open a locked or damaged .docx either: say so, as F draws it.
            if FileKind.quickLookPreviews(file), ![.passwordProtected, .damaged].contains(model.conversionFailures[path]) {
                if !word { ReadOnlyStrip(path: path, file: file) }
                QuickLookPane(file: file)
            } else if word {
                VStack(alignment: .leading, spacing: DuoSpace.gapGlyphToLabel) {
                    Text("No preview").duoText(.bodyEmphasis)
                    Text("\(file.lastPathComponent) isn’t text, and Quick Look can’t show it. Open it in another app, or show it in Finder.")
                        .duoText(.body).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true)
                }
                .padding(DuoSpace.documentPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(spacing: DuoSpace.gapGlyphToLabel) {
                    Text(file.lastPathComponent).duoText(.title).lineLimit(1).truncationMode(.middle)
                    Text("\(FileKind.withArticle(FileKind.plainName(file), capital: true)). Duo can’t show it; open it in another app.")
                        .duoText(.body).foregroundStyle(DuoColor.text2).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: DuoSpace.gapButtonToButton) {
                        OpenWithMenu(path: path, file: file, bordered: true)
                        Button("Show in Finder") { FileActions.reveal(file) }.buttonStyle(.duo)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// The quiet strip over Quick Look (DL-132 e, q52-preview): 36 high on `ground` with a `rule` under
/// it, "PDF · read only" in `text2`, then Open With ⌄ and Show in Finder.
struct ReadOnlyStrip: View {
    let path: String
    let file: URL

    var body: some View {
        HStack(spacing: DuoSpace.gapButtonToButton) {
            Text("\(FileKind.plainName(file)) · read only").duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1)
            Spacer(minLength: DuoSpace.gapRowItems)
            OpenWithMenu(path: path, file: file, bordered: true)
            Button("Show in Finder") { FileActions.reveal(file) }.buttonStyle(.duo)
        }
        .padding(.leading, DuoMetric.noticePaddingX)
        .padding(.trailing, 12)
        .frame(height: DuoMetric.tabStripHeight)
        .background(DuoColor.ground)
        .overlay(alignment: .bottom) { DuoColor.rule.frame(height: DuoMetric.borderHairline) }
    }
}


/// Open With: the apps that open the file, the default first, then Other… (C-26). As the default
/// button when nothing else on the bar is (F, F2).
struct OpenWithMenu: View {
    @Environment(AppModel.self) private var model
    let path: String
    let file: URL
    var isDefault = false
    /// A bordered button with its chevron, as the deck's bar draws it (pptx-handoff A, E).
    var bordered = false

    var body: some View {
        let menu = Menu {
            ForEach(Array(FileActions.apps(for: file).enumerated()), id: \.offset) { i, app in
                Button(FileManager.default.displayName(atPath: app.path) + (i == 0 ? " (default)" : "")) {
                    NSWorkspace.shared.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                }
            }
            Divider()
            Button("Other…") { model.openWithChosenApp(path) }
        } label: {
            if isDefault || bordered {
                // The button style hides the menu's own chevron; draw it, as on the boards (F, F2).
                HStack(spacing: 4) { Text("Open With"); Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)) }
            } else {
                Text("Open With")
            }
        }
        if isDefault {
            menu.menuStyle(.button).buttonStyle(DefaultSheetButtonStyle()).fixedSize()
        } else if bordered {
            menu.menuStyle(.button).buttonStyle(.duo).fixedSize()
        } else {
            menu.menuStyle(.borderlessButton).fixedSize()
        }
    }
}

/// A .docx (DL-123; canvas https://claude.ai/artifact/YRWyEm4MHbxYYtnRVr55xp): the offer to make a
/// Markdown copy (A), its progress (C), or why it couldn't (F, F2). Quick Look's preview stays below.
struct WordDocumentBar: View {
    @Environment(AppModel.self) private var model
    let path: String
    let file: URL

    var body: some View {
        let name = file.lastPathComponent
        if let p = model.converting[path] {
            VStack(alignment: .leading, spacing: DuoSpace.gapGlyphToLabel) {
                Text("Converting \(name) to Markdown…").duoText(.body)
                HStack(spacing: DuoSpace.gapCardToCard) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(DuoColor.rule)
                            Capsule().fill(DuoColor.text2).frame(width: g.size.width * max(0, min(1, p.fraction)))
                        }
                    }
                    .frame(height: 4)
                    Text(p.stage).duoText(.body).foregroundStyle(DuoColor.text2).fixedSize()
                    Button("Cancel") { model.cancelConversion(path) }.buttonStyle(.duo)
                }
            }
            .padding(.vertical, DuoMetric.noticePaddingY)
            .padding(.horizontal, DuoMetric.noticePaddingX)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DuoColor.ground)
            .overlay(alignment: .bottom) { DuoColor.rule.frame(height: DuoMetric.borderHairline) }
        } else if let f = model.conversionFailures[path] {
            NoticeBar(text: "Couldn’t convert \(name): \(f).", sub: Self.advice(f)) {
                if case .noText = f {
                    Button("Convert Anyway") { model.convertAnyway(path) }.buttonStyle(.duo)
                }
                OpenWithMenu(path: path, file: file, isDefault: true)
                Button("Show in Finder") { FileActions.reveal(file) }.buttonStyle(.duo)
            }
        } else {
            NoticeBar(text: "\(name) is a Word document. Duo can make a Markdown copy of it to read and edit here, with Claude.",
                      sub: "The copy goes beside it as \(file.deletingPathExtension().lastPathComponent).md. The Word document isn’t changed.") {
                Button("Convert to Markdown") { model.convertToMarkdown(path) }.buttonStyle(DefaultSheetButtonStyle())
                OpenWithMenu(path: path, file: file)
                Button("Show in Finder") { FileActions.reveal(file) }.buttonStyle(.duo)
            }
        }
    }

    static func advice(_ f: Docx.Failure) -> String {
        switch f {
        case .passwordProtected: "Nothing was written. Remove the password in Word, then convert again."
        case .damaged: "Nothing was written. Word may be able to repair it: open it there and save a copy."
        case .oldFormat: "Nothing was written. Save it as .docx in Word or Pages, then convert again."
        case .notWord: "Nothing was written. Open it in the app that made it."
        case .noText: "It may be a scan. Nothing was written."
        }
    }
}

/// The Markdown copy just made (D), or with gaps (E): where it came from, the summary, and Undo
/// Conversion, Open Original, OK.
struct ConversionNotice: View {
    @Environment(AppModel.self) private var model
    let tab: String
    let conversion: DocxConversion

    var body: some View {
        let c = conversion
        let source = c.source.lastPathComponent
        NoticeBar(text: c.gaps.isEmpty ? "Converted from \(source). The Word document is unchanged."
                                       : "Converted from \(source), with gaps. The Word document is unchanged.",
                  sub: c.gaps.isEmpty ? (c.done.isEmpty ? nil : c.done.joined(separator: " · "))
                                      : "Not carried over: " + c.gaps.joined(separator: " · "),
                  sub2: c.gaps.isEmpty || c.done.isEmpty ? nil : "Also: " + c.done.joined(separator: " · ")) {
            Button("Undo Conversion") { model.undoConversion(c) }.buttonStyle(.duo)
            Button("Open Original") { model.openOriginal(tab) }.buttonStyle(.duo)
            Button("OK") { model.dismissConversion(tab) }.buttonStyle(DefaultSheetButtonStyle()).keyboardShortcut(.defaultAction)
        }
    }
}

/// Quick Look's preview of a file, read only (QLPreviewView). It can't say which page or slide
/// shows, or what was clicked (F-102).
struct QuickLookPane: NSViewRepresentable {
    let file: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let v = QLPreviewView(frame: .zero, style: .normal)!
        v.shouldCloseWithWindow = true
        v.previewItem = file as NSURL
        return v
    }

    func updateNSView(_ v: QLPreviewView, context: Context) {
        if (v.previewItem as? NSURL) as URL? != file { v.previewItem = file as NSURL }
    }

    static func dismantleNSView(_ v: QLPreviewView, coordinator: ()) { v.close() }
}
