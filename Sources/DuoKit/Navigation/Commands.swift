import AppKit
import SwiftUI

/// Every Duo chord in one table (LR-60). Menus are generated from it, so a chord is changed in
/// exactly one place. The map is locked (DL-34); changing a chord needs a decision-log entry. All carry ⌘ so they can't collide with keys typed into Claude Code's TUI
/// (handoff §6.3), and none is on LR-60's avoid list (⌘\, ⌘⌥L, ⌘⌥;, ⌘⌥').
public enum DuoCommand: String, CaseIterable, Sendable {
    case search             // ⇧⌘A: search everything, names first (DL-46, DL-80: Jump merged in; ⌘K is free)
    case allProjects        // ⌘↑, "up a level", as in Finder
    case goHome             // ⇧⌘H (handoff proposal)
    case togglePeek         // ⇧⌘P
    case jumpToPeekSelection // ⌘↩ (handoff proposal), while the peek is open
    case toggleSidebar      // ⌃⌘S, the macOS standard
    case toggleRightPane    // ⌥⌘0, as Xcode's inspector
    case nextPane           // ⌥⌘→
    case previousPane       // ⌥⌘←
    case newMarkdown        // ⌘N: a new Markdown file in the project, named inline (DL-61, DL-62)
    case newFolder          // ⇧⌘N
    case save               // ⌘S saves the open document now (it also autosaves)
    case bold               // ⌘B, only while the editor has focus (stack rec #9)
    case italic             // ⌘I, likewise
    case closeSession       // ⌘W closes the focused tab (document or session), never the window (LR-60, LR-13)
    case closeWindow        // ⇧⌘W, as in browsers once ⌘W closes tabs
    case revertChange       // Edit › Revert Claude's Change (ENH-4); no chord
    case revertAllChanges   // Edit › Revert All of Claude's Changes (ENH-4); no chord
    case newClaudeSession   // ⌘T: a new Claude session in this console (surfaces-handoff DB-4; Q-26)
    case newShell           // ⇧⌘T: a plain shell in this console (DL-8, DB-4; Q-26)
    case sendSelection      // ⌘D: Send Selection to Claude, legacy's chord (Q-22, DL-79); search's Send to Claude too
    case chooseHome         // File › Choose Home Folder… (DL-84); no chord
    case newBrowserTab      // ⌥⌘T: a browser tab in the right pane (ENH-8), beside ⌘T and ⇧⌘T
    case focusAddress       // ⌘L: the browser tab's address field, as in Safari and Chrome (ENH-8)
    case openFile           // ⌘O: any file on the Mac as a tab in this project (DL-106)
    // DL-108 (the menu bar, walk decisions m2–m4)
    case newTask            // File › New Task: a task note in this project, named first (DL-93)
    case newProject         // File › New Project…: the New project sheet (DL-100)
    case code               // Format › Code
    case link               // ⌘K: Format › Link…, free since DL-80
    case heading1, heading2, heading3  // Format › Heading ▸
    case task               // Format › Task: a `- [ ]` line
    case addProperties      // Format › Add Properties (frontmatter-handoff's frontmatter-none)
    // Format › Table ▸ (DL-113, tables-handoff): Markdown commands; no chords (DL-34)
    case tableInsert, tableRowAbove, tableRowBelow, tableColumnBefore, tableColumnAfter
    case tableDeleteRow, tableDeleteColumn, tableAlignLeft, tableAlignCenter, tableAlignRight
    case duo2Reference      // Help: docs/cli/duo2.md on GitHub
    case whatsNew           // Help: this version's release notes
    case reportIssue        // Help: a new GitHub issue with the version and macOS filled in
    // Browser tabs (DL-124): print and page zoom, as in Safari
    case printPage          // ⌘P: File › Print…, the browser tab on screen
    case zoomIn             // ⌘+ (⌘= too): View › Zoom In, while a browser tab has the keyboard
    case zoomOut            // ⌘-
    case actualSize         // ⌘0

