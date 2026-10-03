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
    /// Content area under the toolbar at the design size: 1440 × (900 − 38).
    public static let contentSize = CGSize(
        width: DuoMetric.designWindow.width,
        height: DuoMetric.designWindow.height - DuoMetric.toolbarHeight
    )

    public static func configure(_ window: NSWindow, options: LaunchOptions) {
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

        guard options.capturing else { return }
        // Give SwiftUI and the split view a moment to settle at the new size.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
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
            exit(failed ? 1 : 0)
        }
    }
}
