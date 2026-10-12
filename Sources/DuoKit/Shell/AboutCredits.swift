import AppKit

/// The credits in the standard About panel (DL-176, C-82): each bundled third-party component and its
/// licence, then a link to `THIRD-PARTY-NOTICES.md` in the app's Resources, which has the full texts.
/// System UI, so nothing is designed here. `scripts/gen-notices.py` writes that file from the same list
/// (DuoChecks reads one against the other).
public enum AboutCredits {
    public static let components: [(name: String, licence: String)] = [
        ("SwiftTerm", "MIT"),
        ("Sparkle", "MIT"),
        ("CodeMirror and Lezer", "MIT"),
        ("pptx-renderer (with ECharts, JSZip, mtx-decompressor)", "Apache-2.0, MIT, MPL-2.0"),
        ("@file-viewer/docx", "Apache-2.0"),
        ("JSZip", "MIT"),
        ("bge-small-en-v1.5", "MIT"),
    ]

    /// Where the notices file is in the app (nil in a bare `swift run`, which has no Resources).
    public static var noticesURL: URL? {
        Bundle.main.resourceURL?.appending(path: "THIRD-PARTY-NOTICES.md")
    }

    public static func attributed(noticesURL: URL?) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        var text = "Duo includes third-party software:\n\n"
        for c in components { text += "\(c.name): \(c.licence)\n" }
        let out = NSMutableAttributedString(string: text, attributes: body)
        let link = "\nFull licence texts"
        var linkAttributes = body
        if let url = noticesURL { linkAttributes[.link] = url }
        out.append(NSAttributedString(string: link, attributes: linkAttributes))
        return out
    }

    /// The app menu's About Duo.
    @MainActor public static func show() {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: attributed(noticesURL: noticesURL)])
    }
}
