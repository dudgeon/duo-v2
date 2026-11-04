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
    // Batches of different lengths (F-586, F-593). `fixed`: the app's way, fixed shapes through an EmbedderSource that lets
    // the model go every `SearchService.maxModelUses` (32) uses; otherwise natural shapes through one model held throughout
    // (the control: every call adds GPU memory while a model stays loaded).
    func run(fixed: Bool) -> (mb: Double, line: String) {
        let src = EmbedderSource { let e = try Embedder(use: .indexing); e.fixedShapes = fixed; return e }
        if fixed { src.maxUses = 32 }
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
    // goes at each pass's end and after `maxModelUses`); otherwise one model stays loaded throughout (the old way).
    let minutes = Double(ProcessInfo.processInfo.environment["EMBED_SOAK_MIN"] ?? "") ?? 6
    func soak(release: Bool) -> (readings: [Double], loads: Int, loadMs: Double) {
        nonisolated(unsafe) var readings: [Double] = []
        nonisolated(unsafe) var loads = 0, loadMs = 0.0
        let done = DispatchSemaphore(value: 0)
        let words = ["session", "refresh", "project", "terminal", "history", "index", "model", "buffer", "review", "the", "and",
                     "Claude", "folder", "transcript", "search", "window", "design", "token", "shape", "memory", "leak", "Geoff"]
        Task.detached(priority: .utility) {
            let src = EmbedderSource { let t = Date(); let e = try Embedder(use: .indexing); loadMs += Date().timeIntervalSince(t) * 1000; return e }
            if release { src.maxUses = 32 }
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
            let c = soak(release: false)
            print("  soak, model kept loaded (control), MB every 30 s over \(Int(minutes)) min: \(c.readings.map { Int($0) })")
            check(!plateaus(c.readings), "control: with the model kept loaded, busy indexing's GPU memory doesn't plateau")
        }
        let t = soak(release: true)
        print("  soak, the app's policy, MB every 30 s over \(Int(minutes)) min: \(t.readings.map { Int($0) }); \(t.loads) loads, \(Int(t.loadMs)) ms each")
        check(plateaus(t.readings), "busy indexing for \(Int(minutes)) min on a detached task: GPU memory plateaus under 600 MB (F-593)")
    }
    let natural = run(fixed: false), fixed = run(fixed: true)
    print("  batches of 20 lengths: natural shapes, model held \(natural.line); fixed shapes, the app's source \(fixed.line)")
    check(fixed.mb < 600, "indexing's GPU memory stays bounded however many batches and shapes a pass sees (C-161, F-586, F-593)")
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
