import DuoKit
import Foundation

// F-640: Home's session draws in two slots, Home's column at All projects and the console on Home's own page, and both
// layouts stay in the window. When chat fell back on Home's page, both slots were made in one pass and the one updated
// last took the terminal's view: Home's column, out of sight, left the console black under the fallback bar.
// On their own: `DUO_CHECKS=terminal-slot swift run DuoChecks`. The live proof is scripts/check-chat-fallback-slot-live.sh.

@MainActor func terminalSlotChecks() throws {
    print("terminal slots: the pane on screen holds the terminal (F-640)")
    for homeFirst in [true, false] {
        let order = homeFirst ? "Home's column updated first" : "the console updated first"
        let got = TerminalSlotProof.homePage(homeFirst: homeFirst, old: false)
        check(got == ["console", "home", "console"],
              "\(order): a fallback on Home's page draws in the console, All projects in Home's column, the page again in the console (\(got))")
    }
    // The rule before F-640, so this check is known to catch it: the slot updated last won, and a slot never took its view back.
    let old = TerminalSlotProof.homePage(homeFirst: false, old: true)
    check(old.first == "home", "the old rule leaves the console empty after the fallback (\(old))")
    check(TerminalSlotProof.homePage(homeFirst: true, old: true)[1] == "none", "the old rule leaves Home's column empty back at All projects")
    check(TerminalSlotProof.twoWindows(old: false), "two windows on one session: the second console keeps the view when the first is updated again (C-43)")

    // A Home session's Needs you card is an ordinary card and opens Home's page on that session (DL-336).
    print("Home's Needs you card opens Home's page (DL-336)")
    let m = AppModel(fixture: try repoFixture())
    check(m.altitude == .allProjects && m.leftCollapsed && m.visiblePanes() == [.middle, .right], "All projects has no left pane: the middle and the action column")
    m.showHomeSession("Morning triage")
    check(m.altitude == .project(m.fixture.home?.name ?? "") && m.consoleTab == "Morning triage", "the card's click opens Home's page with the session selected")
}
