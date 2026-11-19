import DuoControl
import DuoKit
import Foundation

// F-749: the work Mac's 2026-11-17 report. A tabbed AskUserQuestion (Audience, Form, Subject, Scope, Submit) on a
// 65×94 screen fell back with `dialog-request-mismatch`, "request pending: none" and "hooks: no event read yet":
// nothing reached the file chat reads. Two ways that happens, each checked here from the report's own screen:
// the process's hooks moved to another session's file (`/clear`, `/resume`), or Claude Code runs none of Duo's hooks.

@MainActor func chatHooksMovedChecks() throws {
    print("chat mode: a question whose hooks went elsewhere, or nowhere (F-749)")
    let screen = spikeScreen("ask-2.1.284/vision-tabs-94x65.txt")
    let idleText = spikeScreen("tour-2.1.291/01-markdown.txt")
    let q1 = "Who is the primary audience for this vision, i.e. who must read it and feel pulled toward it?"

    // The screen reads as the report says: a question, its text whole, five options under a tab strip.
    do {
        let s = ChatScreenReader.read(screen, cols: 94)
        check(screen.components(separatedBy: "\n").count >= 65 && s.kind == .question && s.question == q1 && ChatScreenReader.wellFormed(s),
              "the report's 65×94 tabbed question reads whole (\(s.kind), \(s.question ?? "nil"))")
        check(s.options.map(\.label).prefix(4) == ["The leadership team", "The engineers building it", "Customers", "Everyone in the company"],
              "and its options, one description wrapped (\(s.options.map(\.label)))")
    }

    let cfg = FileManager.default.temporaryDirectory.appending(path: "duo-moved-\(UUID().uuidString.prefix(8))")
    let cwdDir = cfg.appending(path: "work")
    try FileManager.default.createDirectory(at: cwdDir, withIntermediateDirectories: true)
    let was = getenv("CLAUDE_CONFIG_DIR").map { String(cString: $0) }
    setenv("CLAUDE_CONFIG_DIR", cfg.path, 1)
    defer {
        if let was { setenv("CLAUDE_CONFIG_DIR", was, 1) } else { unsetenv("CLAUDE_CONFIG_DIR") }
        try? FileManager.default.removeItem(at: cfg)
    }
    func q(_ text: String, _ header: String, _ labels: [String]) -> String {
        #"{"question":"\#(text)","header":"\#(header)","multiSelect":false,"options":[\#(labels.map { #"{"label":"\#($0)","description":"d"}"# }.joined(separator: ","))]}"#
    }
    let input = #"{"questions":["# + [
        q(q1, "Audience", ["The leadership team", "The engineers building it", "Customers", "Everyone in the company"]),
        q("What form should the options take?", "Form", ["A short memo each", "One page with a table"]),
        q("Which subject should the vision centre on?", "Subject", ["The product", "The platform"]),
        q("How far ahead should it look?", "Scope", ["One year", "Three years"]),
    ].joined(separator: ",") + "]}"
    let ask = #","tool_name":"AskUserQuestion","tool_input":\#(input)"#
    func event(_ sid: String, _ name: String, _ extra: String = "", cwd: String? = nil) -> String {
        #"{"at":\#(String(format: "%.3f", Date().timeIntervalSince1970)),"e":{"session_id":"\#(sid)","cwd":"\#(cwd ?? cwdDir.path)","hook_event_name":"\#(name)"\#(extra)}}"#
    }
    func events(_ sid: String, _ lines: [String]) throws {
        let url = HookEvents.file(for: sid)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
    /// A chat on the session `sid`, the report's screen up after its prompt, and the grace run out.
    func chatOnScreen(_ sid: String) -> ChatSession {
        let tui = FakeTUI(idleText)
        tui.cols = 94
        let c = ChatSession(key: sid, mode: .chat)
        c.persistsFallbackLog = false
        c.setVersion("2.1.284")
        c.attach(tui)
        c.follow(sessionId: sid, cwd: cwdDir.path)
        spin(0.3)
        tui.show(screen)
        spin(ChatSession.requestGrace + 0.5)
        return c
    }

    // `/clear` in the tab before the question: the process now writes under a new id, and Duo hasn't moved the tab.
    // The launch id's file stops at the old session's Stop; the question is in the new id's file.
    do {
        let old = "moved-old-\(UUID().uuidString.prefix(8))", new = "moved-new-\(UUID().uuidString.prefix(8))"
        try events(old, [event(old, "SessionStart", #","source":"startup""#), event(old, "UserPromptSubmit", #","prompt":"hi""#), event(old, "Stop")])
        try events(new, [event(new, "SessionStart", #","source":"clear""#), event(new, "UserPromptSubmit", #","prompt":"go""#),
                         event(new, "PreToolUse", ask + #","tool_use_id":"t1""#), event(new, "PermissionRequest", ask)])
        let c = chatOnScreen(old)
        check(c.fallback == nil && c.cardUp && c.askedQuestions.count == 4 && c.questionIndex(c.screen) == 0,
              "after /clear: the four tabbed questions come from the new session's events, the card is up, no fallback (\(c.lastFallback?.rule ?? "none"), \(c.pendingRequest?.source ?? "no request"))")
        check(c.debugReport().contains("its hooks moved"), "and the report says where the request came from")
        c.feedStop()
        try? FileManager.default.removeItem(at: HookEvents.file(for: new))
    }

    // Moved, but the other file's question was answered, or is a different question: not taken.
    do {
        let old = "moved-old2-\(UUID().uuidString.prefix(8))", new = "moved-ans-\(UUID().uuidString.prefix(8))", other = "moved-other-\(UUID().uuidString.prefix(8))"
        try events(old, [event(old, "SessionStart"), event(old, "Stop")])
        try events(new, [event(new, "PermissionRequest", ask), event(new, "PostToolUse", #","tool_name":"AskUserQuestion""#)])
        let otherAsk = ask.replacingOccurrences(of: q1, with: "Which colour should the button be?")
        let elsewhere = "moved-elsewhere-\(UUID().uuidString.prefix(8))"
        try events(other, [event(other, "PermissionRequest", otherAsk)])
        try events(elsewhere, [event(elsewhere, "PermissionRequest", ask, cwd: "/tmp/another-project")])
        let c = chatOnScreen(old)
        check(c.fallback != nil && c.pendingRequest == nil, "an answered question elsewhere, another question, or the same one in another folder is not taken (\(c.lastFallback?.rule ?? "none"))")
        c.feedStop()
        try? FileManager.default.removeItem(at: HookEvents.file(for: elsewhere))
        try? FileManager.default.removeItem(at: HookEvents.file(for: new))
        try? FileManager.default.removeItem(at: HookEvents.file(for: other))
    }

    // No hooks at all (the report: no event read yet, and nothing elsewhere either): the bar says so.
    do {
        let sid = "silent-\(UUID().uuidString.prefix(8))"
        let c = chatOnScreen(sid)
        let r = c.debugReport()
        try fallbackReportWindowChecks(r, folder: cwdDir)
        check(c.lastFallback?.rule == "hooks-silent" && (c.fallback?.message ?? "").contains("hasn’t sent Duo anything") && r.contains("no event read yet (no events file; managed settings: "),
              "no hook ever read: rule hooks-silent, and the report says there is no events file (\(c.lastFallback?.rule ?? "none"))")
        c.feedStop()
    }

    // Hooks turned off in the user's settings: the bar names the setting.
    do {
        try #"{"disableAllHooks": true}"#.write(to: cfg.appending(path: "settings.json"), atomically: true, encoding: .utf8)
        let sid = "off-\(UUID().uuidString.prefix(8))"
        let c = chatOnScreen(sid)
        check(c.lastFallback?.rule == "hooks-off" && (c.fallback?.message ?? "").contains("disableAllHooks"),
              "disableAllHooks: rule hooks-off, and the bar names the setting (\(c.fallback?.message ?? "none"))")
        c.feedStop()
        try? FileManager.default.removeItem(at: cfg.appending(path: "settings.json"))
        // A managed Mac: the organization's settings in each place Claude Code reads them (F-749).
        let md = cfg.appending(path: "managed").path, prefs = cfg.appending(path: "prefs").path
        try FileManager.default.createDirectory(atPath: md + "/managed-settings.d", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: prefs + "/someone", withIntermediateDirectories: true)
        func blocker() -> String? { HookPolicy.blocker(cwd: nil, managedDir: md, preferences: prefs, claudeDir: cfg, user: "someone") }
        let none = blocker() == nil && HookPolicy.managedPresent(managedDir: md, preferences: prefs, claudeDir: cfg, user: "someone").isEmpty
        try #"{"allowManagedHooksOnly": true}"#.write(toFile: md + "/managed-settings.d/50-security.json", atomically: true, encoding: .utf8)
        let dropIn = blocker()
        try FileManager.default.removeItem(atPath: md + "/managed-settings.d/50-security.json")
        let plist = try PropertyListSerialization.data(fromPropertyList: ["disableAllHooks": true], format: .xml, options: 0)
        try plist.write(to: URL(fileURLWithPath: prefs + "/someone/com.anthropic.claudecode.plist"))
        let mdm = blocker()
        try FileManager.default.removeItem(atPath: prefs + "/someone/com.anthropic.claudecode.plist")
        try #"{"allowManagedHooksOnly": true}"#.write(to: cfg.appending(path: "remote-settings.json"), atomically: true, encoding: .utf8)
        let remote = blocker()
        try #"{"model": "x"}"#.write(to: cfg.appending(path: "remote-settings.json"), atomically: true, encoding: .utf8)
        let present = HookPolicy.managedPresent(managedDir: md, preferences: prefs, claudeDir: cfg, user: "someone")
        try FileManager.default.removeItem(at: cfg.appending(path: "remote-settings.json"))
        check(none && dropIn == "allowManagedHooksOnly, in managed-settings.d/50-security.json" && mdm == "disableAllHooks, in MDM profile (someone)"
              && remote?.hasPrefix("allowManagedHooksOnly, in remote-settings.json") == true && present.count == 1 && blocker() == nil,
              "managed hook settings are read from a drop-in, an MDM profile and the organization's remote settings; one with no hook setting is still listed (\(dropIn ?? "-"), \(mdm ?? "-"), \(remote ?? "-"), \(present))")
    }
}
