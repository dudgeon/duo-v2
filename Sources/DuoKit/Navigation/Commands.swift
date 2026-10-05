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
        case .revertChange, .revertAllChanges, .chooseHome: nil
        case .newBrowserTab: KeyboardShortcut("t", modifiers: [.command, .option])
        case .focusAddress: KeyboardShortcut("l", modifiers: .command)
        case .openFile: KeyboardShortcut("o", modifiers: .command)
        case .newClaudeSession: KeyboardShortcut("t", modifiers: .command)
        case .newShell: KeyboardShortcut("t", modifiers: [.command, .shift])
        }
    }

    @MainActor
    public func isEnabled(in model: AppModel) -> Bool {
        switch self {
        case .search: true
        case .toggleRightPane, .nextPane, .previousPane: false  // not built yet
        case .allProjects: !model.altitude.isAllProjects
        case .togglePeek: !model.altitude.isAllProjects && !model.needsYouElsewhere.isEmpty
        case .jumpToPeekSelection: model.peekOpen
        case .goHome, .toggleSidebar, .closeWindow: true
        case .closeSession: model.visibleTerminal != nil || (model.webFocus == .editor && model.openDocuments.contains(model.rightTab ?? ""))
        case .newMarkdown, .newFolder: model.terminalsMode == .live && model.projectFolder != nil
        case .save: model.terminalsMode == .live && model.editor.url != nil
        case .bold, .italic: model.webFocus == .editor
        case .sendSelection: model.canSendSelection
        case .newClaudeSession, .newShell: model.terminalsMode == .live
        case .chooseHome: model.terminalsMode == .live
        case .newBrowserTab: model.terminalsMode == .live
        case .focusAddress: model.visibleWebTab != nil
        case .openFile: model.terminalsMode == .live && model.projectFolder != nil
        case .revertChange: model.webFocus == .editor && (model.editorIfLoaded?.atClaudeChange ?? false)
        case .revertAllChanges: (model.editorIfLoaded?.claudeChanges ?? 0) > 0
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
        case .bold: model.editor.run("duo.exec('bold'); return 1") { _ in }
        case .italic: model.editor.run("duo.exec('italic'); return 1") { _ in }
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
        case .toggleRightPane, .nextPane, .previousPane: break
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
        CommandGroup(replacing: .newItem) {
            item(.newClaudeSession)
            item(.newShell)
            item(.newBrowserTab)
            item(.focusAddress)
            Divider()
            item(.newMarkdown)
            item(.newFolder)
            Divider()
            item(.openFile)
            Divider()
            item(.chooseHome)
        }
        CommandGroup(replacing: .saveItem) {
            item(.save)
            item(.closeSession)
            item(.closeWindow)
        }
        CommandMenu("Format") {
            item(.bold)
            item(.italic)
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
        CommandGroup(after: .sidebar) {
            item(.toggleSidebar)
            item(.toggleRightPane)
            Divider()
            // Dotfiles in the project's tree (DL-105).
            Toggle("Show Hidden Files", isOn: Binding(get: { model.showHiddenFiles }, set: { model.setShowHiddenFiles($0) }))
            Divider()
            // The map's order (DL-104), the same choice as its Sort popup.
            Picker("Sort Projects By", selection: Binding(get: { model.mapSort }, set: { model.setMapSort($0) })) {
                Text("Recent Activity").tag(MapSort.recent)
                Text("Name").tag(MapSort.name)
            }
        }
        CommandMenu("Go") {
            item(.search)
            Divider()
            item(.allProjects)
            item(.goHome)
            Divider()
            item(.togglePeek)
            item(.jumpToPeekSelection)
            Divider()
            item(.nextPane)
            item(.previousPane)
        }
    }

    private func item(_ c: DuoCommand) -> some View {
        Button(c.title) { c.perform(in: model) }
            .keyboardShortcut(c.shortcut)
            .disabled(!c.isEnabled(in: model))
    }
}
