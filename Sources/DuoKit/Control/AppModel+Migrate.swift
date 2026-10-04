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
