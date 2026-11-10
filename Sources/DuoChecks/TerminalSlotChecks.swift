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

    // The Needs you card for a Home session ("← Waiting in the Home terminal") points at Home's column, which starts
    // closed (DL-315). Its click chose the tab and bumped a counter nothing read: nothing happened on screen.
    print("Home's Needs you card opens Home's column (F-640)")
    let m = AppModel(fixture: try repoFixture())
    check(m.altitude == .allProjects && m.leftCollapsedAllProjects, "All projects starts with Home's column closed (DL-315)")
    m.showHomeSession("Morning triage")
    check(m.homeTab == "Morning triage" && !m.leftCollapsedAllProjects, "the card's click chooses the session's tab and opens Home's column")
    check(m.activePane == .left && m.focusHomeRequest == 1, "and Home's column is the active pane, asked for the keyboard")
    check(!m.leftTouchedAllProjects, "opening it this way isn't the person's own toggle (DL-315's flag stays off)")
}
