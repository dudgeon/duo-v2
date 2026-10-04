import AppKit
import WebKit

// Pass/fail, written first (stack rec spike 4, research §7.4):
// 1. Unedited documents round-trip byte for byte: legacy tasks.md, about-duo.md (HTML comments),
//    a 1.2 MB file, a CRLF file.
// 2. One command (bold) changes only the selected range.
// 3. Typing proxy on the 1.2 MB file: p95 under 16 ms.
// 4. WebContent RSS with the 1.2 MB file open under 150 MB.
// 5. External edits: applied with the caret kept; merged with a disjoint local edit; overlapping
//    edits reported as a conflict with nothing applied.
// 6. Agent insert is highlighted ("added by Claude").
// 7. Find moves the selection to the match.
// Not checkable headless (screen locked): spellcheck, dictation, Writing Tools, native caret.

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let dist = repo.appending(path: "Vendor/codemirror/dist")

@MainActor final class Host: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let web: WKWebView
    var ready: CheckedContinuation<Void, Never>?
    init(_ unused: Void = ()) {
        let cfg = WKWebViewConfiguration()
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 800), configuration: cfg)
        super.init()
        web.configuration.userContentController.add(self, name: "duo")  // the view copied cfg
        web.navigationDelegate = self
    }
    var loaded: CheckedContinuation<String, Never>?
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { loaded?.resume(returning: "finished"); loaded = nil }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { loaded?.resume(returning: "failed \(e)"); loaded = nil }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { loaded?.resume(returning: "failed \(e)"); loaded = nil }
    func userContentController(_ u: WKUserContentController, didReceive m: WKScriptMessage) {
        if let b = m.body as? [String: Any], b["kind"] as? String == "ready" { ready?.resume(); ready = nil }
    }
    func js(_ code: String, _ args: [String: Any] = [:]) async throws -> Any? {
        try await web.callAsyncJavaScript(code, arguments: args, contentWorld: .page)
    }
}

/// pid → RSS (KB) of every process whose command contains `name`.
func processes(named name: String) -> [Int: Int] {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/ps"); p.arguments = ["-axo", "pid=,rss=,comm="]
    let out = Pipe(); p.standardOutput = out; try? p.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()  // read before waiting: a full pipe blocks ps
    p.waitUntilExit()
    let text = String(data: data, encoding: .utf8) ?? ""
    var found: [Int: Int] = [:]
    for line in text.split(separator: "\n") where line.contains(name) {
        let f = line.split(separator: " ", omittingEmptySubsequences: true)
        if f.count >= 2, let pid = Int(f[0]), let kb = Int(f[1]) { found[pid] = kb }
    }
    return found
}

