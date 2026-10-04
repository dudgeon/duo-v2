import DuoControl
import Foundation

/// Groups by hand and by CLI (DL-24, Phase G): stored in the project's `.duo/sessions.json` as
/// session ids, so a renamed session stays in its group. Each change is undoable (⌘Z, `duo2 undo`).
extension AppModel {
    func groupVerb(_ id: ActionID, _ inv: Invocation, _ req: ControlRequest, _ done: @escaping @MainActor (Reply) -> Void) {
        let projectHint = inv.flags["project"] ?? projectFor(cwd: req.cwd)?.name ?? currentProject?.name
        switch id {
        case .groups:
            let gs = indexGroups().filter { g in inv.flags["project"].map { g.project == $0 } ?? true }
            let rows: [[String: Any]] = gs.map { g in
                let members = fixture.sessions.filter { $0.project == g.project && g.sessions.contains($0.name) }
                return ["name": g.name, "project": g.project, "state": members.map(\.state).min().map(stateWord) ?? "idle",
                        "sessions": members.map { ["id": $0.sessionId ?? "", "title": $0.name, "state": stateWord($0.state)] },
                        "threads": g.threads]
            }
            let text = gs.isEmpty ? "No groups." : gs.map { g in
                let members = fixture.sessions.filter { $0.project == g.project && g.sessions.contains($0.name) }
                return "\(g.name) (\(g.project), \(members.map(\.state).min().map(stateWord) ?? "idle"))\n"
                    + g.threads.map { t in "  " + t.joined(separator: " → ") }.joined(separator: "\n")
            }.joined(separator: "\n")
            done(.ok(text, rows))

        case .groupNew:
            guard let name = inv[0], inv.positional.count > 1 else { return done(.fail("usage: \(id.action.usage)")) }
            let found = inv.positional.dropFirst().map { ($0, findSession($0, in: projectHint) ?? findSession($0, in: nil)) }
            if let missing = found.first(where: { $0.1?.sessionId == nil }) { return done(.fail("no session '\(missing.0)'")) }
            let sessions = found.compactMap(\.1)
            let projects = Set(sessions.map(\.project))
            guard projects.count == 1, let project = projects.first else {
                return done(.fail("a group's sessions share a project; these are in \(projects.sorted().joined(separator: ", "))"))
            }
            if indexGroups().contains(where: { $0.project == project && $0.name == name }) {
                return done(.fail("\(project) already has a group named \(name); use `duo2 group add`"))
            }
            editGroups(project, action: "New Group") { index in
                let ids = sessions.compactMap(\.sessionId)
                for i in index.groups.indices { index.groups[i].sessions.removeAll(where: ids.contains) }  // one group per session
                index.groups.removeAll { $0.sessions.isEmpty }
                index.groups.append(.init(name: name, sessions: ids))
            }
            done(.ok("Grouped \(sessions.count) session(s) as \(name) in \(project). Undo: duo2 undo"))

        case .groupAdd, .groupRemove:
            guard let name = inv[0], inv.positional.count > 1, let g = findGroup(name, project: projectHint) else {
                return done(.fail(inv[0].map { "no group '\($0)'" } ?? "usage: \(id.action.usage)"))
            }
            let found = inv.positional.dropFirst().map { ($0, findSession($0, in: g.project)) }
            if let missing = found.first(where: { $0.1?.sessionId == nil }) { return done(.fail("no session '\(missing.0)' in \(g.project)")) }
            let ids = found.compactMap { $0.1?.sessionId }
            editGroups(g.project, action: id == .groupAdd ? "Add to Group" : "Remove from Group") { index in
                if id == .groupAdd {
                    for i in index.groups.indices where index.groups[i].name != g.name { index.groups[i].sessions.removeAll(where: ids.contains) }
                    if let i = index.groups.firstIndex(where: { $0.name == g.name }) {
                        index.groups[i].sessions += ids.filter { !index.groups[i].sessions.contains($0) }
                    }
                } else if let i = index.groups.firstIndex(where: { $0.name == g.name }) {
                    index.groups[i].sessions.removeAll(where: ids.contains)
                }
                index.groups.removeAll { $0.sessions.isEmpty }
            }
            done(.ok("\(id == .groupAdd ? "Added" : "Removed") \(ids.count) session(s) \(id == .groupAdd ? "to" : "from") \(g.name). Undo: duo2 undo"))

        case .groupRename:
            guard let name = inv[0], let new = inv[1], let g = findGroup(name, project: projectHint) else {
                return done(.fail(inv[0].map { "no group '\($0)'" } ?? "usage: \(id.action.usage)"))
            }
            editGroups(g.project, action: "Rename Group") { index in
                if let i = index.groups.firstIndex(where: { $0.name == g.name }) { index.groups[i].name = new }
            }
            if selectedSidebarItem == g.name { selectedSidebarItem = new }
            done(.ok("Renamed \(g.name) to \(new). Undo: duo2 undo"))

        case .groupDelete:
            guard let name = inv[0], let g = findGroup(name, project: projectHint) else {
                return done(.fail(inv[0].map { "no group '\($0)'" } ?? "usage: \(id.action.usage)"))
            }
            editGroups(g.project, action: "Ungroup") { index in index.groups.removeAll { $0.name == g.name } }
            done(.ok("Ungrouped \(g.name); its sessions stay in \(g.project). Undo: duo2 undo"))

        default: done(.fail("not a group verb"))
        }
    }

    /// Groups as the projects' `.duo/sessions.json` say now (the snapshot lags a refresh behind).
    func indexGroups() -> [Fixture.Group] {
        liveFolders.sorted { $0.key < $1.key }.flatMap { project, folder in groups(of: project, index: SessionIndex.load(project: folder)) }
    }

    func groups(of project: String, index: SessionIndex) -> [Fixture.Group] {
        let inProject = fixture.sessions.filter { $0.project == project }
        return index.groups.map { g in
            let names = g.sessions.compactMap { id in inProject.first { $0.sessionId == id }?.name }
            return Fixture.Group(name: g.name, project: project, sessions: names, threads: LiveSnapshot.threads(names, in: inProject))
        }
    }

    func findGroup(_ name: String, project: String?) -> Fixture.Group? {
        let named = indexGroups().filter { $0.name == name || $0.name.caseInsensitiveCompare(name) == .orderedSame }
        return named.first { $0.project == project } ?? (named.count == 1 ? named.first : nil)
    }

    /// Rewrites a project's group list, registers the undo, and refreshes.
    func editGroups(_ project: String, action: String, _ change: (inout SessionIndex) -> Void) {
        guard let folder = liveFolders[project] else { return }
        let before = SessionIndex.load(project: folder)
        var after = before
        change(&after)
        try? after.save(project: folder)
        showGroups(project, after)
        registerUndo(action) { model in
            var now = SessionIndex.load(project: folder)
            now.groups = before.groups
            try? now.save(project: folder)
            model.showGroups(project, now)
            model.refreshLive()
        }
        refreshLive()
    }

    /// The sidebar shows the change now, not at the next refresh.
    func showGroups(_ project: String, _ index: SessionIndex) {
        fixture.groups = fixture.groups.filter { $0.project != project } + groups(of: project, index: index)
    }
}
