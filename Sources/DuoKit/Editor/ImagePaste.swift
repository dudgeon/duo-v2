import Foundation

/// Pasting or dropping a picture into the editor (LR-39, legacy ENH-108): the file is saved
/// beside the document and the text gets a relative markdown link, never an absolute path or a
/// blob URL, so the note stays portable (Obsidian, OKF). Pure rules here; the write is in
/// `EditorController.savePastedImage`.
public enum ImagePaste {
    /// File extension for a pasted type; nil when it isn't a picture Duo saves (HEIC waits).
    public static func fileExtension(mime: String) -> String? {
        switch mime.lowercased() {
        case "image/png": return "png"
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        default: return nil
        }
    }

    /// `<doc stem>-<yyyyMMdd-HHmmss>.<ext>`, or `-2`, `-3` … before the extension if taken.
    /// Spaces in the stem become hyphens so the link needs no escaping in most readers.
    public static func fileName(docStem: String, date: Date, ext: String, taken: (String) -> Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmmss"
        let stem = docStem.split(whereSeparator: { $0 == " " || $0 == "/" }).joined(separator: "-")
        let base = (stem.isEmpty ? "image" : stem) + "-" + f.string(from: date)
        var name = "\(base).\(ext)", n = 2
        while taken(name) { name = "\(base)-\(n).\(ext)"; n += 1 }
        return name
    }

    /// The markdown for a file beside the document: a relative, percent-encoded name.
    public static func link(fileName: String) -> String {
        // `:` would read as a URL scheme and an unmatched `(` `)` would end the link early.
        var safe = CharacterSet.urlPathAllowed; safe.remove(charactersIn: ":()")
        let enc = fileName.addingPercentEncoding(withAllowedCharacters: safe) ?? fileName
        return "![](\(enc))"
    }
}
