import DuoKit
import Foundation
import WebKit

// F-629, C-177: the HTML viewer says why a page is blank, and logs its loads.
@MainActor func htmlViewerBlankChecks() throws {
    check(HTMLViewer.loadsRemoteCode(#"<script src="https://cdnjs.cloudflare.com/x.js"></script>"#), "a page with a remote <script src> is flagged")
    check(HTMLViewer.loadsRemoteCode(#"<LINK rel=stylesheet href='//cdn.example/a.css'>"#), "a remote <link href> (protocol-relative, any case) is flagged")
    check(HTMLViewer.loadsRemoteCode("<style>@import url(https://fonts.googleapis.com/css);</style>"), "a remote @import is flagged")
    check(!HTMLViewer.loadsRemoteCode(#"<script src="app.js"></script><link href="a.css"><a href="https://x.com">x</a>"#), "local scripts, styles and plain links are not")

    let dir = FileManager.default.temporaryDirectory.appending(path: "duochecks-html-\(UUID().uuidString)")
    let real = dir.appending(path: "real"); let linked = dir.appending(path: "linked")
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: real)
    defer { try? FileManager.default.removeItem(at: dir) }
    try "<html><body>hi</body></html>".write(to: real.appending(path: "a.html"), atomically: true, encoding: .utf8)
    try #"<html><body><script src="https://cdnjs.cloudflare.com/react.js"></script></body></html>"#.write(to: real.appending(path: "cdn.html"), atomically: true, encoding: .utf8)

    check(HTMLViewer.unreadableReason(real.appending(path: "a.html")) == nil, "a readable file has no reason")
    check(HTMLViewer.unreadableReason(real.appending(path: "gone.html")) != nil, "a missing file is named")
    let locked = real.appending(path: "locked.html")
    try "x".write(to: locked, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
    check((HTMLViewer.unreadableReason(locked) ?? "").contains("can’t be read"), "a file that can't be read says so")
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path)

    // A symlinked root or file is inside its root, whichever side is spelled through the link.
    check(HTMLViewer.inside(linked.appending(path: "a.html"), real), "a file reached through a symlink is inside the real root")
    check(HTMLViewer.inside(real.appending(path: "a.html"), linked), "a real path is inside a symlinked root")
    check(!HTMLViewer.inside(dir.appending(path: "real-other/a.html"), real), "a sibling folder with the root's name as prefix is not inside")

    // The viewer itself: the notice, the log, a real WebKit load.
    let viewer = HTMLViewer()
    func wait(_ cond: () -> Bool) { let end = Date().addingTimeInterval(15); while !cond() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) } }
    func log() -> String { (try? String(contentsOf: DuoPaths.support.appending(path: "logs/duo.log"), encoding: .utf8)) ?? "" }
    viewer.open(linked.appending(path: "cdn.html"), root: linked)
    wait { viewer.notice.kind != nil }
    check(viewer.notice.kind == .blockedRemote && viewer.notice.buttonTitle == "Open in Safari" && (viewer.notice.message ?? "").contains("DL-175"), "a CDN-built page shows the one-line notice with Open in Safari")
    wait { log().contains("html: loaded") }
    check(log().contains("html: open ") && log().contains("loads remote scripts"), "the open and the blocked remote scripts are logged")
    check(log().contains("html: loaded "), "a page under a symlinked root loads, and the finish is logged: \(log().split(separator: "\n").filter { $0.contains("html:") }.suffix(4))")
    // A file that is itself a link to a page outside the root still loads (from its own folder).
    let outside = dir.appending(path: "outside"); try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try "<html><body>out</body></html>".write(to: outside.appending(path: "o.html"), atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(at: real.appending(path: "o-link.html"), withDestinationURL: outside.appending(path: "o.html"))
    let before = log().components(separatedBy: "html: loaded ").count
    viewer.open(real.appending(path: "o-link.html"), root: real)
    wait { log().components(separatedBy: "html: loaded ").count > before }
    check(log().components(separatedBy: "html: loaded ").count > before, "a linked file outside the root loads, and the finish is logged")
    viewer.open(real.appending(path: "a.html"), root: real)
    wait { viewer.notice.kind == nil }
    check(viewer.notice.kind == nil, "a plain page clears the notice")
    viewer.open(real.appending(path: "gone.html"), root: real)
    check({ if case .failed(let why)? = viewer.notice.kind { return why.contains("isn’t there") } else { return false } }(), "a missing file shows the failure notice")
    check(viewer.notice.buttonTitle == "Reload" && (viewer.notice.message ?? "").hasPrefix("Couldn’t open this page"), "with a Reload button")
    check(log().contains("html: failed ") && log().contains("gone.html"), "and the failure is logged")
    viewer.failed(NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotOpenFile, userInfo: [NSLocalizedDescriptionKey: "bad"]))
    check(viewer.notice.kind == .failed("bad") && log().contains("bad ["), "a WebKit navigation failure shows and logs its reason")
    viewer.failed(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
    check(viewer.notice.kind == .failed("bad"), "a cancelled load is not a failure")
}
