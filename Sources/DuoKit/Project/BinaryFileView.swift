import AppKit
import Quartz
import SwiftUI

/// A file that isn't text (C-26, F-102). Stand-in (Q-52): no screen draws this state, so it is
/// built from drawn parts: the notice bar (S3-4) with Open With and Show in Finder, over Quick
/// Look's own preview when it has one (PDF, Office, Keynote, images, video), or a short note on
/// `pane` when it hasn't. Duo never puts the bytes in its editor.
struct BinaryFileView: View {
    @Environment(AppModel.self) private var model
    let path: String
    let file: URL

    var body: some View {
        VStack(spacing: 0) {
            NoticeBar(text: "Read only: Duo can’t edit \(Self.article(FileKind.description(file))).") {
                Menu("Open With") {
                    ForEach(Array(FileActions.apps(for: file).enumerated()), id: \.offset) { i, app in
                        Button(FileManager.default.displayName(atPath: app.path) + (i == 0 ? " (default)" : "")) {
                            NSWorkspace.shared.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                        }
                    }
                    Divider()
                    Button("Other…") { model.openWithChosenApp(path) }
                }
                .menuStyle(.borderlessButton).fixedSize()
                Button("Show in Finder") { FileActions.reveal(file) }.buttonStyle(.duo)
            }
            if FileKind.quickLookPreviews(file) {
                QuickLookPane(file: file)
            } else {
                VStack(alignment: .leading, spacing: DuoSpace.gapGlyphToLabel) {
                    Text("No preview").duoText(.bodyEmphasis)
                    Text("\(file.lastPathComponent) isn’t text, and Quick Look can’t show it. Open it in another app, or show it in Finder.")
                        .duoText(.body).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true)
                }
                .padding(DuoSpace.documentPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    /// "a PowerPoint presentation", "an Xcode project".
    static func article(_ s: String) -> String {
        let lower = s.prefix(1).lowercased()
        return (["a", "e", "i", "o", "u"].contains(lower) ? "an " : "a ") + s
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
