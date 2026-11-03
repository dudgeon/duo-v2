import AppKit
import DuoKit
import Foundation

// DL-316, F-569: no table, property or code block widens the document past the pane; paragraphs wrap at the pane's width.
@MainActor func editorWrapChecks() throws {
    print("editor: the document never outgrows the pane (DL-316, F-569)")
    let dir = FileManager.default.temporaryDirectory.appending(path: "duo-wrap-\(UUID().uuidString.prefix(6))")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let wide = String(repeating: "x", count: 3000)
    let para = String(repeating: "A paragraph that has to wrap at the pane's width. ", count: 8)
    let doc = """
    ---
    title: \(String(repeating: "a long property ", count: 40))
    status: open
    ---

    # Heading

    \(para)

    | Name | Notes |
    |---|---|
    | one | \(wide) |
    | two | \(String(repeating: "several words of cell text ", count: 40)) |

    ```
    \(String(repeating: "abcdefghij", count: 60))
    ```

    \(para)

    """
    let file = dir.appending(path: "wide.md")
    try Data(doc.utf8).write(to: file)

    func wait(_ seconds: Double = 15, _ ok: () -> Bool) -> Bool {
        let until = Date().addingTimeInterval(seconds)
        while !ok(), Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        return ok()
    }
    func eval(_ e: EditorController, _ js: String) -> String? {
        var out: String?, done = false
        e.run(js) { v in out = v as? String; done = true }
        _ = wait(5) { done }
        return out
    }

    setenv("DUO_EDITOR_DIR", repoRoot().appending(path: "Vendor/codemirror/dist").path, 1)
    let m = AppModel(fixture: try repoFixture())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
    let host = NSView(frame: window.contentView!.bounds)
    window.contentView = host
    let main = m.editors.editor(.main)
    main.webView.frame = NSRect(x: 0, y: 0, width: 500, height: 860)
    host.addSubview(main.webView)
    m.editors.open(file, in: .main)
    check(wait { main.phase == .open }, "the wide document opens")
    RunLoop.main.run(until: Date().addingTimeInterval(0.8))

    let probe = """
    const c = document.querySelector('.cm-content'), s = document.querySelector('.cm-scroller');
    const para = [...document.querySelectorAll('.cm-line')].filter(l => l.textContent.startsWith('A paragraph'))[0];
    const cell = document.querySelector('.duo-table td');
    return JSON.stringify({ pane: s.clientWidth, content: c.getBoundingClientRect().width, scroll: s.scrollWidth,
      para: para ? para.getBoundingClientRect().height : 0, cellWraps: cell ? cell.getBoundingClientRect().height : 0 });
    """
    guard let json = eval(main, probe), let d = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Double] else {
        check(false, "the probe ran"); return
    }
    let pane = d["pane"] ?? 0
    check(pane > 100, "the pane has a width (\(Int(pane)))")
    check((d["content"] ?? 99999) <= pane + 1, "a 3000 px table cell and a long property don't widen the document (content \(Int(d["content"] ?? 0)) of pane \(Int(pane)))")
    check((d["scroll"] ?? 99999) <= pane + 1, "the pane never scrolls sideways (scroll \(Int(d["scroll"] ?? 0)))")
    check((d["para"] ?? 0) > 30, "a paragraph wraps onto several lines at the pane's width")
    check((d["cellWraps"] ?? 0) > 30, "a table cell's text wraps")
}
