import DuoControl
import DuoKit
import Foundation

// duo-signal, the sensor mod spike (ENH-70, DL-183, F-297): it is passed only on a CLI with mods
// that validated it, maps to chat's state only while fresh, and with the flag off changes nothing.

private func snapshot(_ at: Date, busy: Bool, aborted: Bool = false, question: String? = nil, v: Int = 1) -> Data {
    var o: [String: Any] = ["v": v, "seq": 7, "at": at.timeIntervalSince1970 * 1000, "version": "2.1.296", "busy": busy, "aborted": aborted, "turns": 2]
    if let question { o["question"] = ["tool": question, "id": "toolu_1", "input": ["command": "ls"]] }
    return try! JSONSerialization.data(withJSONObject: o)
}

@MainActor func duoSignalChecks() {
    print("duo-signal (ENH-70 spike): version gate, signal to state, stale fallback, flag off")

    // Version gating: never on a CLI without mods, an unknown one, or one the mod didn't validate on.
    let dir = "/tmp/mods/duo-signal"
    let cases: [(Bool, String?, Bool, Bool)] = [
        (true, "2.1.296", true, true), (true, "2.1.287", true, true), (true, "2.2.0", true, true),
        (true, "2.1.286", true, false), (true, "2.1.219", true, false), (true, nil, true, false), (true, "garbage", true, false),
        (true, "2.1.296", false, false), (false, "2.1.296", true, false), (false, "2.1.219", true, false),
    ]
    for (on, v, validated, want) in cases {
        let a = DuoSignal.args(on: on, cliVersion: v, validated: validated, modDir: dir)
        check(a == (want ? ["--plugin-dir", dir] : []), "flag \(on), CLI \(v ?? "unknown"), validated \(validated): \(want ? "passes the mod" : "passes nothing") (\(a))")
    }
    check(DuoSignal.args(on: true, cliVersion: "2.1.296", validated: true, modDir: nil).isEmpty, "no copy of the mod in the support folder: nothing passed")

    // Signal to state.
    let now = Date()
    let idle = ChatScreen(kind: .idle, sig: "idle"), busy = ChatScreen(kind: .busy, sig: "busy")
    guard let on = ChatSignal.parse(snapshot(now, busy: true)), let off = ChatSignal.parse(snapshot(now, busy: false)) else {
        return check(false, "the mod's snapshot parses")
    }
    check(on.busy && !off.busy && on.version == "2.1.296" && on.question == nil, "the mod's snapshot parses: busy, version, no question")
    check(on.overlay(idle, now: now).kind == .busy, "a fresh busy signal turns an idle screen busy (the turn started before the footer drew it)")
    check(off.overlay(busy, now: now).kind == .idle, "a fresh idle signal turns a busy screen idle (the turn ended before the footer redrew)")
    check(!off.overlay(busy, now: now).interrupted, "an ended turn isn't an interrupted one")
    let aborted = ChatSignal.parse(snapshot(now, busy: false, aborted: true))
    check(aborted?.overlay(busy, now: now).interrupted == true && aborted?.overlay(busy, now: now).kind == .idle, "a turn the mod saw interrupted reads as the screen's Interrupted")
    for k in [ChatScreen.Kind.permission, .plan, .question, .questionReview, .picker, .unknown, .starting] {
        check(on.overlay(ChatScreen(kind: k, sig: k.rawValue), now: now).kind == k, "a \(k.rawValue) screen stays the screen's own under a busy signal")
    }
    let q = ChatSignal.parse(snapshot(now, busy: true, question: "Bash"))
    check(q?.question == "Bash" && q?.questionId == "toolu_1" && q?.questionInput["command"] as? String == "ls", "the permission question: tool, id and input")

    // Stale fallback: the screen alone once the heartbeat stops, or from a clock that jumped.
    check(on.overlay(idle, now: now.addingTimeInterval(DuoSignal.staleAfter - 0.1)).kind == .busy, "within \(DuoSignal.staleAfter) s of the last heartbeat the signal holds")
    check(on.overlay(idle, now: now.addingTimeInterval(DuoSignal.staleAfter + 0.1)).kind == .idle, "past it, the screen alone decides (stale signal)")
    check(on.overlay(idle, now: now.addingTimeInterval(-5)).kind == .idle, "a heartbeat from the future (a clock jump) is no heartbeat")
    check(ChatSignal.parse(Data("{\"v\":1,\"seq\":3,\"at\":".utf8)) == nil, "a half-written snapshot reads as none")
    check(ChatSignal.parse(snapshot(now, busy: true, v: 2)) == nil, "another version of the mod's snapshot reads as none")
    check(ChatSignal.parse(Data("{}\n".utf8)) == nil && ChatSignal.parse(Data()) == nil, "an empty or foreign file reads as none")

    // Flag off (the default): nothing passed, nothing in the environment, chat reads the screen as on main.
    check(!DuoSignal.isOn, "the flag is off by default (DUO_SIGNAL unset in the checks)")
    DuoSignal.reset()
    DuoSignal.setValidated("/x/claude", "2.1.296", true)
    check(!DuoSignal.wasPassed("s1"), "a session not started with the mod is never read")
    let chat = ChatSession(key: "s1", mode: .chat)
    let screen = spikeScreen("tour-2.1.291/01-markdown.txt")
    chat.attach(FakeTUI(screen))
    check(chat.reread() == ChatScreenReader.read(screen) && chat.screen.kind == .idle, "with the flag off chat's screen is exactly the screen reader's")
    DuoSignal.reset()

    // The canary (F-297): what doctor says in each case, and that a CLI without mods is only asked its version.
    let at = Date(timeIntervalSince1970: 1_791_800_000)
    var c = ModCanary(at: at, claude: "/x/claude", version: "2.1.296", steps: [.init(ModCanary.hasMods, .ok, "2.1.296")])
    check(c.summary == "not checked yet.", "canary: a partial check says not checked yet (\(c.summary))")
    c.set(.init(ModCanary.installs, .ok, "copied")); c.set(.init(ModCanary.mayRun, .ok, "test passed")); c.set(.init(ModCanary.loads, .notApplicable, "off"))
    check(c.summary.hasPrefix("available:"), "canary: installs and may run, sensor off: available (\(c.summary))")
    c.set(.init(ModCanary.loads, .ok, "seen"))
    check(c.summary.hasPrefix("working:"), "canary: a session reported: working (\(c.summary))")
    c.set(.init(ModCanary.mayRun, .failed, "hooks modules are turned off here (disableAllHooks, allowManagedHooksOnly or a policy)"))
    check(c.summary.contains("mods may run here failed") && c.summary.contains("disableAllHooks"), "canary: a refusal is named, with the CLI's words (\(c.summary))")
    check(c.lines().count == 5 && c.lines()[3].hasPrefix("  ✘ Mods may run here"), "canary: doctor prints the summary and one marked line per step")
    var slow = ModCanary(at: at, claude: "/x/claude", version: "2.1.296", steps: [.init(ModCanary.hasMods, .ok, "2.1.296"), .init(ModCanary.installs, .unknown, "didn't answer in 30 s")])
    check(slow.summary.hasPrefix("no verdict yet:") && !slow.summary.contains("failed"), "canary: a CLI that didn't answer is no verdict, not a refusal (\(slow.summary))")
    slow.set(.init(ModCanary.installs, .ok, "copied"))
    let none = ModCanary(at: at, claude: "/x/claude", version: "2.1.219", steps: [.init(ModCanary.hasMods, .notApplicable, "2.1.219 has none")])
    check(none.summary.hasPrefix("not available:") && none.summary.contains("Duo works as before"), "canary: 2.1.219 is not available, and says Duo works as before")
    let sup = FileManager.default.temporaryDirectory.appending(path: "duo-canary-\(UUID().uuidString.prefix(6))")
    c.save(support: sup)
    check(ModCanary.load(support: sup) == c, "canary: saved and read back as doctor reads it")
    // A stand-in 2.1.219: the canary asks its version and nothing else (no copy, no validate, no test).
    let stub = sup.appending(path: "claude")
    try? "#!/bin/sh\necho \"$*\" >> \(sup.path)/argv.log\necho '2.1.219 (Claude Code)'\n".write(to: stub, atomically: true, encoding: .utf8)
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
    DuoSignal.canary(claude: stub.path, support: sup)
    let asked = (try? String(contentsOf: sup.appending(path: "argv.log"), encoding: .utf8)) ?? ""
    check(ModCanary.load(support: sup)?.step(ModCanary.hasMods)?.state == .notApplicable && asked == "--version\n",
          "canary on 2.1.219: not applicable, and the CLI was asked only --version (\(asked.debugDescription))")
    check(!FileManager.default.fileExists(atPath: sup.appending(path: "mods/duo-signal").path), "canary on 2.1.219: no copy of the mod")
    try? FileManager.default.removeItem(at: sup)
    DuoSignal.reset()

    // The mod itself: no hook does I/O or waits (a hook that hangs at a gating site costs 10 s and
    // can lose the question, F-297); the one write is on the heartbeat timer.
    let src = (try? String(contentsOf: repoRoot().appending(path: "Mods/duo-signal/hooks/register.js"), encoding: .utf8)) ?? ""
    check(!src.isEmpty, "the mod's source is in Mods/duo-signal")
    check(src.components(separatedBy: "$.fs.write").count == 2 && src.contains("$.clock.every(100"), "the mod writes in one place, its timer")
    check(!src.contains("$.clock.sleep") && !src.contains("$.ui.") && !src.contains("$.prompt."), "the mod never waits, draws or types")
    let hooks = src.components(separatedBy: "\n  on(").count - 1
    check(hooks >= 5 && src.components(separatedBy: "}).catch(($, e, next) => next(e))").count - 1 == hooks, "every hook has a .catch that passes the event on (\(hooks) hooks)")
}
