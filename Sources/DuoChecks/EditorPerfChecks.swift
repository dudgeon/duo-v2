import AppKit
import DuoKit
import Foundation

// C-135: what a second editor costs (DL-278). Opt-in (`DUO_CHECKS=editorperf`), and only under the GPU
// lock's --exclusive hold: typing latency in one editor alone, then with a second editor open beside it
// on its own document, and the WebContent processes' memory before and after.
@MainActor func editorPerfChecks() throws {
    print("editor per side: typing latency and memory (C-135)")
    // It holds the GPU lock --exclusive: never past 3 minutes, whatever hangs (a page that never loads).
    DispatchQueue.global().asyncAfter(deadline: .now() + 180) {
        FileHandle.standardError.write(Data("editorperf: timed out after 180 s; exiting so the lock is released\n".utf8))
        exit(2)
    }
    setvbuf(stdout, nil, _IOLBF, 0)   // line by line, so a log shows how far it got
    let dir = FileManager.default.temporaryDirectory.appending(path: "duo-editorperf-\(UUID().uuidString.prefix(6))")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    // Documents of a realistic size: ~600 lines each.
    let para = "Trust broke at the March outage; three of six rebuild the weekly report by hand, about three hours.\n\n"
    let a = dir.appending(path: "notes.md"), b = dir.appending(path: "synthesis.md")
    try Data(("# Notes\n\n" + String(repeating: para, count: 300)).utf8).write(to: a)
    try Data(("# Synthesis\n\n" + String(repeating: para, count: 300)).utf8).write(to: b)

    func wait(_ seconds: Double = 20, _ ok: () -> Bool) -> Bool {
        let until = Date().addingTimeInterval(seconds)
        while !ok(), Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        return ok()
    }
    func bench(_ e: EditorController, _ n: Int = 400) -> (p50: Double, p95: Double, max: Double)? {
        var out: [String: Any]?, done = false
        e.run("duo.selectLines(150, 150); return duo.bench(n)", ["n": n]) { v in out = v as? [String: Any]; done = true }
        _ = wait(30) { done }
        guard let o = out, let p50 = o["p50"] as? Double, let p95 = o["p95"] as? Double, let mx = o["max"] as? Double else { return nil }
        return (p50, p95, mx)
    }
    /// Resident memory of this process's WebContent children, in MB (`footprint` would need root for some).
    func webContentMB() -> Double {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "rss=,ppid=,comm="]
        let pipe = Pipe(); p.standardOutput = pipe
        try? p.run()
        // Read before waiting: ps's output outgrows the pipe's buffer, and waiting first deadlocked (F-508).
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        // WebContent processes are launched by launchd (ppid 1), so match by name and by having started since we did.
        let mine = text.split(separator: "\n").filter { $0.contains("com.apple.WebKit.WebContent") }
        return mine.compactMap { Double($0.split(separator: " ").first ?? "") }.reduce(0, +) / 1024
    }
    func fmt(_ r: (p50: Double, p95: Double, max: Double)?) -> String {
        guard let r else { return "no result" }
        return String(format: "p50 %.2f ms, p95 %.2f ms, max %.2f ms", r.p50, r.p95, r.max)
    }

    setenv("DUO_EDITOR_DIR", repoRoot().appending(path: "Vendor/codemirror/dist").path, 1)
    let m = AppModel(fixture: try repoFixture())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
    let host = NSView(frame: window.contentView!.bounds)
    window.contentView = host
    let memBefore = webContentMB()

    let main = m.editors.editor(.main)
    main.webView.frame = NSRect(x: 0, y: 0, width: 470, height: 860)
    host.addSubview(main.webView)
    m.editors.open(a, in: .main)
    check(wait { main.phase == .open }, "the main editor opens its document")
    _ = bench(main, 50)   // warm up
    let one = bench(main)
    let memOne = webContentMB()

    let second = m.editors.editor(.second)
    second.webView.frame = NSRect(x: 471, y: 0, width: 470, height: 860)
    host.addSubview(second.webView)
    m.editors.open(b, in: .second)
    check(wait { second.phase == .open }, "the second editor opens its document beside it")
    _ = bench(second, 50)
    let twoMain = bench(main), twoSecond = bench(second)
    let memTwo = webContentMB()

    print("  one editor:              \(fmt(one))")
    print("  two editors, main side:  \(fmt(twoMain))")
    print("  two editors, second side: \(fmt(twoSecond))")
    print(String(format: "  WebContent RSS (all on the Mac): before %.0f MB, one editor %.0f MB, two editors %.0f MB (second +%.0f MB)",
                 memBefore, memOne, memTwo, memTwo - memOne))
    if let one, let twoMain {
        check(twoMain.p95 <= max(one.p95 * 1.5, one.p95 + 2), "a second editor beside it doesn't slow typing in the first (p95 \(String(format: "%.2f", one.p95)) → \(String(format: "%.2f", twoMain.p95)) ms)")
    }
    if let twoSecond { check(twoSecond.p95 < 16, "typing in the second side stays inside a frame (p95 \(String(format: "%.2f", twoSecond.p95)) ms)") }
}
