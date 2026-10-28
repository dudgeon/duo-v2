import DuoControl
import DuoKit
import Foundation

// The chat-fallback Debug report and log (DL-234): a report for each fallback rule, built from fixture screens.

@MainActor func chatFallbackReportChecks() {
    print("chat mode: the fallback Debug report and log (DL-234)")
    let idleText = spikeScreen("tour-2.1.291/01-markdown.txt")
    let helpText = spikeScreen("slash-2.1.292/help.txt")
    let permText = spikeScreen("10-bash-perm.txt")
    let log = ChatFallbackLog.file
    try? FileManager.default.removeItem(at: log)

    func session(_ key: String, _ screen: String, version: String? = nil) -> (ChatSession, FakeTUI) {
        let tui = FakeTUI(screen)
        let c = ChatSession(key: key, mode: .chat)
        if let version { c.setVersion(version) }
        c.attach(tui)
        return (c, tui)
    }

    // Rule: an unknown screen for longer than the grace period.
    do {
        let (c, tui) = session("sess-unknown", idleText, version: "2.1.293")
        tui.show(helpText); spin(0.8)
        let r = c.debugReport()
        check(c.fallback == .unknownScreen && c.lastFallback?.rule == "unknown-screen", "unknown screen: the rule is named")
        check(r.contains("rule: unknown-screen") && r.contains("Chat mode can’t show this screen"), "the report names the rule and carries the bar's message")
        check(r.contains("Claude Code 2.1.293") && r.contains("session sess-unknown") && r.contains("Duo "), "and the Claude Code version, the session id and Duo's version")
        check(r.contains("verdict: unknown") && r.contains("Evidence") && r.contains("full-width rules:") && r.contains("permission question: no row"), "the reader's verdict and the evidence it used")
        check(r.contains("Screen the reader judged: last") && r.contains("columns") && r.contains("footer ") && r.contains("dialog no"), "the screen's size, footer and dialog")
        check(r.contains("help") || r.contains("Help") || r.contains("shortcuts"), "the screen rows, as text")
        check(r.contains("fallback: unknown-screen:"), "the state history has the transition")
        c.backToChat()
        check(c.debugReport().contains("back to chat: Back to Chat pressed"), "and Back to Chat is a transition too")
    }

    // Rule: a dialog on a CLI version chat mode wasn't checked with.
    do {
        let (c, tui) = session("sess-version", idleText, version: "2.0.1")
        tui.show(permText); spin(0.2)
        let r = c.debugReport()
        check(c.lastFallback?.rule == "version-unverified" && r.contains("rule: version-unverified") && r.contains("version trust: unverified"), "an unverified version: rule and trust named")
        check(r.contains("permission question: row") && r.contains("dialog yes") && r.contains("verdict: permission"), "the evidence shows the dialog the reader did read")
    }

    // Rule: a dialog that doesn't match Claude's request (no hook request arrives).
    do {
        let (c, tui) = session("sess-mismatch", idleText, version: "2.1.293")
        tui.show(permText); spin(1.6)
        let r = c.debugReport()
        check(c.lastFallback?.rule == "dialog-request-mismatch" && r.contains("request pending: none"), "a dialog with no matching request: rule named, pending request none")
    }

    // Rules: a handover and a refused answer.
    do {
        let (c, _) = session("sess-answer", idleText, version: "2.1.293")
        c.fallBack(.automatic("Chat mode didn’t send your answer: the dialog changed. Here’s the terminal; chat comes back when it’s done."))
        check(c.lastFallback?.rule == "answer-refused", "a refused answer: its rule")
        let (h, _) = session("sess-hand", idleText, version: "2.1.293")
        h.fallBack(.handedOver("Amend Claude’s request here, then press Return. Chat comes back after."))
        check(h.lastFallback?.rule == "handover" && h.debugReport().contains("(handed over)"), "a handover: its rule, marked as handed over")
    }

    // A session with no fallback still gives a report.
    do {
        let (c, _) = session("sess-none", idleText, version: "2.1.293")
        check(c.debugReport().contains("No fallback has been recorded"), "no fallback yet: the report says so")
    }

    // The report keeps the last 40 rows, numbered against the whole screen.
    do {
        let long = (1...60).map { "row \($0)" }.joined(separator: "\n")
        let lines = long.components(separatedBy: "\n")
        let cap = ChatFallbackCapture(at: Date(), rule: "unknown-screen", message: "m", automatic: true, kind: "unknown", sig: "unknown", why: nil,
                                      evidence: ["e"], lines: lines, cols: 100, cliVersion: nil, trust: "unverified", pending: nil, unknownFor: 0.5,
                                      footer: false, dialog: false, mods: ["⚠ a mod: text"], session: "s")
        let r = ChatFallbackReport.text(capture: cap, current: .starting, history: [], session: "s", fallback: nil, cliVersion: nil)
        check(r.contains("last 40 of 60 rows, 100 columns") && r.contains(" 21 | row 21") && !r.contains(" 20 | row 20") && r.contains("mods ⚠ a mod: text"), "the last 40 of the screen's rows, numbered; mods listed")
        let hist = (1...15).map { ChatTransition(at: Date(), event: "fallback", reason: "t\($0)") }
        let h = ChatFallbackReport.text(capture: nil, current: .starting, history: hist, session: "s", fallback: nil, cliVersion: nil)
        check(h.contains("fallback: t15") && h.contains("fallback: t6") && !h.contains("fallback: t5\n") && !h.hasSuffix("t5"), "the last 10 transitions")
    }

    // The local log: one line per automatic fallback, with a hash and 8 rows rather than the screen.
    let recs = ChatFallbackLog.read()
    check(recs.count == 4, "four automatic fallbacks logged, the handover not (\(recs.count))")
    if let u = recs.first {
        check(u.rule == "unknown-screen" && u.nearRows.count <= 8 && u.screenHash.count == 12 && u.session == "sess-unknown" && u.cliVersion == "2.1.293", "a log line: rule, session, version, hash, at most 8 rows")
        let raw = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        check(!raw.contains("\"lines\"") && raw.split(separator: "\n").count == 4, "the full screen is not in the log")
    }
    check(ChatFallbackLog.report(recs).contains("4 automatic fallbacks logged") && ChatFallbackLog.report([]).hasPrefix("No automatic"), "duo2 session chat why --log prints them")
}
