import AppKit

/// `--then anchors:<path.json>` (H2): the on-screen frame of every named UI element in the main
/// window, so a video camera can target elements by name. Walks the accessibility tree in-process
/// (needs no permission), falling back to NSViews when the tree gives no usable frames.
/// Frames are in window points, top-left origin (match `--capture-window` PNGs), and
/// `contentFrame` relative to the content layout rect (match `--capture` PNGs).
@MainActor
public enum Anchors {
    static let maxDepth = 60, maxCount = 4000

    struct Item {
        var role: String, label: String, identifier: String, value: String
        var frame: CGRect, path: String, index: Int, depth: Int
    }

    public static func write(window: NSWindow, to url: URL) throws {
        guard let content = window.contentView else { throw WindowCapture.CaptureError("Window has no content view") }
        content.layoutSubtreeIfNeeded()
        // SwiftUI builds its accessibility tree only for a client that asks; say one has.
        for attr in ["AXEnhancedUserInterface", "AXManualAccessibility"] {
            NSApp.accessibilitySetValue(true as NSNumber, forAttribute: NSAccessibility.Attribute(rawValue: attr))
        }
        let wf = window.frame
        let layout = window.contentLayoutRect   // window base coordinates, bottom-left origin
        let layoutTop = wf.height - layout.maxY // content rect's top edge, down from the window's top
        // Screen (bottom-left) -> window points (top-left).
        func toWindow(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX - wf.minX, y: wf.maxY - r.maxY, width: r.width, height: r.height)
        }
        var items: [Item] = []
        var source = "accessibility"
        // From the frame view, so the toolbar (the titlebar's own views) is walked too.
        walkAX(content.superview ?? content, depth: 0, index: 0, path: "", inherited: "", into: &items, toWindow: toWindow, size: wf.size)
        // Fall back to views when the tree gave nothing usable.
        if items.isEmpty {
            source = "views"
            walkViews(content, depth: 0, index: 0, path: "", into: &items, window: window, toWindow: { _ in .zero })
        }
        func r1(_ v: CGFloat) -> Double { (Double(v) * 10).rounded() / 10 }
        func rect(_ f: CGRect) -> [String: Double] { ["x": r1(f.minX), "y": r1(f.minY), "width": r1(f.width), "height": r1(f.height)] }
        let list: [[String: Any]] = items.map { i in
            var d: [String: Any] = [
                "role": i.role, "path": i.path, "index": i.index, "depth": i.depth,
                "frame": rect(i.frame),
                "contentFrame": rect(i.frame.offsetBy(dx: -layout.minX, dy: -layoutTop)),
            ]
            if !i.label.isEmpty { d["label"] = i.label }
            if !i.identifier.isEmpty { d["identifier"] = i.identifier }
            if !i.value.isEmpty { d["value"] = i.value }
            return d
        }
        let doc: [String: Any] = [
            "source": source,
            "window": ["width": r1(wf.width), "height": r1(wf.height)],
            "content": ["x": r1(layout.minX), "y": r1(layoutTop), "width": r1(layout.width), "height": r1(layout.height)],
            "count": list.count,
            "anchors": list,
        ]
        let data = try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private static func clip(_ s: String?) -> String { String((s ?? "").prefix(120)) }

    /// A getter the node answers to, by selector (SwiftUI's AccessibilityNode adopts only the element
    /// protocol statically; the rest it answers dynamically).
    private static func get(_ node: NSObject, _ key: String) -> Any? {
        node.responds(to: Selector(key)) ? node.value(forKey: key) : nil
    }

    private static func walkAX(_ node: Any, depth: Int, index: Int, path: String, inherited: String, into items: inout [Item],
                               toWindow: (CGRect) -> CGRect, size: CGSize) {
        guard depth <= maxDepth, items.count < maxCount, let obj = node as? NSObject, let el = node as? NSAccessibilityElementProtocol else { return }
        let role = (get(obj, "accessibilityRole") as? String) ?? ""
        let label = clip(get(obj, "accessibilityLabel") as? String)
        let title = clip(get(obj, "accessibilityTitle") as? String)
        let rawIdent = clip(get(obj, "accessibilityIdentifier") as? String)
        let ident = rawIdent == inherited ? "" : rawIdent   // SwiftUI hands a container's identifier to everything inside it
        let value = clip(get(obj, "accessibilityValue") as? String)
        let frame = toWindow(el.accessibilityFrame())
        let name = !label.isEmpty ? label : title
        let named = !name.isEmpty || !ident.isEmpty || !value.isEmpty
        let hidden = (node as? NSView)?.isHiddenOrHasHiddenAncestor ?? false
        let sane = frame.width > 0.5 && frame.height > 0.5 && frame.width < 20000 && frame.height < 20000 && frame.minX.isFinite && frame.minY.isFinite
        let visible = sane && frame.intersects(CGRect(origin: .zero, size: size))
        if named, !hidden, visible {
            items.append(Item(role: role, label: name, identifier: ident, value: value, frame: frame, path: path.isEmpty ? (name.isEmpty ? ident : name) : path + " > " + (name.isEmpty ? (ident.isEmpty ? role : ident) : name), index: index, depth: depth))
        }
        let seg = name.isEmpty ? (ident.isEmpty ? role : ident) : name
        let nextPath = path.isEmpty ? seg : path + " > " + seg
        let kids = (get(obj, "accessibilityChildren") as? [Any]) ?? []
        for (i, k) in kids.enumerated() { walkAX(k, depth: depth + 1, index: i, path: nextPath, inherited: rawIdent.isEmpty ? inherited : rawIdent, into: &items, toWindow: toWindow, size: size) }
    }

    private static func walkViews(_ v: NSView, depth: Int, index: Int, path: String, into items: inout [Item],
                                  window: NSWindow, toWindow: (CGRect) -> CGRect) {
        guard depth <= maxDepth, items.count < maxCount, !v.isHiddenOrHasHiddenAncestor else { return }
        let ident = v.accessibilityIdentifier()
        let label = v.accessibilityLabel() ?? ""
        let seg = !label.isEmpty ? label : (!ident.isEmpty ? ident : String(describing: type(of: v)))
        let nextPath = path.isEmpty ? seg : path + " > " + seg
        let r = v.convert(v.bounds, to: nil)   // window base, bottom-left
        let f = CGRect(x: r.minX, y: window.frame.height - r.maxY, width: r.width, height: r.height)
        if (!label.isEmpty || !ident.isEmpty), f.width > 0.5, f.height > 0.5 {
            items.append(Item(role: v.accessibilityRole()?.rawValue ?? "", label: clip(label), identifier: clip(ident), value: "", frame: f, path: nextPath, index: index, depth: depth))
        }
        for (i, s) in v.subviews.enumerated() { walkViews(s, depth: depth + 1, index: i, path: nextPath, into: &items, window: window, toWindow: toWindow) }
    }
}
