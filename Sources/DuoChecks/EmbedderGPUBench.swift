import Foundation
import DuoSearch

/// This process's IOAccelerator (graphics) line from footprint(1).
func gpu() -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/footprint"); p.arguments = ["\(getpid())"]
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
    try? p.run(); p.waitUntilExit()
    let s = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return s.split(separator: "\n").first { $0.contains("IOAccelerator (graphics)") }.map { $0.split(separator: " ", omittingEmptySubsequences: true).prefix(2).joined(separator: " ") + " regions " + ($0.split(separator: " ").dropLast(2).last ?? "") } ?? "none"
}

func mb(_ line: String) -> Double {
    line.split(separator: " ").first.flatMap { Double($0) }.map { v in line.contains(" GB") ? v * 1024 : line.contains(" KB") ? v / 1024 : v } ?? 0
}

/// The indexing model's GPU memory (C-161, F-586). `DUO_CHECKS=embedder-gpu`, with `DUO_SEARCH_ROOT` a scratch folder and
/// `EMBED_MODEL_DIR` the bundle's `Resources/search`. Core ML keeps GPU buffers per input shape while the model is loaded:
/// fails if 20 batches of different lengths leave more than 600 MB, or if fixed shapes change the vectors.
@MainActor func embedderGPUBench() throws {
    // The bundle's copy (build/Duo.app/Contents/Resources/search): the work tree's Models/ may lack the weights (LFS).
    guard let dir = ProcessInfo.processInfo.environment["EMBED_MODEL_DIR"] else { print("  set EMBED_MODEL_DIR to a folder with bge-small-fp16.mlpackage and vocab.txt"); return }
    let models = URL(fileURLWithPath: dir)
    let sem = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var installed: Error?
    Task.detached { do { _ = try await Embedder.install(package: models.appending(path: "bge-small-fp16.mlpackage"), vocab: models.appending(path: "vocab.txt")) } catch { installed = error }; sem.signal() }
    while sem.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    if let e = installed { print("  install failed: \(e)"); return }
    // EMBED_SPEED=1: ms per call at a few single shapes, one model each.
    if ProcessInfo.processInfo.environment["EMBED_SPEED"] == "1" {
        for (rows, tokens) in [(1, 64), (2, 128), (8, 256), (32, 512)] {
            let e = try Embedder(use: .indexing)
            e.fixedShapes = false
            let texts = (0..<rows).map { r in Array(repeating: "fox", count: tokens - 2).joined(separator: " ") + " \(r)" }
            _ = try? e.embedDocuments(texts)
            let t0 = Date()
            for _ in 0..<40 { autoreleasepool { _ = try? e.embedDocuments(texts) } }
            print("  \(rows) × \(tokens): \(String(format: "%.1f", Date().timeIntervalSince(t0) * 1000 / 40)) ms a call, \(Int(mb(gpu()))) MB")
        }
        return
    }
    // EMBED_ALT=1 (F-594): does switching shapes grow it? A/B alternating with the same content; then varied content at one shape.
    if ProcessInfo.processInfo.environment["EMBED_ALT"] == "1" {
        let src = EmbedderSource { try Embedder(use: .indexing) }
        let a = ["Note: " + Array(repeating: "fox", count: 40).joined(separator: " ")]
        let b = (0..<2).map { "Other \($0): " + Array(repeating: "dog", count: 100).joined(separator: " ") }
        _ = try? src.get().embedDocuments(a); _ = try? src.get().embedDocuments(b)
        let s0 = mb(gpu())
        for _ in 0..<150 { autoreleasepool { _ = try? src.get().embedDocuments(a); _ = try? src.get().embedDocuments(b) } }
        print("  A/B shapes alternating, same content, 300 calls: \(Int(s0)) → \(Int(mb(gpu()))) MB")
        src.releaseIfIdle(after: 0)
        let one = EmbedderSource { try Embedder(use: .indexing) }   // fixed shapes: 32 rows, >256 tokens, so always 32 × 512
        let pad = (0..<32).map { _ in Array(repeating: "pad", count: 480).joined(separator: " ") }
        func call(_ k: Int) -> [String] {   // varied text, always 32 rows padded to the longest (~490 tokens): one shape
            Array(((0..<(1 + k % 3)).map { c in (0..<(20 + (k * 37 + c * 11) % 380)).map { "w\(($0 * 7 + k + c) % 5000)" }.joined(separator: " ") } + pad).prefix(32))
        }
        _ = try? one.get().embedDocuments(call(0))
        let o0 = mb(gpu())
        var mid = 0.0
        for k in 1...300 { autoreleasepool { _ = try? one.get().embedDocuments(call(k)) }; if k == 150 { mid = mb(gpu()) } }
        print("  one shape (32 × 512), varied content: \(Int(o0)) MB, \(Int(mid)) at 150 calls, \(Int(mb(gpu()))) at 300")
        one.releaseIfIdle(after: 0)
        return
    }
    // EMBED_TINY=1: growth per call by shape, one model held for 150 calls each (F-594's budget).
    if ProcessInfo.processInfo.environment["EMBED_TINY"] == "1" {
        for (rows, words) in [(1, 40), (2, 100), (4, 200), (32, 470)] {
            let src = EmbedderSource { try Embedder(use: .indexing) }
            let texts = (0..<rows).map { "Note \($0): " + Array(repeating: "fox", count: words).joined(separator: " ") }
            _ = try? src.get().embedDocuments(texts)
            let start = mb(gpu())
            for _ in 0..<150 { autoreleasepool { _ = try? src.get().embedDocuments(texts) } }
            let end = mb(gpu())
            print("  rows \(rows) × ~\(words) tokens: \(Int(start)) → \(Int(end)) MB over 150 calls, \(String(format: "%.2f", (end - start) / 150)) MB a call")
            src.releaseIfIdle(after: 0)
        }
        return
    }
    // Batches of different lengths (F-586, F-593). `fixed`: the app's way, fixed shapes through an EmbedderSource that lets
    // the model go once memory has grown by `SearchService.modelMemoryBudget`; otherwise natural shapes, fresh arrays, one model held throughout
    // (the control: every call adds GPU memory while a model stays loaded).
    func run(fixed: Bool) -> (mb: Double, line: String) {
        let src = EmbedderSource { let e = try Embedder(use: .indexing); e.fixedShapes = fixed; return e }
        if fixed { src.memoryBudget = 512 << 20 }
        let batches = Int(ProcessInfo.processInfo.environment["EMBED_BATCHES"] ?? "") ?? 20   // more batches: does the ceiling hold? (test pass 0.2.25)
        for i in 1...batches {
            if fixed && batches > 20 && i % 25 == 0 { print("    fixed batch \(i): \(gpu())") }
            let words = 8 + ((i - 1) % 20 + 1) * 23   // 31 … 468 words: a different padded length each batch
            let texts = (0..<(5 + i % 27)).map { "Passage \($0): " + Array(repeating: "fox", count: words).joined(separator: " ") }
            autoreleasepool { _ = try? src.get().embedDocuments(texts) }
        }
        let line = gpu()
        src.releaseIfIdle(after: 0)
        return (mb(line), line)
    }
    // The app's way (F-593): a detached task, passes of 25 "files" of 1–3 chunks, `await` between files (the app's 15 ms
    // pause, so the work hops threads), 2 s between passes; the GPU read every 30 s. `release`: the app's policy (the model
    // goes at each pass's end and past the memory budget); otherwise one model stays loaded throughout. `reuse`: input arrays
    // kept per shape (F-594); off, fresh arrays each call (the old way).
    let minutes = Double(ProcessInfo.processInfo.environment["EMBED_SOAK_MIN"] ?? "") ?? 6
    func soak(release: Bool, fixed: Bool) -> (readings: [Double], loads: Int, loadMs: Double) {
        nonisolated(unsafe) var readings: [Double] = []
        nonisolated(unsafe) var loads = 0, loadMs = 0.0
        let done = DispatchSemaphore(value: 0)
        let words = ["session", "refresh", "project", "terminal", "history", "index", "model", "buffer", "review", "the", "and",
                     "Claude", "folder", "transcript", "search", "window", "design", "token", "shape", "memory", "leak", "Geoff"]
        Task.detached(priority: .utility) {
            let src = EmbedderSource { let t = Date(); let e = try Embedder(use: .indexing); e.fixedShapes = fixed; loadMs += Date().timeIntervalSince(t) * 1000; return e }
            if fixed { src.memoryBudget = 512 << 20 }   // the app's source: per-shape models and the budget
            let end = Date().addingTimeInterval(minutes * 60)
            var nextRead = Date(), pass = 0
            while Date() < end {
                pass += 1
                for f in 0..<25 {
                    let chunks = (0..<(1 + (pass + f) % 3)).map { c in
                        (0..<(20 + (pass * 31 + f * 17 + c * 7) % 380)).map { words[($0 * 7 + f + c + pass) % words.count] }.joined(separator: " ")
                    }
                    _ = try? src.get().embedDocuments(chunks)
                    try? await Task.sleep(for: .milliseconds(15))
                    if Date() >= nextRead { readings.append(mb(gpu())); nextRead = Date().addingTimeInterval(30) }
                }
                if release { src.releaseIfIdle(after: 0) }
                try? await Task.sleep(for: .seconds(2))
            }
            loads = src.loads
            src.releaseIfIdle(after: 0)
            done.signal()
        }
        while done.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        return (readings, loads, loads > 0 ? loadMs / Double(loads) : 0)
    }
    func plateaus(_ r: [Double]) -> Bool {
        guard r.count >= 6 else { return false }
        let half = r.count / 2
        return (r[half...].max() ?? .infinity) <= (r[..<half].max() ?? 0) + 50 && (r.max() ?? .infinity) < 600
    }
    if ProcessInfo.processInfo.environment["EMBED_SOAK"] != "0" {
        if ProcessInfo.processInfo.environment["EMBED_EXPECT_GROWTH"] == "1" {
            let c = soak(release: false, fixed: false)
            print("  soak, one model, natural shapes (control), MB every 30 s over \(Int(minutes)) min: \(c.readings.map { Int($0) })")
            check(!plateaus(c.readings), "control: one model switching shapes, kept loaded, grows")
        }
        let k = soak(release: false, fixed: true)
        print("  soak, the app's source (a model per shape, 512 MB budget), MB every 30 s: \(k.readings.map { Int($0) }); \(k.loads) loads, \(Int(k.loadMs)) ms each")
        check((k.readings.max() ?? .infinity) < 800 && k.loads <= Int(minutes) + 1,
              "busy indexing through the app's source for \(Int(minutes)) min: GPU memory stays under 800 MB, about a load a minute at most (F-594)")
    }
    // A bulk pass (F-594): 3,000 small calls of varied text through the app's source, with no end of pass. F-593's call budget
    // loaded the model every 32 calls; it must load a handful of times at most, and stay bounded.
    if ProcessInfo.processInfo.environment["EMBED_BULK"] != "0" {
        let src = EmbedderSource { try Embedder(use: .indexing) }
        src.memoryBudget = 512 << 20
        var peak = 0.0
        let t0 = Date()
        for f in 0..<3000 {
            let chunks = (0..<(1 + f % 3)).map { c in (0..<(20 + (f * 37 + c * 11) % 380)).map { "w\(($0 * 7 + f + c) % 5000)" }.joined(separator: " ") }
            autoreleasepool { _ = try? src.get().embedDocuments(chunks) }
            if f % 500 == 499 { peak = max(peak, mb(gpu())) }
        }
        let secs = Date().timeIntervalSince(t0)
        print("  bulk pass, 3,000 small calls: \(src.loads) load(s), \((try? src.get().modelCount) ?? 0) shape models, peak \(Int(peak)) MB, \(Int(secs)) s")
        check(src.loads == 1, "a bulk pass of 3,000 small batches loads the embedder once (F-594; F-593 reloaded it ~94 times)")
        check(peak < 600, "and its GPU memory stays under 600 MB")
        src.releaseIfIdle(after: 0)
    }
    // Concurrent embeds on one model (F-594): the reused arrays are taken under the Embedder's lock for the whole batch, so
    // 8 tasks at once must give exactly the serial vectors.
    if let e = try? Embedder(use: .indexing) {
        let sets = (0..<8).map { k in (0..<(1 + k % 4)).map { c in "Set \(k) passage \(c): " + (0..<(30 + k * 40)).map { "w\(($0 + k * 13 + c) % 997)" }.joined(separator: " ") } }
        let serial = sets.map { (try? e.embedDocuments($0)) ?? [] }
        nonisolated(unsafe) var parallel = [[[Float]]](repeating: [], count: sets.count)
        let group = DispatchGroup(), lock = NSLock()
        for (k, set) in sets.enumerated() {
            group.enter()
            Task.detached { let v = (try? e.embedDocuments(set)) ?? []; lock.withLock { parallel[k] = v }; group.leave() }
        }
        while group.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        let same = zip(serial, parallel).allSatisfy { a, b in a.count == b.count && zip(a, b).allSatisfy { $0 == $1 } }
        print("  concurrent embeds on one model: \(same ? "identical to serial" : "DIFFER from serial")")
        check(same && serial.allSatisfy { !$0.isEmpty }, "8 concurrent embeds on one model give exactly the serial vectors (reused arrays are never shared, F-594)")
    }
    let natural = run(fixed: false), fixed = run(fixed: true)
    print("  batches of 20 lengths: natural shapes, model held \(natural.line); fixed shapes, the app's source \(fixed.line)")
    check(fixed.mb < 800, "indexing's GPU memory stays bounded however many batches and shapes a pass sees (C-161, F-586, F-594)")
    if ProcessInfo.processInfo.environment["EMBED_EXPECT_GROWTH"] == "1" { check(natural.mb > 2 * fixed.mb, "control: without fixed shapes it grows") }
    // The same vectors either way: padded positions are masked.
    if var e = try? Embedder(use: .indexing) {
        let texts = ["How do I park a session?", "The refresh runs every two seconds off the main thread, " + String(repeating: "and it reads history ", count: 12)]
        e.fixedShapes = false
        let a = (try? e.embedDocuments(texts)) ?? []
        e.fixedShapes = true
        let b = (try? e.embedDocuments(texts)) ?? []
        let cos = zip(a, b).map { x, y in zip(x, y).map(*).reduce(0, +) }   // unit vectors (L2 inside the model)
        print("  cosine natural vs fixed: \(cos.map { String(format: "%.5f", $0) })")
        check(cos.count == 2 && cos.allSatisfy { $0 > 0.999 }, "a fixed shape gives the same vectors (cosine > 0.999)")
    }
}