    public var title: String {
        switch self {
        case .search: "Search Everything…"
        case .allProjects: "All Projects"
        case .goHome: "Home"
        case .togglePeek: "Needs You Elsewhere"
        case .jumpToPeekSelection: "Jump into Selected Project"
        case .toggleSidebar: "Toggle Sidebar"
        case .toggleRightPane: "Toggle Right Pane"
        case .nextPane: "Next Pane"
        case .previousPane: "Previous Pane"
        case .newMarkdown: "New Markdown File"
        case .newFolder: "New Folder"
        case .save: "Save"
        case .bold: "Bold"
        case .italic: "Italic"
        case .closeSession: "Close Tab"
        case .closeWindow: "Close Window"
        case .sendSelection: "Send Selection to Claude"
        case .newClaudeSession: "New Claude Session"
        case .revertChange: "Revert Claude's Change"
        case .revertAllChanges: "Revert All of Claude's Changes"
        case .newShell: "New Shell"
        case .chooseHome: "Choose Home Folder…"
        case .newBrowserTab: "New Browser Tab"
        case .focusAddress: "Open Location…"
        case .openFile: "Open File…"
        case .newTask: "New Task"
        case .newProject: "New Project…"
        case .code: "Code"
        case .link: "Link…"
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .task: "Task"
        case .addProperties: "Add Properties"
        case .tableInsert: "Insert Table"
        case .tableRowAbove: "Add Row Above"
        case .tableRowBelow: "Add Row Below"
        case .tableColumnBefore: "Add Column Before"
        case .tableColumnAfter: "Add Column After"
        case .tableDeleteRow: "Delete Row"
        case .tableDeleteColumn: "Delete Column"
        case .tableAlignLeft: "Left"
        case .tableAlignCenter: "Center"
        case .tableAlignRight: "Right"
        case .duo2Reference: "duo2 Reference"
        case .whatsNew: "What’s New in This Version"
        case .reportIssue: "Report an Issue…"
        case .printPage: "Print…"
        case .zoomIn: "Zoom In"
        case .zoomOut: "Zoom Out"
        case .actualSize: "Actual Size"
        }
    }

    public var shortcut: KeyboardShortcut? {
        switch self {
        case .search: KeyboardShortcut("a", modifiers: [.command, .shift])  // Chrome's tab search (DL-46)
        case .allProjects: KeyboardShortcut(.upArrow, modifiers: .command)
        case .goHome: KeyboardShortcut("h", modifiers: [.command, .shift])
        case .togglePeek: KeyboardShortcut("p", modifiers: [.command, .shift])
        case .jumpToPeekSelection: KeyboardShortcut(.return, modifiers: .command)
        case .toggleSidebar: KeyboardShortcut("s", modifiers: [.command, .control])
        case .toggleRightPane: KeyboardShortcut("0", modifiers: [.command, .option])
        case .nextPane: KeyboardShortcut(.rightArrow, modifiers: [.command, .option])
        case .previousPane: KeyboardShortcut(.leftArrow, modifiers: [.command, .option])
        case .newMarkdown: KeyboardShortcut("n", modifiers: .command)
        case .newFolder: KeyboardShortcut("n", modifiers: [.command, .shift])
        case .save: KeyboardShortcut("s", modifiers: .command)
        case .bold: KeyboardShortcut("b", modifiers: .command)
        case .italic: KeyboardShortcut("i", modifiers: .command)
        case .closeSession: KeyboardShortcut("w", modifiers: .command)
        case .closeWindow: KeyboardShortcut("w", modifiers: [.command, .shift])
        case .sendSelection: KeyboardShortcut("d", modifiers: .command)
        case .link: KeyboardShortcut("k", modifiers: .command)  // DL-108
        case .revertChange, .revertAllChanges, .chooseHome, .newTask, .newProject, .code, .heading1, .heading2, .heading3,
             .task, .addProperties, .duo2Reference, .whatsNew, .reportIssue, .tableInsert, .tableRowAbove, .tableRowBelow,
             .tableColumnBefore, .tableColumnAfter, .tableDeleteRow, .tableDeleteColumn, .tableAlignLeft, .tableAlignCenter,
             .tableAlignRight: nil
        case .newBrowserTab: KeyboardShortcut("t", modifiers: [.command, .option])
        case .focusAddress: KeyboardShortcut("l", modifiers: .command)
        case .openFile: KeyboardShortcut("o", modifiers: .command)
        case .newClaudeSession: KeyboardShortcut("t", modifiers: .command)
        case .newShell: KeyboardShortcut("t", modifiers: [.command, .shift])
        case .printPage: KeyboardShortcut("p", modifiers: .command)
        case .zoomIn: KeyboardShortcut("+", modifiers: .command)
        case .zoomOut: KeyboardShortcut("-", modifiers: .command)
        case .actualSize: KeyboardShortcut("0", modifiers: .command)
        }
    }

