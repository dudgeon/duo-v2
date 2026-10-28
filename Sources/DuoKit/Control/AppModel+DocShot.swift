import AppKit
import DuoControl
import DuoSearch
import Foundation
import WebKit

// `duo2 doc screenshot [<file>] [--all] [--width <px>]` (F-378, Q-259): PNGs of a document as Duo's
// viewer draws it. A Word document is drawn by a viewer of its own, in a window nobody can see, at the
// pane's width and as tall as the document (a tab that isn't showing has no window of its own, F-118,
// and bringing it forward would move the user's view). A Markdown preview or a slide deck is captured
// only while it is showing: Duo has no second copy of those. Only a document open in a Duo tab or
// inside the session's project folder (C-115); the PNGs go in the session's own folder.
extension AppModel {
    nonisolated static let shotWidth: Double = 460          // the right pane's width (`paneProjectRight`)
    nonisolated static let shotPiece: Double = 1600         // a PNG's height at most
    nonisolated static let shotCeiling: Double = 24_000     // the tallest document drawn

    func docScreenshotVerb(_ inv: Invocation, _ req: ControlRequest, _ done: @escaping @MainActor (Reply) -> Void) {
        let width = inv.flags["width"].flatMap(Double.init) ?? Self.shotWidth
        guard (320...1600).contains(width) else { return done(.fail("--width takes 320 to 1600 px")) }
        // The document: named, or the one showing in the right pane.
        let url: URL
        if let arg = inv[0] {
            switch documentFile(arg, req: req) {
            case .failure(let refusal): return done(.fail(refusal.why))
            case .success(let u): url = u
            }
        } else if let path = rightTab, let p = currentProject?.name, let folder = liveFolders[p], path != "Project", FileManager.default.fileExists(atPath: folder.appending(path: path).path) {
            url = folder.appending(path: path)
        } else { return done(.fail("no document is showing: name one (`duo2 doc screenshot <file>`)")) }
        let out = Self.shotFolder(req)
        let name = url.deletingPathExtension().lastPathComponent
        let shown = displayPath(url)
        func reply(_ files: [String], _ note: String?) {
            guard !files.isEmpty else { return done(.fail("couldn't draw \(shown)")) }
            let count = files.count == 1 ? "a picture" : "\(files.count) pictures"
            var text = "Saved \(count) of \(shown):\n" + files.map { SendFormat.tilde($0) }.joined(separator: "\n")
            if let note { text += "\n" + note }
            var json: [String: Any] = ["files": files]
            if let note { json["note"] = note }
            done(.ok(text, json))
        }
        if Self.isWordViewable(url.lastPathComponent) {
            OffscreenShot.word(url, width: width, all: inv.has("all"), name: name, into: out) { files, note, why in
                if let why { done(.fail("\(shown): \(why)")) } else { reply(files, note) }
            }
            return
        }
        // Showing only: what the pane draws now.
        var showing: (web: WKWebView, where_: String)?
        let target = url.standardizedFileURL
        if let d = visibleDeck, d.url?.standardizedFileURL == target { showing = (d.webView, "slide deck") }
        else if url.pathExtension.lowercased() == "md", let tab = rightTab, let p = currentProject?.name, let folder = liveFolders[p],
                folder.appending(path: tab).standardizedFileURL == target { showing = (editor.webView, "Markdown preview") }
        guard let showing else {
            return done(.fail("\(displayPath(url)) isn't showing: a \(url.pathExtension.lowercased() == "md" ? "Markdown preview" : "slide deck") is captured only while it is on screen (`duo2 doc open` shows it)"))
        }
        let config = WKSnapshotConfiguration()
        config.rect = showing.web.bounds
        config.afterScreenUpdates = false
        showing.web.takeSnapshot(with: config) { image, _ in
            MainActor.assumeIsolated {
                guard let image, let data = Shots.png(image) else { return done(.fail("couldn't take a picture of the \(showing.where_)")) }
                try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
                let file = out.appending(path: "\(name)-\(Shots.stamp()).png")
                do { try data.write(to: file); reply([file.path], "The \(showing.where_) as it shows now (the part on screen).") } catch { done(.fail("couldn't write \(file.path)")) }
            }
        }
    }

    /// The session's own folder, which its sandbox already reads and writes; Duo's support folder for a caller outside a session.
    static func shotFolder(_ req: ControlRequest) -> URL {
        guard let cwd = req.cwd else { return Shots.contextFolder() }
        return URL(fileURLWithPath: cwd, isDirectory: true).appending(path: ".duo/screenshots")
    }
}

