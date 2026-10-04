import Foundation

/// The session list inside a project (handoff §3.3, DL-24): groups of threads, threads folding
/// fork families, and plain sessions, sectioned by state.
public struct SidebarRow: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case group(threads: [SidebarRow], sessionCount: Int)
        /// A fork family folded into one row; `count` is its sessions (shown when ≥ 2).
        case thread(count: Int)
        case older(rows: [SidebarRow])
        case session
    }

    public var id: String
    public var name: String
    public var state: SessionState
    public var wait: String?
    public var kind: Kind

    /// The session a row stands for (its id when live, else its name): rows are keyed by identity.
    public var sessionKey: String { id.components(separatedBy: "/thread/").last ?? name }

    /// Builds the rows for one project's sessions, most urgent first within each state.
    public static func rows(for project: String, in fixture: Fixture) -> [SidebarRow] {
        let sessions = fixture.sessions(inProject: project)
        func session(named name: String) -> Fixture.Session? { sessions.first { $0.name == name } }

        /// Rows are keyed by session identity (id when live, else name): live sessions can share a
        /// name ("New session"), and keying by name folded them into a false thread (F-43).
        func threadRow(_ members: [Fixture.Session]) -> SidebarRow? {
            guard let lead = mostUrgent(members) else { return nil }
            return SidebarRow(id: "\(project)/thread/\(lead.tabKey)", name: lead.name, state: lead.state,
                              wait: lead.wait, kind: members.count >= 2 ? .thread(count: members.count) : .session)
        }

        var grouped = Set<String>()   // tabKeys
        var rows: [SidebarRow] = []
        for g in fixture.groups where g.project == project {
            let threads = g.threads.map { $0.compactMap(session(named:)) }.compactMap(threadRow).sorted(by: urgency)
            guard let lead = threads.first else { continue }
            grouped.formUnion(g.sessions.compactMap { session(named: $0)?.tabKey })
            rows.append(SidebarRow(id: "\(project)/group/\(g.name)", name: g.name, state: lead.state, wait: lead.wait,
                                   kind: .group(threads: threads, sessionCount: g.sessions.count)))
        }
        // Fork families outside groups fold too: a session and the sessions forked from it.
        let loose = sessions.filter { !grouped.contains($0.tabKey) }
        var seen = Set<String>()
        for s in loose where !seen.contains(s.tabKey) {
            let family = loose.filter { $0.tabKey == s.tabKey || ($0.forkOf != nil && $0.forkOf == s.name) || (s.forkOf != nil && s.forkOf == $0.name) }
            seen.formUnion(family.map(\.tabKey))
            if let row = threadRow(family) { rows.append(row) }
        }
        var sorted = rows.sorted(by: urgency)
        // DL-59: every past session is listed; beyond the five most recent idle ones they fold
        // under "Older · N" so the list stays short.
        let idle = sorted.filter { $0.state == .idle }
        if idle.count > 7 {
            let older = Array(idle.dropFirst(5))
            let olderIDs = Set(older.map(\.id))
            sorted.removeAll { olderIDs.contains($0.id) }
            sorted.append(SidebarRow(id: "\(project)/older", name: "Older", state: .idle, wait: nil, kind: .older(rows: older)))
        }
        return sorted
    }

    static func mostUrgent(_ sessions: [Fixture.Session]) -> Fixture.Session? {
        sessions.min { a, b in a.state != b.state ? a.state < b.state : WaitTime(a.wait) > WaitTime(b.wait) }
    }

    static func urgency(_ a: SidebarRow, _ b: SidebarRow) -> Bool {
        a.state != b.state ? a.state < b.state : WaitTime(a.wait) > WaitTime(b.wait)
    }
}
