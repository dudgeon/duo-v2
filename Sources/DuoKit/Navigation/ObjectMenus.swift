import SwiftUI

// The menu bar's Project and Session menus (DL-108, walk decision m1): the right-click menus'
// actions, acting on what's in front of you. No chords (DL-34).

extension AppModel {
    /// The Project menu's project: the one you're in, or the tile focused at All projects.
    public var menuProject: Fixture.Project? {
        if let p = currentProject { return p }
        guard altitude.isAllProjects, let name = focusedTile else { return nil }
        return fixture.projects.first { $0.name == name }
    }

    /// The Session menu's session: the one showing in the console, or the selected row (the
    /// session list inside a project, the action column at All projects).
    public var menuSession: Fixture.Session? {
        let all = fixture.sessions + (fixture.archivedSessions ?? [])
        if let key = visibleSessionId, !isShell(key), let s = all.first(where: { $0.tabKey == key }) { return s }
        let row = altitude.isAllProjects ? selectedActionSession : selectedSidebarItem
        return row.flatMap { r in all.first { $0.id == r || $0.tabKey == r } }
    }

    /// Project › Open Project File: the project's Project tab, which shows its PROJECT.md.
    public func openProjectFile(_ name: String) {
        if currentProject?.name != name { open(project: name) }
        rightTab = "Project"
        selectedFile = nil
    }
}

struct ProjectMenuItems: View {
    let model: AppModel

    var body: some View {
        let live = model.terminalsMode == .live
        let p = live ? model.menuProject : nil
        let organisable = p.map { $0.isHome != true } ?? false
        Button("Open Project File") { if let p { model.openProjectFile(p.name) } }
            .disabled(p == nil || p!.isFolderOnly)
        Button("Reveal in Finder") { if let p { FileActions.reveal(URL(fileURLWithPath: p.path)) } }
            .disabled(p == nil || p!.isMissing)
        Divider()
        Button("Make a Project") { if let p { model.makeProject(p.name) } }
            .disabled(!(p.map { $0.isFolderOnly && !$0.isMissing } ?? false))
        Button("Move into Home…") { if let p { model.moveIntoHome(p.name) } }
            .disabled(!(p.map { organisable && model.liveRoot != nil && !model.isInHome($0.name) && !$0.isMissing } ?? false))
        if let p, organisable {
            MergeIntoMenu(model: model, project: p)
        } else {
            // A menu bar submenu can't be dimmed (AppKit enables any item with a submenu), so
            // with nothing to act on it's a plain dimmed item.
            Button("Merge Into") {}.disabled(true)
        }
        Divider()
        Button("Archive Project") { if let p { model.setArchived(p.name, true) } }
            .disabled(!organisable || (p.map { model.isArchived($0.name) } ?? true))
        Button("Locate Folder…") { if let p { model.locateFolder(p.name) } }
            .disabled(!(p?.isMissing ?? false))
    }
}

struct SessionMenuItems: View {
    let model: AppModel

    var body: some View {
        let s = model.terminalsMode == .live ? model.menuSession : nil
        let id = s?.sessionId
        let key = s?.tabKey ?? ""
        Button("Copy Link") { model.copySessionLink(key) }.disabled(id == nil)
        Button("Resume as a Fork") { if let s, let id { model.resumeAsFork(id, in: s.project) } }.disabled(id == nil)
        Divider()
        Button("Make a Task") { model.makeTask(fromSession: key) }.disabled(id == nil)
        if let s, let id {
            AddToTaskMenu(model: model, session: s, id: id)
            MoveToProjectMenu(model: model, session: s, id: id)
        } else {
            Button("Add to Task") {}.disabled(true)
            Button("Move to Project") {}.disabled(true)
        }
        Divider()
        if let id, model.isSessionArchived(id) {
            Button("Unarchive Session") { _ = model.setSessionArchived(key, false) }
        } else {
            Button("Archive Session") { if let why = model.setSessionArchived(key, true) { model.info(why) } }.disabled(id == nil)
        }
        Button("Delete Session…") { model.deleteSession(key) }.disabled(id == nil)
        Divider()
        // Ends the process; the session stays listed and resumable (as ⌘W on its tab).
        Button("End Session") { model.confirmClose(key) { model.closeSession(key) } }   // asks first when Claude is working (Q-71)
            .disabled(s == nil || model.terminals.existing(key) == nil)
    }
}

// MARK: Submenus shared by the menu bar and the right-click menus

struct MergeIntoMenu: View {
    let model: AppModel
    let project: Fixture.Project

    var body: some View {
        Menu(project.isFolderOnly ? "Merge Sessions Into" : "Merge Into") {
            ForEach(model.moveTargets(excluding: project.name)) { p in
                Button(p.isFolderOnly ? "\(p.name) (folder)" : p.name) { model.mergeProject(project.name, into: p.name) }
            }
        }
    }
}

/// Tasks (DL-93): a note in tasks/ whose `sessions:` links this session.
struct AddToTaskMenu: View {
    let model: AppModel
    let session: Fixture.Session
    let id: String

    var body: some View {
        let tasks = model.taskNotes(in: session.project)
        if tasks.isEmpty {
            Button("Add to Task") {}.disabled(true)  // no task notes in the project yet
        } else {
            Menu("Add to Task") {
                ForEach(tasks, id: \.path) { t in
                    Button(t.title) { if let why = model.addToTask(sessionKey: session.tabKey, task: t.path) { model.info(why) } }
                        .disabled(t.sessionIds.contains(id))
                }
            }
        }
    }
}

struct MoveToProjectMenu: View {
    let model: AppModel
    let session: Fixture.Session
    let id: String

    var body: some View {
        Menu("Move to Project") {
            Button("New Project…") { model.moveSessionsToNewProject([id]) }
            Divider()
            ForEach(model.moveTargets(excluding: session.project)) { p in
                Button(p.isFolderOnly ? "\(p.name) (folder)" : p.name) { model.moveSessions([id], to: p.name) }
            }
        }
    }
}
