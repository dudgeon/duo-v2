import Foundation
import UniformTypeIdentifiers

/// Whether a file is text Duo can put in its editor, or something else (C-26, F-102). A PowerPoint
/// deck once opened as text and showed noise: the right pane now asks here first.
public enum FileKind {
    /// Extensions whose system type is wrong for code: `.ts` is an MPEG stream to the system.
    static let codeExtensions: Set<String> = ["ts", "mts", "cts", "m", "mm"]

    /// Types that are never text, known from the name alone.
    static let binaryTypes: [UTType] = [.image, .pdf, .presentation, .spreadsheet, .audiovisualContent, .archive,
                                        .executable, .font, .database, .diskImage, .package]

    /// True when the file isn't text: its type says so (unless it's also text, like SVG), or its
    /// first 8 KB do. Unknown types are always sniffed, so a `.data` file of text still opens.
    public static func isBinary(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if !codeExtensions.contains(ext), let type = UTType(filenameExtension: ext), !type.conforms(to: .text),
           binaryTypes.contains(where: { type.conforms(to: $0) }) {
            return true
        }
        guard let h = FileHandle(forReadingAtPath: url.path) else { return false }
        defer { try? h.close() }
        return looksBinary((try? h.read(upToCount: 8192)) ?? Data())
    }

    /// Content sniffing: a NUL byte, or more than one byte in ten a control character that text
    /// doesn't use (tab, newlines, form feed and escape are text's).
    public static func looksBinary(_ data: Data) -> Bool {
        if data.isEmpty { return false }
        if data.contains(0) { return true }
        let odd = data.reduce(0) { n, b in n + (b < 0x20 && ![0x09, 0x0A, 0x0C, 0x0D, 0x1B].contains(b) || b == 0x7F ? 1 : 0) }
        return odd * 10 > data.count
    }

    /// What the file is, for the pane's notice: "PowerPoint presentation", "PNG image".
    public static func description(_ url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.localizedDescription ?? "binary file"
    }

    /// The kind in plain words (DL-132 e): "PDF", "ZIP archive", "Keynote deck"; the system's own
    /// name for anything else ("Xcode project").
    public static func plainName(_ url: URL) -> String {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return "binary file" }
        let byID: [(String, String)] = [
            ("com.apple.iwork.keynote.key", "Keynote deck"), ("com.apple.iwork.keynote.sffkey", "Keynote deck"),
            ("com.apple.iwork.numbers.numbers", "Numbers sheet"), ("com.apple.iwork.numbers.sffnumbers", "Numbers sheet"),
            ("com.apple.iwork.pages.pages", "Pages document"), ("com.apple.iwork.pages.sffpages", "Pages document"),
            ("org.openxmlformats.presentationml.presentation", "PowerPoint deck"), ("com.microsoft.powerpoint.ppt", "PowerPoint deck"),
            ("org.openxmlformats.spreadsheetml.sheet", "Excel sheet"), ("com.microsoft.excel.xls", "Excel sheet"),
            ("org.openxmlformats.wordprocessingml.document", "Word document"), ("com.microsoft.word.doc", "Word document"),
        ]
        if let n = byID.first(where: { $0.0 == type.identifier }) { return n.1 }
        let byKind: [(UTType, String)] = [
            (.pdf, "PDF"), (.zip, "ZIP archive"), (.archive, "archive"), (.diskImage, "disk image"), (.application, "app"),
            (.image, "image"), (.movie, "video"), (.audio, "audio file"), (.font, "font"), (.database, "database"),
        ]
        return byKind.first(where: { type.conforms(to: $0.0) })?.1 ?? type.localizedDescription ?? "binary file"
    }

    /// "a PowerPoint deck", "an archive"; "A ZIP archive" with `capital`.
    public static func withArticle(_ s: String, capital: Bool = false) -> String {
        let a = ["a", "e", "i", "o", "u"].contains(s.prefix(1).lowercased()) ? "an " : "a "
        return (capital ? a.prefix(1).uppercased() + a.dropFirst() : a) + s
    }

    /// Types Quick Look draws more than an icon for. Anything else gets the note instead.
    public static func quickLookPreviews(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return [UTType.pdf, .image, .presentation, .spreadsheet, .audiovisualContent, .rtf, .rtfd]
            .contains { type.conforms(to: $0) }
            || ["org.openxmlformats.wordprocessingml.document", "com.microsoft.word.doc", "com.apple.iwork.pages.sffpages",
                "com.apple.iwork.pages.pages", "com.apple.iwork.keynote.sffkey", "com.apple.iwork.keynote.key",
                "com.apple.iwork.numbers.sffnumbers", "com.apple.iwork.numbers.numbers"].contains(type.identifier)
    }
}
