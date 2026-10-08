import SwiftUI

// Inside a project (handoff §3.3). Targets: screens/project.html, flow-zoom-2.html, flow-zoom-3.html.

// MARK: - Left: sessions over files

struct ProjectSidebarPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let project = model.currentProject
        let sections = model.sidebarSections()
        let items = SidebarItem.items(sections)
        let movers = model.sidebarMovers(sections)
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let project {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(project.name).duoText(.title).lineLimit(1)
                            // A folder says what it is where a project shows its health and next step, as its tile does (DL-110).
                            Text(project.kind == "folder" ? (project.hasClaudeMD == true ? "Has CLAUDE.md · no project file" : "Folder · no project file")
                                 : [project.health, project.next].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                .duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1)
                        }
                        .padding(EdgeInsets(top: 14, leading: DuoSpace.panePadding, bottom: 4, trailing: DuoSpace.panePadding))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        // The project's heading opens the project itself: its Project tab (DL-60).
                        .onActivate { model.rightTab = "Project"; model.selectedFile = nil }  // action: view tab
                        .accessibilityLabel("\(project.name), open the project file")
                        if project.isMissing { MissingNotice(project: project) }
                        else if project.kind == "folder", project.notNow != true { FolderNotice(project: project) }
                    }
                    // Needs you, Open, then history by date, then the folds (DL-91). One flat list, so a
                    // row keeps its identity when it changes section and travels there (DL-130):
                    // `rowMove`; a new row fades in (`rowIn`), a row that goes fades out (`rowOut`).
                    // Each item is opaque on the pane, and a row changing section travels above the rows
                    // it passes, so no text overprints mid-move.
                    ForEach(items) { item in
                        switch item.kind {
                        case .label(let section):
                            SectionLabel(text: section.title, count: section.id == "needs" || section.id == "open" ? section.rows.count : nil,
                                         needsYou: section.needsYou)
                                .padding(EdgeInsets(top: 12, leading: DuoSpace.panePadding, bottom: 4, trailing: DuoSpace.panePadding))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(DuoColor.pane)
                        case .gap:
                            Color.clear.frame(height: 8)
                        case .row(let row):
                            SidebarRowView(row: row)
                                .background(DuoColor.pane)
                                .zIndex(movers.contains(row.id) ? 1 : 0)
                                .transition(.listRow)
                        }
                    }
                    .onChange(of: items.map(\.id), initial: true) { model.noteSidebar(sections) }
                    if let project, model.terminalsMode == .live { TasksFold(project: project.name) }
                    if let project { ArchivedSessionsFold(project: project.name) }
                    HStack(spacing: DuoSpace.gapButtonToButton) {
                        Button("+ New session") { model.newSession() }.buttonStyle(.duo)
                        if let project, model.terminalsMode == .live {
                            Button("+ New task") { model.newTask(in: project.name) }.buttonStyle(.duo)
                        }
                    }
                    .padding(.horizontal, DuoSpace.panePadding)
                    .padding(.vertical, 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Everything under a row that moves goes with it, the buttons and folds too.
                .duoAnimation(.rowMove, value: items.map(\.id))
                // Another project is another list: it replaces this one at once, rather than its
                // rows fading in over these (DL-130).
                .id(project?.name)
            }
            .onHover { model.hoverSidebar($0) }
            FileTreePane()
        }
        .foregroundStyle(DuoColor.text)
        .background(DuoColor.pane)
    }
}

/// The session list flattened: section labels, gaps and rows in one run, keyed so a row is the
/// same view in whichever section it sits (DL-130).
struct SidebarItem: Identifiable {
    enum Kind { case label(SidebarSection), gap, row(SidebarRow) }
    let id: String
    let kind: Kind