/// A Word document drawn out of sight: a viewer of its own in a borderless window far off every screen, never
/// ordered in front and never key, so nothing appears and no focus moves. Kept alive here until its pictures are saved.
@MainActor
public final class OffscreenShot {
    nonisolated(unsafe) private static var live: [ObjectIdentifier: OffscreenShot] = [:]
    private let viewer = DocxViewer()
    private let window: NSWindow
    private let width: Double

    private init(width: Double) {
        self.width = width
        window = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: width, height: 900), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.level = .normal
        viewer.webView.frame = NSRect(x: 0, y: 0, width: width, height: 900)
        window.contentView = viewer.webView
        window.orderBack(nil)
    }

    /// `files`, a note when the picture was cut short or only the top was taken, or why it couldn't be drawn.
    public static func word(_ file: URL, width: Double, all: Bool, name: String, into dir: URL, _ done: @escaping @MainActor ([String], String?, String?) -> Void) {
        let shot = OffscreenShot(width: width)
        let key = ObjectIdentifier(shot)
        live[key] = shot
        let finish: @MainActor ([String], String?, String?) -> Void = { files, note, why in
            shot.viewer.sleep()
            shot.window.orderOut(nil)
            shot.window.contentView = nil
            live[key] = nil
            done(files, note, why)
        }
        shot.viewer.open(file)
        shot.viewer.whenSettled {
            if case .failed(let why) = shot.viewer.state { return finish([], nil, "Duo can’t draw it: \(why)") }
            // Let the page lay out (fonts, pictures), then size the view to the document and take it in pieces.
            // The text flows at `width`; a table wider than the sheet is drawn whole (not in its scroll box), out to
            // the right, and the picture is as wide as the widest table (Q-258: tables at the document's own widths).
            let js = """
                document.documentElement.style.width = '\(Int(width))px';
                const s = document.createElement('style');
                s.textContent = '#host .duo-tablebox { overflow: visible !important; max-width: none !important; }';
                document.head.append(s);
                await new Promise(r => setTimeout(r, 250));
                let right = \(Int(width));
                for (const t of document.querySelectorAll('#host table')) right = Math.max(right, t.getBoundingClientRect().right + window.scrollX);
                return { h: Math.max(document.documentElement.scrollHeight, document.body.scrollHeight), w: Math.ceil(right) + 20 };
                """
            shot.viewer.inspect(js) { r in
                let m = r as? [String: Any]
                let full = (m?["h"] as? NSNumber)?.doubleValue ?? 900
                let wide = (m?["w"] as? NSNumber)?.doubleValue ?? width
                let canvas = wide > width + 20 ? min(wide, 4000) : width
                let height = min(max(full, 300), AppModel.shotCeiling)
                shot.window.setContentSize(NSSize(width: canvas, height: height))
                shot.viewer.webView.frame = NSRect(x: 0, y: 0, width: canvas, height: height)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    MainActor.assumeIsolated {
                        let pieces = Int((height / AppModel.shotPiece).rounded(.up))
                        let take = all ? pieces : 1
                        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                        var files: [String] = []
                        @MainActor func next(_ i: Int) {
                            if i >= take {
                                var note: String?
                                if full > AppModel.shotCeiling { note = "The document is \(Int(full)) px tall; Duo stopped drawing at \(Int(AppModel.shotCeiling)) px." }
                                else if !all, pieces > 1 { note = "That's the top \(Int(min(AppModel.shotPiece, height))) px of \(Int(height)); `--all` saves the other \(pieces - 1) \(pieces - 1 == 1 ? "piece" : "pieces")." }
                                return finish(files, note, nil)
                            }
                            let y = Double(i) * AppModel.shotPiece
                            let config = WKSnapshotConfiguration()
                            config.rect = CGRect(x: 0, y: y, width: canvas, height: min(AppModel.shotPiece, height - y))
                            config.snapshotWidth = NSNumber(value: canvas)   // points: the picture comes out at the screen's scale
                            config.afterScreenUpdates = false
                            shot.viewer.webView.takeSnapshot(with: config) { image, _ in
                                MainActor.assumeIsolated {
                                    guard let image, let data = Shots.png(image) else { return finish(files, nil, "the page didn't give a picture") }
                                    let file = dir.appending(path: "\(name)-\(String(format: "%02d", i + 1)).png")
                                    do { try data.write(to: file); files.append(file.path) } catch { return finish(files, nil, "couldn't write \(file.path)") }
                                    next(i + 1)
                                }
                            }
                        }
                        next(0)
                    }
                }
            }
        }
    }
}
