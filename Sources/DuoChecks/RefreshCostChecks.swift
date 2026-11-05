import Foundation
import DuoKit

/// The refresh's cost on a heavy user's history (F-584). `LiveSnapshot.build` runs every 2 s off the main thread; on
/// 0.2.22 it sorted all of Claude's history once per project and asked which project owns each entry by filtering
/// every project, so a Home with many projects and thousands of past sessions kept it running back to back (~60% of a
/// core, idle). `DUO_CHECKS=refresh-cost`: fails if one build of 40 projects × 6,000 sessions takes over 2.5 s (what is left is about five stats per session), or if
/// a session lands anywhere but the deepest project its folder is in, newest first.
@MainActor func refreshCostChecks() throws {
    // REFRESH_ROOT=<workspace> (with its CLAUDE_CONFIG_DIR and DUO_SUPPORT_DIR): time builds of a real fixture, for a profile.
    if let root = ProcessInfo.processInfo.environment["REFRESH_ROOT"] {
        var c = LiveSnapshot.Context(root: URL(fileURLWithPath: root))
        c.includeHistory = true
        _ = LiveSnapshot.build(c, beacons: [])
        let n = Int(ProcessInfo.processInfo.environment["REFRESH_RUNS"] ?? "") ?? 10
        let t0 = Date()
        var count = 0
        for _ in 0..<n { count = LiveSnapshot.build(c, beacons: []).0.sessions.count }
        print("  \(root): \(count) sessions, one refresh build \(Int(Date().timeIntervalSince(t0) * 1000 / Double(n))) ms")
        return
    }
    let base = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "duo-refresh-cost-\(UUID().uuidString.prefix(8))").resolvingSymlinksInPath()
    defer { try? FileManager.default.removeItem(at: base) }
    // Claude's folder is this check's own (never ~/.claude), with a real transcript per session as on a real Mac.
    let previousConfig = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
    setenv("CLAUDE_CONFIG_DIR", base.appending(path: "cfg").path, 1)
    defer { if let p = previousConfig { setenv("CLAUDE_CONFIG_DIR", p, 1) } else { unsetenv("CLAUDE_CONFIG_DIR") } }
    let home = base.appending(path: "home")
    func put(_ rel: String) throws {
        let u = home.appending(path: rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# \(u.deletingLastPathComponent().lastPathComponent)\n".write(to: u, atomically: true, encoding: .utf8)
    }
    try put("HOME.md")
    let projects = 40, perProject = 150
    for p in 0..<projects { try put("topic\(p % 5)/proj\(p)/PROJECT.md") }
    try put("topic0/proj0/inner/PROJECT.md")   // a project inside a project: the deepest wins
    var hist: [(id: String, transcript: URL, cwd: String)] = []
    func session(_ id: String, cwd: String) throws {
        let bucket = ClaudeStorage.projects.appending(path: ClaudeStorage.encode(URL(fileURLWithPath: cwd).realPath))
        try FileManager.default.createDirectory(at: bucket, withIntermediateDirectories: true)
        let t = bucket.appending(path: "\(id).jsonl")   // Claude's own layout: <bucket>/<session id>.jsonl
        // A real head: the first user record names the cwd (how `history()` files it) and the thread's root uuid.
        try ("{\"type\":\"user\",\"cwd\":\"\(cwd)\",\"uuid\":\"u-\(id)\",\"timestamp\":\"2026-11-04T10:00:00Z\",\"message\":{\"role\":\"user\",\"content\":\"hello\"}}\n"
             + "{\"type\":\"summary\",\"summary\":\"Title \(id)\"}\n").write(to: t, atomically: false, encoding: .utf8)
        hist.append((id: id, transcript: t, cwd: cwd))
    }
    for p in 0..<projects {
        for i in 0..<perProject {
            try session("s-\(p)-\(i)", cwd: home.appending(path: "topic\(p % 5)/proj\(p)" + (i % 3 == 0 ? "/src/deep" : "")).path)
        }
    }
    let innerCwd = home.appending(path: "topic0/proj0/inner/x")
    try FileManager.default.createDirectory(at: innerCwd, withIntermediateDirectories: true)
    try session("s-inner", cwd: innerCwd.path)
    var c = LiveSnapshot.Context(root: home)
    c.includeHistory = true   // the real listing (`ClaudeStorage.history()`) of this check's own Claude folder
    _ = LiveSnapshot.build(c, beacons: [])   // warm: realPath and the file system
    let runs = Int(ProcessInfo.processInfo.environment["REFRESH_RUNS"] ?? "") ?? 3   // more for a profile
    let t0 = Date()
    var snap = LiveSnapshot.build(c, beacons: []).0
    for _ in 1..<runs { snap = LiveSnapshot.build(c, beacons: []).0 }
    let ms = Date().timeIntervalSince(t0) * 1000 / Double(runs)
    print("  one refresh build, \(projects) projects × \(perProject) sessions: \(Int(ms)) ms")
    check(ms < 2500, "a refresh of 40 projects × 6,000 past sessions builds in under 2.5 s (F-584: 0.2.22 and main took 5.2 s, the fix 1.1 s)")
    let in5 = snap.sessions.filter { $0.project == "proj5" }.compactMap(\.sessionId)
    check(in5.count == perProject && Set(in5) == Set((0..<perProject).map { "s-5-\($0)" }), "every session in a project's folder, and below it, is listed in that project")
    let newest = hist.filter { $0.id.hasPrefix("s-5-") }.sorted { $0.transcript.path > $1.transcript.path }.map(\.id)
    check(in5 == newest, "a project's past sessions are in history's order, newest first")
    check(snap.sessions.first { $0.sessionId == "s-5-7" }?.name == "Title s-5-7", "a session's title comes from the transcript history names")
    check(snap.sessions.first { $0.sessionId == "s-inner" }?.project == "inner", "a session in a project inside a project belongs to the inner one")
}
