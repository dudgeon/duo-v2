import DuoControl
import DuoSearch
import Foundation

// `duo2 doc layout <file.docx>` (F-378): the document's geometry from the file. A verb runs in
// Duo, outside the session's sandbox, so it reads only what the session could reach anyway (C-115).
struct DocumentRefusal: Error { var why: String }

extension AppModel {
    /// A document a document verb may read for this caller: open in a Duo tab, or inside the
    /// project folder of the session that asked (the showing project for a caller outside a session).
    /// Anything else is refused, whether or not it exists.
    func documentFile(_ arg: String, req: ControlRequest) -> Result<URL, DocumentRefusal> {
        let expanded = (arg as NSString).expandingTildeInPath
        var url: URL?
        if expanded.hasPrefix("/") { url = URL(fileURLWithPath: expanded) }
        else if let cwd = req.cwd { url = URL(fileURLWithPath: cwd).appending(path: expanded) }
        if url == nil || !FileManager.default.fileExists(atPath: url!.path) { url = deckFile(arg, req: req) }
        guard let found = url, FileManager.default.fileExists(atPath: found.path) else {
            return .failure(DocumentRefusal(why: "no document '\(arg)' here (a path from the project's folder, or absolute)"))
        }
        let real = found.realPath
        var folders: [URL] = []
        if let p = projectFor(cwd: req.cwd)?.name, let f = liveFolders[p] { folders.append(f) }
        else if req.cwd == nil, let p = currentProject?.name, let f = liveFolders[p] { folders.append(f) }
        if folders.contains(where: { real.hasPrefix($0.realPath + "/") }) { return .success(found) }
        for (project, paths) in openDocumentsByProject {
            guard let folder = liveFolders[project] else { continue }
            if paths.contains(where: { folder.appending(path: $0).realPath == real }) { return .success(found) }
        }
        return .failure(DocumentRefusal(why: "\(displayPath(found)) is outside this session's project folder and isn't open in a Duo tab, so this verb won't read it (open it in Duo with `duo2 doc open`, or copy it into the project)"))
    }

    func layoutVerb(_ inv: Invocation, _ req: ControlRequest, _ done: @escaping @MainActor (Reply) -> Void) {
        guard let arg = inv[0] else { return done(.fail("usage: \(ActionID.docLayout.action.usage)")) }
        let url: URL
        switch documentFile(arg, req: req) {
        case .failure(let refusal): return done(.fail(refusal.why))
        case .success(let u): url = u
        }
        do {
            let l = try Docx.layout(url)
            let json = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(l))) ?? [:]
            done(.ok(Self.layoutText(l, path: SendFormat.tilde(displayPath(url))), json))
        } catch { done(.fail("\(displayPath(url)): \(error)")) }
    }

    public static func layoutText(_ l: Docx.Layout, path: String) -> String {
        func inches(_ v: Double) -> String { String(format: "%g", (v / 72 * 100).rounded() / 100) }
        var lines = [path]
        for s in l.sections {
            lines.append("Section \(s.index): page \(inches(s.pageWidth))×\(inches(s.pageHeight)) in \(s.orientation)\(s.assumed ? " (not stated; Word's Letter default)" : ""), "
                + "margins L \(Docx.pts(s.marginLeft)) R \(Docx.pts(s.marginRight)) T \(Docx.pts(s.marginTop)) B \(Docx.pts(s.marginBottom)); text width \(Docx.pts(s.textWidth))")
        }
        for t in l.tables {
            let width = t.declaredWidth.map { "declared \(Docx.pts($0))" } ?? (t.widthType == "pct" ? "declared as a percentage" : "no declared width")
            lines.append("Table \(t.index)\(t.depth > 0 ? " (in a cell)" : ""), section \(t.section), after ¶\(t.afterParagraph): \(t.rows) rows × \(t.columns.count) columns, \(width), columns total \(Docx.pts(t.gridWidth)) of \(Docx.pts(t.room))"
                + (t.label.isEmpty ? "" : ", starts “\(t.label)”"))
            if !t.columns.isEmpty { lines.append("    columns: " + t.columns.map { String(format: "%g", ($0 * 10).rounded() / 10) }.joined(separator: " + ") + " pt") }
        }
        for i in l.images {
            lines.append("Image \(i.index), section \(i.section), in ¶\(i.paragraph): \(i.name.isEmpty ? "unnamed" : i.name), \(Docx.pts(i.width)) × \(Docx.pts(i.height)) \(i.placement)\(i.alt.isEmpty ? ", no alt text" : "")")
        }
        let w = l.warnings
        lines.append(w.isEmpty ? "No warnings: every table and picture fits its room." : "Warnings:\n" + w.map { "  ! " + $0 }.joined(separator: "\n"))
        return lines.joined(separator: "\n")
    }
}