@MainActor func run() async {
    let html = """
    <!doctype html><meta charset=utf-8><style>
    body{margin:0;font:13px -apple-system} #editor{height:100vh}
    .duo-h1{font-size:1.6em;font-weight:600}.duo-h2{font-size:1.3em;font-weight:600}.duo-strong{font-weight:600}
    .duo-em{font-style:italic}.duo-code{font-family:ui-monospace}.duo-link{color:#0a66c2}.duo-added{background:#fff3c4}
    </style><div id=editor></div><script src="cm6.js"></script>
    """
    try? html.write(to: dist.appending(path: "s4.html"), atomically: true, encoding: .utf8)
    let before = processes(named: "WebKit.WebContent")
    let h = Host()
    var results: [(String, Bool)] = [] {
        didSet { if let l = results.last { print("\(l.1 ? "✔" : "✘") \(l.0)") } }
    }
    let nav = await withCheckedContinuation { c in
        h.loaded = c
        h.web.loadFileURL(dist.appending(path: "s4.html"), allowingReadAccessTo: dist)
    }
    print("navigation: \(nav)")
    if let flags = ProcessInfo.processInfo.environment["DUO_FLAGS"] {
        _ = try? await h.js("window.duoFlags = Object.fromEntries(f.split(',').map(k => [k, true]))", ["f": flags])
    }
    for _ in 0..<100 {
        if let t = try? await h.js("return typeof window.duo"), t as? String == "object" { break }
        try? await Task.sleep(for: .milliseconds(100))
    }
    func mem(_ label: String) { let m = processes(named: "WebKit.WebContent").filter { before[$0.key] == nil }; print("  RSS \(label): \(m.values.map { $0 / 1024 }) MB") }
    mem("page loaded, empty")
    print("loaded: duo is \((try? await h.js("return typeof window.duo")) as? String ?? "unreachable")")

    let tasks = try! Data(contentsOf: URL(fileURLWithPath: NSString(string: "~/repos/duo/tasks.md").expandingTildeInPath))
    let about = try! Data(contentsOf: URL(fileURLWithPath: NSString(string: "~/repos/duo/docs/about-duo.md").expandingTildeInPath))
    var big = Data(); while big.count < 1_200_000 { big.append(tasks) }
    let crlf = Data(String(decoding: about, as: UTF8.self).replacingOccurrences(of: "\n", with: "\r\n").utf8)

    // 1. Round trips.
    for (name, data) in [("tasks.md 385 KB", tasks), ("about-duo.md", about), ("1.2 MB", big), ("CRLF", crlf)] {
        let t0 = Date()
        let info: Any?
        do { info = try await h.js("return duo.create(text)", ["text": String(decoding: data, as: UTF8.self)]) } catch { print("  create threw: \(error)"); info = nil }

        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        let back = (try? await h.js("return duo.text()")) as? String ?? ""
        results.append(("1 \(name): opens in \(ms) ms, byte-identical (\(info.map { "\($0)" } ?? ""))", Data(back.utf8) == data))
    }

    mem("after four documents")
    // 2. Bold changes only the selection, on the 1.2 MB doc.
    _ = try? await h.js("duo.create(text)", ["text": String(decoding: big, as: UTF8.self)])
    let beforeText = (try? await h.js("return duo.text()")) as? String ?? ""
    _ = try? await h.js("duo.select(100, 110); return duo.exec('bold')")
    let after = (try? await h.js("return duo.text()")) as? String ?? ""
    let b = Array(beforeText.utf16), a = Array(after.utf16)
    let expected = Array(beforeText.utf16.prefix(100)) + Array("**".utf16) + Array(b[100..<110]) + Array("**".utf16) + Array(b[110...])
    results.append(("2 bold edits only the selection (+4 chars)", a == expected))

    mem("1.2 MB open")
    // 3. Typing proxy.
    _ = try? await h.js("duo.select(600000)")
    if ProcessInfo.processInfo.environment["DUO_SLOW"] != nil { mem("before the latency burst") }
    if ProcessInfo.processInfo.environment["DUO_SLOW"] == nil, let s = (try? await h.js("return duo.bench(300)")) as? [String: Any] {
        let p95 = s["p95"] as? Double ?? 99
        results.append((String(format: "3 typing proxy on 1.2 MB: p50 %.2f ms, p95 %.2f ms, max %.2f ms", s["p50"] as? Double ?? 0, p95, s["max"] as? Double ?? 0), p95 < 16))
    }

    // 4. RSS.
    mem("after 300 typed characters")
    for round in 2...4 {
        if ProcessInfo.processInfo.environment["DUO_SLOW"] != nil {
            // Paced from Swift: a hidden web view throttles its own timers.
            for _ in 0..<300 {
                _ = try? await h.js("const at = duo.caret(); duo.typeOne(at)")
                try? await Task.sleep(for: .milliseconds(30))
            }
        } else {
            _ = try? await h.js("return duo.bench(300)")
        }
        try? await Task.sleep(for: .seconds(1))
        mem("after round \(round) (\(round * 300) characters)")
    }
    _ = try? await h.js("duo.create('')")
    try? await Task.sleep(for: .seconds(2))
    mem("after closing to an empty doc (+2 s)")
    _ = try? await h.js("duo.create(text)", ["text": String(decoding: big, as: UTF8.self)])
    let mine = processes(named: "WebKit.WebContent").filter { before[$0.key] == nil }
    let kb = mine.values.max() ?? 0
    results.append(("4 WebContent RSS \(kb / 1024) MB", kb > 0 && kb < 150 * 1024))

    // 2b. An edit in a CRLF document keeps CRLF everywhere.
    _ = try? await h.js("duo.create(t); duo.select(3, 8); duo.exec('bold')", ["t": String(decoding: crlf, as: UTF8.self)])
    let crlfAfter = (try? await h.js("return duo.text()")) as? String ?? ""
    let bareLF = crlfAfter.utf8.enumerated().contains { i, c in c == 10 && (i == 0 || Array(crlfAfter.utf8)[i - 1] != 13) }
    results.append(("2b edited CRLF document keeps CRLF line endings", !bareLF && crlfAfter.utf8.count == crlf.count + 4))

    // 5. External edits on a small doc.
    let doc = "# Title\n\nalpha line\n\nmiddle\n\nomega line\n"
    _ = try? await h.js("duo.create(t); duo.markSaved(); duo.select(t.indexOf('middle') + 3)", ["t": doc])
    let disk1 = doc.replacingOccurrences(of: "alpha line", with: "alpha line, edited outside")
    let r1 = (try? await h.js("return duo.external(d)", ["d": disk1])) as? [String: Any]
    let caret = (try? await h.js("return duo.caret()")) as? Int ?? -1
    let caretOK = caret == (disk1 as NSString).range(of: "middle").location + 3
    results.append(("5a outside edit applied, caret kept on its word (\(r1?["result"] ?? "-"))", r1?["result"] as? String == "applied" && caretOK))

    _ = try? await h.js("duo.select(0); duo.exec('noop'); return 0")
    _ = try? await h.js("duo.select(2, 7); duo.exec('bold')")   // local edit in the title
    let disk2 = disk1.replacingOccurrences(of: "omega line", with: "omega line, edited outside")
    let r2 = (try? await h.js("return duo.external(d)", ["d": disk2])) as? [String: Any]
    let merged = (try? await h.js("return duo.text()")) as? String ?? ""
    results.append(("5b disjoint local + outside edits merge (\(r2?["result"] ?? "-"))",
                    r2?["result"] as? String == "merged" && merged.contains("**Title**") && merged.contains("omega line, edited outside")))

    let disk3 = disk2.replacingOccurrences(of: "# Title", with: "# Renamed")
    let r3 = (try? await h.js("return duo.external(d)", ["d": disk3])) as? [String: Any]
    let unchanged = (try? await h.js("return duo.text()")) as? String ?? ""
    results.append(("5c overlapping edits: conflict, nothing applied (\(r3?["result"] ?? "-"))", r3?["result"] as? String == "conflict" && unchanged == merged))

    // 6. Agent insert highlighted.
    _ = try? await h.js("duo.agentInsert(0, 'Added by Claude. ')")
    let added = (try? await h.js("return duo.addedCount()")) as? Int ?? 0
    results.append(("6 agent insert highlighted", added == 1))

    // 7. Find.
    let at = (try? await h.js("return duo.find('omega')")) as? Int ?? -1
    let textNow = (try? await h.js("return duo.text()")) as? String ?? ""
    results.append(("7 find selects the match", at == (textNow as NSString).range(of: "omega").location))

    try? FileManager.default.removeItem(at: dist.appending(path: "s4.html"))
    exit(results.allSatisfy(\.1) ? 0 : 1)
}

setvbuf(stdout, nil, _IONBF, 0)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { @MainActor in await run() }
app.run()
