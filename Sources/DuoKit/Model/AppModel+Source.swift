import Foundation

/// View › Source (⌥⌘U) and `duo2 doc mode` (DL-167, DL-346): a Markdown or HTML document drawn as its highlighted,
/// editable text in place of its page, remembered per document. No button or switch in the document: the menu
/// and the verb are the only ways in.
extension AppModel {
    /// Whether a tab's path is an HTML page (the viewer's file kinds).
    static func isHTMLPath(_ path: String) -> Bool { ["html", "htm"].contains((path as NSString).pathExtension.lowercased()) }

    /// The HTML page on the right pane, if that is what is showing (its viewer or its source).
    private var htmlFileOnScreen: URL? {
        guard let t = rightTab, Self.isHTMLPath(t) else { return nil }
        return liveFile(t)
    }

    /// The document whose mode View › Source flips, by standardized path: the HTML page on screen, else the editor's document.
    private var sourceDocumentPath: String? { htmlFileOnScreen?.standardizedFileURL.path ?? editorIfLoaded?.url?.standardizedFileURL.path }

    /// Whether the document on screen is in Source mode.
    public var showingSourceMode: Bool { sourceDocumentPath.map { sourceDocuments.contains($0) } ?? false }

    /// Whether View › Source has a document to act on: live terminals and a document (a split tab's HTML
    /// side is always source, so there is nothing to flip there).
    public var canToggleSource: Bool {
        guard terminalsMode == .live else { return false }
        if let t = rightTab, Self.isHTMLPath(t) { return liveFile(t) != nil && splitTab(t) == nil }
        return editorIfLoaded?.url != nil
    }

    /// Turns Source mode on or off for the document on screen, and remembers it.
    public func setSourceMode(_ on: Bool) {
        guard let path = sourceDocumentPath else { return }
        let apply = { [self] in
            if on { sourceDocuments.insert(path) } else { sourceDocuments.remove(path) }
            let all = sourceDocuments.sorted()
            DuoState.update { $0.sourceDocuments = all }
            for x in loadedEditors { x.sourceModes = all; x.sendSourceModes() }
            editorIfLoaded?.showSource(on)
        }
        if htmlFileOnScreen != nil, !on, let e = editorIfLoaded, e.url?.standardizedFileURL.path == path {
            // Back to the page: it reads the file, so what was typed is saved first.
            e.flush { apply() }
        } else {
            apply()
        }
    }

    /// View › Source: the other mode.
    public func toggleSourceMode() { setSourceMode(!showingSourceMode) }
}
