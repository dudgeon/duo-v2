import SwiftUI

/// Archiving a session (Geoff, 2026-10-04): filing, like archiving a project. It leaves every list
/// and count, keeps its transcript (and Duo's copy), stays searchable, and sits in its project's
/// Archived fold, where Unarchive brings it back. Wherever a session is listed, right-click offers it.
extension AppModel {
    public func isSessionArchived(_ id: String) -> Bool { DuoState.load().archivedSessions.contains(id) }

    /// Refused while the session runs (a tab open in Duo, or live elsewhere): end it first.
    @discardableResult
    public func setSessionArchived(_ key: String, _ on: Bool) -> String? {
        let all = fixture.sessions + (fixture.archivedSessions ?? [])
        guard let s = all.first(where: { $0.tabKey == key || $0.sessionId == key }), let id = s.sessionId else { return "no session '\(key)'" }
        if on, hasOpenTerminal(s.tabKey) || liveElsewhere.contains(id) { return "\(s.name) is running; end it before archiving it" }
        guard isSessionArchived(id) != on else { return nil }
        DuoState.update { st in
            if on { st.archivedSessions.append(id) } else { st.archivedSessions.removeAll { $0 == id } }
        }
        if on {
            if consoleTab == s.tabKey { consoleTab = nil }
            if homeTab == s.tabKey { homeTab = nil }
        }
        registerUndo(on ? "Archive Session" : "Unarchive Session") { model in model.setSessionArchived(key, !on) }
        refreshLive()
        return nil
    }
}

/// `Archived · n` at the end of a project's session list; open, the archived sessions.
struct ArchivedSessionsFold: View {
    @Environment(AppModel.self) private var model
    let project: String

    var body: some View {
        let archived = model.fixture.archivedSessions(inProject: project)
        if !archived.isEmpty {
            let key = "\(project)/archived"
            let expanded = model.expandedGroups.contains(key)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DuoSpace.gapRowItems) {
                    Chevron(direction: expanded ? .down : .right).frame(width: 10)
                    Text("Archived · \(archived.count)").duoText(.body).foregroundStyle(DuoColor.text2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8 + DuoSpace.selectionInset)
                .frame(height: DuoMetric.rowGroup)
                .contentShape(Rectangle())
                .onActivate { if expanded { model.expandedGroups.remove(key) } else { model.expandedGroups.insert(key) } }  // action: view group
                .accessibilityLabel(expanded ? "Hide archived sessions" : "Show \(archived.count) archived sessions")
                .padding(.top, 12)
                if expanded {
                    ForEach(archived, id: \.tabKey) { s in
                        SidebarLeafRow(row: SidebarRow(id: "\(project)/thread/\(s.tabKey)", name: s.name, state: .idle, wait: s.wait, kind: .session), nested: false)
                    }
                }
            }
        }
    }
}
