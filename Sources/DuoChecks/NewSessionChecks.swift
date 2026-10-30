import DuoControl
import DuoKit
import Foundation

// DL-253: `+` and the split pill [robot | shell] end the console strip, one click each; the Terminal / Chat
// toggle rides on the selected Claude tab.
@MainActor func newSessionChecks() throws {
    print("new session pill and the toggle on the tab (DL-253)")
    let strip = (try? String(contentsOf: repoRoot().appending(path: "Sources/DuoKit/Project/ConsoleTabStrip.swift"), encoding: .utf8)) ?? ""
    let lines = strip.split(separator: "\n").map(String.init)

    // One click each: the robot is `session new`, the shell is `shell new`.
    let robot = lines.filter { $0.contains("id: \"new-claude\"") }
    let shell = lines.filter { $0.contains("id: \"new-shell\"") }
    check(robot.count == 1 && robot[0].contains("newSession()") && robot[0].contains("// action: session new"), "the robot half runs `duo2 session new`")
    check(shell.count == 1 && shell[0].contains("model.newShell()") && shell[0].contains("// action: shell new"), "the shell half runs `duo2 shell new`")
    check(robot.first?.contains("⌘T") == false && strip.contains("New Claude session ⌘T · in") && strip.contains("New shell ⇧⌘T · in"), "the tooltips name the shortcut and the place")
    check(DuoAction.resolve(["session", "new"]) != nil && DuoAction.resolve(["shell", "new"]) != nil, "both verbs exist (DL-71)")
    check(ActionID.sessionNew.action.ui.contains("New session pill, robot half") && ActionID.shellNew.action.ui.contains("New session pill, shell half"), "Actions.swift names both halves")

    // The chevron and its menu are gone; the pill ends the strip, or starts Home's empty one.
    check(!strip.contains("PopUp.show") && !strip.contains("Chevron(direction: .down, color: dim)"), "the ⌄ menu is gone from the console strip")
    check(strip.contains("plus: { if isHome && tabs.isEmpty { newSessionPill } }") && strip.contains("edge: { if !(isHome && tabs.isEmpty) { newSessionPill } }"), "the pill ends the strip, and starts Home's empty one")

    // The toggle moved onto the tab: no longer the strip's edge, shown only on the selected Claude tab with a chat.
    check(!strip.contains("ChatToggle(key: key, light: light).padding"), "the toggle is no longer at the strip's edge")
    check(strip.contains("if showsToggle(t) { ChatToggle(key: t.id, light: light) }"), "the toggle follows the tab's name")
    let m = AppModel(fixture: try repoFixture())
    TargetState.project.apply(to: m)
    let project = m.currentProject?.name ?? ""
    let keys = m.consoleTabKeys(inProject: project)
    check(keys.count >= 2, "the console has tabs (\(keys.count))")
    let a = keys[0]
    check(!m.showsModeToggle(a), "a Claude tab with no chat shows no toggle")
    m.fixtureChats[a] = ChatSession(key: a, mode: .terminal)
    check(m.showsModeToggle(a), "a Claude tab with a chat shows the toggle")
    let shellKey = "shell:zsh"
    m.fixtureChats[shellKey] = ChatSession(key: shellKey, mode: .terminal)
    check(!m.showsModeToggle(shellKey), "a shell tab never shows the toggle")
    // Its segments are the toggle's one-click actions: Terminal and Chat, each `duo2 session chat`.
    let chrome = (try? String(contentsOf: repoRoot().appending(path: "Sources/DuoKit/Chat/ChatChrome.swift"), encoding: .utf8)) ?? ""
    check(chrome.split(separator: "\n").filter { $0.contains("PillSegment(id: \"mode-") && $0.contains("// action: session chat") }.count == 2, "the toggle's two segments each run `duo2 session chat`")
    m.setChatMode(.chat, for: a)
    check(m.chat(for: a)?.mode == .chat, "Chat segment: the tab shows chat")
    m.setChatMode(.terminal, for: a)
    check(m.chat(for: a)?.mode == .terminal, "Terminal segment: the tab shows the terminal")
}
