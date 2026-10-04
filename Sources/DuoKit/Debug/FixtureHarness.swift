import AppKit
import SwiftUI

/// Hands the hosting NSWindow to a closure once the view is in it.
public struct WindowConfigurator: NSViewRepresentable {
    let configure: @MainActor (NSWindow) -> Void

    public init(_ configure: @escaping @MainActor (NSWindow) -> Void) {
        self.configure = configure
    }

    public func makeNSView(context: Context) -> NSView {
        let v = Probe()
        v.onWindow = configure
        return v
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}

    final class Probe: NSView {
        var onWindow: (@MainActor (NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let onWindow else { return }
            self.onWindow = nil
            DispatchQueue.main.async { onWindow(window) }
        }
    }
}

/// Sets the window up for fixture mode and, when asked, captures it and quits.
@MainActor
public enum FixtureHarness {
    /// Where the panes start in the targets: the 38 pt toolbar plus its 1 pt bottom border, which
    /// CSS adds on top of the height (findings F-10).
    public static let designContentTop = DuoMetric.toolbarHeight + DuoMetric.borderHairline

    /// Content area under the toolbar at the design size: 1440 × (900 − 39).
    public static let contentSize = CGSize(
        width: DuoMetric.designWindow.width,
        height: DuoMetric.designWindow.height - designContentTop
    )

    /// Cleanup the app registers for the capture path's direct exit.
    nonisolated(unsafe) public static var beforeExit: (@MainActor () -> Void)?

