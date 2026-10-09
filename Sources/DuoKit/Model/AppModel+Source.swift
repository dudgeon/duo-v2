import Foundation

/// View › Source Mode and `duo2 doc mode` (DL-167): a document drawn as its text, the live preview off,
/// remembered per document.
extension AppModel {
    /// The document showing in the editor, by standardized path.
    private var sourceDocumentPath: String? { editorIfLoaded?.url?.standardizedFileURL.path }

    /// Whether the document on screen is in Source mode.
    public var showingSourceMode: Bool { sourceDocumentPath.map { sourceDocuments.contains($0) } ?? false }

    /// Turns Source mode on or off for the document on screen, and remembers it.
    public func setSourceMode(_ on: Bool) {
        guard let path = sourceDocumentPath, let e = editorIfLoaded else { return }
        if on { sourceDocuments.insert(path) } else { sourceDocuments.remove(path) }
        let all = sourceDocuments.sorted()
        DuoState.update { $0.sourceDocuments = all }
        e.sourceModes = all
        e.sendSourceModes()
        e.showSource(on)
    }

}
