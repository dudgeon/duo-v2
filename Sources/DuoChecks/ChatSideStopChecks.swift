import DuoKit
import Foundation

// F-689, F-691: a SubagentStop whose agent never had a SubagentStart (Claude's /btw side answer sends
// one with agent_type "") is not an Agent card's result. Run by `chatChecks()`.
@MainActor func sideStopChecks() throws {
    print("a SubagentStop with no SubagentStart leaves chat's Agent cards alone (F-689, F-691)")
    func logWithRunningAgent() -> ChatLog {
        let log = ChatLog()
        log.toolUse(id: "toolu_agent", name: "Agent", input: ["description": "Look around", "prompt": "summarise", "subagent_type": "general-purpose"], time: Date())
        return log
    }
    func stop(_ id: String?, _ type: String, _ text: String, into log: ChatLog) {
        var e: [String: Any] = ["hook_event_name": "SubagentStop", "agent_type": type, "last_assistant_message": text, "stop_hook_active": false]
        if let id { e["agent_id"] = id }
        ChatIngest.hook(e, at: Date().timeIntervalSince1970, into: log)
    }
    do {
        let log = logWithRunningAgent()
        stop("a120d35719bfb7456", "", "BTW-ANSWER: the side answer.", into: log)
        let agent = log.steps.first { $0.agent != nil }?.agent
        check(agent?.finished == false && agent?.message.isEmpty == true,
              "an unmatched stop doesn't finish or fill a running Agent card (finished: \(agent?.finished ?? true), message: \(agent?.message.prefix(30) ?? ""))")
        check(!log.items.contains { if case .note = $0 { true } else { false } }, "…and adds no 'Background agent finished' line")
        check(log.sideStops.last?.message == "BTW-ANSWER: the side answer.", "…but its text is kept for later (\(log.sideStops.count) kept)")
    }
    do {
        let log = logWithRunningAgent()
        stop(nil, "", "no id at all", into: log)
        check(log.steps.first { $0.agent != nil }?.agent?.finished == false, "a stop with no agent id doesn't finish the card either")
    }
    do {
        let log = logWithRunningAgent()
        ChatIngest.hook(["hook_event_name": "SubagentStart", "agent_id": "real1", "agent_type": "general-purpose"], at: Date().timeIntervalSince1970, into: log)
        stop("side9", "", "side answer", into: log)
        check(log.steps.first { $0.agent != nil }?.agent?.finished == false, "a side stop between a start and its stop leaves the card running")
        stop("real1", "general-purpose", "the real result", into: log)
        let agent = log.steps.first { $0.agent != nil }?.agent
        check(agent?.finished == true && agent?.message == "the real result", "the matching stop finishes the card with its own message (\(agent?.message.prefix(20) ?? ""))")
    }
}
