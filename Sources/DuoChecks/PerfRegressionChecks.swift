import Foundation
import DuoControl
import DuoKit
import DuoSearch

/// Regression checks for the idle-CPU work (F-584, F-595, F-597..F-600): each faster path gives the old answer, and the
/// work counters (`Work`) say the per-session scans stay gone. Deterministic (no timings), so they run in the full set.
/// `DUO_CHECKS=perf`.
@MainActor func perfRegressionChecks() throws {
    print("perf regressions (idle CPU, F-584..F-600)")
    let base = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "duo-perf-\(UUID().uuidString.prefix(8))").resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    let saved = ["CLAUDE_CONFIG_DIR", "DUO_ARCHIVE_ROOT", "DUO_PERF_PROBE"].map { ($0, ProcessInfo.processInfo.environment[$0]) }
    defer {
        for (k, v) in saved { if let v { setenv(k, v, 1) } else { unsetenv(k) } }
        try? FileManager.default.removeItem(at: base)
    }

    // 1. Env.value reads getenv (F-598): setenv, empty and unset behave as the dictionary form does.
    setenv("DUO_PERF_PROBE", "on", 1)
    check(Env.value("DUO_PERF_PROBE") == "on" && Env.isSet("DUO_PERF_PROBE"), "Env.value sees a setenv at once")
    setenv("DUO_PERF_PROBE", "", 1)
    check(Env.value("DUO_PERF_PROBE") == nil && !Env.isSet("DUO_PERF_PROBE"), "an empty variable is unset (F-190, F-201)")
    unsetenv("DUO_PERF_PROBE")
    check(Env.value("DUO_PERF_PROBE") == nil, "an unset variable is nil")
    check(Env.value("X", ["X": "a"]) == "a" && Env.value("X", ["X": ""]) == nil, "the dictionary form is unchanged")

    // 2. A Claude folder with real transcripts, listed by history() (F-595): stamps, the listing map, no bucket scans.
    let cfg = base.appending(path: "cfg")
    setenv("CLAUDE_CONFIG_DIR", cfg.path, 1)
    setenv("DUO_ARCHIVE_ROOT", base.appending(path: "archive").path, 1)
    let home = base.appending(path: "home")
    for rel in ["HOME.md", "alpha/PROJECT.md", "beta/PROJECT.md"] {
        let u = home.appending(path: rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# x\n".write(to: u, atomically: true, encoding: .utf8)
    }
    var transcripts: [String: URL] = [:]
    func session(_ id: String, in project: String) throws {
        let cwd = home.appending(path: project).path
        let bucket = ClaudeStorage.projects.appending(path: ClaudeStorage.encode(URL(fileURLWithPath: cwd).realPath))
        try FileManager.default.createDirectory(at: bucket, withIntermediateDirectories: true)
        let t = bucket.appending(path: "\(id).jsonl")
        try ("{\"type\":\"user\",\"cwd\":\"\(cwd)\",\"uuid\":\"u-\(id)\",\"timestamp\":\"2026-11-05T10:00:00Z\",\"message\":{\"role\":\"user\",\"content\":\"hi\"}}\n"
             + "{\"type\":\"summary\",\"summary\":\"Title \(id)\"}\n").write(to: t, atomically: false, encoding: .utf8)
        transcripts[id] = t
    }
    func uid(_ p: String, _ i: Int) -> String { String(format: "%@0000000-0000-4000-8000-%012d", p == "a" ? "a" : "b", i) }
    for i in 0..<20 { try session(uid("a", i), in: "alpha"); try session(uid("b", i), in: "beta") }
    // A task note in alpha linking two sessions (the snapshot's task groups, F-599's index).
    try FileManager.default.createDirectory(at: home.appending(path: "alpha/tasks"), withIntermediateDirectories: true)
    try "---\ntitle: Linked\nstatus: open\nsessions:\n  - \"[one](duo2://session/\(uid("a", 3)))\"\n  - \"[two](duo2://session/\(uid("a", 7)))\"\n---\n# Linked\n"
        .write(to: home.appending(path: "alpha/tasks/linked.md"), atomically: true, encoding: .utf8)

    let history = ClaudeStorage.history()
    check(history.count == 40 && ClaudeStorage.hasListing, "history() lists the folder's 40 transcripts and keeps the listing")
    // The listing's own URLs (real paths, /private/var/…): the app always passes those back.
    let listedA3 = ClaudeStorage.listed(sessionId: uid("a", 3))
    check(listedA3?.resolvingSymlinksInPath().path == transcripts[uid("a", 3)]?.resolvingSymlinksInPath().path && ClaudeStorage.listed(sessionId: "zz") == nil,
          "the listing maps a session id to its transcript")
    let st = listedA3.flatMap { ClaudeStorage.stamp($0) }
    let real = try FileManager.default.attributesOfItem(atPath: transcripts[uid("a", 3)]!.path)
    check(st?.size == (real[.size] as? NSNumber)?.uint64Value && st?.mtime == real[.modificationDate] as? Date, "a stamp is the file's size and date")

    // 3. One snapshot build: no bucket scans, no stats behind the listing; titles, attribution and task groups as before.
    var c = LiveSnapshot.Context(root: home)
    c.includeHistory = true
    Work.reset()
    let (snap, _, _) = LiveSnapshot.build(c, beacons: [])
    check(Work.value(.bucketScan) == 0, "a refresh with a listing never lists every bucket to find a transcript (was one per session, F-595; \(Work.value(.bucketScan)))")
    check(Work.value(.statFallback) == 0, "and stats no listed transcript again (title, thread head, date: \(Work.value(.statFallback)))")
    check(snap.sessions.filter { $0.project == "alpha" }.count == 20 && snap.sessions.first { $0.sessionId == uid("b", 4) }?.project == "beta",
          "every session lands in its project")
    check(snap.sessions.first { $0.sessionId == uid("a", 3) }?.name == "Title \(uid("a", 3))", "titles come from the transcripts the listing named")
    check(snap.groups.first { $0.name == "Linked" }?.sessions == ["Title \(uid("a", 3))", "Title \(uid("a", 7))"], "a task note's sessions resolve through the index (F-599)")

    // 4. A config folder change: a listing of another folder doesn't answer (F-598).
    setenv("CLAUDE_CONFIG_DIR", base.appending(path: "other").path, 1)
    check(!ClaudeStorage.hasListing && ClaudeStorage.listed(sessionId: uid("a", 3)) == nil, "after CLAUDE_CONFIG_DIR changes, the old listing doesn't count")
    setenv("CLAUDE_CONFIG_DIR", cfg.path, 1)
    _ = ClaudeStorage.history()

    // 5. The archive: sync from stamps, purged() from the listing, the manifest decoded once per change (F-598, F-599).
    let all = history.map { (id: $0.id, transcript: $0.transcript) }
    check(try SessionArchive.sync(all) == 40, "the archive copies the 40 transcripts")
    _ = ClaudeStorage.history()
    Work.reset()
    check(try SessionArchive.sync(all) == 0, "unchanged (by the listing's stamps), none is copied again")
    check(Work.value(.statFallback) == 0, "and the archive's check stats nothing behind the listing")
    _ = SessionArchive.manifest(); _ = SessionArchive.manifest()
    check(Work.value(.manifestDecode) <= 1, "the manifest is decoded once, not on every ask (\(Work.value(.manifestDecode)))")
    try FileManager.default.removeItem(at: transcripts[uid("b", 5)]!)   // Claude's cleanup took it
    _ = ClaudeStorage.history()
    Work.reset()
    let purged = SessionArchive.purged()
    check(purged.map(\.id) == [uid("b", 5)], "purged() is exactly the session the listing no longer has (\(purged.map(\.id)))")
    check(Work.value(.bucketScan) == 0, "found without looking any transcript up by path")
    try "{\"type\":\"summary\",\"summary\":\"changed\"}\n".write(to: transcripts[uid("a", 1)]!, atomically: false, encoding: .utf8)
    _ = ClaudeStorage.history()
    check(try SessionArchive.sync(all.filter { $0.id != uid("b", 5) }) == 1, "a changed transcript is copied again")

    // 6. The session index on the core (F-598, F-600): first match, and right after the fixture changes.
    let f = try repoFixture()
    let core = AppCore(fixture: f)
    let model = AppModel(core: core)
    let keys = f.sessions.map(\.tabKey)
    check(keys.allSatisfy { k in model.session(tabKey: k) == f.sessions.first { $0.tabKey == k } }, "session(tabKey:) is fixture.sessions.first { tabKey }, for every session")
    check(model.session(tabKey: "no-such-tab") == nil, "an unknown tab is nil")
    if let first = f.sessions.first {
        var g = f
        g.sessions.removeAll { $0.tabKey == first.tabKey }
        core.fixture = g
        check(model.session(tabKey: first.tabKey) == nil, "a session removed from the fixture is gone at once")
        var renamed = first; renamed.summary = "Edited for the check"   // not `name`: a session without an id is keyed by it
        g.sessions.insert(renamed, at: 0)
        g.sessions.append(first)   // a duplicate key: the first one wins
        core.fixture = g
        check(model.session(tabKey: first.tabKey)?.summary == "Edited for the check", "a changed fixture answers with its own sessions, first match first")
        var h = g
        h.sessions[0].summary = "Edited in place"
        core.fixture.sessions = h.sessions   // a mutation through the property, not a new fixture
        check(model.session(tabKey: first.tabKey)?.summary == "Edited in place", "and after an in-place edit")
        core.fixture = f
    }

    // 7. The session list's task index (F-598): the same task as task(of:in:) for every row.
    let list = SessionList.build(f, isOpen: { _ in false })
    let rows = list.needsYou + list.sections.flatMap(\.rows) + list.earlier + list.archived
    check(!rows.isEmpty && rows.allSatisfy { $0.task == SessionList.task(of: $0.session, in: f) }, "each row's task is task(of:in:)'s answer (\(rows.count) rows)")

    // 8. Search chunks without the Core ML model (F-599).
    let vocab = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../Models/bge-small-fp16/vocab.txt").standardized
    if FileManager.default.fileExists(atPath: vocab.path) {
        let src = EmbedderSource { throw SearchError("the model must not load just to tokenize") }
        src.tokenizerLoad = { try WordPiece(vocabFile: vocab) }
        let tk = try src.tokenizer()
        check(src.loads == 0 && !src.isLoaded && !tk.encode("hello world", maxLength: 16).isEmpty, "the indexer's tokenizer loads without the model")
    }

    // 9. Every view asks the core's index for a session by tab, not a scan per row (F-600).
    let kit = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../DuoKit").standardized
    var scans: [String] = []
    for case let u as URL in FileManager.default.enumerator(at: kit, includingPropertiesForKeys: nil)! where u.pathExtension == "swift" {
        let text = (try? String(contentsOf: u, encoding: .utf8)) ?? ""
        for (n, line) in text.components(separatedBy: "\n").enumerated()
        where line.range(of: #"fixture\.sessions\.first(\(where: | )\{ \$0\.tabKey == [^|&}]+\}"#, options: .regularExpression) != nil && !line.contains("///") {
            scans.append("\(u.lastPathComponent):\(n + 1)")
        }
    }
    check(scans.isEmpty, "no `fixture.sessions.first { $0.tabKey == … }` in DuoKit: use session(tabKey:) (\(scans.prefix(5).joined(separator: ", ")))")

    // 10. The terminal mic's 20 Hz tick reads a screen once until it changes (F-599): with Claude's input box on it, and
    // without one (the case that read every tick, because hiding the chip cleared what it had seen).
    let box = String(repeating: "─", count: 78)
    for (label, screen) in [("no input box", "Some reply text from Claude\nand a second line\n"),
                            ("Claude's input box", "Reply above\n\n╭\(box)╮\n│ > \(String(repeating: " ", count: 75))│\n╰\(box)╯\n")] {
        let r = PerfProbe.micReads(screen: screen, ticks: 50)
        check(r.idle <= 1, "mic, \(label): 50 idle ticks read the screen at most once (\(r.idle); was 50)")
        check(r.afterOutput >= 1 && r.afterOutput <= 1, "mic, \(label): new output is read once (\(r.afterOutput))")
        check(r.afterInput >= 1 && r.afterInput <= 1, "mic, \(label): a key, click or scroll makes it read again (\(r.afterInput))")
    }

    // 11. The folder watch reports only what's under its folders (DL-318).
    let watched = base.appending(path: "w/watched"), other = base.appending(path: "w/other")
    try FileManager.default.createDirectory(at: watched, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    nonisolated(unsafe) var seen: [String] = []
    let watch = FolderWatch(roots: [base.appending(path: "w").path], only: [watched.path]) { seen.append($0) }
    defer { watch.stop() }
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    seen.removeAll()   // FSEvents may still deliver the folders' own creation, from just before the stream began
    try "x".write(to: other.appending(path: "noise.txt"), atomically: true, encoding: .utf8)
    RunLoop.main.run(until: Date().addingTimeInterval(1.2))
    check(seen.isEmpty, "a change outside the watched folders doesn't count (Duo's own logs and index)")
    try "x".write(to: watched.appending(path: "beacon.json"), atomically: true, encoding: .utf8)
    let until = Date().addingTimeInterval(3)
    while !seen.contains(where: { $0.contains("/watched/") }), Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    check(seen.contains { $0.contains("/watched/") }, "a change inside one does, with its path (\(seen.prefix(2)))")
}
