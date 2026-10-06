// Drives a proof page in a WKWebView, the engine Duo would use (ENH-12 spike):
//   swift snap.swift <url> <out.png> [width] [js-to-run-after-render]
// Waits for the render, runs the script (e.g. a click), prints its result and window.__duo_last,
// then snapshots the whole page.
import AppKit
import WebKit

let args = CommandLine.arguments
let url = URL(string: args[1])!, out = args[2]
let width = args.count > 3 ? Double(args[3])! : 1400
let script = args.count > 4 ? args[4] : ""

final class Driver: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: 900))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
    func start() { window.contentView = web; window.alphaValue = 0.02; window.level = .floating; window.ignoresMouseEvents = true; window.orderFrontRegardless(); web.navigationDelegate = self; web.load(URLRequest(url: url)) }
    func webView(_ w: WKWebView, didFinish _: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { self.after() }
    }
    func after() {
        let js = script.isEmpty ? "null" : script
        web.evaluateJavaScript("(() => { const r = (() => { \(js) })(); return JSON.stringify({ result: r ?? null, last: window.__duo_last ?? null, slides: document.getElementById('count')?.textContent, ms: document.getElementById('ms')?.textContent, h: document.documentElement.scrollHeight }); })()") { r, e in
            print(r ?? e ?? "nil")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.snap() }
        }
    }
    func snap() {
        web.evaluateJavaScript("document.documentElement.scrollHeight") { h, _ in
            let height = min((h as? Double) ?? 900, 9000)
            self.window.setContentSize(NSSize(width: width, height: height)); self.web.frame.size.height = height
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let c = WKSnapshotConfiguration(); c.rect = NSRect(x: 0, y: 0, width: width, height: height)
                self.web.takeSnapshot(with: c) { img, err in
                    guard let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { print("snapshot failed", err as Any); exit(1) }
                    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
                    print("wrote", out); exit(0)
                }
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let d = Driver()
d.start()
DispatchQueue.main.asyncAfter(deadline: .now() + 60) { print("timeout"); exit(2) }
app.run()
