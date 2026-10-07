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

// ENH-24, DL-144: the Dock menu lists what `duo2 needs-you` lists, longest wait first, and says
// how many more wait past nine; nothing waiting, Duo adds nothing to macOS's menu.
@MainActor func dockMenuChecks() {
    print("dock menu: the sessions that need you (ENH-24, DL-144)")
    guard var f = try? repoFixture() else { return check(false, "fixture loads") }
    let (items, more) = f.dockMenuItems()
    check(items.map(\.session.id) == f.needsYou.map(\.id) && more == 0, "one item per waiting session, in needs-you's order")
    check(items.first.map { $0.title == "\($0.session.name) · \($0.session.project) · \($0.session.wait ?? "now")" } == true, "titled session · project · wait")
    let menu = AppModel(fixture: f).dockMenu()
    check(menu?.items.map(\.title) == ["Needs you"] + items.map(\.title) && menu?.items.first?.isEnabled == false,
          "the menu: a disabled Needs you, then the items")
    let template = f.needsYou[0]
    f.sessions += (0..<10).map { i in var s = template; s.name = "Extra \(i)"; s.sessionId = "extra-\(i)"; return s }
    let big = f.dockMenuItems()
    check(big.items.count == 9 && big.more == f.needsYou.count - 9, "past nine: the first nine, then how many more")
    for i in f.sessions.indices where f.sessions[i].state == .needsYou { f.sessions[i].state = .idle }
    check(f.dockMenuItems().items.isEmpty && AppModel(fixture: f).dockMenu() == nil, "nothing waiting: no items, macOS's menu only")
}
