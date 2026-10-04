import AppKit

/// Captures the window for the comparison loop (handoff §0.2).
@MainActor
public enum WindowCapture {
    /// The content below the toolbar at 2x, in sRGB so token colours sample exactly.
    /// Compare with `compare.sh <screen> <png> --content-only`.
    public static func content(of window: NSWindow, to url: URL) throws {
        guard let view = window.contentView else { throw CaptureError("Window has no content view") }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let rect = view.convert(window.contentLayoutRect, from: nil).integral
        guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { throw CaptureError("Could not allocate a bitmap") }
        view.cacheDisplay(in: rect, to: rep)
        guard let srgb = rep.converting(to: .sRGB, renderingIntent: .default) else { throw CaptureError("Could not convert to sRGB") }
        let scaled = try resample(srgb, width: Int(rect.width * 2), height: Int(rect.height * 2), force: true)
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
        guard let rep = frame.bitmapImageRepForCachingDisplay(in: rect) else { throw CaptureError("Could not allocate a bitmap") }
        frame.cacheDisplay(in: rect, to: rep)
        guard let srgb = rep.converting(to: .sRGB, renderingIntent: .default),
              let png = try resample(srgb, width: Int(rect.width * 2), height: Int(rect.height * 2)).representation(using: .png, properties: [:])
        else { throw CaptureError("PNG encoding failed") }
        try png.write(to: url)
    }

    /// Popovers (the peek) are separate windows; draw any that are showing over the capture at
    /// their on-screen position, so flow-zoom-3 can be compared.
    private static func compositePopovers(of window: NSWindow, onto rep: NSBitmapImageRep, contentRect: NSRect) throws {
        let content = window.convertToScreen(window.convertFromBacking(window.convertToBacking(window.contentLayoutRect)))
        for w in NSApp.windows where w !== window && w.isVisible && String(describing: type(of: w)).contains("Popover") {
            guard let frameView = w.contentView?.superview ?? w.contentView,
                  let pop = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { continue }
            frameView.cacheDisplay(in: frameView.bounds, to: pop)
                let origin = NSPoint(x: w.frame.minX - content.minX, y: w.frame.minY - content.minY)
            NSGraphicsContext.saveGraphicsState()
            guard let context = NSGraphicsContext(bitmapImageRep: rep) else { throw CaptureError("Cannot draw into the capture bitmap") }
            NSGraphicsContext.current = context
            // The bitmap is 2x; its point size is the content size.
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
