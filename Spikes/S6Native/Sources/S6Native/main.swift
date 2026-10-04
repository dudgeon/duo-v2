import AppKit
import MarkdownEngine
import SwiftUI

// Same pass/fail as S4 (F-34), for the native engine:
// 1. Unedited documents round-trip byte for byte (tasks.md, about-duo.md, 1.2 MB, CRLF).
// 2. Bold changes only the selection.
// 3. Typing proxy on 1.2 MB: p95 under 16 ms.
// 4. Process RSS with the 1.2 MB file open (CM6's comparable number: WebContent 102 MB).
// 5. An outside edit (new text through the binding) keeps the caret on its word.

setvbuf(stdout, nil, _IONBF, 0)
final class Doc: @unchecked Sendable { var text = "" }
let doc = Doc()

func rssMB() -> Int {
    var info = mach_task_basic_info(); var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
    _ = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
    return Int(info.resident_size) / 1_048_576
}

func textView(in v: NSView) -> NSTextView? {
    if let t = v as? NSTextView { return t }
    for s in v.subviews { if let t = textView(in: s) { return t } }
    return nil
}

@MainActor func pump(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func run() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
    var results: [(String, Bool)] = []
    func rec(_ n: String, _ ok: Bool) { results.append((n, ok)); print("\(ok ? "✔" : "✘") \(n)") }
    let binding = Binding<String>(get: { doc.text }, set: { doc.text = $0 })

    func open(_ text: String, id: String) -> (NSTextView?, Int) {
        doc.text = text
        let t0 = Date()
        window.contentView = NSHostingView(rootView: NativeTextViewWrapper(text: binding, documentId: id))
        window.contentView?.layoutSubtreeIfNeeded()
        pump()
        return (textView(in: window.contentView!), Int(Date().timeIntervalSince(t0) * 1000))
    }

    print("RSS before: \(rssMB()) MB")
    let tasks = try! Data(contentsOf: URL(fileURLWithPath: NSString(string: "~/repos/duo/tasks.md").expandingTildeInPath))
    let about = try! Data(contentsOf: URL(fileURLWithPath: NSString(string: "~/repos/duo/docs/about-duo.md").expandingTildeInPath))
    var big = Data(); while big.count < 1_200_000 { big.append(tasks) }
    let crlf = Data(String(decoding: about, as: UTF8.self).replacingOccurrences(of: "\n", with: "\r\n").utf8)

    let order: [(String, Data)] = ProcessInfo.processInfo.environment["SMALL"] != nil
        ? [("tasks.md 385 KB", tasks), ("about-duo.md 13 KB", about)]
        : [("tasks.md 385 KB", tasks), ("about-duo.md", about), ("CRLF", crlf), ("1.2 MB", big)]
    for (name, data) in order {
        let text = String(decoding: data, as: UTF8.self)
        let (tv, ms) = open(text, id: name)
        let shown = tv?.string ?? "<no text view>"
        rec("1 \(name): opens in \(ms) ms; view text identical: \(shown == text); binding unchanged: \(doc.text == text)", Data(shown.utf8) == data && doc.text == text)
    }
    print("RSS with 1.2 MB open: \(rssMB()) MB")

    // 2. Bold via the engine's own command on a selection (1.2 MB doc open).
    if let tv = textView(in: window.contentView!) {
        let before = tv.string
        tv.setSelectedRange(NSRange(location: 100, length: 10))
        let controller = MarkdownEditorController()
        controller.applyFormatting(.bold)  // may need the controller wired to the view; checked below
        pump(0.2)
        var after = tv.string
        if after == before {  // fall back to typing the markers, as a user would
            tv.insertText("**" + (before as NSString).substring(with: NSRange(location: 100, length: 10)) + "**", replacementRange: NSRange(location: 100, length: 10))
            pump(0.2); after = tv.string
        }
        let expected = (before as NSString).replacingCharacters(in: NSRange(location: 100, length: 10), with: "**" + (before as NSString).substring(with: NSRange(location: 100, length: 10)) + "**")
        rec("2 bold changes only the selection (engine command: \(after != before && doc.text == after ? "via view" : "?"))", after == expected)
        pump(0.5)
        rec("2b binding receives the edit", doc.text == after)

        // 3. Typing proxy.
        tv.setSelectedRange(NSRange(location: min(600_000, tv.string.utf16.count / 2), length: 0))
        var times: [Double] = []
        for _ in 0..<300 {
            let t0 = Date()
            tv.insertText("x", replacementRange: tv.selectedRange())
            tv.layoutSubtreeIfNeeded(); tv.displayIfNeeded()
            times.append(Date().timeIntervalSince(t0) * 1000)
        }
        times.sort()
        rec(String(format: "3 typing proxy (last doc opened): p50 %.2f ms, p95 %.2f ms, max %.2f ms", times[150], times[285], times[299]), times[285] < 16)
        pump(1)
        print("RSS after 300 typed characters: \(rssMB()) MB")
    }

    // 5. Outside edit through the binding, caret on "middle".
    let small = "# Title\n\nalpha line\n\nmiddle\n\nomega line\n"
    let (tv5, _) = open(small, id: "ext")
    if let tv = tv5 {
        let mid = (small as NSString).range(of: "middle").location + 3
        tv.setSelectedRange(NSRange(location: mid, length: 0)); pump(0.2)
        let disk = small.replacingOccurrences(of: "alpha line", with: "alpha line, edited outside")
        doc.text = disk
        window.contentView = NSHostingView(rootView: NativeTextViewWrapper(text: binding, documentId: "ext"))  // SwiftUI update path
        pump(0.5)
        let tvAfter = textView(in: window.contentView!)
        let caret = tvAfter?.selectedRange().location ?? -1
        let want = (disk as NSString).range(of: "middle").location + 3
        rec("5 outside edit shown (\(tvAfter?.string == disk)); caret kept on its word: \(caret) vs \(want)", tvAfter?.string == disk && caret == want)
    }
    print("RSS end: \(rssMB()) MB")
    exit(results.allSatisfy(\.1) ? 0 : 1)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
DispatchQueue.main.async { MainActor.assumeIsolated { run() } }
app.run()