    static func items(_ sections: [SidebarSection]) -> [SidebarItem] {
        sections.flatMap { s -> [SidebarItem] in
            let head = SidebarItem(id: "section/\(s.id)", kind: s.title.isEmpty ? .gap : .label(s))
            return [head] + s.rows.map { SidebarItem(id: "row/\($0.id)", kind: .row($0)) }
        }
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
        case .older(let rows):
            let expanded = model.expandedGroups.contains(row.id)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DuoSpace.gapRowItems) {
                    Chevron(direction: expanded ? .down : .right).frame(width: 10)
                    Text("\(row.name) · \(rows.count)").duoText(.body).foregroundStyle(DuoColor.text2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8 + DuoSpace.selectionInset)
                .frame(height: DuoMetric.rowGroup)
                .contentShape(Rectangle())
                .onActivate { withDuoAnimation(.fold) { if expanded { model.expandedGroups.remove(row.id) } else { model.expandedGroups.insert(row.id) } } }  // action: view group
                .accessibilityLabel(expanded ? "Hide \(row.name.lowercased()) sessions" : "Show \(rows.count) \(row.name.lowercased()) sessions")
                if expanded { ForEach(rows) { r in SidebarLeafRow(row: r, nested: false) }.transition(.foldRows) }
            }
        case .group(let threads, let count):
            let expanded = model.expandedGroups.contains(row.name)
            let selected = model.selectedSidebarItem == row.name
            // A task row under the pointer (DL-132 a, standins2-handoff q46-hover): the selected fill,
            // its status kept whole and the + after it; the name gives way instead.
            let hovered = row.task.map { task in model.terminalsMode == .live && model.currentProject.map { model.hoveredTaskRow == TaskRowHover.key(project: $0.name, path: task) } == true } ?? false
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DuoSpace.gapRowItems) {
                    Chevron(direction: expanded ? .down : .right).frame(width: 10)
                        .contentShape(Rectangle())
                        .onActivate {  // action: view group
                            withDuoAnimation(.fold) { if expanded { model.expandedGroups.remove(row.name) } else { model.expandedGroups.insert(row.name) } }
                        }
                        .accessibilityLabel(expanded ? "Collapse" : "Expand")
                    StateGlyph(row.state)
                    // A task leads with its box and reads "status · n"; a group keeps its pill (DL-100).
                    if row.task != nil { TaskBox(color: DuoColor.text) }
                    Text(row.name).duoText(.bodyEmphasis).lineLimit(1).layoutPriority(1)   // the name keeps its room; status gives way, except under the pointer (fixed below)
                    if let task = row.task {
                        let st = model.fixture.tasks?.first(where: { $0.path == task && $0.project == model.currentProject?.name })?.status ?? "open"
                        Text(st == "open" ? "\(count) session\(count == 1 ? "" : "s")" : "\(st.replacingOccurrences(of: "-", with: " ")) · \(count)")
                            .duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1)
                            .fixedSize(horizontal: hovered, vertical: false).layoutPriority(hovered ? 0 : -1)
                    } else {
                        CountPill(text: "group · \(count)", emphasised: true)
                    }
                    Spacer(minLength: 8)
                    if hovered, let task = row.task, let project = model.currentProject?.name {
                        // On hover, the + after the status (DL-112, DL-132 a).
                        NewSessionInTaskButton(project: project, path: task)
                    } else {
                        // A task row has no wait of its own: its sessions show theirs (S2-1).
                        WaitLabel(text: row.task == nil ? row.wait : nil)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: DuoMetric.rowGroup)
                .background {
                    if selected || hovered { RoundedRectangle(cornerRadius: DuoMetric.radiusSelection).fill(DuoColor.selected) }
                }
                .padding(.horizontal, DuoSpace.selectionInset)
                .contentShape(Rectangle())
                .onActivate {  // action: view tab
                    model.selectedSidebarItem = row.name
                    // A task row opens its note; a group row its group tab.
                    if let task = row.task { model.openDocument(task) } else { model.rightTab = row.name }
                }
                .modifier(GroupRowMenu(name: row.name, task: row.task))
                .modifier(TaskRowHover(key: row.task.map { TaskRowHover.key(project: model.currentProject?.name ?? "", path: $0) } ?? ""))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(row.name), \(row.task == nil ? "group" : "task") of \(count), \(row.state.spokenName)")
                .accessibilityAddTraits(selected ? .isSelected : [])

                if expanded {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(threads) { t in SidebarLeafRow(row: t, nested: true) }
                    }
                    .overlay(alignment: .leading) {
                        DuoColor.controlEdge.frame(width: DuoMetric.borderEmphasis)
                    }
                    .padding(.leading, DuoSpace.threadRuleX)
                    .transition(.foldRows)
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
            // Open in Duo (DL-91): say what it's doing rather than how long ago.
            WaitLabel(text: row.state.waitText(row.wait, open: model.hasOpenTerminal(row.sessionKey)))
        }
        // Nested rows sit 11 pt from the group's rule (which is 1.5 wide at x 21).
        .padding(.leading, nested ? 11 + DuoMetric.borderEmphasis : DuoSpace.panePadding)
        .padding(.trailing, DuoSpace.panePadding)
        .frame(height: DuoMetric.rowSession)
        // A terminal is open for it in Duo (ENH-7). The selected row's own fill is drawn by the list.
        .background { if model.hasOpenTerminal(row.sessionKey) { DuoColor.activeTint } }
        .contentShape(Rectangle())
        .onActivate { model.openConsoleTab(row.sessionKey) }  // action: session open
        .modifier(SessionOrganizeMenu(sessionKey: row.sessionKey))
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
        // Files dropped on the empty area go to the project root (DL-117).
        .background {
            if model.treeDropTarget == "" { DropHighlight(radius: DuoMetric.radiusCard).padding(.horizontal, DuoSpace.selectionInset).padding(.top, DuoMetric.borderFilesDivider + 4) }
        }
        // A drop target lights up (`dropIn`, DL-130).
        .duoAnimation(.dropIn, value: model.treeDropTarget == "")
        .modifier(TakesFileDrops(target: ""))
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
            let open = node.children != nil && model.isFolderOpen(node.path)
            HStack(spacing: node.children == nil ? DuoSpace.gapRowItems : DuoSpace.gapGlyphToLabel) {
                if node.children != nil { Chevron(direction: open ? .down : .right) }
                if model.renamingPath == node.path {
                    InlineNameField(name: node.name) { new in
                        if let new { model.commitRename(node.path, to: new) } else { model.renamingPath = nil }
                    }
                    .frame(height: 18)
                } else {
                    Text(node.children == nil ? node.name : "\(node.name)/")
                        .duoText(selected ? .monoActiveTab : .mono)
                        // Hidden files, when shown, are quieter (DL-105).
                        .foregroundStyle(node.path.split(separator: "/").contains { $0.hasPrefix(".") } ? DuoColor.text2 : DuoColor.text)
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
                if node.children != nil && model.treeDropTarget == node.path { DropHighlight() }
                else if selected { RoundedRectangle(cornerRadius: DuoMetric.radiusSelection).fill(DuoColor.selected) }
            }
            .duoAnimation(.dropIn, value: model.treeDropTarget == node.path)   // the drop target lights up (DL-130)
            .padding(.horizontal, DuoSpace.selectionInset)
            .contentShape(Rectangle())
            .onActivate { if node.children == nil { model.openDocument(node.path) } else { withDuoAnimation(.fold) { model.toggleFolder(node.path) } } }  // action: doc open
            .modifier(LiveContextMenu { FileMenu(path: node.path, isFolder: node.children != nil, onTab: false) })
            // Drag the file out (a terminal types its path); drop files on a folder, or on a file for its folder (DL-117).
            .modifier(DragsFile(path: node.path, name: node.name))
            .modifier(TakesFileDrops(target: node.children != nil ? node.path : (node.path as NSString).deletingLastPathComponent))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? .isSelected : [])
            if let children = node.children, open {
                ForEach(children) { c in FileRow(node: c, depth: depth + 1) }.transition(.foldRows)
            }
        }
    }
}

