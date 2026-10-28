import AppKit
import WebKit

// `duo2 browser screenshot --full-page` and `duo2 browser scroll` (F-378): the page top to bottom,
// by scrolling and joining what `takeSnapshot` sees (it clamps to the view's bounds), and a scroll
// that says where the page is. Both run in the page's `world` and leave the page where it was.
enum Shots {
    /// A PNG from a snapshot or a drawn image.
    static func png(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// A timestamped name, so a later capture doesn't replace one Claude hasn't looked at.
    static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return f.string(from: Date())
    }

    /// Where a capture with no session folder goes (what element screenshots use).
    static func contextFolder() -> URL {
        let dir = DuoPaths.support.appending(path: "context")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Pictures stacked top to bottom, each at its y in points; `scale` pixels per point.
    static func join(_ parts: [(y: CGFloat, image: NSImage)], width: CGFloat, height: CGFloat, scale: CGFloat) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.cgContext.scaleBy(x: scale, y: scale)
        for p in parts {
            // The bitmap's origin is bottom-left; the page's top-left.
            p.image.draw(in: NSRect(x: 0, y: height - p.y - p.image.size.height, width: width, height: p.image.size.height),
                         from: .zero, operation: .copy, fraction: 1)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}

extension PageHost {
    /// The page's height, where it is scrolled to and the screen's height, in points.
    private func pageMetrics(_ done: @escaping @MainActor ([String: Double]?) -> Void) {
        webView.callAsyncJavaScript("""
            const d = document.documentElement, b = document.body;
            return { h: Math.max(d.scrollHeight, b ? b.scrollHeight : 0), y: window.scrollY, vh: window.innerHeight };
            """, arguments: [:], in: nil, in: world) { r in
            if case .success(let v) = r, let m = v as? [String: Any] {
                done(["h": (m["h"] as? NSNumber)?.doubleValue ?? 0, "y": (m["y"] as? NSNumber)?.doubleValue ?? 0, "vh": (m["vh"] as? NSNumber)?.doubleValue ?? 0])
            } else { done(nil) }
        }
    }

    /// The whole page as one PNG: the view's height at a time, each scrolled into place, joined. Stops at
    /// `maxHeight` and says so in the note. Fixed headers repeat in each piece. The page is put back where it was.
    public func screenshotFullPage(maxHeight: CGFloat = 20_000, _ done: @escaping @MainActor (String?, String?) -> Void) {
        pageMetrics { [weak self] m in
            guard let self, let m else { return done(nil, nil) }
            let width = self.webView.bounds.width, view = self.webView.bounds.height
            let total = min(CGFloat(m["h"] ?? 0), maxHeight)
            let startY = m["y"] ?? 0
            guard total > view + 1 else {
                return self.screenshot(rect: nil, whole: true) { done($0, nil) }
            }
            var parts: [(y: CGFloat, image: NSImage)] = []
            @MainActor func finish(_ note: String?) {
                self.webView.callAsyncJavaScript("window.scrollTo(0, y)", arguments: ["y": startY], in: nil, in: self.world, completionHandler: nil)
                let scale = parts.first.map { $0.image.representations.first.map { CGFloat($0.pixelsWide) / max(width, 1) } ?? 2 } ?? 2
                guard let data = Shots.join(parts, width: width, height: total, scale: max(scale, 1)) else { return done(nil, nil) }
                let file = Shots.contextFolder().appending(path: "fullpage-\(Shots.stamp()).png")
                do { try data.write(to: file); done(file.path, note) } catch { done(nil, nil) }
            }
            @MainActor func step(_ y: CGFloat) {
                self.webView.callAsyncJavaScript("window.scrollTo(0, y); return window.scrollY", arguments: ["y": Double(y)], in: nil, in: self.world) { r in
                    // Let the page paint what the scroll uncovered (lazy images, sticky bars) before the picture.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        MainActor.assumeIsolated {
                            var at = y
                            if case .success(let v) = r, let n = v as? NSNumber { at = CGFloat(n.doubleValue) }
                            let config = WKSnapshotConfiguration()
                            config.rect = self.webView.bounds
                            self.webView.takeSnapshot(with: config) { image, _ in
                                MainActor.assumeIsolated {
                                    guard let image else { return done(nil, nil) }
                                    parts.append((y: at, image: image))
                                    let next = y + view
                                    if next >= total { return finish((m["h"] ?? 0) > Double(maxHeight) ? "stopped at \(Int(maxHeight)) px of \(Int(m["h"] ?? 0))" : nil) }
                                    // The last piece can't scroll past the end: it starts at total - view and overlaps.
                                    step(min(next, max(total - view, 0)))
                                }
                            }
                        }
                    }
                }
            }
            step(0)
        }
    }

    /// Scrolls the page: `top`, `bottom`, `up`, `down` (a screen less a little), pixels (signed), or an element.
    /// Hands back where it is now (`y`), the page's `height` and the `screen`'s, or nil if no element matches.
    public func scroll(to target: String, _ done: @escaping @MainActor ([String: Any]?) -> Void) {
        webView.callAsyncJavaScript("""
            const d = document.documentElement, b = document.body;
            const height = () => Math.max(d.scrollHeight, b ? b.scrollHeight : 0);
            const t = target.trim(), n = Number(t);
            if (t === 'top') window.scrollTo(0, 0);
            else if (t === 'bottom') window.scrollTo(0, height());
            else if (t === 'down') window.scrollBy(0, Math.round(window.innerHeight * 0.9));
            else if (t === 'up') window.scrollBy(0, -Math.round(window.innerHeight * 0.9));
            else if (t !== '' && Number.isFinite(n)) window.scrollBy(0, n);
            else {
              const el = document.querySelector(t);
              if (!el) return null;
              el.scrollIntoView({ block: 'start', inline: 'nearest' });
            }
            return { y: Math.round(window.scrollY), height: height(), screen: window.innerHeight };
            """, arguments: ["target": target], in: nil, in: world) { r in
            if case .success(let v) = r { done(v as? [String: Any]) } else { done(nil) }
        }
    }
}
