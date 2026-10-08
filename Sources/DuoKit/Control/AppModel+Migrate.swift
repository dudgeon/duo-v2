import AppKit
import DuoControl
import Foundation

/// `duo2 migrate …` (CONS §6.4: the migrator executes; a person or a Claude session proposes,
/// and the user confirms in Duo). The curation surface that will call these waits for DB-31.
extension AppModel {
    func migrateVerb(_ id: ActionID, _ inv: Invocation, _ done: @escaping @MainActor (Reply) -> Void) {
        let m = Migrator()
        let live = Set(Beacon.readAll().map(\.sessionId))
        func show(_ j: Migrator.Journal) -> String {
            "\(j.id)  \(j.state.rawValue)  \(j.summary)\n" + j.steps.map { s in
                "  \(s.n). \(s.op.rawValue)  \(Self.short(s.from))\(s.op == .appendRelocated ? "  (relocatedCwd \(Self.short(s.relocatedCwd ?? "")))" : "  →  \(Self.short(s.to))")"
            }.joined(separator: "\n") + (j.warnings.isEmpty ? "" : "\n" + j.warnings.map { "  note: " + $0 }.joined(separator: "\n"))
        }
        func find(_ key: String?) -> Migrator.Journal? { key.flatMap { k in m.journals().first { $0.id == k || $0.id.hasSuffix(k) } } }
        switch id {
        case .migrations:
            let js = m.journals()
            done(.ok(js.isEmpty ? "No migrations." : js.map { "\($0.id)  \($0.state.rawValue)  \($0.summary)" }.joined(separator: "\n"),
                     js.map { ["id": $0.id, "state": $0.state.rawValue, "summary": $0.summary] }))
        case .migratePlan:
            do {
                let plan: Migrator.Journal
                switch inv[0] {
                case "relocate":
                    guard let k = inv[1], let to = inv.flags["to"] else { return done(.fail("usage: \(id.action.usage)")) }
                    let sid = findSession(k, in: nil)?.sessionId ?? k
                    plan = try m.planRelocate(sid, to: (to as NSString).expandingTildeInPath, live: live)
                case "move-folder":
                    guard let from = inv[1], let to = inv.flags["to"] else { return done(.fail("usage: \(id.action.usage)")) }
                    let open = terminals.all.map(\.cwd)
                    plan = try m.planFolderMove((from as NSString).expandingTildeInPath, to: (to as NSString).expandingTildeInPath, live: live, openFolders: open)
                default: return done(.fail("usage: \(id.action.usage)"))
                }
                try m.save(plan)
                done(.ok(show(plan) + "\nNothing has moved. Run it with `duo2 migrate apply \(plan.id)`; the user confirms in Duo."))
            } catch { done(.fail("\(error)")) }
        case .migrateApply:
            guard let j = find(inv[0]), j.state == .planned else { return done(.fail(inv[0].map { "no planned migration '\($0)'" } ?? "usage: \(id.action.usage)")) }
            guard Migrator.cliUnderstandsRelocation(ClaudeLocator.resolve()) else {
                return done(.fail("this Claude Code doesn't understand relocated sessions; only pointer moves are available (FR-7.4.8)"))
            }
            confirm(title: j.summary + "?",
                    detail: "\(j.steps.count) step(s). Transcripts move the way Claude's /cd moves them; their history isn't changed. Every step is journaled, and you can undo it.\n\n"
                        + j.warnings.joined(separator: "\n"),
                    button: "Move") { [weak self] ok in
                guard let self else { return }
                guard ok else { return done(.fail("Not moved: the user clicked Cancel in Duo. Nothing changed and nothing is pending.")) }
                do {
                    let r = try m.apply(j, live: Set(Beacon.readAll().map(\.sessionId)))
                    self.refreshLive()
                    done(.ok("Done: \(r.summary). Undo: duo2 migrate undo \(r.id)"))
                } catch { done(.fail("Stopped and put back: \(error)")) }
            }
        case .migrateUndo:
            guard let j = find(inv[0]), j.state == .committed || j.state == .applying || j.state == .reverting else {
                return done(.fail(inv[0].map { "no migration '\($0)' to undo" } ?? "usage: \(id.action.usage)"))
            }
            do { try m.undo(j); refreshLive(); done(.ok("Undid \(j.summary).")) } catch { done(.fail("\(error)")) }
        default: done(.fail("not a migrate verb"))
        }
    }