    @MainActor
    public func isEnabled(in model: AppModel) -> Bool {
        switch self {
        case .search: true
        case .toggleRightPane: true
        case .nextPane, .previousPane: false  // not built yet
        case .allProjects: !model.altitude.isAllProjects
        case .togglePeek: !model.altitude.isAllProjects && !model.needsYouElsewhere.isEmpty
        case .jumpToPeekSelection: model.peekOpen
        case .goHome, .toggleSidebar, .closeWindow: true
        case .closeSession: model.visibleTerminal != nil || (model.webFocus == .editor && model.openDocuments.contains(model.rightTab ?? ""))
        case .newMarkdown, .newFolder: model.terminalsMode == .live && model.projectFolder != nil
        case .save: model.terminalsMode == .live && model.editor.url != nil
        case .bold, .italic, .code, .link, .heading1, .heading2, .heading3, .task, .addProperties, .tableInsert: model.webFocus == .editor
        case .tableRowAbove, .tableRowBelow, .tableColumnBefore, .tableColumnAfter, .tableDeleteRow, .tableDeleteColumn,
             .tableAlignLeft, .tableAlignCenter, .tableAlignRight: model.webFocus == .editor && (model.editorIfLoaded?.inTable ?? false)
        case .newTask: model.terminalsMode == .live && model.currentProject.map { !$0.isFolderOnly } == true
        case .newProject: model.terminalsMode == .live && model.liveRoot != nil
        case .duo2Reference, .whatsNew, .reportIssue: true
        case .sendSelection: model.canSendSelection
        case .newClaudeSession, .newShell: model.terminalsMode == .live
        case .chooseHome: model.terminalsMode == .live
        case .newBrowserTab: model.terminalsMode == .live
        case .focusAddress: model.visibleWebTab != nil
        case .openFile: model.terminalsMode == .live && model.projectFolder != nil
        case .revertChange: model.webFocus == .editor && (model.editorIfLoaded?.atClaudeChange ?? false)
        case .revertAllChanges: (model.editorIfLoaded?.claudeChanges ?? 0) > 0
        case .printPage: model.visibleWebTab.map { $0.blocked == nil } ?? false
        case .zoomIn, .zoomOut, .actualSize: model.webFocus == .html && model.visibleWebTab.map { $0.blocked == nil } == true
        }
    }

    /// The editor's name for a Format item (`duo.exec`, `duo2 doc format`).
    public var formatName: String? {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .code: "code"
        case .link: "link"
        case .heading1: "heading1"
        case .heading2: "heading2"
        case .heading3: "heading3"
        case .task: "task"
        case .addProperties: "properties"
        default: nil
        }
    }

    /// The editor's name for a Format › Table item, and its `duo2 doc table` word.
    public var tableName: String? {
        switch self {
        case .tableInsert: "tableInsert"
        case .tableRowAbove: "tableRowAbove"
        case .tableRowBelow: "tableRowBelow"
        case .tableColumnBefore: "tableColumnBefore"
        case .tableColumnAfter: "tableColumnAfter"
        case .tableDeleteRow: "tableDeleteRow"
        case .tableDeleteColumn: "tableDeleteColumn"
        case .tableAlignLeft: "tableAlignLeft"
        case .tableAlignCenter: "tableAlignCenter"
        case .tableAlignRight: "tableAlignRight"
        default: nil
        }
    }

    @MainActor
    public func perform(in model: AppModel) {
        switch self {
        case .allProjects: model.zoomOut()
        case .goHome: model.goHome()
        case .togglePeek: model.togglePeek()
        case .jumpToPeekSelection: model.jumpToPeekSelection()
        case .toggleSidebar: model.leftCollapsed.toggle()
        case .closeSession:
            if model.editorIfLoaded?.hasFocus == true, let doc = model.rightTab, model.openDocuments.contains(doc) { model.closeDocument(doc) }
            else { model.closeVisibleSession() }
        case .newMarkdown: model.newMarkdownFile(near: model.selectedFile)
        case .newFolder: model.newFolder(near: model.selectedFile)
        case .save: model.editor.saveNow()
        case .bold, .italic, .code, .link, .heading1, .heading2, .heading3, .task, .addProperties, .tableInsert, .tableRowAbove,
             .tableRowBelow, .tableColumnBefore, .tableColumnAfter, .tableDeleteRow, .tableDeleteColumn, .tableAlignLeft,
             .tableAlignCenter, .tableAlignRight:
            model.editor.run("duo.exec(f); return 1", ["f": (formatName ?? tableName)!]) { _ in }
        case .newTask: if let p = model.currentProject?.name { model.newTask(in: p) }
        case .newProject: model.showNewProject()
        case .duo2Reference: NSWorkspace.shared.open(DuoLinks.duo2Reference)
        case .whatsNew: NSWorkspace.shared.open(DuoLinks.releaseNotes)
        case .reportIssue: NSWorkspace.shared.open(DuoLinks.newIssue)
        case .closeWindow: NSApp.keyWindow?.performClose(nil)
        case .sendSelection: model.sendSelection()
        case .newClaudeSession: model.newSession()
        case .revertChange: model.editor.revertAtCaret()
        case .revertAllChanges: model.editor.revertAll()
        case .newShell: model.newShell()
        case .chooseHome: model.chooseHomeFolder()
        case .newBrowserTab: model.newBrowserTab()
        case .focusAddress: model.focusAddressField()
        case .openFile: model.chooseFilesToOpen()
        case .search: model.openSearch()
        case .toggleRightPane: model.rightCollapsed.toggle()
        case .nextPane, .previousPane: break
        case .printPage: model.visibleWebTab?.printPage()
        case .zoomIn: if let t = model.visibleWebTab { t.zoom(ZoomStore.zoomIn(t.zoom)) }
        case .zoomOut: if let t = model.visibleWebTab { t.zoom(ZoomStore.zoomOut(t.zoom)) }
        case .actualSize: model.visibleWebTab?.zoom(1.0)
        }
    }
}

