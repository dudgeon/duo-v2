import SwiftUI

// Inside a project (handoff §3.3). Targets: screens/project.html, flow-zoom-2.html, flow-zoom-3.html.

// MARK: - Left: sessions over files

struct ProjectSidebarPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let project = model.currentProject
        let rows = project.map { SidebarRow.rows(for: $0.name, in: model.fixture) } ?? []
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let project {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(project.name).duoText(.title).lineLimit(1)
                            Text([project.health, project.next].compactMap { $0 }.joined(separator: " · "))
                                .duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1)
                        }
                        .padding(EdgeInsets(top: 14, leading: DuoSpace.panePadding, bottom: 4, trailing: DuoSpace.panePadding))
                    }
                    ForEach(SessionState.allCases, id: \.self) { state in
                        let section = rows.filter { $0.state == state }
                        if !section.isEmpty {
                            SectionLabel(text: state.sectionTitle, count: section.count, needsYou: state == .needsYou)
                                .padding(EdgeInsets(top: 12, leading: DuoSpace.panePadding, bottom: 4, trailing: DuoSpace.panePadding))
                            ForEach(section) { row in SidebarRowView(row: row) }
                        }
                    }
                    HStack(spacing: DuoSpace.gapButtonToButton) {
                        Button("+ New session") { model.newSession() }.buttonStyle(.duo)
                    }
                    .padding(.horizontal, DuoSpace.panePadding)
                    .padding(.vertical, 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            FileTreePane()
        }
        .foregroundStyle(DuoColor.text)
        .background(DuoColor.pane)
    }
}

extension SessionState {
    var sectionTitle: String {
        switch self {
        case .needsYou: "Needs you"
        case .readyForReview: "Ready for review"
        case .working: "Working"
        case .idle: "Idle"
        case .resolved: "Resolved"
        }
    }
}

/// One row: group (28), thread or session (26). Groups expand to their threads under a rule.
struct SidebarRowView: View {
    @Environment(AppModel.self) private var model
    let row: SidebarRow

    var body: some View {
        switch row.kind {
        case .group(let threads, let count):
            let expanded = model.expandedGroups.contains(row.name)
            let selected = model.selectedSidebarItem == row.name
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DuoSpace.gapRowItems) {
                    Chevron(direction: expanded ? .down : .right).frame(width: 10)
                        .contentShape(Rectangle())
                        .onActivate {
                            if expanded { model.expandedGroups.remove(row.name) } else { model.expandedGroups.insert(row.name) }
                        }
                        .accessibilityLabel(expanded ? "Collapse" : "Expand")
                    StateGlyph(row.state)
                    Text(row.name).duoText(.bodyEmphasis).lineLimit(1)
                    CountPill(text: "group · \(count)", emphasised: true)
                    Spacer(minLength: 8)
                    WaitLabel(text: row.wait)
                }
                .padding(.horizontal, 8)
                .frame(height: DuoMetric.rowGroup)
                .background {
                    if selected { RoundedRectangle(cornerRadius: DuoMetric.radiusSelection).fill(DuoColor.selected) }
                }
                .padding(.horizontal, DuoSpace.selectionInset)
                .contentShape(Rectangle())
                .onActivate { model.selectedSidebarItem = row.name; model.rightTab = row.name }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(row.name), group of \(count), \(row.state.spokenName)")
                .accessibilityAddTraits(selected ? .isSelected : [])

                if expanded {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(threads) { t in SidebarLeafRow(row: t, nested: true) }
                    }
                    .overlay(alignment: .leading) {
                        DuoColor.controlEdge.frame(width: DuoMetric.borderEmphasis)
                    }
                    .padding(.leading, DuoSpace.threadRuleX)
                }
            }
        case .thread, .session:
            SidebarLeafRow(row: row, nested: false)
        }
    }
}

/// A thread or session row, 26 high: chevron (threads) or a 10 pt spacer, glyph, name, pill, wait.
struct SidebarLeafRow: View {
    @Environment(AppModel.self) private var model
    let row: SidebarRow
    let nested: Bool

