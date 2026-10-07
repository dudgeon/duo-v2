import DuoKit
import Foundation

// DL-138: the Dock badge counts what `duo2 needs-you` lists, across every project and Home,
// follows sessions as they start and stop waiting, and shows nothing at 0 or when it's off.
@MainActor func dockBadgeChecks() {
    print("dock badge: the needs-you count (S3-6, DL-138)")
    guard var f = try? repoFixture() else { return check(false, "fixture loads") }
    let n = f.needsYou.count
    check(n > 0 && f.dockBadgeLabel(enabled: true) == "\(n)", "the badge is the needs-you count (\(n))")
    check(f.dockBadgeLabel(enabled: false) == nil, "switched off, the badge shows nothing")
    check(Set(f.needsYou.map(\.project)).count > 1, "the fixture's waiting sessions span projects, all counted")

    // A Home session that starts waiting counts too; so does one in a project not on screen.
    let home = f.home?.name ?? "Home"
    if let i = f.sessions.firstIndex(where: { $0.state != .needsYou }) {
        f.sessions[i].project = home; f.sessions[i].state = .needsYou
        check(f.dockBadgeLabel(enabled: true) == "\(n + 1)", "a Home session that starts waiting adds one")
    }
    // Every waiting session stops waiting: the badge clears to nothing, not "0".
    for i in f.sessions.indices where f.sessions[i].state == .needsYou { f.sessions[i].state = .working }
    check(f.dockBadgeLabel(enabled: true) == nil, "at 0 the badge clears")
}
