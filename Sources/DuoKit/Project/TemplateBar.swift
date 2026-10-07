import DuoControl
import SwiftUI

/// The template bar (DL-146, templates-handoff A1 to A3): over a template open in the right pane,
/// what it's for, whose it is, and Insert ▾, Preview and Reset… (Use Home's… on a project's own).
struct TemplateBar: View {
    @Environment(AppModel.self) private var model
    let info: AppModel.TemplateInfo

    var body: some View {
        let _ = model.editorRevision
        let previewing = model.editorIfLoaded?.previewing ?? false
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DuoSpace.gapButtonToButton) {
                // Too narrow for one line (a project's own: Use Home's… is wider), the title wraps (board A3).
                Text("Template for new \(info.kind.rawValue)s").duoText(.bodyEmphasis).fixedSize(horizontal: false, vertical: true)
                Text("· \(info.project ?? "Home")").duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1).layoutPriority(1)
                Spacer(minLength: DuoSpace.gapButtonToButton)
                Menu {
                    ForEach(["{{title}}", "{{date}}", "{{time}}"], id: \.self) { p in
                        Button(p) { model.editorIfLoaded?.insertAtCaret(p) }   // action: doc insert
                    }
                } label: { Text("Insert ▾") }
                    .menuStyle(.button).buttonStyle(.duo).menuIndicator(.hidden).fixedSize()
                    .disabled(previewing)
                Button("Preview") { model.toggleTemplatePreview() }
                    .buttonStyle(DuoButtonStyle(on: previewing, boldWhenOn: true)).fixedSize()
                Button(info.project == nil ? "Reset…" : "Use Home's…") { model.resetTemplate(info) }
                    .buttonStyle(.duo).fixedSize()
            }
            line(previewing)
        }
        .padding(.vertical, DuoMetric.noticePaddingY)
        .padding(.horizontal, DuoSpace.panePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DuoColor.ground)
        .overlay(alignment: .bottom) { DuoColor.rule.frame(height: DuoMetric.borderHairline) }
    }

    /// Line 2: what uses it and where it is, or, in Preview, what's shown.
    private func line(_ previewing: Bool) -> some View {
        let lead: String
        if previewing {
            lead = "A new \(info.kind.rawValue) named “\(AppModel.previewTitle)”, made today. Nothing is saved; Preview again to edit."
        } else if info.project != nil {
            lead = "This project's own: Home's template isn't used here · "
        } else {
            lead = info.kind == .task ? "Used by + New task in every project without its own · " : "Used by New Project and Make a Project · "
        }
        let path = previewing ? "" : shortPath
        return (Text(lead) + Text(path).font(DuoTextStyle.monoPath.spec.font))
            .duoText(.control).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true)
    }

    /// The path as the board writes it: a project's own from the project, Home's from the home folder.
    private var shortPath: String {
        if let p = info.project, let folder = model.liveFolders[p] {
            return p + "/" + (model.relativePathIn(info.file, folder: folder) ?? info.file.lastPathComponent)
        }
        return model.abbreviated(info.file)
    }
}

extension AppModel {
    /// The name Preview fills a template for (board A2).
    static let previewTitle = "Draft PRD v2"

    /// Preview on or off (board A2): the file the open template would make, read-only, over it.
    public func toggleTemplatePreview() {
        guard let e = editorIfLoaded else { return }
        if e.previewing { e.endPreview(); return }
        e.currentText { [weak self, weak e] text in
            guard let self, let e, let text else { return }
            e.startPreview(self.previewTemplate(text, title: Self.previewTitle))
        }
    }
}
