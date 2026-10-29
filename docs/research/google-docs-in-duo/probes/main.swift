// Throwaway probe (gdocs-frame, 2026-10-29): load a public Google Doc in a WKWebView configured
// as Duo's browser tab (non-persistent store, Safari UA token), off screen and never activated,
// then run JS probes in the page world and in an isolated world, printing JSON.
// usage: probe <url> <probe.js> [seconds-before-probe] [png-out]
import AppKit
import WebKit

let args = CommandLine.arguments
let url = URL(string: args[1])!
let js = try! String(contentsOfFile: args[2], encoding: .utf8)
let wait = args.count > 3 ? Double(args[3])! : 12
let png = args.count > 4 ? args[4] : nil

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

final class D: NSObject, WKNavigationDelegate {
    var t0 = Date()
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
        FileHandle.standardError.write("didFinish +\(Int(Date().timeIntervalSince(t0) * 1000)) ms\n".data(using: .utf8)!)
    }
}

let config = WKWebViewConfiguration()
config.websiteDataStore = .nonPersistent()
config.applicationNameForUserAgent = "Version/27.0 Safari/605.1.15"
if let pre = ProcessInfo.processInfo.environment["PRE_JS"], let s = try? String(contentsOfFile: pre, encoding: .utf8) {
    config.userContentController.addUserScript(WKUserScript(source: s, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
}
let w = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 1200, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), configuration: config)
let occ = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
if wv.responds(to: occ) { typealias F = @convention(c) (AnyObject, Selector, Bool) -> Void; unsafeBitCast(wv.method(for: occ), to: F.self)(wv, occ, false); FileHandle.standardError.write("occlusion detection off\n".data(using: .utf8)!) }
w.contentView = wv
w.orderFrontRegardless()
let d = D()
wv.navigationDelegate = d
d.t0 = Date()
wv.load(URLRequest(url: url))

func mouse(_ type: NSEvent.EventType, _ css: CGPoint, mods: NSEvent.ModifierFlags = [], clicks: Int = 1) {
    var p = CGPoint(x: css.x * wv.pageZoom, y: css.y * wv.pageZoom)
    if !wv.isFlipped { p.y = wv.bounds.height - p.y }
    let at = wv.convert(p, to: nil)
    let e = NSEvent.mouseEvent(with: type, location: at, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: type == .leftMouseUp ? 0 : 1)!
    switch type { case .leftMouseDown: wv.mouseDown(with: e); case .leftMouseDragged: wv.mouseDragged(with: e); case .leftMouseUp: wv.mouseUp(with: e); default: wv.mouseMoved(with: e) }
}
func key(_ code: UInt16, _ chars: String, mods: NSEvent.ModifierFlags = []) {
    for t in [NSEvent.EventType.keyDown, .keyUp] {
        let e = NSEvent.keyEvent(with: t, location: .zero, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        if t == .keyDown { wv.keyDown(with: e) } else { wv.keyUp(with: e) }
    }
}
// ACTS: "drag x1 y1 x2 y2; key shiftright; key right"
func runActs(_ list: [String], _ done: @escaping () -> Void) {
    guard let a = list.first else { return done() }
    let f = a.split(separator: " ").map(String.init)
    let rest = Array(list.dropFirst())
    let next = { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { runActs(rest, done) } }
    switch f[0] {
    case "drag":
        let a = CGPoint(x: Double(f[1])!, y: Double(f[2])!), b = CGPoint(x: Double(f[3])!, y: Double(f[4])!)
        w.makeFirstResponder(wv)
        mouse(.mouseMoved, a); mouse(.leftMouseDown, a)
        for i in 1...8 { let t = Double(i) / 8; mouse(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)) }
        mouse(.leftMouseUp, b); next()
    case "click":
        let a = CGPoint(x: Double(f[1])!, y: Double(f[2])!)
        w.makeFirstResponder(wv); mouse(.mouseMoved, a); mouse(.leftMouseDown, a); mouse(.leftMouseUp, a); next()
    case "key":
        let shift: NSEvent.ModifierFlags = f[1].hasPrefix("shift") ? [.shift] : []
        let name = f[1].replacingOccurrences(of: "shift", with: "")
        let codes: [String: (UInt16, String)] = ["right": (124, "\u{F703}"), "left": (123, "\u{F702}"), "down": (125, "\u{F701}"), "x": (7, "x")]
        let (c, ch) = codes[name]!
        key(c, ch, mods: shift); next()
    default: next()
    }
}

DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
  let acts = (ProcessInfo.processInfo.environment["ACTS"] ?? "").split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
  runActs(acts) {
    let world = ProcessInfo.processInfo.environment["WORLD"] == "isolated" ? WKContentWorld.defaultClient : WKContentWorld.page
    wv.callAsyncJavaScript(js, arguments: [:], in: nil, in: world) { r in
        switch r {
        case .success(let v):
            if JSONSerialization.isValidJSONObject(v), let data = try? JSONSerialization.data(withJSONObject: v, options: [.prettyPrinted, .sortedKeys]) {
                print(String(data: data, encoding: .utf8)!)
            } else { print(String(describing: v)) }
        case .failure(let e): print("JS error: \(e)")
        }
        guard let png else { exit(0) }
        wv.takeSnapshot(with: nil) { img, _ in
            if let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: png))
            }
            exit(0)
        }
    }
  }
}
app.run()
