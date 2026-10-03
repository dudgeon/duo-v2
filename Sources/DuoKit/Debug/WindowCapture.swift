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
        let scaled = try resample(srgb, width: Int(rect.width * 2), height: Int(rect.height * 2))
        guard let png = scaled.representation(using: .png, properties: [:]) else { throw CaptureError("PNG encoding failed") }
        try png.write(to: url)
    }

    /// The whole window, frame and toolbar included, via screencapture(1). That needs the Screen
    /// Recording permission for whichever app launched Duo; without it, falls back to drawing the
    /// window's frame view, which shows the toolbar's contents but not always the system material.
    public static func window(_ window: NSWindow, to url: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) { return }

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
        FileHandle.standardError.write(Data("note: no Screen Recording permission; drew the frame view instead\n".utf8))
    }

    private static func resample(_ rep: NSBitmapImageRep, width: Int, height: Int) throws -> NSBitmapImageRep {
        if rep.pixelsWide == width && rep.pixelsHigh == height { return rep }
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
