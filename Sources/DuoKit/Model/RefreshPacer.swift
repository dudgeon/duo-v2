import AppKit
import CoreServices
import Foundation

/// When the live loop's tick refreshes (DL-318, Q-462). The 2 s refresh rebuilt a heavy Home's whole snapshot even when
/// nothing had changed (226 ms of 2 s at 6,150 sessions, F-598). After `quietRuns` refreshes in a row that change nothing
/// (the clock aside), it waits `idle` seconds between refreshes instead of `base`; a poke (input, a beacon, a hook event,
/// a watched folder changing) brings it back to `base` at once. Relative times ("2m ago") may lag a few seconds while idle.
public struct RefreshPacer: Equatable, Sendable {
    public static let base: TimeInterval = 2
    public static let idle: TimeInterval = 8
    public static let quietRuns = 3

    public private(set) var interval: TimeInterval = RefreshPacer.base
    public private(set) var unchanged = 0
    private var last = Date.distantPast
    public init() {}

    public var backedOff: Bool { interval > Self.base }
    /// A tick at `now` should refresh. A quarter second of slack, so a 2 s timer doesn't skip a 2 s interval.
    public func due(_ now: Date) -> Bool { now.timeIntervalSince(last) >= interval - 0.25 }
    public mutating func started(_ now: Date) { last = now }
    /// A refresh applied: `changed` is whether the snapshot differed (apart from the clock).
    public mutating func finished(changed: Bool) {
        if changed { unchanged = 0; interval = Self.base; return }
        unchanged += 1
        if unchanged >= Self.quietRuns { interval = Self.idle }
    }
    /// Something changed outside the snapshot's view of it: back to `base`, and true if it was backed off (refresh now).
    public mutating func poke() -> Bool {
        let was = backedOff
        unchanged = 0
        interval = Self.base
        return was
    }
}

/// Calls `changed` on the main thread when anything under `only` changes (FSEvents, coalesced over `latency`). It watches
/// `roots` (folders that exist: a stream started on a missing folder never reports it appearing) and drops events outside
/// `only`, so Duo's own writes elsewhere in its support folder (logs, the search index) don't count.
public final class FolderWatch: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let changed: @MainActor (String) -> Void
    public let roots: [String]
    let prefixes: [String]

    /// `changed` gets the first path that counted (for the log).
    public init(roots: [String], only: [String], latency: TimeInterval = 0.3, changed: @escaping @MainActor (String) -> Void) {
        let fm = FileManager.default
        self.roots = roots.filter { fm.fileExists(atPath: $0) }
        // Both spellings of each (FSEvents reports real paths: /private/var/…, not /var/…).
        self.prefixes = Array(Set(only.flatMap { [$0, URL(fileURLWithPath: $0).resolvingSymlinksInPath().path, Self.real($0)] }.map { $0.hasSuffix("/") ? $0 : $0 + "/" }))
        self.changed = changed
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            nonisolated(unsafe) let watch = Unmanaged<FolderWatch>.fromOpaque(info).takeUnretainedValue()
            let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            guard let hit = list.prefix(count).first(where: { p in watch.prefixes.contains { (p + "/").hasPrefix($0) } }) else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { watch.changed(hit) } }
        }
        guard !self.roots.isEmpty, let s = FSEventStreamCreate(nil, callback, &context, self.roots as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
                                                               FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)) else { return }
        FSEventStreamSetDispatchQueue(s, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(s)
        stream = s
    }

    static func real(_ path: String) -> String {
        guard let r = realpath(path, nil) else {
            // Not there yet: resolve the nearest folder that is, and put the rest back.
            let u = URL(fileURLWithPath: path)
            return u.pathComponents.count > 1 ? real(u.deletingLastPathComponent().path) + "/" + u.lastPathComponent : path
        }
        defer { free(r) }
        return String(cString: r)
    }

    public func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s)
        stream = nil
    }
    deinit { stop() }
}
