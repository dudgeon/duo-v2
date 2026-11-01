import SwiftUI

/// Which editor a document's bars belong to (C-135): each side of a split has its own stack.
struct EditorSideKey: EnvironmentKey { static let defaultValue = EditorRef.main }

extension EnvironmentValues {
    var editorSide: EditorRef {
        get { self[EditorSideKey.self] }
        set { self[EditorSideKey.self] = newValue }
    }
}

/// A document in the right pane, or on one side of a split (DL-278): its notices, template bar,
/// review bar and the editor of `ref`. The bars act on this side's editor, and a click on one makes
/// this side the active one first.
struct DocumentStack: View {
    @Environment(AppModel.self) private var model
    let file: URL
    var ref: EditorRef = .main
    /// The Project tab's own file shows no template bar.
    var templates = true

    var body: some View {
        VStack(spacing: 0) {
            DocumentStateBar()
            // A template (DL-146): what it's for, Preview and Reset over it.
            if templates, let info = model.templateInfo(forFile: file) { TemplateBar(info: info) }
            MarkdownReviewSlot(file: file)   // DL-237: marks, comments or Suggest Edits on
            // The formatting bar (DL-266) is laid over the editor's top 24, so the text never moves.
            DocumentEditorView(editors: model.editors, ref: ref, file: file)
                .overlay(alignment: .top) { MarkdownFormatBarSlot(file: file) }
        }
        .environment(\.editorSide, ref)
        .modifier(NoticeMotion(key: DocumentStateBar.key(model, ref)))
    }
}

extension AppModel {
    /// Runs `action` with `ref` as the active editor: a bar's button on a side that didn't have the keyboard.
    func onSide(_ ref: EditorRef, _ action: () -> Void) {
        editors.active = ref
        action()
    }
}
