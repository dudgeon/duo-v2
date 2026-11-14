import Foundation
import CoreServices

/// Does this Mac's FSEvents service deliver at all right now (F-670)? A plain stream, none of Duo's code, on a scratch folder:
/// write a file, wait up to 6 s. On 2026-11-12/14 fseventsd sat at 100 % CPU (uptime 42 days, Darwin 27) and delivered nothing
/// to any client, so the checks that wait for the folder watcher's poke failed with no fault in Duo.
/// The checks that need a delivered event ask here first: with a working service they run and fail as usual; with a dead one
/// they print a loud SKIPPED line and count it, instead of a failure nobody can fix in the code.
/// `DUO_CHECKS_REQUIRE_FSEVENTS=1` turns a dead service back into a failure (for a machine that should have one).
final class FSEventsCanary: @unchecked Sendable {
    nonisolated(unsafe) static var skipped = 0

    private let lock = NSLock()
    private var hit = false
    private var marker = ""
    private func note(_ paths: [String]) { lock.lock(); if paths.contains(where: { $0.contains(marker) }) { hit = true }; lock.unlock() }
    private var got: Bool { lock.lock(); defer { lock.unlock() }; return hit }
    private func arm(_ m: String) { lock.lock(); marker = m; hit = false; lock.unlock() }

    private static func probe() -> Bool {
        let dir = FileManager.default.temporaryDirectory.appending(path: "duochecks-fsevents-\(getpid())")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let me = FSEventsCanary()
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(me).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            Unmanaged<FSEventsCanary>.fromOpaque(info).takeUnretainedValue().note(Array(list.prefix(count)))
        }
        guard let s = FSEventStreamCreate(nil, callback, &context, [dir.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2,
                                          FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)) else { return false }
        FSEventStreamSetDispatchQueue(s, DispatchQueue.global(qos: .utility))
        defer { FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s) }
        guard FSEventStreamStart(s) else { return false }
        Thread.sleep(forTimeInterval: 0.5)
        // Only an event for the file written now counts: the folder's own creation can be delivered late (F-670), and
        // an earlier version of this probe took that for a working service.
        let name = "canary-\(UUID().uuidString.prefix(8)).txt"
        me.arm(name)
        try? "x".write(to: dir.appending(path: name), atomically: true, encoding: .utf8)
        let until = Date().addingTimeInterval(6)
        while !me.got, Date() < until { Thread.sleep(forTimeInterval: 0.05) }
        return me.got
    }

    /// True when a check that waits for FSEvents should run; otherwise prints why it didn't (or lets it fail, when required).
    static func available(_ what: String) -> Bool {
        if ProcessInfo.processInfo.environment["DUO_CHECKS_REQUIRE_FSEVENTS"] == "1" || probe() { return true }
        skipped += 1
        print("  ⚠ SKIPPED \(what): this Mac's FSEvents service delivered no event to a plain stream within 6 s (fseventsd wedged, F-670); not a Duo fault")
        return false
    }
}
