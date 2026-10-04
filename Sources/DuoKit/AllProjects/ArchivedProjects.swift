import SwiftUI

/// Archiving a project (ENH-6, Geoff 2026-10-04): a filing mechanism that reduces clutter. The
/// tile leaves its topic column for an Archived rollup at the bottom of the map; its sessions,
/// counts and search are unchanged. Plain look until designed.
extension AppModel {
    public func isArchived(_ project: String) -> Bool {
        if let fixed = fixtureArchived { return fixed.contains(project) }
        guard let path = liveFolders[project]?.path else { return false }
        return archivedProjectPaths.contains(path)
    }

    /// The map's tiles in a topic: archived ones are in the rollup instead.
    public func mapProjects(inTopic topic: String) -> [Fixture.Project] {
        fixture.projects(inTopic: topic).filter { !isArchived($0.name) }
    }

    public var archivedProjects: [Fixture.Project] { fixture.projects.filter { isArchived($0.name) } }

    public func setArchived(_ project: String, _ on: Bool) {
        guard let path = liveFolders[project]?.path, isArchived(project) != on else { return }
        DuoState.update { s in
            if on { s.archivedProjects.append(path) } else { s.archivedProjects.removeAll { $0 == path } }
        }
        archivedProjectPaths = DuoState.load().archivedProjects
        if focusedTile == project { focusedTile = nil }
        registerUndo(on ? "Archive Project" : "Unarchive Project") { model in model.setArchived(project, !on) }
    }
}

/// `Archived · n ›` under the map's columns; open, a compact row per project.
struct ArchivedRollup: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let archived = model.archivedProjects
        if !archived.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: DuoSpace.gapRowItems) {
                    SectionLabel(text: "Archived", count: archived.count)
                    Chevron(direction: model.archivedOpen ? .down : .right)
                        .frame(width: model.archivedOpen ? 10 : 8, height: model.archivedOpen ? 8 : 10)
                }
                .contentShape(Rectangle())
                .onActivate { model.archivedOpen.toggle() }  // action: projects
                .accessibilityLabel("\(archived.count) archived projects")
                .accessibilityAddTraits(.isButton)
                if model.archivedOpen {
                    ForEach(archived) { p in
                        HStack(spacing: DuoSpace.gapRowItems) {
                            Text(p.name).duoText(.bodyEmphasis).foregroundStyle(DuoColor.text).lineLimit(1)
                            Text(p.isFolderOnly ? p.path : p.goal).duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1)
                            Spacer(minLength: 8)
                            let n = model.fixture.sessions(inProject: p.name).count
                            Text("\(n) session\(n == 1 ? "" : "s")").duoText(.body).foregroundStyle(DuoColor.text2).fixedSize()
                        }
                        .padding(.horizontal, 10)
                        .frame(height: DuoMetric.rowSession)
                        .bordered(EdgeInsets(), color: DuoColor.rule)
                        .contentShape(Rectangle())
                        .onActivate { model.open(project: p.name) }  // action: open
                        .contextMenu {
                            Button("Unarchive Project") { model.setArchived(p.name, false) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DuoSpace.panePadding)
            .padding(.bottom, DuoSpace.panePadding)
        }
    }
}
