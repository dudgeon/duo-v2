import DuoKit
import Foundation

// F-688 to F-690: `/btw` (Claude Code's side question) sent from chat makes chat fall back to the terminal.
// These checks reproduce it and FAIL until it is fixed; they run alone (`DUO_CHECKS=btw swift run DuoChecks`)
// and are not in the default run, so main stays green until the fix build adds them there.
//
// The screens are Claude Code 2.1.284 (the work Mac's pin) and 2.1.323 (newest here), run headless on the
// chat spike's mock API with a scratch config, 100×34 (Spikes/chat-mode/screens/btw-2.1.*; docs/research/btw-in-chat.md).
// What /btw does: it runs at once, even while Claude works (it never queues), and draws a panel in the input
// box's place: `/btw <question>`, `Answering…`, then the answer and `↑/↓ to scroll · c to copy · f to fork ·
// Esc to close`. Nothing goes into the transcript and no UserPromptSubmit fires; the answer comes only on
// screen and in a SubagentStop hook with `agent_type: ""` and no SubagentStart before it.
@MainActor func btwChecks() throws {
    func screen(_ v: String, _ name: String) -> String { spikeScreen("btw-2.1.\(v)/\(name).txt") }

    print("/btw: what the reader makes of the side-question panel (F-688)")
    for v in ["284", "323"] {
        let busy = ChatScreenReader.read(screen(v, "01-busy"), cols: 100)
        check(busy.kind == .busy, "\(v): the turn before /btw reads busy (\(busy.kind))")
        let closed = ChatScreenReader.read(screen(v, "04-closed-busy"), cols: 100)
        check(closed.kind == .busy, "\(v): after Esc, the turn still running reads busy (\(closed.kind))")
        // The bug: the panel has no input box and no footer, so it reads as unknown and chat falls back.
        var panels = ["03-panel-answer", "05-panel-idle-history"]
        if v == "323" { panels += ["02b-panel-answering", "06-panel-over-agent"] }
        for p in panels {
            let s = ChatScreenReader.read(screen(v, p), cols: 100)
            check(s.kind != .unknown, "\(v) \(p): the /btw panel is read as a side question, not an unknown screen (got \(s.kind))")
        }
    }

    print("/btw sent from chat while Claude works: chat stays (F-688)")
    for v in ["284", "323"] {
        let tui = FakeTUI(screen(v, "01-busy"))
        let chat = ChatSession(key: "btw-\(v)", mode: .chat)
        chat.attach(tui)
        check(chat.showsChat && chat.screen.kind == .busy, "\(v): chat shows a turn running")
        let typed = screen(v, "02-sent")   // the question in Claude's prompt, the turn still running
        tui.react = { keys, t in
            if keys.hasPrefix("\u{1b}[200~") { t.show(typed) }
            if keys == "\r" { t.show(screen(v, "03-panel-answer")) }
        }
        var result: ChatAnswerResult?
        Task { result = await chat.send("/btw what is two plus two") }
        let until = Date().addingTimeInterval(5)
        while result == nil, Date() < until { spin(0.02) }
        check(result?.ok == true, "\(v): the composer sends /btw while Claude works (\(String(describing: result)))")
        spin(0.8)
        check(chat.showsChat && chat.fallback == nil,
              "\(v): the side question's panel keeps chat up, no fallback (fallback: \(chat.fallback?.message ?? "none"))")
        let you = chat.log.items.compactMap { item -> ChatYou? in if case .you(let y) = item { y } else { nil } }.last
        check(you?.queued != true,
              "\(v): /btw isn't shown as queued for Claude: it runs at once and Claude's turn never reads it (queued: \(you?.queued ?? false))")
    }

    print("/btw's answer arrives as a SubagentStop with no SubagentStart: not an agent's result (F-689)")
    do {
        let log = ChatLog()
        log.toolUse(id: "toolu_agent", name: "Agent", input: ["description": "Look around", "prompt": "summarise", "subagent_type": "general-purpose"], time: Date())
        // 2.1.284 and 2.1.323 both send this for /btw (agent_type empty; the transcript path it names is never written).
        ChatIngest.hook(["hook_event_name": "SubagentStop", "agent_id": "a120d35719bfb7456", "agent_type": "",
                         "last_assistant_message": "BTW-ANSWER: the side answer.", "stop_hook_active": false], at: Date().timeIntervalSince1970, into: log)
        let agent = log.steps.first { $0.agent != nil }?.agent
        check(agent?.finished == false && agent?.message.isEmpty == true,
              "a running Agent card isn't finished with the side answer (finished: \(agent?.finished ?? false), message: \(agent?.message.prefix(30) ?? ""))")
    }
}
