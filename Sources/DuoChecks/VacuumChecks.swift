import Foundation
import DuoSearch

/// F-596: `vacuumContent` at 246k transcripts. `DUO_CHECKS=vacuum` (`VACUUM_ROWS`, default 246,000). An index with that many
/// content rows and chunks, a tenth of the chunks removed, then each query run with no room for a large temp structure
/// (temp in memory, a small cache, a 6 MB heap cap). The new `NOT EXISTS` must use the chunks_content index, complete and
/// remove exactly the orphans; the old `NOT IN (SELECT DISTINCT …)`'s plan and result are printed for comparison.
@MainActor func vacuumChecks() throws {
    let base = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "duo-vacuum-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    let rows = Int(ProcessInfo.processInfo.environment["VACUUM_ROWS"] ?? "") ?? 246_000, orphans = rows / 10
    func make(_ name: String) throws -> SearchIndex {
        let index = try SearchIndex(at: base.appending(path: name), readOnly: false)
        let t0 = Date()
        try index.db.transaction {
            try index.db.prepare("INSERT INTO items(kind, project, path, title, modified, size, indexed) VALUES ('session', 'p', 'session:x', 'x', 0, 0, 0)").run()
            let c = try index.db.prepare("INSERT INTO content(hash, vector) VALUES (?, ?)")
            let k = try index.db.prepare("INSERT INTO chunks(item, content, start, end, text) VALUES (1, ?, 0, 0, 'w')")
            let v = Data(repeating: 0, count: 16)
            for i in 1...rows { try c.run(["h\(i)", v]); try k.run([i]) }
        }
        try index.db.exec("DELETE FROM chunks WHERE id <= \(orphans)")   // their content rows are now orphans
        print("  \(name): \(rows) content rows, \(orphans) orphaned, built in \(Int(Date().timeIntervalSince(t0))) s")
        return index
    }
    // A run that can't have a large temp structure: temp in memory, a small cache, and SQLite's hard heap limit at 6 MB
    // (process-wide; lifted after). A temp file it can't write (sandbox, TMPDIR, a full disk) fails the same query.
    func starve(_ index: SearchIndex) throws { try index.db.exec("PRAGMA temp_store=MEMORY; PRAGMA cache_size=-256; PRAGMA hard_heap_limit=\(6 << 20)") }
    func lift(_ index: SearchIndex) { try? index.db.exec("PRAGMA hard_heap_limit=0") }
    func plan(_ index: SearchIndex, _ sql: String) throws -> String {
        let s = try index.db.prepare("EXPLAIN QUERY PLAN " + sql); var out: [String] = []
        while try s.step() { out.append(s.string(3) ?? "") }
        return out.joined(separator: " / ")
    }
    let oldSQL = "DELETE FROM content WHERE id NOT IN (SELECT DISTINCT content FROM chunks)"
    let newSQL = "DELETE FROM content WHERE NOT EXISTS (SELECT 1 FROM chunks WHERE chunks.content = content.id)"
    func count(_ index: SearchIndex) throws -> Int { let s = try index.db.prepare("SELECT count(*) FROM content"); _ = try s.step(); return s.int(0) }

    let old = try make("old.sqlite")
    print("  old plan: \(try plan(old, oldSQL))")
    try starve(old)
    var oldError: String?
    let t1 = Date()
    do { try old.db.exec(oldSQL) } catch { oldError = "\(error)" }
    lift(old)
    print("  old NOT IN (SELECT DISTINCT …), no room for a temp structure: \(oldError ?? "completed") in \(Int(Date().timeIntervalSince(t1) * 1000)) ms")
    // Measured (F-596): it doesn't. SQLite runs NOT IN as an in-memory list with a bloom filter and completes even at 1.5M rows
    // under a 6 MB heap cap, so this vacuum isn't shown to be the field's "disk I/O error". Printed, not asserted.

    let new = try make("new.sqlite")
    let newPlan = try plan(new, newSQL)
    print("  new plan: \(newPlan)")
    check(newPlan.contains("USING COVERING INDEX chunks_content") && !newPlan.contains("TEMP B-TREE"), "the new vacuum probes chunks_content and builds no temp b-tree (F-596)")
    try starve(new)
    let t2 = Date()
    var newError: String?
    do { try new.vacuumContent() } catch { newError = "\(error)" }
    lift(new)
    let left = try count(new)
    print("  new vacuumContent (NOT EXISTS via chunks_content), same temp folder: \(newError ?? "completed") in \(Int(Date().timeIntervalSince(t2) * 1000)) ms, \(left) rows left")
    check(newError == nil && left == rows - orphans, "the new vacuum completes without a temp file and removes exactly the orphans (F-596)")
    let fullOld = try make("full.sqlite")
    let t3 = Date(); try fullOld.db.exec(oldSQL)
    print("  for scale, the old query with room: \(Int(Date().timeIntervalSince(t3) * 1000)) ms")
}