    var body: some View {
        HStack(spacing: DuoSpace.gapRowItems) {
            Group {
                if case .thread = row.kind { Chevron(direction: .right) } else { Color.clear }
            }
            .frame(width: 10, height: 10)
            StateGlyph(row.state)
            Text(row.name).duoText(.body).lineLimit(1)
            if case .thread(let n) = row.kind { CountPill(text: "thread · \(n)", emphasised: false) }
            Spacer(minLength: 8)
            WaitLabel(text: row.wait)
        }
        // Nested rows sit 11 pt from the group's rule (which is 1.5 wide at x 21).
        .padding(.leading, nested ? 11 + DuoMetric.borderEmphasis : DuoSpace.panePadding)
        .padding(.trailing, DuoSpace.panePadding)
        .frame(height: DuoMetric.rowSession)
        .contentShape(Rectangle())
        .onActivate { model.openConsoleTab(row.name) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.name), \(row.state.spokenName)\(row.wait.map { ", waiting \($0)" } ?? "")")
    }
}

/// `group · n` and `thread · n` (handoff §5 `CountPill`).
struct CountPill: View {
    let text: String
    let emphasised: Bool

    var body: some View {
        Text(text)
            .duoText(.pill)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7 + DuoMetric.borderHairline)
            .padding(.vertical, DuoMetric.borderHairline)
            .background(Capsule().fill(emphasised ? DuoColor.pane : Color.clear))
            .overlay(Capsule().strokeBorder(emphasised ? DuoColor.controlEdge : DuoColor.rule, lineWidth: DuoMetric.borderHairline))
    }
}

/// Files, pinned to the bottom of the left pane under a 2 pt rule: a tree rooted in the
/// project's folder (handoff §3.3). Fixture mode lists the fixture's files; Phase E reads the
/// real folder.
struct FileTreePane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let project = model.currentProject
        let files = project.flatMap { model.fixture.projectFiles[$0.name] } ?? []
        let tree = FileNode.tree(from: files)
        VStack(alignment: .leading, spacing: 0) {
            DuoColor.controlEdge.frame(height: DuoMetric.borderFilesDivider)
            SectionLabel(text: "Files")
                .padding(EdgeInsets(top: 12, leading: DuoSpace.panePadding, bottom: 0, trailing: DuoSpace.panePadding))
            Text(project?.path ?? "")
                .duoText(.monoPath)
                .foregroundStyle(DuoColor.text2)
                .lineLimit(1)
                .padding(EdgeInsets(top: 0, leading: DuoSpace.panePadding, bottom: 6, trailing: DuoSpace.panePadding))
            ForEach(tree) { node in FileRow(node: node, depth: 0) }
        }
        .padding(.bottom, 12)
        .contentShape(Rectangle())
        .modifier(LiveContextMenu { NewItemsMenu(near: nil) })
    }
}

struct FileNode: Identifiable, Equatable {
    var name: String
    var path: String
    var children: [FileNode]?
    var id: String { path }

    /// A tree from relative paths, folders first, then files, each alphabetical.
    static func tree(from paths: [String]) -> [FileNode] {
        var root: [FileNode] = []
        for path in paths {
            var parts = path.split(separator: "/").map(String.init)
            if path.hasSuffix("/"), let last = parts.popLast() { parts.append(last + "/") }
            insert(parts, prefix: "", into: &root)
        }
        return sorted(root)
    }

