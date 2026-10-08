import AppKit
import DuoSearch
import Foundation
import DuoControl

/// A Markdown copy just made from a Word document (DL-123): what its bar says, and what Undo
/// Conversion takes away again.
public struct DocxConversion: Sendable {
    public var source: URL
    public var markdown: URL
    /// The images folder, when the document had pictures.
    public var images: URL?
    /// The summary: what was inferred, cleaned or kept, and what didn't come over whole.
    public var done: [String]
    public var gaps: [String]
    /// The text written, so Undo leaves a copy that has been edited since.
    var written: String
    /// What Replace moved to the Trash: where it was, and where it is now. Undo puts it back.
    var replaced: [(was: URL, now: URL)]
}

/// Opening a Word document as Markdown (ENH-14, DL-123; canvas
/// https://claude.ai/artifact/YRWyEm4MHbxYYtnRVr55xp). The .docx is never written: the copy goes
/// beside it as `<name>.md`, its pictures in `<name>-images`, and Undo takes both away.
extension AppModel {
    public static func isWordDocument(_ url: URL) -> Bool { url.pathExtension.lowercased() == "docx" }
    public static func isOldWordDocument(_ url: URL) -> Bool { url.pathExtension.lowercased() == "doc" }

    /// `Report 2.md`, `Report 3.md`… beside `Report.md`: the first name that's free, with its
    /// images folder free too.
    public static func freeMarkdownName(_ md: URL) -> URL {
        let dir = md.deletingLastPathComponent(), stem = md.deletingPathExtension().lastPathComponent
        var n = 2
        while true {
            let u = dir.appending(path: "\(stem) \(n).md")
            if !FileManager.default.fileExists(atPath: u.path), !FileManager.default.fileExists(atPath: imagesFolder(for: u).path) { return u }
            n += 1
        }
    }

    static func imagesFolder(for md: URL) -> URL {
        md.deletingLastPathComponent().appending(path: md.deletingPathExtension().lastPathComponent + "-images")
    }

    /// The viewer's Convert to Markdown… (DL-162, fallback board): asks first, saying what won't come
    /// over, with the document's own counts and only the parts it has. A document with no changes,
    /// comments, columns or text boxes skips the question. `yes` skips it too (`duo2 file convert --yes`),
    /// and so does a scripted run (DUO_AUTOCONFIRM=1).
    public func askConvertToMarkdown(_ tab: String, yes: Bool = false) {
        guard let docx = fileURL(tab), FileManager.default.fileExists(atPath: docx.path) else { return }
        let inv = Docx.inventory(docx)
        if yes || inv.isLossless { return convertToMarkdown(tab, beside: true) }
        let stem = docx.deletingPathExtension().lastPathComponent
        var q = DuoQuestion(title: "Convert \(docx.lastPathComponent) to Markdown?", choices: [])
        q.paragraphs = ["Duo makes an editable copy, \(stem).md, beside it. The Word document isn’t changed."]
        q.note = Self.lossNote(inv)
        q.choices = [
            .init(label: "Cancel", isCancel: true) {},
            .init(label: "Convert", isDefault: true) { [weak self] in self?.convertToMarkdown(tab, beside: true) },
        ]
        if Env.autoconfirm {
            FileHandle.standardError.write(Data("confirm: \(q.title) | Convert\n".utf8))
            return q.choices.last!.action()
        }
        SheetCenter.shared.ask(q)
    }

    /// "Not everything comes over: its 12 tracked changes are accepted, its 4 comments become notes
    /// at the end, and page layout, columns and text boxes are left out." Only what the document has.
    public static func lossNote(_ inv: Docx.Inventory) -> String {
        var parts: [String] = []
        if inv.changes > 0 { parts.append(inv.changes == 1 ? "its 1 tracked change is accepted" : "its \(inv.changes) tracked changes are accepted") }
        if inv.comments > 0 { parts.append(inv.comments == 1 ? "its 1 comment becomes a note at the end" : "its \(inv.comments) comments become notes at the end") }
        var left = ["page layout"]
        if inv.columns > 0 { left.append("columns") }
        if inv.textBoxes > 0 { left.append("text boxes") }
        let list = left.count == 1 ? left[0] : left.dropLast().joined(separator: ", ") + " and " + left.last!
        parts.append("\(list) \(left.count == 1 ? "is" : "are") left out")
        let body = parts.count == 1 ? parts[0] : parts.dropLast().joined(separator: ", ") + (parts.count > 2 ? ", and " : " and ") + parts.last!
        return "Not everything comes over: " + body + "."
    }

    /// The bar's Convert to Markdown (A). When `<name>.md` is taken, asks first (B). `beside` puts the
    /// copy in a tab of its own next to the viewer, instead of in the .docx's tab.
    public func convertToMarkdown(_ tab: String, beside: Bool = false) {
        guard let docx = fileURL(tab), FileManager.default.fileExists(atPath: docx.path) else { return }
        let md = docx.deletingPathExtension().appendingPathExtension("md")
        guard FileManager.default.fileExists(atPath: md.path) else {
            return startConversion(tab, docx: docx, md: md, replace: false, allowEmpty: false, show: true, beside: beside) { _ in }
        }
        askNameTaken(tab, docx: docx, md: md, suggest: Self.freeMarkdownName(md).lastPathComponent, beside: beside)
    }

