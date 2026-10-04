import SwiftUI

/// Every Duo chord in one table (LR-60). Menus are generated from it, so a chord is changed in
/// exactly one place. The map is locked (DL-34); changing a chord needs a decision-log entry. All carry ⌘ so they can't collide with keys typed into Claude Code's TUI
/// (handoff §6.3), and none is on LR-60's avoid list (⌘\, ⌘⌥L, ⌘⌥;, ⌘⌥').
public enum DuoCommand: String, CaseIterable, Sendable {
    case jump               // ⌘K: project, group and session picker (DL-38; not designed yet)
    case search             // ⇧⌘A: search everything (DL-46, was ⇧⌘F in DL-38; v1.1)
    case allProjects        // ⌘↑, "up a level", as in Finder
    case goHome             // ⇧⌘H (handoff proposal)
    case togglePeek         // ⇧⌘P
    case jumpToPeekSelection // ⌘↩ (handoff proposal), while the peek is open
    case toggleSidebar      // ⌃⌘S, the macOS standard
    case toggleRightPane    // ⌥⌘0, as Xcode's inspector
    case nextPane           // ⌥⌘→
    case previousPane       // ⌥⌘←

    public var title: String {
        switch self {
        case .jump: "Jump to…"
        case .search: "Search Everything…"
        case .allProjects: "All Projects"
        case .goHome: "Home"
        case .togglePeek: "Needs You Elsewhere"
        case .jumpToPeekSelection: "Jump into Selected Project"
        case .toggleSidebar: "Toggle Sidebar"
        case .toggleRightPane: "Toggle Right Pane"
        case .nextPane: "Next Pane"
        case .previousPane: "Previous Pane"
        }
    }

    public var shortcut: KeyboardShortcut {
        switch self {
        case .jump: KeyboardShortcut("k", modifiers: .command)
        case .search: KeyboardShortcut("a", modifiers: [.command, .shift])  // Chrome's tab search (DL-46)
        case .allProjects: KeyboardShortcut(.upArrow, modifiers: .command)
        case .goHome: KeyboardShortcut("h", modifiers: [.command, .shift])
        case .togglePeek: KeyboardShortcut("p", modifiers: [.command, .shift])
        case .jumpToPeekSelection: KeyboardShortcut(.return, modifiers: .command)
        case .toggleSidebar: KeyboardShortcut("s", modifiers: [.command, .control])
        case .toggleRightPane: KeyboardShortcut("0", modifiers: [.command, .option])
        case .nextPane: KeyboardShortcut(.rightArrow, modifiers: [.command, .option])
        case .previousPane: KeyboardShortcut(.leftArrow, modifiers: [.command, .option])
        }
    }

    @MainActor
    public func isEnabled(in model: AppModel) -> Bool {
        switch self {
        case .jump, .search, .toggleRightPane, .nextPane, .previousPane: false  // not built yet
        case .allProjects: !model.altitude.isAllProjects
        case .togglePeek: !model.altitude.isAllProjects && !model.needsYouElsewhere.isEmpty
        case .jumpToPeekSelection: model.peekOpen
        case .goHome, .toggleSidebar: true
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
        case .jump, .search, .toggleRightPane, .nextPane, .previousPane: break
        }
    }
}

/// The Go menu and the sidebar item in View, generated from `DuoCommand`.
public struct DuoCommands: Commands {
    let model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some Commands {
        CommandGroup(after: .sidebar) {
            item(.toggleSidebar)
            item(.toggleRightPane)
        }
        CommandMenu("Go") {
            item(.jump)
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