    private static func insert(_ parts: [String], prefix: String, into nodes: inout [FileNode]) {
        guard let head = parts.first else { return }
        let path = prefix.isEmpty ? head : "\(prefix)/\(head)"
        // "folder/" (live snapshot) is a folder, even an empty one.
        if parts.count == 1, head.hasSuffix("/") {
            let name = String(head.dropLast()), folderPath = String(path.dropLast())
            if !nodes.contains(where: { $0.name == name && $0.children != nil }) {
                nodes.append(FileNode(name: name, path: folderPath, children: []))
            }
            return
        }
        if parts.count == 1 {
            nodes.append(FileNode(name: head, path: path, children: nil))
            return
        }
        if let i = nodes.firstIndex(where: { $0.name == head && $0.children != nil }) {
            insert(Array(parts.dropFirst()), prefix: path, into: &nodes[i].children!)
        } else {
            var folder = FileNode(name: head, path: path, children: [])
            insert(Array(parts.dropFirst()), prefix: path, into: &folder.children!)
            nodes.append(folder)
        }
    }

    private static func sorted(_ nodes: [FileNode]) -> [FileNode] {
        nodes.map { n in var n = n; n.children = n.children.map(sorted); return n }
            .sorted { a, b in
                (a.children == nil) != (b.children == nil)
                    ? a.children == nil   // the target lists PROJECT.md before docs/
                    : a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }
}

struct FileRow: View {
    @Environment(AppModel.self) private var model
    let node: FileNode
    let depth: Int

    var body: some View {
        let selected = model.selectedFile == node.path
        let edited = model.fixture.focusDocument.path == node.path
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: node.children == nil ? DuoSpace.gapRowItems : DuoSpace.gapGlyphToLabel) {
                if node.children != nil { Chevron(direction: .down) }
                if model.renamingPath == node.path {
                    InlineNameField(name: node.name) { new in
                        if let new { model.commitRename(node.path, to: new) } else { model.renamingPath = nil }
                    }
                    .frame(height: 18)
                } else {
                    Text(node.children == nil ? node.name : "\(node.name)/")
                        .duoText(selected ? .monoActiveTab : .mono)
                        .lineLimit(1)
                }
                if edited {
                    Spacer(minLength: 8)
                    Text("edited by Claude").font(.system(size: 12)).lineHeight(.exact(points: 20)).offset(y: 2)
                        .foregroundStyle(DuoColor.text2).fixedSize()
                }
            }
            // Nested rows: text at 26 pt inside the 8 pt selection inset, as the target draws them.
            .padding(.leading, CGFloat(depth) * (26 - 8))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: DuoMetric.rowFile)
            .background {
                if selected { RoundedRectangle(cornerRadius: DuoMetric.radiusSelection).fill(DuoColor.selected) }
            }
            .padding(.horizontal, DuoSpace.selectionInset)
            .contentShape(Rectangle())
            .onActivate { if node.children == nil { model.openDocument(node.path) } }
            .modifier(LiveContextMenu { FileMenu(path: node.path, isFolder: node.children != nil, onTab: false) })
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? .isSelected : [])
            if let children = node.children {
                ForEach(children) { c in FileRow(node: c, depth: depth + 1) }
            }
        }
    }
}

// MARK: - Middle: console

/// The console: a tab per open session in this project, over the terminal (Phase D).
struct ConsolePane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let tabs = model.currentProject.map { model.tabSessions(inProject: $0.name) } ?? []
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                ForEach(tabs) { s in
                    let active = s.tabKey == model.consoleTab
                    HStack(spacing: DuoSpace.gapGlyphToLabel) {
                        StateGlyph(s.state, on: .console(active: active))
                        Text(s.name)
                            .duoText(active ? .monoActiveTab : .mono)
                            .foregroundStyle(active ? DuoColor.consoleText : DuoColor.consoleText2)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .onActivate { model.openConsoleTab(s.tabKey) }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
                }
                Text("+").duoText(.mono).foregroundStyle(DuoColor.consoleText2)
                    .onActivate { model.newSession() }
                    .accessibilityLabel("New session")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DuoSpace.panePadding)
            .frame(height: DuoMetric.tabStripHeight)
            ConsoleRule()
            if let project = model.currentProject, let tab = model.consoleTab,
               let t = model.terminal(project: project.name, session: tab) {
                TerminalSlot(session: t)
            } else {
                Color.clear
            }
        }
        .background(DuoColor.console)
    }
}

