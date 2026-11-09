import DuoControl
import DuoKit
import Foundation
import WebKit

// F-629, C-177: the HTML viewer says why a page is blank, and logs its loads.
@MainActor func htmlViewerBlankChecks() throws {
    // What counts as a page that can come up blank or unstyled (and what doesn't).
    check(HTMLViewer.loadsRemoteCode(#"<script src="https://cdnjs.cloudflare.com/x.js"></script>"#), "a remote <script src> is flagged")
    check(HTMLViewer.loadsRemoteCode(#"<LINK rel=stylesheet href='//cdn.example/a.css'>"#), "a remote style sheet link (protocol-relative, any case) is flagged")
    check(HTMLViewer.loadsRemoteCode(#"<link href="https://fonts.googleapis.com/css2?family=Inter" rel="stylesheet">"#), "a Google Fonts style sheet is flagged, as a style that won't load")
    check(HTMLViewer.loadsRemoteCode("<style>@import url(https://fonts.googleapis.com/css);</style>"), "a remote @import is flagged")
    check(HTMLViewer.loadsRemoteCode(#"<script type="module">import React from "https://esm.sh/react"; </script>"#), "an inline module importing from https is flagged")
    check(HTMLViewer.loadsRemoteCode(#"<script>const m = await import("https://esm.sh/x")</script>"#), "a dynamic import from https is flagged")
    check(!HTMLViewer.loadsRemoteCode(#"<link rel="canonical" href="https://example.com/p"><link rel="icon" href="https://example.com/f.ico">"#), "a canonical or icon link is not")
    check(!HTMLViewer.loadsRemoteCode(#"<!-- <script src="https://cdn.example/x.js"></script> --><p>hi</p>"#), "a script tag inside a comment is not")
    check(!HTMLViewer.loadsRemoteCode(#"<script src="app.js"></script><link rel=stylesheet href="a.css"><a href="https://x.com">x</a><script type="module">import x from "./x.js"</script>"#), "local scripts, styles, imports and plain links are not")

    let dir = FileManager.default.temporaryDirectory.appending(path: "duochecks-html-\(UUID().uuidString)")
    let real = dir.appending(path: "real"); let linked = dir.appending(path: "linked")
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: real)
    defer { try? FileManager.default.removeItem(at: dir) }
    let cdnPage = #"<html><body><p>cdn page</p><script src="https://cdnjs.cloudflare.com/react.js"></script></body></html>"#
    try "<html><body>hi A</body></html>".write(to: real.appending(path: "a.html"), atomically: true, encoding: .utf8)
    try cdnPage.write(to: real.appending(path: "cdn.html"), atomically: true, encoding: .utf8)

    // Why a file can't be read.
    check(HTMLViewer.unreadableReason(real.appending(path: "a.html")) == nil, "a readable file has no reason")
    check(HTMLViewer.unreadableReason(real.appending(path: "gone.html")) != nil, "a missing file is named")
    let locked = real.appending(path: "locked.html")
    try "<html><body>hi B</body></html>".write(to: locked, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
    let lockedReason = HTMLViewer.unreadableReason(locked) ?? ""
    check(lockedReason.contains("permission to read") && !lockedReason.contains("save"), "a file with no read permission says so in those words (the real error, F-631): \(lockedReason)")
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path)

    // A symlinked root or file is inside its root, whichever side is spelled through the link.
    check(HTMLViewer.inside(linked.appending(path: "a.html"), real), "a file reached through a symlink is inside the real root")
    check(HTMLViewer.inside(real.appending(path: "a.html"), linked), "a real path is inside a symlinked root")
    check(!HTMLViewer.inside(dir.appending(path: "real-other/a.html"), real), "a sibling folder with the root's name as prefix is not inside")

    // The viewer itself: the notice, the log, real WebKit loads.
    let viewer = HTMLViewer()
    func wait(_ cond: () -> Bool) { let end = Date().addingTimeInterval(15); while !cond() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) } }
    func log() -> String { (try? String(contentsOf: DuoPaths.support.appending(path: "logs/duo.log"), encoding: .utf8)) ?? "" }
    func count(_ needle: String) -> Int { log().components(separatedBy: needle).count - 1 }
    func pageText() -> String {
        var out: String?
        viewer.webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { v, _ in out = (v as? String) ?? "" }
        wait { out != nil }
        return out ?? ""
    }
    func waitText(_ s: String) { wait { pageText().contains(s) } }

    viewer.open(linked.appending(path: "cdn.html"), root: linked)
    wait { viewer.notice.kind != nil }
    check(viewer.notice.kind == .blockedRemote && viewer.notice.buttonTitle == "Open in Browser", "a CDN-built page shows the notice with Open in Browser")
    let msg = viewer.notice.message ?? ""
    check(msg.contains("scripts or styles") && !msg.contains("DL-") && !msg.contains("Safari"), "worded for a style-only page too, with no record number")
    wait { count("html: loaded") > 0 }
    check(log().contains("html: open ") && log().contains("uses scripts or styles from the web"), "the open and the blocked remote code are logged")
    check(log().contains("html: loaded "), "a page under a symlinked root loads, and the finish is logged")

    // The watcher's and Reload's path re-checks the page: inlining the script clears the bar; adding one sets it.
    try "<html><body>cdn page, inlined</body></html>".write(to: real.appending(path: "cdn.html"), atomically: true, encoding: .utf8)
    viewer.reload()
    wait { viewer.notice.kind == nil }
    check(viewer.notice.kind == nil, "after the script is inlined, a reload clears the bar")
    waitText("inlined")
    try cdnPage.write(to: real.appending(path: "cdn.html"), atomically: true, encoding: .utf8)
    viewer.reload()
    wait { viewer.notice.kind == .blockedRemote }
    check(viewer.notice.kind == .blockedRemote, "a page that gains a CDN script gets the bar on reload")

    // A linked file outside the root still loads, from its own folder.
    let outside = dir.appending(path: "outside"); try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try "<html><body>out</body></html>".write(to: outside.appending(path: "o.html"), atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(at: real.appending(path: "o-link.html"), withDestinationURL: outside.appending(path: "o.html"))
    viewer.open(real.appending(path: "o-link.html"), root: real)
    waitText("out")
    check(pageText().contains("out"), "a linked file outside the root loads")

    // Page A, then an unreadable B: A is never drawn under B's name.
    viewer.open(real.appending(path: "a.html"), root: real)
    waitText("hi A")
    check(viewer.notice.kind == nil && pageText().contains("hi A"), "a plain page shows with no bar")
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
    viewer.open(locked, root: real)
    wait { if case .failed? = viewer.notice.kind { return true } else { return false } }
    check({ if case .failed(let why)? = viewer.notice.kind { return why.contains("permission to read") } else { return false } }(), "an unreadable B shows the failure bar")
    wait { pageText().isEmpty }
    check(pageText().isEmpty, "and the view is blank, not still page A")
    check(viewer.notice.buttonTitle == "Reload" && (viewer.notice.message ?? "").hasPrefix("Couldn’t open this page"), "with a Reload button")
    check(log().contains("html: failed ") && log().contains("locked.html"), "and the failure is logged")
    // Reload once it can be read: the bar clears and B draws.
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path)
    viewer.noticeAction()
    waitText("hi B")
    check(viewer.notice.kind == nil && pageText().contains("hi B"), "Reload after the file becomes readable loads it and clears the bar")

    viewer.open(real.appending(path: "gone.html"), root: real)
    wait { if case .failed? = viewer.notice.kind { return true } else { return false } }
    check({ if case .failed(let why)? = viewer.notice.kind { return why.contains("isn’t there") } else { return false } }(), "a missing file shows the failure bar")

    // A navigation failure from WebKit shows and logs its reason (when the scan hadn't already).
    viewer.open(real.appending(path: "a.html"), root: real)
    waitText("hi A")
    viewer.failed(NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotOpenFile, userInfo: [NSLocalizedDescriptionKey: "bad"]))
    check(viewer.notice.kind == .failed("bad") && log().contains("bad ["), "a WebKit navigation failure shows and logs its reason")
    viewer.failed(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
    check(viewer.notice.kind == .failed("bad"), "a cancelled load is not a failure")

    // Split view re-renders the buffer on every pause: the log says it once.
    let buffered = real.appending(path: "buffer.html")
    try cdnPage.write(to: buffered, atomically: true, encoding: .utf8)
    viewer.renderBuffer(cdnPage, file: buffered, root: real)
    wait { viewer.notice.kind == .blockedRemote }
    let before = count("buffer.html")
    for i in 0..<12 { viewer.renderBuffer(cdnPage + "<!-- \(i) -->", file: buffered, root: real); RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    check(viewer.notice.kind == .blockedRemote && count("buffer.html") == before, "twelve buffer renders add no log lines (it logs a change of state, not each render)")
    viewer.endBuffer()

    // The rule-list wait can't hang silently: a timer logs and shows the failure (the answer itself can't be faked here).
    let source = try String(contentsOf: repoRoot().appending(path: "Sources/DuoKit/Editor/HTMLViewer.swift"), encoding: .utf8)
    check(source.contains("rulesTimedOut") && source.contains("haven't compiled after") && source.contains("DuoLog.write(\"html: open \\(file.path)\")   // before the rules wait"),
          "the open is logged before the rules wait, and a timeout logs and shows the failure (read from source: not exercised)")

    // The bar's buttons name their duo2 action.
    check(Parity.uiOnly["Open in Browser (HTML page bar)"] != nil, "Open in Browser is listed as UI-only, with why")
    check(DuoAction.all.first { $0.id == .htmlReload }?.ui.contains("Reload") == true, "the bar's Reload is tied to `duo2 html reload`")
}