    static func short(_ p: String) -> String {
        p.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}

extension AppModel {
    /// Delete Session… (Geoff, 2026-10-04): the session and its local logs, gone for good, after the
    /// user confirms in Duo. Refused while it runs anywhere.
    public func deleteSession(_ key: String, done: (@MainActor (Result<String, Error>) -> Void)? = nil) {
        guard let s = (fixture.sessions + (fixture.archivedSessions ?? [])).first(where: { $0.tabKey == key || $0.sessionId == key }), let id = s.sessionId else {
            done?(.failure(Migrator.Refusal("no session '\(key)'"))); return
        }
        let m = Migrator()
        let plan: Migrator.Journal
        // Running in one of Duo's own terminals: Duo ends it after the user confirms. Running anywhere else
        // (a Terminal window, another Duo) is refused: Duo can't end that.
        let inDuo = terminals.existing(s.tabKey).map { !$0.exited } ?? false
        let beaconPids = Beacon.readAll().filter { $0.sessionId == id }.map(\.pid)
        let ownPids = Set(terminals.existing(s.tabKey)?.view.process.map { [$0.shellPid] } ?? [])
        let elsewhere = beaconPids.contains { !ownPids.contains($0) && !Self.isDescendant($0, of: ownPids) }
        if elsewhere || (!inDuo && !beaconPids.isEmpty) {
            done?(.failure(Migrator.Refusal("“\(s.name)” is running outside Duo. End it there first, then delete it."))); return
        }
        do {
            plan = try m.planDelete(id, live: [], extra: [SessionArchive.copyURL(id), SessionArchive.sidecarURL(id)])
        } catch { done?(.failure(error)); return }
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(plan.steps.compactMap(\.bytesBefore).reduce(0, +)), countStyle: .file)
        let list = plan.steps.prefix(8).map { "• " + Self.short($0.from) }.joined(separator: "\n") + (plan.steps.count > 8 ? "\n• and \(plan.steps.count - 8) more" : "")
        confirm(title: "Delete “\(s.name)”?",
                detail: "Its transcript goes to the Trash, and Duo’s archived copy with it (\(plan.steps.count) item\(plan.steps.count == 1 ? "" : "s"), \(bytes)). \(inDuo ? "It is running: Duo ends it first. " : "")You can put it back from the Trash, but Duo can’t undo this.\n\n\(list)",
                button: "Move to Trash") { [weak self] ok in
            guard let self else { return }
            guard ok else { done?(.failure(Migrator.Refusal("Not deleted: the user clicked Cancel in Duo. Nothing changed."))); return }
            let pids = ownPids
            if inDuo { self.terminals.close(s.tabKey) }
            if self.consoleTab == s.tabKey { self.consoleTab = nil }
            if self.homeTab == s.tabKey { self.homeTab = nil }
            // Wait (up to 8 s) for the process to end and its beacon to go before the files do; a session with no turn yet has no beacon.
            @MainActor func attempt(_ left: Int) {
                if left > 0, Beacon.readAll().contains(where: { $0.sessionId == id }) || pids.contains(where: { ProcessLiveness.isRunning($0) }) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { MainActor.assumeIsolated { attempt(left - 1) } }
                    return
                }
                do {
                    try self.applyDelete(plan, id: id, key: key)
                    done?(.success("Deleted \(s.name) and its local logs (\(bytes))."))
                } catch { done?(.failure(error)) }
            }
            attempt(40)
        }
    }

    /// Delete Task…'s sessions (DL-115): the same delete, without its own question (the task's asked).
    @discardableResult
    func deleteSessionNow(_ s: Fixture.Session) throws -> String {
        guard let id = s.sessionId else { throw Migrator.Refusal("\(s.name) has no session id") }
        let live = Set(Beacon.readAll().map(\.sessionId)).union(terminals.existing(s.tabKey).map { $0.exited ? [] : [id] } ?? [])
        let plan = try Migrator().planDelete(id, live: live, extra: [SessionArchive.copyURL(id), SessionArchive.sidecarURL(id)])
        try applyDelete(plan, id: id, key: s.tabKey)
        return "Deleted \(s.name)."
    }

    /// Whether `pid` runs under any of `parents` (Claude is a child of the terminal's shell).
    public static func isDescendant(_ pid: Int32, of parents: Set<Int32>) -> Bool {
        var p = pid
        for _ in 0..<8 {
            p = ProcessLiveness.parent(p)
            if p <= 1 { return false }
            if parents.contains(p) { return true }
        }
        return false
    }

    /// Applies a session's delete and forgets it everywhere Duo files it.
    func applyDelete(_ plan: Migrator.Journal, id: String, key: String) throws {
        try Migrator().apply(plan, live: Set(Beacon.readAll().map(\.sessionId)))
        SessionArchive.forget(id)
        // Duo's filing: out of every project's index and group.
        for folder in liveFolders.values {
            var index = SessionIndex.load(project: folder)
            let before = index
            index.sessions.removeAll { $0.sessionId == id }
            for i in index.groups.indices { index.groups[i].sessions.removeAll { $0 == id } }
            index.groups.removeAll { $0.sessions.isEmpty }
            if index != before { try? index.save(project: folder) }
        }
        DuoState.update { $0.archivedSessions.removeAll { $0 == id } }
        terminals.close(key)
        if consoleTab == key { consoleTab = nil }
        if homeTab == key { homeTab = nil }
        refreshLive()
    }
}