    /// Runs one scripted action (`--then`), as a click or chord would.
    static func perform(_ action: String, on model: AppModel) {
        let parts = action.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts[0] {
        case "open":
            let target = parts.count > 1 ? parts[1].split(separator: "/", maxSplits: 1).map(String.init) : []
            if let project = target.first { model.open(project: project, session: target.count > 1 ? target[1] : nil) }
        case "peek": model.togglePeek()
        case "down": model.movePeekSelection(by: 1)
        case "up": model.movePeekSelection(by: -1)
        case "jump": model.jumpToPeekSelection()
        case "home": model.goHome()
        case "zoom-out": model.zoomOut()
        case "focus-tile": model.moveTileFocus(dx: 0, dy: 0)
        case "new": model.newSession()
        case "close": model.closeVisibleSession()
        case "resume":
            if parts.count > 1, let s = model.fixture.sessions.first(where: { $0.sessionId?.hasPrefix(parts[1]) == true }), let id = s.sessionId {
                model.open(project: s.project); model.consoleTab = id
                _ = model.terminal(project: s.project, session: id)
            }
        case "file": if parts.count > 1 { model.selectedFile = parts[1]; model.rightTab = parts[1] }
        case "edit-bold": model.editor.run("duo.select(2, 9); duo.exec('bold'); return 1") { _ in }
        case "editor-snapshot":
            let out = parts.count > 1 ? parts[1] : "/tmp/editor.png"
            model.editor.webView.takeSnapshot(with: nil) { image, _ in
                if let tiff = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: out))
                }
            }
        case "outside-title":
            if let url = model.editor.url, let text = try? String(contentsOf: url, encoding: .utf8) {
                let lines = text.components(separatedBy: "\n")
                try? (["# PRD v3, renamed outside"] + lines.dropFirst()).joined(separator: "\n").write(to: url, atomically: false, encoding: .utf8)
            }
        case "doc-status":
            if let url = model.editor.url { FileHandle.standardError.write(Data("doc-status: \(model.editor.status(of: url))\n".utf8)) }
        case "outside":
            if let url = model.editor.url, var text = try? String(contentsOf: url, encoding: .utf8) {
                text += "\nA line added by another app.\n"
                try? text.write(to: url, atomically: false, encoding: .utf8)
            }
        case "editor":
            let e = model.editor
            e.run("""
                const c = document.querySelector('.cm-content'), cs = c && getComputedStyle(c), h = document.querySelector('.duo-h');
                return JSON.stringify({ length: duo.text().length, head: duo.text().slice(0, 60), font: cs && cs.fontSize, line: cs && cs.lineHeight,
                  padding: cs && cs.padding, bg: getComputedStyle(document.body).backgroundColor, color: cs && cs.color,
                  heading: h && getComputedStyle(h).fontSize + ' ' + getComputedStyle(h).fontWeight, added: duo.addedCount() })
                """) { v in
                FileHandle.standardError.write(Data("editor: \(e.url?.lastPathComponent ?? "-") event=\(e.lastEvent) readOnly=\(e.readOnlyReason ?? "no") conflict=\(e.conflict) \(v ?? "nil")\n".utf8))
            }
        case "type": model.visibleTerminal?.view.send(txt: parts.count > 1 ? parts[1] : "")
        case "enter": model.visibleTerminal?.view.send(txt: "\r")
        case "dump":
            for t in model.terminals.all.sorted(by: { $0.key < $1.key }) {
                t.view.selectAll()
                let text = (t.view.getSelection() ?? "").split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                t.view.selectNone()
                FileHandle.standardError.write(Data("---- \(t.key) frame=\(t.view.frame.size) window=\(t.view.window != nil) ----\n\(text.prefix(12).joined(separator: "\n"))\n".utf8))
            }
            for s in model.fixture.sessions where s.sessionId != nil {
                FileHandle.standardError.write(Data("== \(s.sessionId!.prefix(8)) \(s.project)/\(s.name) [\(s.state)] wait=\(s.wait ?? "-") q=\(s.question ?? "-") opts=\(s.options ?? []) summary=\(s.summary ?? "-")\n".utf8))
            }
        case let a where a.hasPrefix("wait"): break
        default: FileHandle.standardError.write(Data("Unknown action '\(action)'\n".utf8))
        }
    }

    public static func configure(_ window: NSWindow, model: AppModel, options: LaunchOptions) {
        if options.capturing { FileHandle.standardError.write(Data("trace configure\n".utf8)) }
        window.isRestorable = false
        window.tabbingMode = .disallowed
        guard options.state != nil || options.capturing else { return }

        // Render in sRGB so captured pixels are the token values exactly. Otherwise the window
        // draws in the display's colour space and the capture is off by a unit after conversion.
        window.colorSpace = .sRGB

        // The system toolbar may not be 38 high; the panes start below whatever it is (§0.4),
        // so size the area below it to exactly the design's.
        let chrome = window.frame.height - window.contentLayoutRect.height
        let height = contentSize.height + chrome
        let screen = window.screen?.visibleFrame ?? .zero
        let origin = CGPoint(x: max(screen.minX, screen.midX - contentSize.width / 2),
                             y: max(screen.minY, screen.maxY - height))
        window.setFrame(CGRect(origin: origin, size: CGSize(width: contentSize.width, height: height)), display: true)

        // Scripted actions, one every 0.6 s, so each change renders before the next.
        for (i, action) in options.thenActions.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 * Double(i + 1)) { perform(action, on: model) }
        }

        guard options.capturing else { return }
        // Give SwiftUI and the split view a moment to settle at the new size.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + 0.6 * Double(options.thenActions.count)) {
            var failed = false
            do {
                if let path = options.capturePath {
                    try WindowCapture.content(of: window, to: URL(fileURLWithPath: path))
                    print("captured content \(path)")
                }
                if let path = options.captureWindowPath {
                    try WindowCapture.window(window, to: URL(fileURLWithPath: path))
                    print("captured window \(path)")
                }
            } catch {
                FileHandle.standardError.write(Data("capture failed: \(error.localizedDescription)\n".utf8))
                failed = true
            }
            fflush(stdout)
            beforeExit?()  // exit() skips willTerminate: end sessions, remove the endpoint
            exit(failed ? 1 : 0)
        }
    }
}
