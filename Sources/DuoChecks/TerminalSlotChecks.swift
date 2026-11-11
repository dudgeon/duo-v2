import DuoKit
import Foundation

// F-640, DL-336: a terminal's view is held by the slot on screen. Home's column is gone, so a window has one console
// slot per session; two windows may show one session (C-43).
// On their own: `DUO_CHECKS=terminal-slot swift run DuoChecks`. The live proof is scripts/check-chat-fallback-slot-live.sh.

@MainActor func terminalSlotChecks() throws {
    print("terminal slots: the pane on screen holds the terminal (F-640)")
    check(TerminalSlotProof.twoWindows(), "two windows on one session: the second console keeps the view when the first is updated again (C-43)")

    // A Home session's Needs you card is an ordinary card and opens Home's page on that session (DL-336).
    print("Home's Needs you card opens Home's page (DL-336)")
    let m = AppModel(fixture: try repoFixture())
    check(m.altitude == .allProjects && m.leftCollapsed && m.visiblePanes() == [.middle, .right], "All projects has no left pane: the middle and the action column")
    m.showHomeSession("Morning triage")
    check(m.altitude == .project(m.fixture.home?.name ?? "") && m.consoleTab == "Morning triage", "the card's click opens Home's page with the session selected")
}
