import AppKit
import Foundation

/// The document editors (C-135): one per side of a split tab (DL-278), behind `EditorRef`. Today's API
/// is kept: `editor` and `editorIfLoaded` are the active slot's, so a caller written for one editor
/// acts on the side the user is in. Code about a particular file asks `editorShowing(_:)`.
extension AppModel {
    func makeEditorSet() -> EditorSet {
        let set = EditorSet(homes: DocumentHomes()) { [weak self] ref in
            let e = EditorController()
            self?.wireEditor(e, ref: ref)
            return e
        }
        set.onActiveChange = { [weak self] in self?.editorRevision += 1 }
        return set
    }

    /// The editor the menus and `duo2 doc` act on: the active side's in a split of two documents,
    /// else the main one (a preview's source, an ordinary tab), whichever side last had the keyboard.
    public var activeEditorRef: EditorRef { showingSplit?.isDocPair == true ? editors.active : .main }
    /// The active side's editor (made on first use).
    public var editor: EditorController { editors.editor(activeEditorRef) }
    /// The active side's editor if it has been made (doc-status mustn't make one).
    public var editorIfLoaded: EditorController? { editors.ifLoaded(activeEditorRef) }

    public func editor(_ ref: EditorRef) -> EditorController { editors.editor(ref) }
    public func editorIfLoaded(_ ref: EditorRef) -> EditorController? { editors.ifLoaded(ref) }

    /// The editor whose document on screen is `file`, on either side.
    public func editorShowing(_ file: URL) -> EditorController? { editors.showing(file) }
    /// Every editor made so far (quit, appearance, Source mode), main first.
    public var loadedEditors: [EditorController] { editors.loaded.map(\.editor) }
}
