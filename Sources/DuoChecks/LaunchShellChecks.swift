import DuoKit
import Foundation

// F-564: finding `claude` falls back to the user's login shell, which ran on the main thread at launch with no
// limit. A shell that never answers must not hold Duo's launch: the lookup gives up within its timeout, a shell
// that leaves a child holding the pipe still answers, and launch doesn't resolve on the main thread.
@MainActor func launchShellChecks() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "duochecks-launchshell-\(getpid())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    func script(_ name: String, _ body: String) throws -> String {
        let u = dir.appending(path: name)
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: u)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path)
        return u.path
    }
    let saved = (ClaudeLocator.candidates, ClaudeLocator.shell, ClaudeLocator.shellTimeout)
    defer { ClaudeLocator.candidates = saved.0; ClaudeLocator.shell = saved.1; ClaudeLocator.shellTimeout = saved.2 }
    ClaudeLocator.candidates = { [] }
    ClaudeLocator.shellTimeout = 1

    /// `found()` on another thread, given `limit` seconds; nil-nil when it never came back.
    func timedFound(limit: TimeInterval) -> (returned: Bool, path: String?, seconds: Double) {
        let sem = DispatchSemaphore(value: 0)
        let box = LockedBox()
        let start = Date()
        Thread { box.set(ClaudeLocator.found()); sem.signal() }.start()
        let ok = sem.wait(timeout: .now() + limit) == .success
        return (ok, box.get(), Date().timeIntervalSince(start))
    }

    // A login shell that never returns (a .zprofile waiting on a prompt).
    ClaudeLocator.shell = try script("hang.sh", "sleep 30")
    let hung = timedFound(limit: 4)
    check(hung.returned && hung.path == nil && hung.seconds < 3, "F-564: a login shell that never answers ends the lookup within its timeout (took \(String(format: "%.1f", hung.seconds)) s)")

    // A login shell that answers, then leaves a child holding stdout (old code waited on the pipe's end for good).
    ClaudeLocator.shell = try script("child.sh", "(sleep 30 &)\necho /bin/ls")
    let child = timedFound(limit: 4)
    check(child.returned && child.path == "/bin/ls", "F-564: a shell that answers and leaves a child holding the pipe still answers (\(child.path ?? "nil"), \(String(format: "%.1f", child.seconds)) s)")

    // An ordinary shell's answer is kept.
    ClaudeLocator.shell = try script("ok.sh", "echo /bin/ls")
    let ok = timedFound(limit: 4)
    check(ok.returned && ok.path == "/bin/ls" && ok.seconds < 1, "F-564: an ordinary login shell's answer is used")

    // Launch resolves off the main thread: DuoApp.init calls resolve() only inside a global-queue block.
    let app = (try? String(contentsOf: repoRoot().appending(path: "Sources/Duo/DuoApp.swift"), encoding: .utf8)) ?? ""
    let initBody = app.components(separatedBy: "var body: some Scene").first ?? ""
    let lines = initBody.components(separatedBy: "\n")
    let calls = lines.indices.filter { lines[$0].contains("ClaudeLocator.resolve()") }
    let offMain = calls.allSatisfy { i in lines[max(0, i - 3)...i].contains { $0.contains("DispatchQueue.global") } }
    check(!calls.isEmpty && offMain, "F-564: DuoApp.init finds claude off the main thread")
}

final class LockedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    func set(_ v: String?) { lock.lock(); value = v; lock.unlock() }
    func get() -> String? { lock.lock(); defer { lock.unlock() }; return value }
}
