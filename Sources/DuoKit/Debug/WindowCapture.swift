import AppKit
import WebKit

/// Captures the window for the comparison loop (handoff §0.2).
@MainActor
public enum WindowCapture {
    /// Pixels per point for captures: `--capture-scale` / `DUO_CAPTURE_SCALE`, default 2 (the original path, untouched).
    public static let scale: Double = LaunchOptions.captureScale(arguments: CommandLine.arguments)

    /// A bitmap `scale` pixels per point over `rect`, with `view` drawn into it at that scale (vector
    /// content is rendered at that resolution, not upsampled). Only used when `scale` is not 2.
    private static func scaledRep(of view: NSView, in rect: NSRect) throws -> NSBitmapImageRep {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int((rect.width * scale).rounded()), pixelsHigh: Int((rect.height * scale).rounded()),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw CaptureError("Could not allocate a bitmap") }
        rep.size = rect.size
        view.cacheDisplay(in: rect, to: rep)
        return rep
    }

    /// Runs `body` (the captures) with each showing web view's own snapshot laid over it.
    ///
    /// A web view's pixels come from WebKit's web process. While its window is on screen they're
    /// in the view's layers and a capture draws them; once the window is covered by other apps'
    /// windows (an isolated Duo never takes focus, C-28) or the screen is locked, WebKit treats the
    /// page as hidden and they're gone, so the capture showed a blank pane (F-25, F-120).
    /// `takeSnapshot` has the web process paint the page whether or not it's on screen. Each
    /// snapshot goes in as an image view inside the web view, so anything drawn above the web view
    /// still draws above it. Gives up waiting after `timeout` and captures what it has.
    public static func withWebSnapshots(in window: NSWindow, timeout: TimeInterval = 5, _ body: @escaping @MainActor () -> Void) {
        let webViews = (window.contentView?.superview).map(webViews(under:)) ?? []
        var overlays: [NSView] = [], waiting = webViews.count, finished = false
        func finish() {
            guard !finished else { return }
            finished = true
            body()
            overlays.forEach { $0.removeFromSuperview() }
        }
        guard waiting > 0 else { return finish() }
        for web in webViews {
            // WKWebView's visibleRect reaches under the toolbar (its obscured inset); keep to its bounds.
            let visible = web.visibleRect.intersection(web.bounds)
            let config = WKSnapshotConfiguration()
            config.rect = visible
            config.afterScreenUpdates = false   // a hidden page has no screen updates to wait for
            // Points; the image comes out at the screen's backing scale, so ask for more width at other scales.
            let backing = Double(window.backingScaleFactor)
            config.snapshotWidth = NSNumber(value: scale == 2 ? Double(visible.width) : Double(visible.width) * scale / max(backing, 1))
            web.takeSnapshot(with: config) { image, _ in
                MainActor.assumeIsolated {
                    if let image, !finished {
                        let overlay = NSImageView(frame: visible)
                        overlay.image = image
                        overlay.imageScaling = .scaleAxesIndependently
                        overlay.identifier = NSUserInterfaceItemIdentifier("duo.capture.webSnapshot")
                        web.addSubview(overlay)
                        overlays.append(overlay)
                    }
                    waiting -= 1
                    if waiting == 0 { finish() }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            MainActor.assumeIsolated {
                if !finished { FileHandle.standardError.write(Data("capture: \(waiting) web view snapshot(s) didn't arrive in \(Int(timeout)) s\n".utf8)) }
                finish()
            }
        }
    }

    /// Web views showing in the window: in it, not hidden, with some of them in view.
    static func webViews(under view: NSView) -> [WKWebView] {
        if let web = view as? WKWebView {
            return !web.isHiddenOrHasHiddenAncestor && !web.visibleRect.intersection(web.bounds).isEmpty ? [web] : []
        }
        return view.subviews.flatMap(webViews(under:))
    }

    /// The content below the toolbar at 2x, in sRGB so token colours sample exactly.
    /// Compare with `compare.sh <screen> <png> --content-only`.
    public static func content(of window: NSWindow, to url: URL) throws {
        guard let view = window.contentView else { throw CaptureError("Window has no content view") }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let rect = view.convert(window.contentLayoutRect, from: nil).integral
        let rep: NSBitmapImageRep
        if scale == 2 {
            guard let r = view.bitmapImageRepForCachingDisplay(in: rect) else { throw CaptureError("Could not allocate a bitmap") }
            view.cacheDisplay(in: rect, to: r)
            rep = r
        } else {
            rep = try scaledRep(of: view, in: rect)
        }
        guard let srgb = rep.converting(to: .sRGB, renderingIntent: .default) else { throw CaptureError("Could not convert to sRGB") }
        let scaled = try resample(srgb, width: Int((rect.width * scale).rounded()), height: Int((rect.height * scale).rounded()), force: true)
        try compositePopovers(of: window, onto: scaled, contentRect: rect)
        guard let png = scaled.representation(using: .png, properties: [:]) else { throw CaptureError("PNG encoding failed") }
        try png.write(to: url)
    }

    /// The whole window, frame and toolbar included. By default the window's frame view is drawn,
    /// which needs no permission. screencapture(1) is used only with DUO_SCREENCAPTURE=1: it needs
    /// Screen Recording, and every rebuild (a new ad-hoc signature) made macOS ask again, which
    /// blocked unattended test runs (F-54).
    public static func window(_ window: NSWindow, to url: URL) throws {
        if ProcessInfo.processInfo.environment["DUO_SCREENCAPTURE"] == "1" { try screencapture(window, to: url); return }
        try drawFrame(window, to: url)
    }

    static func screencapture(_ window: NSWindow, to url: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) { return }
        try drawFrame(window, to: url)
    }

    static func drawFrame(_ window: NSWindow, to url: URL) throws {
        guard let frame = window.contentView?.superview else { throw CaptureError("No frame view") }
        frame.layoutSubtreeIfNeeded()
        frame.displayIfNeeded()
        let rect = frame.bounds
        let rep: NSBitmapImageRep
        if scale == 2 {
            guard let r = frame.bitmapImageRepForCachingDisplay(in: rect) else { throw CaptureError("Could not allocate a bitmap") }
            frame.cacheDisplay(in: rect, to: r)
            rep = r
        } else {
            rep = try scaledRep(of: frame, in: rect)
        }
        guard let srgb = rep.converting(to: .sRGB, renderingIntent: .default),
              let png = try resample(srgb, width: Int((rect.width * scale).rounded()), height: Int((rect.height * scale).rounded())).representation(using: .png, properties: [:])
        else { throw CaptureError("PNG encoding failed") }
        try png.write(to: url)
    }

    /// Popovers (the peek) are separate windows; draw any that are showing over the capture at
    /// their on-screen position, so flow-zoom-3 can be compared.
    private static func compositePopovers(of window: NSWindow, onto rep: NSBitmapImageRep, contentRect: NSRect) throws {
        let content = window.convertToScreen(window.convertFromBacking(window.convertToBacking(window.contentLayoutRect)))
        for w in NSApp.windows where w !== window && w.isVisible && String(describing: type(of: w)).contains("Popover") {
            guard let frameView = w.contentView?.superview ?? w.contentView else { continue }
            let pop: NSBitmapImageRep
            if scale == 2 {
                guard let r = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { continue }
                frameView.cacheDisplay(in: frameView.bounds, to: r)
                pop = r
            } else {
                guard let r = try? scaledRep(of: frameView, in: frameView.bounds) else { continue }
                pop = r
            }
                let origin = NSPoint(x: w.frame.minX - content.minX, y: w.frame.minY - content.minY)
            NSGraphicsContext.saveGraphicsState()
            guard let context = NSGraphicsContext(bitmapImageRep: rep) else { throw CaptureError("Cannot draw into the capture bitmap") }
            NSGraphicsContext.current = context
            // The bitmap is `scale`x; its point size is the content size.
            let scale = CGFloat(rep.pixelsWide) / contentRect.width
            NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
            pop.draw(in: NSRect(origin: origin, size: w.frame.size))
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// Redraws into a standard RGBA bitmap at the given size. `force` redraws even at the same
    /// size, so the result is a format AppKit can draw into (a converted rep may not be).
    private static func resample(_ rep: NSBitmapImageRep, width: Int, height: Int, force: Bool = false) throws -> NSBitmapImageRep {
        if !force, rep.pixelsWide == width && rep.pixelsHigh == height { return rep }
        guard let out = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )?.retagging(with: .sRGB) else { throw CaptureError("Could not allocate a bitmap") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        NSGraphicsContext.current?.imageInterpolation = .high
        rep.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return out
    }

    struct CaptureError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