// MARK: - Middle: console

/// The console: a tab per open session in this project, over the terminal (Phase D).
struct ConsolePane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ConsoleTabStrip(project: model.currentProject?.name)
            // Under the thin light strip over chat, the light chrome's rule (DL-136).
            if model.consoleShowsChat { DuoColor.rule.frame(height: DuoMetric.borderHairline) } else { ConsoleRule() }
            let _ = model.endedRevision
            if let ended = model.fixtureEnded, model.consoleTab == ended.key {
                Color.clear
                ConsoleEndedBar(key: ended.key, message: ended.message)
            } else if let tab = model.consoleTab, let chat = model.fixtureChats[tab] {
                // Fixture mode: a chat-mode target (ChatTargets), drawn from recorded hooks and screens.
                ConsoleChatBody(chat: chat, terminal: nil)
            } else if let project = model.currentProject, let tab = model.consoleTab, model.fixtureConsole == nil,
               let t = model.terminal(project: project.name, session: tab), !t.missingClaude {
                if let chat = model.chats.existing(t.key) {
                    ConsoleChatBody(chat: chat, terminal: t)
                } else {
                    TerminalSlot(session: t)
                }
                if t.ended != nil { ConsoleEndedBar(session: t, name: model.consoleTitle(t.key)) }
                Color.clear.frame(height: 0).task(id: t.key) { model.attachChat(t) }
            } else if let project = model.currentProject, model.terminalsMode == .live || model.fixtureConsole != nil,
                      let empty = model.consoleEmpty(project: project.name) {
                ConsoleMessage(state: empty)
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
            // Spacing is laid out by hand so a document tab's × (DL-126) sits in the gap before its
            // title: the gap is the 1 left over, the × box and the 1 before the title.
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { i, tab in
                    let active = tab.id == model.rightTab
                    // A document waiting in conflict says so on its tab (S3-4).
                    let conflicted = !active && tab.isDocument && (model.liveFile(tab.id).map { model.editorIfLoaded?.keptInConflict($0) == true } ?? false)
                    let closeSlot = tab.isDocument ? DuoMetric.tabCloseSize + DuoMetric.tabCloseTitleGap : 0
                    let outside = AppModel.isOutsideFile(tab.id)
                    let opener = model.webTabs[tab.id]?.opener.flatMap { o in tabs.first(where: { $0.id == o })?.title }   // gone with its opener
                    HStack(spacing: DuoMetric.tabCloseTitleGap) {
                        if tab.isDocument {
                            if model.showsTabClose(tab.id) {
                                TabCloseButton(key: tab.id, onConsole: false, active: active) { model.closeDocument(tab.id) }  // action: doc close
                            } else {
                                Color.clear.frame(width: DuoMetric.tabCloseSize, height: DuoMetric.tabCloseSize)
                            }
                        }
                        // A popup's tab leads with ↳ (DL-132 i, standins2-handoff q67-popup).
                        if opener != nil { Text("↳").duoText(.body).foregroundStyle(DuoColor.text2).padding(.trailing, 3) }
                        Text("\(Text(tab.title).foregroundStyle(active ? DuoColor.text : DuoColor.text2))\(conflicted ? Text(" · conflict").foregroundStyle(DuoColor.text) : Text(""))")
                            .duoText(active ? .bodyEmphasis : .body)
                            .lineLimit(1)
                        // A file outside the project shows its folder under the pointer (DL-132 f, q39-hover).
                        if outside, model.showsTabClose(tab.id) {
                            Text(AppModel.short(URL(fileURLWithPath: String(tab.id.dropFirst(AppModel.outsideFilePrefix.count))).deletingLastPathComponent().path))
                                .duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1).truncationMode(.head)
                                .padding(.leading, DuoSpace.gapGlyphToLabel - DuoMetric.tabCloseTitleGap)
                        }
                    }
                        .modifier(TabHoverFill(key: tab.id, onConsole: false, leading: 3))   // 3 past the × box, as drawn (DL-134)
                        .padding(.leading, (i == 0 ? 0 : DuoSpace.gapPaneTabs) - closeSlot)
                        .contentShape(Rectangle())
                        .modifier(TabHover(key: tab.id, enabled: tab.isDocument) { model.closeDocument(tab.id) })
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
                        // A file outside the project: its path is the tooltip (DL-106); a popup: its opener (DL-132 i).
                        .help(outside ? String(tab.id.dropFirst(AppModel.outsideFilePrefix.count)) : opener.map { "Opened from \($0)" } ?? "")
                        .onActivate { model.rightTab = tab.id; if tab.isDocument { model.selectedFile = tab.id } }  // action: view tab
                        .modifier(LiveContextMenu(enabled: tab.isDocument) {
                            Button("Close Tab") { model.closeDocument(tab.id) }
                            Button("Close Other Tabs") { model.closeOtherDocuments(than: tab.id) }
                            Divider()
                            if let web = model.webTabs[tab.id] {
                                Button("Open in Browser") { if let u = web.url { NSWorkspace.shared.open(u) } }
                                Button("Copy Address") { if let u = web.url { FileActions.copy(u.absoluteString) } }
                            } else {
                                FileMenu(path: tab.id, isFolder: false, onTab: true)
                            }
                        })
                        .background(DuoColor.pane)
                        .zIndex(model.showsTabClose(tab.id) ? 1 : 0)   // its fill reaches over the next tab's padding (DL-134)
                        .transition(.tab)
                }
                // New Markdown file, the same treatment as the console's + (DL-61).
                if model.terminalsMode == .live, model.projectFolder != nil {
                    Text("+").duoText(.body).foregroundStyle(DuoColor.text2)
                        .padding(.leading, tabs.isEmpty ? 0 : DuoSpace.gapPaneTabs)
                        .onActivate { model.newMarkdownFile(near: model.selectedFile) }  // action: file new
                        // Right-click + for the other new tabs (ENH-8).
                        .contextMenu {
                            Button("New Markdown File") { model.newMarkdownFile(near: model.selectedFile) }
                            Button("New Browser Tab") { model.newBrowserTab() }
                        }
                        .accessibilityLabel("New Markdown file")
                        .background(DuoColor.pane)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(height: DuoMetric.tabStripHeight)
            .duoAnimation(.tabMove, value: tabs.map(\.id))
            .id(model.currentProject?.name)   // another project's tabs replace these at once
            DuoColor.rule.frame(height: 1)
            if let id = model.rightTab, let web = model.webTabs[id] {
                // A browser tab (Phase K, ENH-8): allowed sites in Duo, the rest in the browser (DL-3).
                ZStack(alignment: .bottom) {
                    BrowserTabView(tab: web)
                    PickerBar()
                }
            } else if model.rightTab == ReadOnlySession.tabKey, let ro = model.readOnlySession {
                ReadOnlySessionView(session: ro)
            } else if let path = model.rightTab, ["html", "htm"].contains((path as NSString).pathExtension.lowercased()),
               let file = model.liveFile(path),
               // An outside page reads from its own folder (DL-106); a project's from the project.
               let root = AppModel.isOutsideFile(path) ? file.deletingLastPathComponent() : model.projectFolder {
                // Local HTML, read-only and live (v1; DL-67): its own web view, with the element picker.
                ZStack(alignment: .bottom) {
                    HTMLViewerView(viewer: model.htmlViewer, file: file, root: root)
                    PickerBar()
                }
            } else if let path = model.rightTab, AppModel.isDeck(path), let file = model.liveFile(path) {
                // A PowerPoint deck: drawn, with its slide and the shape picker (DL-125).
                DeckView(viewer: model.deckViewer, path: path, file: file)
            } else if let path = model.rightTab, let file = model.liveFile(path), FileKind.isBinary(file) {
                // Never the editor for a file that isn't text (C-26): Quick Look, or a note (Q-52).
                BinaryFileView(path: path, file: file)
            } else if let path = model.rightTab, path.contains("."), let file = model.liveFile(path) ?? model.keptFile(path) {
                VStack(spacing: 0) {
                    DocumentStateBar()
                    // A template (DL-146): what it's for, Preview and Reset over it.
                    if let info = model.templateInfo(forFile: file) { TemplateBar(info: info) }
                    DocumentEditorView(editor: model.editor, file: file)
                }
                .modifier(NoticeMotion(key: DocumentStateBar.key(model)))
            } else if model.rightTab == "Project" || model.rightTab == nil, let own = model.projectFile, let file = model.liveFile(own) {
                // The Project tab is the project's own file (DL-60).
                VStack(spacing: 0) {
                    DocumentStateBar()
                    DocumentEditorView(editor: model.editor, file: file)
                }
                .modifier(NoticeMotion(key: DocumentStateBar.key(model)))
            } else if let path = model.rightTab, path.contains(".") {
                DocumentPlaceholder(path: path)
            } else if model.rightTab == "Project" || model.rightTab == nil, let p = model.currentProject, p.kind == "folder" {
                // A folder's Project tab offers to make it one, rather than a blank page (DL-110).
                FolderProjectTab(project: p)
            } else {
                // Fixture mode: the Project tab isn't designed in the final look (handoff §3.5).
                Color.clear
            }
        }
        .foregroundStyle(DuoColor.text)
        .background(DuoColor.pane)
        // Files dropped from Finder open as tabs here, from inside the project or anywhere (DL-106).
        .dropDestination(for: URL.self) { urls, _ in
            let opened = urls.filter(\.isFileURL).compactMap { model.openFile(at: $0) }
            return !opened.isEmpty
        }
    }

    private var rightTabs: [(id: String, title: String, isDocument: Bool)] {
        var tabs: [(id: String, title: String, isDocument: Bool)] = [(id: "Project", title: "Project", isDocument: false)]
        if let group = model.selectedSidebarItem, model.fixture.groups.contains(where: { $0.name == group }) {
            tabs.append((id: group, title: group, isDocument: false))
        }
        for doc in model.openDocuments where doc != model.projectFile {
            let title = model.webTabs[doc].map { $0.title }
                ?? model.templateInfo(forTab: doc).map { $0.kind == .task ? "Task template" : "Project template" }   // DL-146, board A1
                ?? (doc as NSString).lastPathComponent
            tabs.append((id: doc, title: title, isDocument: true))
        }
        if let ro = model.readOnlySession { tabs.append((id: ReadOnlySession.tabKey, title: ro.title, isDocument: false)) }
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
                if let url = model.fileURL(path) {
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
        // A file outside the project (DL-106) has no place in it: no relative path, link, new
        // items, rename, move or trash from here; Finder is a click away.
        let outside = AppModel.isOutsideFile(path)
        if !outside { Button("Copy Relative Path") { model.copyPath(path, relative: true) } }
        if !isFolder && !outside { Button("Copy as Link") { model.copyLink(path) } }
        SendMenu { key in model.filePayload(path, for: key) }
        if !isFolder && !outside { Button("Find Similar") { model.findSimilar(file: path) } }
        if !outside {
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
}

/// Inline naming in the tree, like Finder (DL-62): the name is selected without its extension;
/// Return confirms, Esc cancels.
struct InlineNameField: NSViewRepresentable {
    let name: String
    /// Another font and a placeholder (a board's Column name field, DL-150); the tree's mono otherwise.
    var font: NSFont? = nil
    var placeholder: String? = nil
    let done: (String?) -> Void

    func makeNSView(context: Context) -> NSTextField {
        let f = EscapableField(string: name)
        f.onEscape = { [weak coordinator = context.coordinator] in coordinator?.cancel() }
        f.font = font ?? NSFont.monospacedSystemFont(ofSize: DuoTextStyle.mono.spec.size, weight: .regular)
        f.placeholderString = placeholder
        f.focusRingType = .none
        f.isBezeled = false
        f.drawsBackground = true
        f.backgroundColor = DuoNSColor.pane
        f.delegate = context.coordinator
        f.selectStem = (name as NSString).deletingPathExtension
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

        func cancel() { finish(nil) }

        private func finish(_ value: String?) {
            guard !finished else { return }
            finished = true
            done(value)
        }
    }

    /// Takes Escape while editing: the window's SwiftUI host claimed it as a key equivalent
    /// before the field editor saw `cancelOperation`, so Escape never cancelled naming.
    final class EscapableField: NSTextField {
        var onEscape: (() -> Void)?
        /// Set until the field has taken focus with the name's stem selected. Focus is taken
        /// once the field is in a window: an async call from makeNSView could run before
        /// SwiftUI attached it, leaving typing in the terminal or editor.
        var selectStem: String?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, selectStem != nil else { return }
            DispatchQueue.main.async { [weak self] in self?.takeFocus() }
        }
        private func takeFocus() {
            guard let window, let stem = selectStem else { return }
            selectStem = nil
            window.makeFirstResponder(self)
            currentEditor()?.selectedRange = NSRange(location: 0, length: (stem as NSString).length)
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if event.keyCode == 53, currentEditor() != nil { onEscape?(); return true }
            return super.performKeyEquivalent(with: event)
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
                            let landed = model.searchLanding?.section == section
                            HStack(alignment: .firstTextBaseline, spacing: DuoSpace.gapRowItems) {
                                Text(section).duoText(.title)
                                Text("added by Claude").duoText(.body).foregroundStyle(DuoColor.text2)
                                if landed, let label = model.searchLanding?.label {
                                    Spacer(minLength: 8)
                                    Text(label).duoText(.body).foregroundStyle(DuoColor.text2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12))
                            .background(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).fill(DuoColor.selected))
                            // Opened from search: outlined in 1.5 text, apart from Claude's fill (search-open-file).
                            .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).strokeBorder(landed ? DuoColor.text : .clear, lineWidth: 1.5))
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

/// The element picker's bar (DL-70: plain system look until designed, Q-21). Shows while picking;
/// once an element is frozen it names it and offers Send to Claude, Send To, Pick Another, Cancel.
struct PickerBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.pickerRevision
        if let v = model.visiblePage, v.picking {
            VStack(alignment: .leading, spacing: 6) {
                if let e = v.picked {
                    Text("<\(e.label)>").font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 8) {
                        switch model.sendTarget {
                        case .success(let t): Button("Send to Claude") { model.sendPickedElement(to: t.key) }.keyboardShortcut(.defaultAction)
                        case .failure(let why): Button("Send to Claude") {}.disabled(true).help(why.reason)
                        }
                        Menu("Send To") {
                            let visible = (try? model.sendTarget.get())?.key
                            ForEach(model.sendTargets.filter { $0.key != visible }) { t in
                                Button(t.project.isEmpty ? t.title : "\(t.title) — \(t.project)") { model.sendPickedElement(to: t.key) }
                            }
                            Divider()
                            Button("New Session") { model.sendPickedElement(to: nil) }
                        }
                        .fixedSize()
                        Button("Pick Another") { v.pickAgain() }
                        Spacer(minLength: 0)
                        Button("Cancel") { v.stopPicking() }.keyboardShortcut(.cancelAction)
                    }
                    if case .failure(let why) = model.sendTarget {
                        Text("\(why.reason): use Send To.").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Text("Click an element to select it. Esc to stop.").font(.callout)
                        Spacer(minLength: 8)
                        Button("Cancel") { v.stopPicking() }.keyboardShortcut(.cancelAction)
                    }
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }
}

/// Over the document when it needs a decision or a word (S3-4, DL-77): a conflict, the file
/// removed or renamed on disk, or why it's read only. A bar under the tabs on `ground`.
struct DocumentStateBar: View {
    @Environment(AppModel.self) private var model

    /// Which bar shows, if any: the document's container animates on it (DL-130).
    static func key(_ model: AppModel) -> String? {
        let _ = model.editorRevision
        guard let e = model.editorIfLoaded, e.url != nil else { return nil }
        if e.conflict { return "conflict" }
        if e.removedOnDisk { return "removed" }
        if e.renamedTo != nil { return "renamed" }
        if e.readOnlyReason != nil { return "read-only" }
        if let tab = model.rightTab, model.conversions[tab] != nil { return "converted" }
        return nil
    }

    var body: some View {
        Group { bar }.transition(.notice)
    }

    @ViewBuilder var bar: some View {
        let _ = model.editorRevision
        if let e = model.editorIfLoaded, let file = e.url {
            if e.conflict {
                let lines = e.conflictLines.map { $0[0] == $0[1] ? "line \($0[0])" : "lines \($0[0])–\($0[1])" }.joined(separator: ", ")
                NoticeBar(text: "Changed on disk where you’re editing\(lines.isEmpty ? "" : " (\(lines))"). Both versions are kept.",
                          sub: "Saving is paused until you choose.") {
                    Button("Use Theirs") { e.resolve(keepMine: false) }.buttonStyle(.duo)
                    Button("Keep Mine") { e.resolve(keepMine: true) }.buttonStyle(DefaultSheetButtonStyle()).keyboardShortcut(.defaultAction)
                }
            } else if e.removedOnDisk {
                NoticeBar(text: "\(file.lastPathComponent) was removed on disk. Your text is still here.") {
                    Button("Save to Recreate") { e.recreate() }.buttonStyle(DefaultSheetButtonStyle())
                }
            } else if let to = e.renamedTo {
                NoticeBar(text: "Renamed on disk to \(model.projectFolder.flatMap { model.relativePathIn(URL(fileURLWithPath: to), folder: $0) } ?? AppModel.short(to)). Duo followed it.") {
                    Button("OK") { e.renamedTo = nil }.buttonStyle(DefaultSheetButtonStyle())   // not an action: dismisses a notice
                }
            } else if let why = e.readOnlyReason {
                NoticeBar(text: "Read only: " + Self.reason(why)) {
                    Button("Show in Finder") { FileActions.reveal(file) }.buttonStyle(.duo)
                }
            } else if let tab = model.rightTab, let c = model.conversions[tab] {
                ConversionNotice(tab: tab, conversion: c)
            }
        }
    }

    static func reason(_ r: String) -> String {
        switch r {
        case "mixed line endings": "this file mixes Windows and Mac line endings, so Duo can’t save it exactly as it was."
        case "not UTF-8": "this file isn’t UTF-8 text, so saving it from Duo would change it."
        case "can't read the file": "Duo can’t read this file."
        case "changed on disk to text that isn't UTF-8": "it changed on disk to text that isn’t UTF-8, so Duo won’t save over it."
        default: r + "."
        }
    }
}

/// The notice bar (S3-4): padding 10 20, the message, a `text2` line, the buttons; a `rule` below.
struct NoticeBar<Buttons: View>: View {
    let text: String
    var sub: String? = nil
    /// A second `text2` line (a converted document's gaps, then what was done: DL-123, E).
    var sub2: String? = nil
    @ViewBuilder let buttons: () -> Buttons

    var body: some View {
        VStack(alignment: .leading, spacing: DuoSpace.gapGlyphToLabel) {
            Text(text).duoText(.body).fixedSize(horizontal: false, vertical: true)
            if let sub { Text(sub).duoText(.body).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true) }
            if let sub2 { Text(sub2).duoText(.body).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: DuoSpace.gapButtonToButton) { buttons() }
        }
        .padding(.vertical, DuoMetric.noticePaddingY)
        .padding(.horizontal, DuoMetric.noticePaddingX)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DuoColor.ground)
        .overlay(alignment: .bottom) { DuoColor.rule.frame(height: DuoMetric.borderHairline) }
    }
}