    /// F2's Convert Anyway: a document with only pictures, converted all the same.
    public func convertAnyway(_ tab: String) {
        guard let docx = fileURL(tab) else { return }
        var md = docx.deletingPathExtension().appendingPathExtension("md")
        if FileManager.default.fileExists(atPath: md.path) { md = Self.freeMarkdownName(md) }
        startConversion(tab, docx: docx, md: md, replace: false, allowEmpty: true, show: true, beside: tab.hasSuffix(".docx")) { _ in }
    }

    /// Board B: the name's taken. A free name is offered in a field the user can change.
    func askNameTaken(_ tab: String, docx: URL, md: URL, suggest: String, beside: Bool = false) {
        let field = DuoQuestion.Field(label: "Save new as", text: suggest)
        let stem = (suggest as NSString).deletingPathExtension
        var q = DuoQuestion(title: "\(md.lastPathComponent) already exists", choices: [])
        q.paragraphs = ["A Markdown file with that name is already beside \(docx.lastPathComponent). It may be an earlier copy you’ve since edited."]
        let edited = (try? md.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { d -> String in let a = Self.ago(d); return a == "now" ? "edited just now" : "edited \(a) ago" }
        q.items = [.init(what: "", path: Self.short(md.path), detail: edited)]
        q.field = field
        q.note = "Duo suggests a free name; change it if you like. Its images go in \(stem)-images. Replace moves the old copy to the Trash."
        q.choices = [
            .init(label: "Cancel", isCancel: true) {},
            .init(label: "Replace") { [weak self] in self?.startConversion(tab, docx: docx, md: md, replace: true, allowEmpty: false, show: true, beside: beside) { _ in } },
            .init(label: "Open Existing") { [weak self] in self?.openFile(at: md) },
            .init(label: "Convert", isDefault: true) { [weak self] in
                guard let self else { return }
                var name = field.text.trimmingCharacters(in: .whitespaces)
                if !name.lowercased().hasSuffix(".md") { name += ".md" }
                let target = docx.deletingLastPathComponent().appending(path: name)
                if name.contains("/") || name == ".md" || FileManager.default.fileExists(atPath: target.path) {
                    // Taken too, or not a name: ask again with a free one.
                    return self.askNameTaken(tab, docx: docx, md: name.contains("/") || name == ".md" ? md : target,
                                             suggest: Self.freeMarkdownName(md).lastPathComponent, beside: beside)
                }
                self.startConversion(tab, docx: docx, md: target, replace: false, allowEmpty: false, show: true, beside: beside) { _ in }
            },
        ]
        if Env.autoconfirm {
            // A scripted run takes the default: the free name (F-54).
            FileHandle.standardError.write(Data("confirm: \(q.title) | Convert as \(suggest)\n".utf8))
            return q.choices.last!.action()
        }
        SheetCenter.shared.ask(q)
    }

    /// "4m", "1h", "3d" (the README's wait times).
    static func ago(_ date: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(date)))
        return s < 60 ? "now" : s < 3600 ? "\(s / 60)m" : s < 86_400 ? "\(s / 3600)h" : "\(s / 86_400)d"
    }

    /// Converts off the main thread, writes the copy, and (with `show`) puts it in the .docx's tab
    /// with its notice. The progress bar (C) shows only once it has taken half a second.
    public func startConversion(_ tab: String, docx: URL, md: URL, replace: Bool, allowEmpty: Bool, show: Bool, beside: Bool = false,
                         completion: @escaping @MainActor (Result<DocxConversion, Error>) -> Void) {
        conversionFailures[tab] = nil
        var images = Self.imagesFolder(for: md)
        if !replace, FileManager.default.fileExists(atPath: images.path) {
            // A folder left from before, with no .md of that name: don't write into it.
            var n = 2
            while FileManager.default.fileExists(atPath: images.path + " \(n)") { n += 1 }
            images = URL(fileURLWithPath: images.path + " \(n)")
        }
        var options = Docx.Options(imagesFolder: images.lastPathComponent)
        options.allowEmpty = allowEmpty
        let started = Date()
        options.progress = { fraction, stage in
            Task { @MainActor [weak self] in
                guard let self, self.conversionTasks[tab] != nil, Date().timeIntervalSince(started) > 0.5 else { return }
                self.converting[tab] = (fraction, stage)
            }
        }
        let opts = options
        let work = Task.detached(priority: .userInitiated) { () -> Result<Docx.Result, Error> in
            Result { try Docx.convert(docx, options: opts) }
        }
        conversionTasks[tab] = Task { @MainActor [weak self] in
            let outcome = await work.value
            guard let self else { return }
            let cancelled = self.conversionTasks[tab] == nil
            self.conversionTasks[tab] = nil
            self.converting[tab] = nil
            if cancelled { return completion(.failure(CancellationError())) }
            switch outcome {
            case .failure(let e):
                if let f = e as? Docx.Failure { self.conversionFailures[tab] = f }
                completion(.failure(e))
            case .success(let r):
                do {
                    let c = try self.write(r, docx: docx, md: md, images: images, replace: replace, options: opts)
                    if show { self.showConversion(c, from: tab, beside: beside) } else { self.refreshLive() }
                    self.registerUndo("Convert to Markdown") { model in model.undoConversion(c) }
                    completion(.success(c))
                } catch {
                    completion(.failure(error))
                }
            }
        }
        // A slow one shows the bar even before its first progress report.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { MainActor.assumeIsolated { [weak self] in
            guard let self, self.conversionTasks[tab] != nil, self.converting[tab] == nil else { return }
            self.converting[tab] = (0, "Reading")
        } }
    }

    /// C's Cancel: nothing is written.
    public func cancelConversion(_ tab: String) {
        conversionTasks[tab]?.cancel()
        conversionTasks[tab] = nil
        converting[tab] = nil
    }

    private func write(_ r: Docx.Result, docx: URL, md: URL, images: URL, replace: Bool, options: Docx.Options) throws -> DocxConversion {
        let fm = FileManager.default
        var replaced: [(was: URL, now: URL)] = []
        if replace {
            for u in [md, images] where fm.fileExists(atPath: u.path) {
                closeDocumentsUnder(relative(u) ?? Self.outsideFilePrefix + u.path)
                var now: NSURL?
                try fm.trashItem(at: u, resultingItemURL: &now)
                if let now = now as URL? { replaced.append((u, now)) }
            }
        }
        if !r.images.isEmpty {
            try fm.createDirectory(at: images, withIntermediateDirectories: true)
            for i in r.images { try i.data.write(to: images.appending(path: i.name)) }
        }
        try r.markdown.write(to: md, atomically: true, encoding: .utf8)
        let (done, gaps) = r.report.summary(options)
        return DocxConversion(source: docx, markdown: md, images: r.images.isEmpty ? nil : images, done: done, gaps: gaps,
                              written: r.markdown, replaced: replaced)
    }

    /// D, E: the copy takes the .docx's tab, with its notice; or, with `beside` (the Word viewer, DL-162),
    /// opens in a tab of its own right after the viewer's, which stays.
    func showConversion(_ c: DocxConversion, from tab: String, beside: Bool = false) {
        let new = relative(c.markdown) ?? Self.outsideFilePrefix + c.markdown.standardizedFileURL.path
        var docs = openDocuments.filter { $0 != new }
        if let i = docs.firstIndex(of: tab) {
            if beside { docs.insert(new, at: i + 1) } else { docs[i] = new }
        } else { docs.append(new) }
        openDocuments = docs
        conversions[new] = c
        refreshLive()
        openDocument(new)
    }

    /// Undo Conversion, and Edit › Undo: the copy and its images go to the Trash, the .docx's tab
    /// comes back, and anything Replace put in the Trash returns. A copy edited since is left.
    public func undoConversion(_ c: DocxConversion) {
        let fm = FileManager.default
        let tab = relative(c.markdown) ?? Self.outsideFilePrefix + c.markdown.standardizedFileURL.path
        guard fm.fileExists(atPath: c.markdown.path) else { return }
        let unsaved = editorIfLoaded.map { $0.dirty && $0.url?.standardizedFileURL == c.markdown.standardizedFileURL } ?? false
        guard !unsaved, (try? String(contentsOf: c.markdown, encoding: .utf8)) == c.written else {
            return info("\(c.markdown.lastPathComponent) has changed since Duo made it, so Undo left it as it is.")
        }
        let source = relative(c.source) ?? Self.outsideFilePrefix + c.source.standardizedFileURL.path
        if let i = openDocuments.firstIndex(of: tab) {
            if let e = editorIfLoaded, e.url?.standardizedFileURL == c.markdown.standardizedFileURL { e.closeFile() }
            if openDocuments.contains(source) {
                // The viewer's tab is still there (the copy opened beside it): the copy's tab just goes.
                openDocuments = openDocuments.filter { $0 != tab }
                if rightTab == tab { rightTab = source; selectedFile = source }
            } else {
                var docs = openDocuments.filter { $0 != source }
                if let j = docs.firstIndex(of: tab) { docs[j] = source } else { docs.insert(source, at: min(i, docs.count)) }
                openDocuments = docs
                if rightTab == tab { rightTab = source; selectedFile = source }
            }
        }
        conversions[tab] = nil
        for u in [c.markdown, c.images].compactMap({ $0 }) where fm.fileExists(atPath: u.path) { try? fm.trashItem(at: u, resultingItemURL: nil) }
        for r in c.replaced where !fm.fileExists(atPath: r.was.path) { try? fm.moveItem(at: r.now, to: r.was) }
        refreshLive()
    }

    /// D's Open Original: the .docx in its own app (Word, or Pages).
    public func openOriginal(_ tab: String) {
        guard let c = conversions[tab] else { return }
        FileActions.openInDefaultApp(c.source)
    }

    /// D's OK: the notice goes; the copy stays.
    public func dismissConversion(_ tab: String) { conversions[tab] = nil }
}
