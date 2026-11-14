import DuoControl
import DuoKit
import Foundation

// F-573: 0.2.23 bounced in the Dock for good when the user's login shell never answered, and hangs.jsonl stayed
// empty. `Process.waitUntilExit()` in DuoApp.init runs a nested run loop, which answered the hang monitor's pings,
// so the stuck launch never counted as a stall. A launch that doesn't finish is now logged with its stacks, and no
// app code waits on a process with `waitUntilExit()` on the main thread.
@MainActor func launchHangChecks() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "duochecks-launchhang-\(getpid())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    // A launch stuck in a nested run loop (as waitUntilExit is): the pings are answered, the launch never finishes.
    let stuck = dir.appending(path: "stuck.jsonl")
    let m = HangMonitor(log: stuck, launchLimit: 0.5)
    m.start { "test" }
    RunLoop.current.run(until: Date().addingTimeInterval(2.5))
    m.stop()
    Thread.sleep(forTimeInterval: 0.3)   // the write is on a utility queue
    let rec = HangLog.read(from: stuck)
    check(rec.contains { $0.screen.hasPrefix("launching: not finished") && $0.ongoing == true && !($0.samples ?? []).isEmpty },
          "F-573: a launch stuck in a nested run loop is logged with main-thread samples (\(rec.map(\.screen)))")

    // A launch that finishes in time logs nothing.
    let fine = dir.appending(path: "fine.jsonl")
    let ok = HangMonitor(log: fine, launchLimit: 0.5)
    ok.start { "test" }
    ok.launchFinished()
    RunLoop.current.run(until: Date().addingTimeInterval(1.2))
    ok.stop()
    Thread.sleep(forTimeInterval: 0.3)
    check(HangLog.read(from: fine).isEmpty, "F-573: a launch that finishes in time leaves no line")

    // A slow launch that does finish: its line says so and is no longer ongoing.
    let slow = dir.appending(path: "slow.jsonl")
    let s = HangMonitor(log: slow, launchLimit: 0.5)
    s.start { "test" }
    RunLoop.current.run(until: Date().addingTimeInterval(1.6))
    s.launchFinished()
    RunLoop.current.run(until: Date().addingTimeInterval(1.5))
    s.stop()
    Thread.sleep(forTimeInterval: 0.3)
    let slowRec = HangLog.read(from: slow)
    check(slowRec.count == 1 && slowRec[0].screen.hasPrefix("launching: finished") && slowRec[0].ongoing == nil,
          "F-573: a slow launch that finishes replaces its ongoing line (\(slowRec.map(\.screen)))")

    // The app said when it finished launching.
    let root = repoRoot()
    let app = (try? String(contentsOf: root.appending(path: "Sources/Duo/DuoApp.swift"), encoding: .utf8)) ?? ""
    check(app.contains("HangMonitor.shared.launchFinished()"), "F-573: DuoApp tells the hang monitor when launch has finished")

    // No app code waits on a process with waitUntilExit() except where it's off the main thread by construction.
    let offMain: Set<String> = ["Sources/DuoKit/Live/GitIgnoreOffer.swift",   // nonisolated, from Task.detached
                                "Sources/DuoKit/Debug/WindowCapture.swift"]   // scripted captures only
    var found: [String] = []
    for top in ["Sources/Duo", "Sources/DuoKit"] {
        guard let e = FileManager.default.enumerator(at: root.appending(path: top), includingPropertiesForKeys: nil) else { continue }
        for case let u as URL in e where u.pathExtension == "swift" {
            let rel = String(u.path.dropFirst(root.path.count + 1))
            guard !offMain.contains(rel), let text = try? String(contentsOf: u, encoding: .utf8) else { continue }
            if text.components(separatedBy: "\n").contains(where: { $0.contains("waitUntilExit()") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }) { found.append(rel) }
        }
    }
    check(found.isEmpty, "F-573: no waitUntilExit() in app code outside the reviewed off-main places (found in \(found))")
}