// MARK: - Right: Project · group pages · documents

struct RightPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let tabs = rightTabs
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DuoSpace.gapPaneTabs) {
                ForEach(tabs, id: \.id) { tab in
                    let active = tab.id == model.rightTab
                    Text(tab.title)
                        .duoText(active ? .bodyEmphasis : .body)
                        .foregroundStyle(active ? DuoColor.text : DuoColor.text2)
                        .lineLimit(1)
                        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
                        .onActivate { model.rightTab = tab.id; if tab.isDocument { model.selectedFile = tab.id } }
                        .modifier(LiveContextMenu(enabled: tab.isDocument) {
                            Button("Close Tab") { model.closeDocument(tab.id) }
                            Button("Close Other Tabs") { model.closeOtherDocuments(than: tab.id) }
                            Divider()
                            FileMenu(path: tab.id, isFolder: false, onTab: true)
                        })
                }
                // New Markdown file, the same treatment as the console's + (DL-61).
                if model.terminalsMode == .live, model.projectFolder != nil {
                    Text("+").duoText(.body).foregroundStyle(DuoColor.text2)
                        .onActivate { model.newMarkdownFile(near: model.selectedFile) }
                        .accessibilityLabel("New Markdown file")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(height: DuoMetric.tabStripHeight)
            DuoColor.rule.frame(height: 1)
            if let path = model.rightTab, path.contains("."), let file = model.liveFile(path) {
                DocumentEditorView(editor: model.editor, file: file)
            } else if model.rightTab == "Project" || model.rightTab == nil, let own = model.projectFile, let file = model.liveFile(own) {
                // The Project tab is the project's own file (DL-60).
                DocumentEditorView(editor: model.editor, file: file)
            } else if let path = model.rightTab, path.contains(".") {
                DocumentPlaceholder(path: path)
            } else {
                // Fixture mode: the Project tab isn't designed in the final look (handoff §3.5).
                Color.clear
            }
        }
        .foregroundStyle(DuoColor.text)
        .background(DuoColor.pane)
    }

    private var rightTabs: [(id: String, title: String, isDocument: Bool)] {
        var tabs: [(id: String, title: String, isDocument: Bool)] = [(id: "Project", title: "Project", isDocument: false)]
        if let group = model.selectedSidebarItem, model.fixture.groups.contains(where: { $0.name == group }) {
            tabs.append((id: group, title: group, isDocument: false))
        }
        for doc in model.openDocuments where doc != model.projectFile {
            tabs.append((id: doc, title: (doc as NSString).lastPathComponent, isDocument: true))
        }
        // Fixture mode keeps its single document tab (the targets).
        if let doc = model.rightTab, doc.contains("."), !tabs.contains(where: { $0.id == doc }), doc != model.projectFile {
            tabs.append((id: doc, title: (doc as NSString).lastPathComponent, isDocument: true))
        }
        return tabs
    }
}

/// The "new" verbs: for the tree's background, folders and files (DL-61).
struct NewItemsMenu: View {
    @Environment(AppModel.self) private var model
    let near: String?

    var body: some View {
        Button("New Markdown File") { model.newMarkdownFile(near: near) }
        Button("New Folder") { model.newFolder(near: near) }
        Menu("New from Template") {
            let templates = model.templates
            if templates.isEmpty {
                Button("No templates yet: add .md files to a templates folder") {}.disabled(true)
            }
            ForEach(templates, id: \.self) { t in
                Button(t.deletingPathExtension().lastPathComponent) { model.newFromTemplate(t, near: near) }
            }
        }
    }
}

/// Everything you can do with a file or folder: the tree's right-click menu and document tabs
/// show the same verbs (DL-61).
struct FileMenu: View {
    @Environment(AppModel.self) private var model
    let path: String
    let isFolder: Bool
    let onTab: Bool

