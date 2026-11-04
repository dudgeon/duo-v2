import Foundation
import DuoSearch

/// The indexing model's GPU memory (C-161, F-586). `DUO_CHECKS=embedder-gpu`, with `DUO_SEARCH_ROOT` a scratch folder and
/// `EMBED_MODEL_DIR` the bundle's `Resources/search`. Core ML keeps GPU buffers per input shape while the model is loaded:
/// fails if 20 batches of different lengths leave more than 600 MB, or if fixed shapes change the vectors.
@MainActor func embedderGPUBench() throws {
    // The bundle's copy (build/Duo.app/Contents/Resources/search): the work tree's Models/ may lack the weights (LFS).
    guard let dir = ProcessInfo.processInfo.environment["EMBED_MODEL_DIR"] else { print("  set EMBED_MODEL_DIR to a folder with bge-small-fp16.mlpackage and vocab.txt"); return }
    let models = URL(fileURLWithPath: dir)
    func gpu() -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/footprint"); p.arguments = ["\(getpid())"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        let s = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return s.split(separator: "\n").first { $0.contains("IOAccelerator (graphics)") }.map { $0.split(separator: " ", omittingEmptySubsequences: true).prefix(2).joined(separator: " ") + " regions " + ($0.split(separator: " ").dropLast(2).last ?? "") } ?? "none"
    }
    let sem = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var installed: Error?
    Task.detached { do { _ = try await Embedder.install(package: models.appending(path: "bge-small-fp16.mlpackage"), vocab: models.appending(path: "vocab.txt")) } catch { installed = error }; sem.signal() }
    while sem.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    if let e = installed { print("  install failed: \(e)"); return }
    // Shape count is what grows (F-586): 20 batches of different lengths through one loaded indexing model.
    func run(fixed: Bool) -> (mb: Double, line: String) {
        var e = try? Embedder(use: .indexing)
        e?.fixedShapes = fixed
        let batches = Int(ProcessInfo.processInfo.environment["EMBED_BATCHES"] ?? "") ?? 20   // more batches: does the ceiling hold? (test pass 0.2.25)
        for i in 1...batches {
            if fixed && batches > 20 && i % 25 == 0 { print("    fixed batch \(i): \(gpu())") }
            let words = 8 + ((i - 1) % 20 + 1) * 23   // 31 … 468 words: a different padded length each batch
            let texts = (0..<(5 + i % 27)).map { "Passage \($0): " + Array(repeating: "fox", count: words).joined(separator: " ") }
            autoreleasepool { _ = try? e?.embedDocuments(texts) }
        }
        let line = gpu()
        e = nil
        let mb = line.split(separator: " ").first.flatMap { Double($0) }.map { v in line.contains(" GB") ? v * 1024 : line.contains(" KB") ? v / 1024 : v } ?? 0
        return (mb, line)
    }
    let natural = run(fixed: false), fixed = run(fixed: true)
    print("  20 batch shapes, model held: natural \(natural.line); fixed \(fixed.line)")
    check(fixed.mb < 600, "indexing's GPU memory stays bounded however many batch shapes a pass sees (C-161, F-586)")
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
