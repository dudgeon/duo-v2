import Darwin
import DuoKit
import Foundation

// C-30, F-126: a closed terminal is kept, and read, until its process has ended and been reaped;
// a process that is exiting counts as ended. Stand-ins write their goodbye the way Claude Code
// does (a writer thread, more than a terminal buffers), so a terminal nobody reads would hold them
// in state E for good.

/// Runs the main run loop until `done` or the deadline.
@MainActor func spin(until deadline: TimeInterval, _ done: () -> Bool) {
    let end = Date().addingTimeInterval(deadline)
    while Date() < end, !done() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
}

private func script(_ name: String, _ body: String) -> String {
    let url = FileManager.default.temporaryDirectory.appending(path: "duo-reap-\(getpid())-\(name)")
    try? body.write(to: url, atomically: true, encoding: .utf8)
    chmod(url.path, 0o755)
    return url.path
}

@MainActor func reapChecks() {
    print("terminals: a closed one is kept until its process ends (C-30, F-126)")
    check(ProcessLiveness.isEnded(stat: CChar(SZOMB), flag: 0) && ProcessLiveness.isEnded(stat: CChar(SRUN), flag: P_WEXIT)
          && !ProcessLiveness.isEnded(stat: CChar(SRUN), flag: 0) && !ProcessLiveness.isEnded(stat: CChar(SSLEEP), flag: 0),
          "a zombie or a process past exit has ended; a running or sleeping one hasn't")
    check(ProcessLiveness.isRunning(getpid()) && !ProcessLiveness.isRunning(0) && ProcessLiveness.parent(getpid()) == getppid(),
          "this process runs; its parent is read")

    // A child that exits with output its terminal never reads: exiting (E), kill -0 still reaches it.
    let holder = script("holder.py", """
        #!/usr/bin/python3 -I
        import os, pty, select, sys, threading, time
        pid, fd = pty.fork()
        if pid == 0:
            threading.Thread(target=lambda: os.write(1, b"goodbye " * 100000), daemon=True).start()
            time.sleep(0.2); os._exit(0)
        print(pid, flush=True)
        sys.stdin.readline()
        while select.select([fd], [], [], 0.5)[0]:
            try:
                if not os.read(fd, 1 << 16): break
            except OSError: break
        os.waitpid(pid, 0)
        """)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: holder)
    let out = Pipe(), inp = Pipe()
    p.standardOutput = out; p.standardInput = inp
    if (try? p.run()) != nil, let line = String(data: out.fileHandleForReading.availableData, encoding: .utf8),
       let stuck = Int32(line.trimmingCharacters(in: .whitespacesAndNewlines)) {
        spin(until: 5) { !ProcessLiveness.isRunning(stuck) }
        check(kill(stuck, 0) == 0 && !ProcessLiveness.isRunning(stuck), "a child exiting with its last output unread: kill -0 reaches it, but it has ended")
        let beacons = FileManager.default.temporaryDirectory.appending(path: "duo-reap-beacons-\(getpid())")
        try? FileManager.default.createDirectory(at: beacons, withIntermediateDirectories: true)
        for (pid, id) in [(stuck, "exiting"), (getpid(), "running")] {
            try? Data(#"{"pid":\#(pid),"sessionId":"\#(id)","cwd":"/tmp","status":"idle"}"#.utf8).write(to: beacons.appending(path: "\(pid).json"))
        }
        check(Beacon.readAll(in: beacons).map(\.sessionId) == ["running"], "its beacon doesn't count: the session isn't running, so it can be archived")
        try? FileManager.default.removeItem(at: beacons)
        inp.fileHandleForWriting.write(Data("\n".utf8))
        p.waitUntilExit()
        check(kill(stuck, 0) != 0, "read once, it ends and is reaped")
    } else {
        check(false, "the stand-in holder runs")
    }

    // The store: close keeps the terminal, still read, until the process is gone.
    let shell = ProcessInfo.processInfo.environment["SHELL"]
    defer { if let shell { setenv("SHELL", shell, 1) } else { unsetenv("SHELL") } }
    func run(_ name: String, onTerm: String) -> (TerminalStore, TerminalSession, Int32) {
        setenv("SHELL", script(name, """
            #!/usr/bin/python3 -I
            import os, signal, threading, time
            print("ready", flush=True)
            def bye(*_):
                \(onTerm)
            signal.signal(signal.SIGTERM, bye); signal.signal(signal.SIGHUP, bye)
            while True: time.sleep(0.1)
            """), 1)
        let store = TerminalStore()
        let t = store.session(name, command: .shell, cwd: NSTemporaryDirectory())
        spin(until: 5) { (t.view.process?.shellPid ?? 0) > 0 }
        spin(until: 1) { false }  // at its prompt
        return (store, t, t.view.process?.shellPid ?? 0)
    }
    // Claude's way out: its goodbye frame, then its exit hooks for a second.
    let (store, _, pid) = run("claude-like", onTerm: #"threading.Thread(target=lambda: os.write(1, b"goodbye " * 100000), daemon=True).start(); time.sleep(1); os._exit(0)"#)
    check(pid > 0, "the stand-in starts in a terminal")
    store.close("claude-like")
    check(store.existing("claude-like") == nil && store.closingCount == 1 && store.closingPids == [pid] && ProcessLiveness.isRunning(pid),
          "closed: gone from the store, kept as closing while its process ends")
    var seenExiting = false
    spin(until: 8) {
        if kill(pid, 0) == 0, !ProcessLiveness.isRunning(pid) { seenExiting = true }
        return store.closingCount == 0
    }
    check(store.closingCount == 0 && kill(pid, 0) != 0, "it ends and is reaped, and the store lets it go")
    check(!seenExiting || kill(pid, 0) != 0, "never left exiting")

    // One that ignores SIGTERM gets SIGKILL after the wait.
    let wait = TerminalStore.killAfter
    TerminalStore.killAfter = 0.5
    let (stubborn, _, spid) = run("stubborn", onTerm: "pass")
    stubborn.close("stubborn")
    spin(until: 6) { stubborn.closingCount == 0 }
    check(stubborn.closingCount == 0 && kill(spid, 0) != 0, "one that ignores SIGTERM gets SIGKILL, then is reaped")
    TerminalStore.killAfter = wait

    // Re-keying onto a key that has a terminal closes that one properly instead of dropping it.
    let (rekeyed, displaced, dpid) = run("taken", onTerm: "os._exit(0)")
    _ = rekeyed.session("other", command: .shell, cwd: NSTemporaryDirectory())
    rekeyed.rekey("other", to: "taken")
    check(rekeyed.existing("taken") !== displaced && rekeyed.closingPids == [dpid], "re-keying onto a taken key closes the terminal there")
    spin(until: 5) { rekeyed.closingCount == 0 }
    check(kill(dpid, 0) != 0, "and it is reaped")
    rekeyed.terminateAll()
}