    var body: some View {
        if !isFolder && !onTab { Button("Open") { model.openDocument(path) } }
        if !isFolder {
            Menu("Open With") {
                if let url = model.projectFolder?.appending(path: path) {
                    ForEach(Array(FileActions.apps(for: url).enumerated()), id: \.offset) { i, app in
                        Button(FileManager.default.displayName(atPath: app.path) + (i == 0 ? " (default)" : "")) {
                            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                        }
                    }
                    Divider()
                }
                Button("Other…") { model.openWithChosenApp(path) }
            }
        }
        Button("Reveal in Finder") { model.reveal(path) }
        Divider()
        Button("Copy Path") { model.copyPath(path, relative: false) }
        Button("Copy Relative Path") { model.copyPath(path, relative: true) }
        if !isFolder { Button("Copy as Link") { model.copyLink(path) } }
        Button("Send to Claude") { model.sendToClaude(path) }.disabled(model.consoleTerminal == nil)
        Divider()
        NewItemsMenu(near: path)
        Divider()
        Button("Rename") { model.renamingPath = path }.disabled(onTab && !model.isInTree(path))
        Button("Duplicate") { model.duplicate(path) }
        Button("Move To…") { model.moveToFolder(path) }
        Divider()
        Button("Move to Trash") { model.moveToTrash(path) }
    }
}

/// Inline naming in the tree, like Finder (DL-62): the name is selected without its extension;
/// Return confirms, Esc cancels.
struct InlineNameField: NSViewRepresentable {
    let name: String
    let done: (String?) -> Void

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField(string: name)
        f.font = NSFont.monospacedSystemFont(ofSize: DuoTextStyle.mono.spec.size, weight: .regular)
        f.focusRingType = .none
        f.isBezeled = false
        f.drawsBackground = true
        f.backgroundColor = DuoNSColor.pane
        f.delegate = context.coordinator
        DispatchQueue.main.async {
            f.window?.makeFirstResponder(f)
            let stem = (name as NSString).deletingPathExtension
            f.currentEditor()?.selectedRange = NSRange(location: 0, length: (stem as NSString).length)
        }
        return f
    }

    func updateNSView(_ f: NSTextField, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let done: (String?) -> Void
        var finished = false
        init(done: @escaping (String?) -> Void) { self.done = done }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) { finish(nil); return true }
            if selector == #selector(NSResponder.insertNewline(_:)) { finish(control.stringValue); return true }
            return false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            if let f = obj.object as? NSTextField { finish(f.stringValue) }  // clicking away confirms, like Finder
        }

        private func finish(_ value: String?) {
            guard !finished else { return }
            finished = true
            done(value)
        }
    }
}

/// Stands in for the CodeMirror editor (Phase I): section headings, and the "added by Claude"
/// block (LR-33, DL-5). The targets' grey bars are placeholders and aren't drawn (§0.4).
struct DocumentPlaceholder: View {
    @Environment(AppModel.self) private var model
    let path: String

    var body: some View {
        let doc = model.fixture.focusDocument
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if doc.path == path {
                    ForEach(Array(doc.sections.enumerated()), id: \.element) { i, section in
                        if doc.addedByClaude.contains(section) {
                            HStack(alignment: .firstTextBaseline, spacing: DuoSpace.gapRowItems) {
                                Text(section).duoText(.title)
                                Text("added by Claude").duoText(.body).foregroundStyle(DuoColor.text2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12))
                            .background(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).fill(DuoColor.selected))
                            .padding(.horizontal, -12)
                            .padding(.top, 8)
                        } else {
                            Text(section).duoText(.title).padding(.top, i == 0 ? 0 : 10)
                        }
                    }
                }
            }
            .padding(DuoSpace.documentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A context menu only in live mode: the file verbs act on real folders, and fixture mode has none.
struct LiveContextMenu<Items: View>: ViewModifier {
    @Environment(AppModel.self) private var model
    var enabled = true
    @ViewBuilder let items: () -> Items

    func body(content: Content) -> some View {
        if enabled && model.terminalsMode == .live { content.contextMenu { items() } } else { content }
    }
}
