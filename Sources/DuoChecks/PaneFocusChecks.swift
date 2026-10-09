import AppKit
import DuoKit
import Foundation

// DL-165: the active pane, ⌥⌘→ / ⌥⌘←, and ⌃Tab through the active pane's tabs.
@MainActor func paneFocusChecks() throws {
    print("pane focus: the active pane and its tabs (DL-165)")

    // step
    check(PaneCycle.step([1, 2, 3], from: 1, forward: true) == 2, "step: forward")
    check(PaneCycle.step([1, 2, 3], from: 3, forward: true) == 1, "step: forward wraps")
    check(PaneCycle.step([1, 2, 3], from: 2, forward: false) == 1, "step: backward")
    check(PaneCycle.step([1, 2, 3], from: 1, forward: false) == 3, "step: backward wraps")
    check(PaneCycle.step([1, 2, 3], from: nil, forward: true) == 1 && PaneCycle.step([1, 2, 3], from: nil, forward: false) == 3, "step: no current gives the first, or the last backward")
    check(PaneCycle.step([1, 2, 3], from: 9, forward: true) == 1 && PaneCycle.step([1, 2, 3], from: 9, forward: false) == 3, "step: a current not in the list is like none")
    check(PaneCycle.step([7], from: 7, forward: true) == 7 && PaneCycle.step([7], from: 7, forward: false) == 7, "step: one item stays")
    check(PaneCycle.step([Int](), from: nil, forward: true) == nil, "step: empty is nil")

    // order
    check(PaneCycle.order(leftShown: true, rightShown: true) == [.left, .middle, .right], "order: all three")
    check(PaneCycle.order(leftShown: false, rightShown: true) == [.middle, .right], "order: left hidden")
    check(PaneCycle.order(leftShown: true, rightShown: false) == [.left, .middle], "order: right hidden")
    check(PaneCycle.order(leftShown: false, rightShown: false) == [.middle], "order: both hidden")

    // ⌃Tab
    check(PaneCycle.tabCycleDirection(keyCode: 48, flags: .control) == true, "⌃Tab is forward")
    check(PaneCycle.tabCycleDirection(keyCode: 48, flags: [.control, .shift]) == false, "⌃⇧Tab is backward")
    check(PaneCycle.tabCycleDirection(keyCode: 48, flags: []) == nil, "Tab alone is not ours")
    check(PaneCycle.tabCycleDirection(keyCode: 48, flags: .shift) == nil, "⇧Tab is not ours")
    check(PaneCycle.tabCycleDirection(keyCode: 48, flags: [.command, .control]) == nil, "⌘⌃Tab is not ours")
    check(PaneCycle.tabCycleDirection(keyCode: 48, flags: [.option, .control]) == nil, "⌥⌃Tab is not ours")
    check(PaneCycle.tabCycleDirection(keyCode: 0, flags: .control) == nil, "⌃A is not ours")

    // The model, inside a project
    let f = try repoFixture()
    let m = AppModel(fixture: f)
    TargetState.project.apply(to: m)
    check(m.activePane == .middle && m.visiblePanes() == [.left, .middle, .right], "in a project the console is active")
    m.nextPane(); check(m.activePane == .right, "next pane: the right")
    m.nextPane(); check(m.activePane == .left, "next pane wraps to the left")
    m.previousPane(); check(m.activePane == .right, "previous pane wraps back to the right")
    m.activate(.middle, focus: false)
    m.rightCollapsed = true
    check(m.visiblePanes() == [.left, .middle], "a hidden right pane is out of the order")
    m.nextPane(); check(m.activePane == .left, "next pane from the middle, right hidden: the left")
    m.activate(.right, focus: false)
    check(m.activePane == .middle, "an active pane that is hidden falls back to the middle")
    m.rightCollapsed = false
    check(m.activePane == .right, "and is active again when it comes back")
    check(DuoCommand.nextPane.isEnabled(in: m) && DuoCommand.previousPane.isEnabled(in: m), "Next and Previous Pane are enabled")
    m.rightCollapsed = true; m.leftCollapsed = true
    check(!DuoCommand.nextPane.isEnabled(in: m) && m.visiblePanes() == [.middle], "with one pane showing they are not")
    m.rightCollapsed = false; m.leftCollapsed = false

    // ⌃Tab in the console
    m.activate(.middle, focus: false)
    let consoleKeys = m.consoleTabKeys(inProject: "checkout-redesign")
    check(consoleKeys.count > 1 && m.consoleTab.map(consoleKeys.contains) == true, "the console has tabs (\(consoleKeys.count))")
    var seen: [String?] = []
    for _ in consoleKeys { m.cycleTab(forward: true); seen.append(m.consoleTab) }
    let start = consoleKeys.firstIndex(of: "PRD v2 edits") ?? 0
    check(seen == (1...consoleKeys.count).map { consoleKeys[(start + $0) % consoleKeys.count] }, "⌃Tab steps the console's tabs in order and wraps")
    m.consoleTab = consoleKeys.first
    m.cycleTab(forward: false)
    check(m.consoleTab == consoleKeys.last, "⌃⇧Tab from the first tab goes to the last")
    check(DuoCommand.nextTab.isEnabled(in: m) && DuoCommand.previousTab.isEnabled(in: m), "Show Next / Previous Tab are enabled with tabs")

    // In the right pane
    m.openDocuments = ["docs/prd-v2.md"]   // as a live project has it; the fixture's single tab only shows while selected
    m.activate(.right, focus: false)
    let rightKeys = m.rightTabKeys()
    check(rightKeys.first == "Project" && rightKeys.count > 1 && m.rightTab.map(rightKeys.contains) == true, "the right pane has tabs (\(rightKeys.joined(separator: ", ")))")
    var order: [String?] = []
    for _ in rightKeys { m.cycleTab(forward: true); order.append(m.rightTab) }
    let rstart = rightKeys.firstIndex(of: "docs/prd-v2.md") ?? 0
    check(order == (1...rightKeys.count).map { rightKeys[(rstart + $0) % rightKeys.count] }, "⌃Tab steps the right pane's tabs in order and wraps")
    check(m.activePane == .right, "stepping the right pane leaves the active pane there")
    if m.rightTab == "docs/prd-v2.md" { check(m.selectedFile == "docs/prd-v2.md", "a document tab selects its file, as a click does") }

    // A pane without tabs
    m.activate(.left, focus: false)
    let before = (m.consoleTab, m.rightTab)
    m.cycleTab(forward: true)
    check(m.consoleTab == before.0 && m.rightTab == before.1 && m.tabCount(in: .left) == 0, "the left pane has no tabs: ⌃Tab changes nothing")
    check(!DuoCommand.nextTab.isEnabled(in: m), "Show Next Tab is disabled there")

    // All projects
    let all = AppModel(fixture: f)
    TargetState.overview.apply(to: all)
    check(all.activePane == .left, "at All projects Home is active")
    check(all.homeTabKeys().count >= 2 && all.homeTab == "Morning triage", "Home has tabs")
    let home = all.homeTabKeys()
    all.cycleTab(forward: true)
    check(all.homeTab == home[(home.firstIndex(of: "Morning triage")! + 1) % home.count], "⌃Tab steps Home's tabs")
    all.cycleTab(forward: false)
    check(all.homeTab == "Morning triage", "and ⌃⇧Tab steps back")
    all.nextPane(); check(all.activePane == .middle, "next pane: the map")
    all.nextPane(); check(all.activePane == .right, "next pane: the action column")
    all.cycleTab(forward: true); check(all.homeTab == "Morning triage", "the map and column have no tabs")
    all.leftCollapsed = true
    check(all.visiblePanes() == [.middle, .right], "Home hidden at All projects is out of the order")
    all.activate(.left, focus: false)
    check(all.activePane == .middle, "a hidden Home falls back to the map")
    check(m.activePane == .left && all.activePane == .middle, "each altitude keeps its own active pane")

    check(parityGaps().isEmpty, "every command and verb has its pair: \(parityGaps().prefix(3))")
}
