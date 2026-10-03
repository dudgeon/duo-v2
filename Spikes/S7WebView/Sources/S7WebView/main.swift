import AppKit
import Network
import WebKit

// Pass/fail, written first:
// 1. A page served from 127.0.0.1 loads.
// 2. Navigating to an external host is refused by default (no request leaves the machine).
// 3. A local page's external subresource (img) is blocked by default.
// 4. With example.com on the allow list, navigation to it is allowed (decision only; no network needed).
// 5. isInspectable can be set.

@MainActor final class Spike: NSObject, WKNavigationDelegate {
    var allow: Set<String> = []
    var log: [String] = []
    let web: WKWebView
    var done: ((String) -> Void)?

    init(rules: WKContentRuleList) {
        let cfg = WKWebViewConfiguration()
        if ProcessInfo.processInfo.environment["NORULES"] == nil { cfg.userContentController.add(rules) }
        cfg.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: cfg)
        super.init()
        web.navigationDelegate = self
        web.isInspectable = true
    }

    static func isLocal(_ url: URL) -> Bool {
        guard let h = url.host else { return url.isFileURL || url.scheme == "about" }
        return h == "localhost" || h == "127.0.0.1" || h == "::1" || h.hasSuffix(".localhost")
    }

    func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction) async -> WKNavigationActionPolicy {
        let url = a.request.url!
        let ok = Self.isLocal(url) || (url.host.map { allow.contains($0) } ?? false)
        log.append("nav \(url.host ?? url.absoluteString): \(ok ? "allow" : "deny")")
        return ok ? .allow : .cancel
    }

    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { done?("finish") }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { done?("fail \(e.localizedDescription)") }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { done?("fail \(e.localizedDescription)") }
}

// A tiny local HTTP server: / returns a page with an external image and a local one.
final class Server: @unchecked Sendable {
    let listener: NWListener
    var hits: [String] = []
    init() throws {
        let p = NWParameters.tcp
        p.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 8765)  // random ports can hit WebKit's restricted list
        listener = try NWListener(using: p)
        listener.newConnectionHandler = { [unowned self] c in
            c.start(queue: .main)
            c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { d, _, _, _ in
                let line = String(data: d ?? Data(), encoding: .utf8)?.split(separator: "\r\n").first.map(String.init) ?? ""
                self.hits.append(line)
                let body = line.contains("/local.png")
                    ? "x"
                    : "<html><body><h1 id=t>local ok</h1><img id=ext src='https://example.com/x.png'><img id=loc src='/local.png'></body></html>"
                let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                c.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in c.cancel() })
            }
        }
    }
}

@MainActor func run() async {
    // Block every http(s) load whose host isn't local, at the content-blocker level: covers
    // subresources the navigation delegate never sees.
    // Block every http(s) load, then un-block local hosts (one rule each: no disjunctions in
    // content-blocker regexes). `unless-domain` would key on the page, not the resource.
    let rulesJSON = """
    [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}},
     {"trigger":{"url-filter":"^https?://localhost[:/]"},"action":{"type":"ignore-previous-rules"}},
     {"trigger":{"url-filter":"^https?://127\\\\.0\\\\.0\\\\.1[:/]"},"action":{"type":"ignore-previous-rules"}}]
    """
    let rules: WKContentRuleList
    do {
        guard let r = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "duo-local-only", encodedContentRuleList: rulesJSON) else {
            print("✘ rule list didn't compile (nil)"); exit(1)
        }
        rules = r
    } catch { print("✘ rule list: \(error)"); print(rulesJSON); exit(1) }
    let server = try! Server()
    server.listener.start(queue: .main)
    while server.listener.state != .ready { try? await Task.sleep(for: .milliseconds(20)) }
    let port = 8765
    let s = Spike(rules: rules)
    var results: [(String, Bool)] = []

    func load(_ url: String) async -> String {
        await withCheckedContinuation { c in
            var once = false
            s.done = { r in if !once { once = true; c.resume(returning: r) } }
            s.web.load(URLRequest(url: URL(string: url)!))
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { if !once { once = true; c.resume(returning: "timeout") } }
        }
    }

    let r1 = await load("http://127.0.0.1:\(port)/")
    let title = try? await s.web.evaluateJavaScript("document.getElementById('t')?.textContent") as? String
    results.append(("1 local page loads (\(r1), \(title ?? "-"))", title == "local ok"))
    try? await Task.sleep(for: .seconds(1))
    let ext = try? await s.web.evaluateJavaScript("[document.getElementById('ext').naturalWidth, document.getElementById('loc').complete]") as? [Any]
    results.append(("3 external subresource blocked (ext width \(ext?.first ?? "?"))", (ext?.first as? Int) == 0))
    results.append(("  local subresource requested", server.hits.contains { $0.contains("/local.png") }))
    let entries = (try? await s.web.evaluateJavaScript("performance.getEntriesByType('resource').map(e => e.name).join(' ')") as? String) ?? ""
    let rulesOn = ProcessInfo.processInfo.environment["NORULES"] == nil
    print("  resource entries: \(entries)")
    results.append(("3b example.com request \(rulesOn ? "never made (rules on)" : "made (rules off)")", entries.contains("example.com") != rulesOn))

    let before = s.log.count
    _ = await load("https://example.com/")
    results.append(("2 external navigation refused: \(s.log.dropFirst(before).joined(separator: "; "))", s.log.dropFirst(before).contains { $0.contains("example.com: deny") }))

    s.allow = ["example.com"]
    let before2 = s.log.count
    _ = await load("https://example.com/")
    results.append(("4 allow-listed host passes the policy: \(s.log.dropFirst(before2).joined(separator: "; "))", s.log.dropFirst(before2).contains { $0.contains("example.com: allow") }))
    results.append(("5 isInspectable", s.web.isInspectable))

    for (name, ok) in results { print("\(ok ? "✔" : "✘") \(name)") }
    exit(results.allSatisfy(\.1) ? 0 : 1)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { @MainActor in await run() }
app.run()
