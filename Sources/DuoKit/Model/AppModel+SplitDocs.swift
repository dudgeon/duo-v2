import AppKit
import Foundation

/// Split view, slice 2 (DL-278, `split-docs`): two documents side by side, both editable, one editor per
/// side (C-135). The tab's key is the source's path; the other document is `with`, edited in `.second`.
/// A file is never open in two editors (one home per file; ENH-301 stays deferred).
extension AppModel {
    /// The split tab and side that hold `path` as a document, if any: its own key (the source) or a pair's `with`.
    public func splitHolding(_ path: String) -> (key: String, role: SplitRole)? {
        if splitTabs[path] != nil { return (path, .source) }
        return splitTabs.first { $0.value.with == path }.map { ($0.key, .preview) }
    }

    /// The editor a side of a pair uses: the source is always `.main`, the other document `.second`.
    static func editorRef(for role: SplitRole) -> EditorRef { role == .source ? .main : .second }

    /// A side's name in the strip, the rail and `duo2 split`: the file's name, or the preview's.
    public func splitSideName(_ t: SplitTab, _ role: SplitRole) -> String {
        if role == .source { return (t.source as NSString).lastPathComponent }
        if let w = t.with { return (w as NSString).lastPathComponent }
        return t.kind.sideName
    }

    /// Open in Split View (DL-278): `other` beside `path`, both editable, `other` on the right with the
    /// keyboard. A file already open as a tab moves into the split; one already in a split selects that
    /// split and side instead. False (and nothing changes) when either isn't a text file that exists,
    /// they're the same file, or `path` is already a split.
    @discardableResult
    public func openSplitView(_ path: String, with other: String) -> Bool {
        guard currentProject != nil, path != other, !path.hasPrefix("web:"), !other.hasPrefix("web:") else { return false }
        if let held = splitHolding(other) {
            rightTab = held.key
            selectedFile = other
            activate(.right, focus: false)
            focusSplitRole(held.role, in: held.key)
            return true
        }
        guard splitHolding(path) == nil, let a = liveFile(path), let b = liveFile(other),
              Self.splittable(path, a), Self.splittable(other, b) else { return false }
        // A PDF is one side at most, beside a text document (DL-333): the text document is the pair's source (its editor),
        // the PDF its `with`, drawn by the viewer on the side the caller asked for.
        let pdfs = [path, other].filter(Self.isPdfViewable)
        guard pdfs.count < 2 else { return false }
        let (source, with) = Self.isPdfViewable(path) ? (other, path) : (path, other)
        if !openDocuments.contains(source) { openDocument(source) }
        // The other file's tab moves into the split (its place in the strip is the pair's).
        if let i = openDocuments.firstIndex(of: with) { openDocuments.remove(at: i) }
        rightCollapsed = false
        takeRoomIfNeeded()
        if pdfs.isEmpty {
            splitTabs[source] = SplitTab(source: source, kind: .document, active: .preview, with: with)
            rightTab = source
            selectedFile = with
            activate(.right, focus: false)
            focusSplitRole(.preview, in: source)
        } else {
            // The PDF side is view only: the text side keeps the editor and the keyboard.
            splitTabs[source] = SplitTab(source: source, kind: .document, swapped: Self.isPdfViewable(path), active: .source, with: with)
            rightTab = source
            selectedFile = source
            activate(.right, focus: false)
            focusSplitRole(.source, in: source)
        }
        return true
    }

    /// The open tabs a tab's Open in Split View ▸ offers: documents that are text, not this one, not in a split.
    public func splitCandidates(beside path: String) -> [String] {
        guard splitHolding(path) == nil, path.contains("."), !path.hasPrefix("web:"), liveFile(path).map({ Self.splittable(path, $0) }) == true else { return [] }
        let pdf = Self.isPdfViewable(path)
        return openDocuments.filter { o in
            o != path && o.contains(".") && !o.hasPrefix("web:") && splitHolding(o) == nil && !(pdf && Self.isPdfViewable(o))
                && liveFile(o).map { Self.splittable(o, $0) } == true
        }
    }