/// The Go menu and the sidebar item in View, generated from `DuoCommand`.
public struct DuoCommands: Commands {
    let model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some Commands {
        // Until Sparkle (v1.1): ask GitHub for a newer release.
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { model.checkForUpdates(userInitiated: true) }
        }
        // File (DL-108, m2): new things, then opening, then saving and closing, then Home.
        CommandGroup(replacing: .newItem) {
            item(.newClaudeSession)
            item(.newShell)
            item(.newBrowserTab)
            Divider()
            item(.newMarkdown)
            item(.newFolder)
            item(.newTask)
            item(.newProject)
            Divider()
            item(.openFile)
            item(.focusAddress)
        }
        CommandGroup(replacing: .saveItem) {
            item(.save)
            item(.closeSession)
            item(.closeWindow)
            Divider()
            item(.chooseHome)
            Divider()
            item(.printPage)
        }
        // Format (DL-108, m3), in the system's Format menu so it sits between Edit and View.
        CommandGroup(replacing: .textFormatting) {
            item(.bold)
            item(.italic)
            item(.code)
            item(.link)
            Divider()
            Menu("Heading") {
                item(.heading1)
                item(.heading2)
                item(.heading3)
            }
            item(.task)
            // Tables (DL-113): edited as Markdown; the bar over a table has the same items.
            Menu("Table") {
                item(.tableInsert)
                Divider()
                item(.tableRowAbove)
                item(.tableRowBelow)
                item(.tableColumnBefore)
                item(.tableColumnAfter)
                Divider()
                item(.tableDeleteRow)
                item(.tableDeleteColumn)
                Divider()
                Menu("Align Column") {
                    item(.tableAlignLeft)
                    item(.tableAlignCenter)
                    item(.tableAlignRight)
                }
            }
            Divider()
            item(.addProperties)
        }
        // The standard text items (Find, Spelling and Grammar, Substitutions, Transformations,
        // Speech) for the editor; Writing Tools joins them where the system supports it.
        TextEditingCommands()
        // Send to Claude (DL-67), ⌘D (DL-79).
        CommandGroup(after: .pasteboard) {
            Divider()
            item(.sendSelection)
            Divider()
            item(.revertChange)
            item(.revertAllChanges)
        }
        // View (DL-108, m2): the items that aren't built (the right pane's toggle, moving between
        // panes) are left out until they work; Enter Full Screen is the system's.
        CommandGroup(after: .sidebar) {
            item(.toggleSidebar)
            Divider()
            // A browser tab's page zoom (DL-124), as Safari's View menu has it.
            item(.zoomIn)
            item(.zoomOut)
            item(.actualSize)
            Divider()
            // Dotfiles in the project's tree (DL-105).
            Toggle("Show Hidden Files", isOn: Binding(get: { model.showHiddenFiles }, set: { model.setShowHiddenFiles($0) }))
            // The map's order (DL-104), the same choice as its Sort popup.
            Picker("Sort Projects By", selection: Binding(get: { model.mapSort }, set: { model.setMapSort($0) })) {
                Text("Recent Activity").tag(MapSort.recent)
                Text("Name").tag(MapSort.name)
            }
            Divider()
            // The system's item, made here: AppKit's own isn't added to a SwiftUI View menu.
            Button(model.fullScreen ? "Exit Full Screen" : "Enter Full Screen") {
                (NSApp.windows.first { $0.title == "Duo" } ?? NSApp.keyWindow)?.toggleFullScreen(nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .control])
        }
        // What's in front of you (DL-108, m1).
        CommandMenu("Project") { ProjectMenuItems(model: model) }
        CommandMenu("Session") { SessionMenuItems(model: model) }
        CommandMenu("Go") {
            item(.search)
            Divider()
            item(.allProjects)
            item(.goHome)
            Divider()
            item(.togglePeek)
            item(.jumpToPeekSelection)
        }
        // Help (DL-108, m4); the system adds its search field.
        CommandGroup(replacing: .help) {
            item(.duo2Reference)
            item(.whatsNew)
            Divider()
            item(.reportIssue)
        }
    }

    private func item(_ c: DuoCommand) -> some View {
        Button(c.title) { c.perform(in: model) }
            .keyboardShortcut(c.shortcut)
            .disabled(!c.isEnabled(in: model))
    }
}
