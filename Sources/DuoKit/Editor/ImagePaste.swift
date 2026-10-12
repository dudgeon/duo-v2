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

    /// What a paste into a document does (DL-181). Mirrors `decidePaste` in `duo-editor.js`, which runs in the
    /// page where the paste event is; the live check (`scripts/check-paste-image.sh`) proves the page agrees.
    public enum Decision: Equatable { case text, table(String), image, nothing }

    /// Text wins when the clipboard holds both (Numbers, Excel, Word and Pages put a picture of the selection beside
    /// the text). Tab-separated text from a spreadsheet becomes a Markdown table. Only a picture pastes as a picture.
    public static func decide(text: String?, hasImage: Bool) -> Decision {
        if let t = text, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let md = tableMarkdown(tsv: t) { return .table(md) }
            return .text
        }
        return hasImage ? .image : .nothing
    }

    /// Tab-separated text (`public.utf8-tab-separated-values-text`, which Numbers and Excel also write as
    /// `text/plain`) as a Markdown table: at least two rows, every row with the same number of tabs (one or more).
    /// The first row is the header. Pipes are escaped and a cell's line breaks become `<br>` (DL-113). nil if it isn't a table.
    public static func tableMarkdown(tsv: String) -> String? {
        var rows = tsv.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        while rows.last == "" { rows.removeLast() }
        guard rows.count >= 2 else { return nil }
        let cells = rows.map { $0.components(separatedBy: "\t") }
        let n = cells[0].count
        guard n >= 2, cells.allSatisfy({ $0.count == n }) else { return nil }
        func cell(_ c: String) -> String {
            var t = c.trimmingCharacters(in: .whitespaces)
            if t.count >= 2, t.hasPrefix("\""), t.hasSuffix("\"") { t = String(t.dropFirst().dropLast()).replacingOccurrences(of: "\"\"", with: "\"") }
            return t.replacingOccurrences(of: "|", with: "\\|")
        }
        func line(_ r: [String]) -> String { "| " + r.map(cell).joined(separator: " | ") + " |" }
        var out = [line(cells[0]), "| " + Array(repeating: "---", count: n).joined(separator: " | ") + " |"]
        out += cells.dropFirst().map(line)
        return out.joined(separator: "\n")
    }
}