    /// The tree's Open in Split View: a text file, beside a showing document that isn't itself split
    /// (or a file already in a split, which it selects).
    public func canOpenInSplitView(_ path: String) -> Bool {
        if splitHolding(path) != nil { return true }
        guard terminalsMode == .live, let b = rightTab, b != path, b.contains("."), !b.hasPrefix("web:"), splitHolding(b) == nil,
              let f = liveFile(path), Self.splittable(path, f), !(Self.isPdfViewable(path) && Self.isPdfViewable(b)) else { return false }
        return true
    }

    /// A file that can be a side of a split: a text document, or a PDF (DL-333). Other binaries and Word documents can't.
    static func splittable(_ path: String, _ file: URL) -> Bool {
        if isPdfViewable(path) { return true }
        return !FileKind.isBinary(file) && !isWordViewable(path)
    }

    /// Close Split View on a pair: both documents stay, as ordinary tabs side by side in the strip.
    public func separateDocPair(_ path: String) {
        guard let t = splitTabs[path], let other = t.with else { return }
        releaseSecond(other)
        endSplit(path)
        if let i = openDocuments.firstIndex(of: path), !openDocuments.contains(other) { openDocuments.insert(other, at: i + 1) }
        if rightTab == path { selectedFile = t.active == .source ? path : other; if t.active == .preview { rightTab = other } }
        editors.active = .main
    }

    /// ⌘W or a name's × on one side of a pair: that document closes; the other stays as an ordinary tab.
    public func closeDocPairSide(_ role: SplitRole, in key: String? = nil) {
        guard let k = key ?? rightTab, let t = splitTabs[k], let other = t.with else { return }
        if role == .preview {
            releaseSecond(other)
            endSplit(k)
            rightTab = k
            selectedFile = k
        } else {
            // The source's tab closes; the other document takes its place in the strip.
            let i = openDocuments.firstIndex(of: k) ?? openDocuments.count
            releaseSecond(other)
            endSplit(k)
            openDocuments.insert(other, at: min(i + 1, openDocuments.count))
            closeDocument(k)
            rightTab = other
            selectedFile = other
        }
        editors.active = .main
    }

    /// The second editor lets go of `other` (saved first), so the main editor can show it as a tab.
    private func releaseSecond(_ other: String) {
        guard let e = editorIfLoaded(.second), let u = liveFile(other) ?? fileURL(other), e.url.map(DocumentHomes.key) == DocumentHomes.key(u) else { return }
        e.saveNow(force: true)
        e.closeFile()
    }

    /// Makes `role` the active side of the split `key` and gives it the keyboard.
    func focusSplitRole(_ role: SplitRole, in key: String) {
        setActiveRole(role, in: key)
        guard let t = splitTabs[key] else { return }
        focusSplitSide(t.place(of: role))
    }

    /// A preview's pin asks for the source's review margin (Duo Decks R11, R12): neither takes focus from it.
    func previewRequest(_ e: PreviewEvent, _ policy: PreviewPolicy) {
        let source = editor(.main)
        switch e {
        case .openThread(let thread): source.openThread(id: thread)
        case .addComment(let anchor): if let lines = policy.lines(of: anchor) { source.addComment(lines: lines) }
        default: break
        }
    }

    /// An editor took the keyboard: in a pair, its side becomes the active one (DL-275: typing in a side).
    func editorTookFocus(_ ref: EditorRef) {
        guard let k = rightTab, let t = splitTabs[k], t.isDocPair else { return }
        setActiveRole(ref == .main ? .source : .preview, in: k)
    }

    /// The pair's active side is the active editor: `editor`, ⌘S, Format, review and `duo2 doc` act on it.
    func syncActiveEditor(_ t: SplitTab) {
        if t.isDocPair { editors.active = t.with.map(Self.isPdfViewable) == true ? .main : Self.editorRef(for: t.active) }   // a PDF side has no editor (DL-333)
    }
}
