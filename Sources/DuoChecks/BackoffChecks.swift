import AppKit
import DuoControl
import DuoKit
import Foundation

/// DL-318 (Q-462): the idle refresh backs off, and comes straight back. `DUO_CHECKS=backoff`; also run by the core checks.
@MainActor func backoffChecks() throws {
    print("idle back-off (DL-318)")
    // The pacer by itself
    var p = RefreshPacer()
    let t0 = Date()
    check(p.due(t0), "a fresh pacer is due")
    p.started(t0)
    check(!p.due(t0.addingTimeInterval(1)) && p.due(t0.addingTimeInterval(2)), "every 2 s while things change")
    p.finished(changed: false); p.finished(changed: false)
    check(!p.backedOff, "two quiet refreshes: still 2 s")
    p.finished(changed: false)
    check(p.backedOff && p.interval == RefreshPacer.idle, "three quiet refreshes in a row: it backs off to \(Int(RefreshPacer.idle)) s")
    check(!p.due(t0.addingTimeInterval(6)) && p.due(t0.addingTimeInterval(8)), "backed off: the next refresh 8 s after the last")
    check(p.poke() && !p.backedOff && p.unchanged == 0, "a poke brings it back to 2 s and says to refresh now")
    check(!p.poke(), "a poke at 2 s changes nothing (no extra refresh per keystroke)")
    p.finished(changed: false); p.finished(changed: false); p.finished(changed: true)
    check(!p.backedOff && p.unchanged == 0, "a refresh that changed something starts the count again")

    // The core's loop, with a stand-in snapshot and a clock the check moves
    _ = NSApplication.shared
    let f = try repoFixture()
    let core = AppCore(fixture: f)
    let model = AppModel(core: core)
    _ = model
    nonisolated(unsafe) var now = Date()
    core.clock = { now }
    nonisolated(unsafe) var served = f
    core.snapshotSource = { _, _ in (served, folders: [:], moves: []) }
    core.isLive = true
    func applied() -> Int { core.passCounts["apply"] ?? 0 }
    func scans() -> Int { core.passCounts["scan"] ?? 0 }
    func settle(_ n: Int, within: TimeInterval = 5) -> Bool {
        let until = Date().addingTimeInterval(within)
        while applied() < n, Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        return applied() >= n
    }
    model.refreshLive(); _ = settle(1)   // the first snapshot is the fixture itself: unchanged from here on
    let startScans = scans()
    for _ in 0..<10 {   // 20 s of 2 s ticks
        now = now.addingTimeInterval(2)
        let before = applied()
        core.tick()
        if scans() > startScans + (before - 1) { _ = settle(before + 1) }
    }
    let quietScans = scans() - startScans
    check(core.pacer.backedOff && quietScans <= 5 && (core.passCounts["backoff"] ?? 0) >= 1,
          "20 s of ticks with nothing changing: \(quietScans) refreshes, not 10, and it backed off")

    // Each kind of change brings it straight back
    func pokeRefreshes(_ label: String, _ act: () -> Void) {
        while !core.pacer.backedOff { now = now.addingTimeInterval(2); let b = applied(); core.tick(); _ = settle(b + 1) }
        let b = applied()
        act()
        let ok = settle(b + 1, within: 4)
        check(ok && !core.pacer.backedOff, "\(label) while backed off: a refresh at once and back to 2 s")
    }
    pokeRefreshes("a poke for a file change") { core.poke("files") }
    core.watchForChanges()   // the real watcher, input monitor and activation observer
    defer { core.stopLoop() }
    pokeRefreshes("a key press in Duo") {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil,
                                 characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
        NSApp.sendEvent(e)
    }
    pokeRefreshes("Duo becoming active") { NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil) }

    // No missed needs-you: backed off, Claude writes a beacon; the needs-you snapshot arrives within seconds, not at 8 s
    var waiting = f
    if let i = waiting.sessions.firstIndex(where: { $0.state != .needsYou }) {
        waiting.sessions[i].state = .needsYou
        waiting.sessions[i].reason = "question"
        waiting.counts.needsYou += 1
    }
    while !core.pacer.backedOff { now = now.addingTimeInterval(2); let b = applied(); core.tick(); _ = settle(b + 1) }
    let notifiesBefore = core.passCounts["notify"] ?? 0, pokesBefore = core.passCounts["poke-files"] ?? 0
    served = waiting
    try FileManager.default.createDirectory(at: ClaudeStorage.sessions, withIntermediateDirectories: true)
    let beacon = ClaudeStorage.sessions.appending(path: "backoff-check-\(UUID().uuidString.prefix(6)).json")
    let started = Date()
    try #"{"sessionId":"backoff-check","status":"waiting"}"#.write(to: beacon, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: beacon) }
    let until = Date().addingTimeInterval(5)
    while core.fixture.counts.needsYou != waiting.counts.needsYou, Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    let took = Date().timeIntervalSince(started)
    check(core.fixture.counts.needsYou == waiting.counts.needsYou && took < 3,
          "backed off, a beacon written: the needs-you shows in \(String(format: "%.1f", took)) s, with no tick (the watcher's poke)")
    check((core.passCounts["notify"] ?? 0) > notifiesBefore, "and the notification pass ran for it")
    check((core.passCounts["poke-files"] ?? 0) > pokesBefore, "brought by the folder watcher's poke, not a tick")
    core.isLive = false
}
