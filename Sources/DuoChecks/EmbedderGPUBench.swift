import Foundation
import DuoSearch

/// Bench (C-161): does loading and releasing the indexing model leave GPU memory behind? `DUO_CHECKS=embedder-gpu`,
/// with `DUO_SEARCH_ROOT` a scratch folder. Prints this process's IOAccelerator after each load, embed and release.
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
    let texts = (0..<64).map { "Passage \($0): " + String(repeating: "the quick brown fox jumps over the lazy dog ", count: 20) }
    let use: Embedder.Use = ProcessInfo.processInfo.environment["EMBED_USE"] == "query" ? .query : .indexing
    print("  start: \(gpu())  use=\(use)")
    for i in 1...15 {
        autoreleasepool {
            let src = EmbedderSource { try Embedder(use: use) }
            _ = try? src.get().embedDocuments(texts)
            src.releaseIfIdle(after: 0)
        }
        print("  after cycle \(i): \(gpu())")
    }
}