/// Inside a folder with no project file (DL-63, DL-110): a notice in MissingNotice's look, offering
/// Make a Project; Not Now hides it for that folder. Target: folder-handoff `folder-not-project.html`.
struct FolderNotice: View {
    @Environment(AppModel.self) private var model
    let project: Fixture.Project

    var body: some View {
        VStack(alignment: .leading, spacing: DuoSpace.gapGlyphToLabel) {
            Text("This folder isn’t a project yet.")
                .duoText(.body).fixedSize(horizontal: false, vertical: true)
            Text("A project file gives it a goal and a next step, shown here and on the map.")
                .duoText(.body).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DuoSpace.gapButtonToButton) {
                Button("Make a Project") { model.makeProject(project.name) }.buttonStyle(DefaultSheetButtonStyle())
                Button("Not Now") { model.notNowProject(project.name) }.buttonStyle(.duo)
            }
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).fill(DuoColor.ground))
        .padding(.horizontal, DuoSpace.panePadding)
        .padding(.vertical, 8)
    }
}

/// The Project tab of a folder that isn't a project (DL-110): what a project file adds, and the offer.
struct FolderProjectTab: View {
    @Environment(AppModel.self) private var model
    let project: Fixture.Project

    var body: some View {
        VStack(alignment: .leading, spacing: DuoSpace.gapGlyphToLabel) {
            Text("No project file").duoText(.bodyEmphasis)
            Text("A \(Text("PROJECT.md").font(Font(NSFont.monospacedSystemFont(ofSize: DuoTextStyle.mono.spec.size, weight: .regular)))) holds this folder’s goal, health and next step. Duo shows them here and on the map.")
                .duoText(.body).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DuoSpace.gapButtonToButton) {
                Button("Make a Project") { model.makeProject(project.name) }.buttonStyle(DefaultSheetButtonStyle())
                if project.hasClaudeMD == true {
                    Button("Open CLAUDE.md") { model.openDocument("CLAUDE.md") }.buttonStyle(.duo)
                }
            }
            .padding(.top, 6)
        }
        .padding(DuoSpace.documentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Inside a project whose folder is gone (S3-2): a notice on `ground` over the session list.
struct MissingNotice: View {
    @Environment(AppModel.self) private var model
    let project: Fixture.Project

    var body: some View {
        VStack(alignment: .leading, spacing: DuoSpace.gapGlyphToLabel) {
            Text("This project’s folder isn’t at \(Text(project.path).font(Font(NSFont.monospacedSystemFont(ofSize: DuoTextStyle.mono.spec.size, weight: .regular)))) any more.")
                .duoText(.body).fixedSize(horizontal: false, vertical: true)
            Text(project.movedTo.map { "Duo found it at \(AppModel.short($0))." } ?? "Its sessions open again once it’s found.")
                .duoText(.body).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DuoSpace.gapButtonToButton) {
                if project.movedTo != nil { Button("Use New Place") { model.useNewPlace(project.name) }.buttonStyle(DefaultSheetButtonStyle()) }
                Button("Locate Folder…") { model.locateFolder(project.name) }.buttonStyle(.duo)
                Button("Remove from Duo") { model.forgetFolder(project.name) }.buttonStyle(.duo)
            }
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).fill(DuoColor.ground))
        .padding(.horizontal, DuoSpace.panePadding)
        .padding(.vertical, 8)
    }
}

/// A container whose notice bar comes and goes (DL-130): the bar slides down from under the tab
/// strip and pushes the content (`noticeIn`), and slides back up (`noticeOut`), clipped to it.
struct NoticeMotion: ViewModifier {
    let key: String?
    func body(content: Content) -> some View {
        content
            .clipped()
            .animation((key != nil ? DuoMotionToken.noticeIn : .noticeOut).animation, value: key)
    }
}
