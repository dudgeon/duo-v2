import AppKit
import SwiftUI
import WebKit

/// Markdown turned into the preview's page: the rendered document, read only, in the editor's
/// reading styles (no bar). Pure, so DuoChecks can run it.
public enum MarkdownPreviewHTML {
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Bold, italic, code and links; everything else is text.
    static func inline(_ s: String) -> String {
        var t = esc(s)
        func sub(_ pattern: String, _ template: String) {
            if let re = try? NSRegularExpression(pattern: pattern) {
                t = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: template)
            }
        }
        sub("`([^`]+)`", "<code>$1</code>")
        sub("\\*\\*([^*]+)\\*\\*", "<strong>$1</strong>")
        sub("(?<![\\w*])\\*([^*]+)\\*(?![\\w*])", "<em>$1</em>")
        sub("\\[([^\\]]+)\\]\\(([^)\\s]+)\\)", "<a href=\"$2\">$1</a>")
        return t
    }

    static func html(_ blocks: [ChatBlock]) -> String {
        blocks.map { b -> String in
            switch b {
            case .heading(let level, let text): "<h\(min(6, max(1, level)))>\(inline(text))</h\(min(6, max(1, level)))>"
            case .paragraph(let p): "<p>\(inline(p).replacingOccurrences(of: "\n", with: " "))</p>"
            case .list(let ordered, let start, let items):
                "<\(ordered ? "ol start=\"\(start)\"" : "ul")>" + items.map { "<li>\(html($0))</li>" }.joined() + "</\(ordered ? "ol" : "ul")>"
            case .code(_, let text): "<pre><code>\(esc(text))</code></pre>"
            case .table(let header, let rows):
                "<table><tr>" + header.map { "<th>\(inline($0))</th>" }.joined() + "</tr>"
                + rows.map { "<tr>" + $0.map { "<td>\(inline($0))</td>" }.joined() + "</tr>" }.joined() + "</table>"
            case .quote(let inner): "<blockquote>\(html(inner))</blockquote>"
            case .rule: "<hr>"
            }
        }.joined(separator: "\n")
    }

    /// The source lines of each heading, outside code fences: the anchor map. A heading's anchor is
    /// `h:<n>`, the nth heading; it runs to the line before the next heading.
    public static func anchorMap(_ text: String) -> [AnchorRange] {
        let lines = text.components(separatedBy: "\n")
        var fenced = false, starts: [Int] = []
        for (i, l) in lines.enumerated() {
            if l.hasPrefix("```") || l.hasPrefix("~~~") { fenced.toggle(); continue }
            if !fenced, l.hasPrefix("#"), l.drop(while: { $0 == "#" }).hasPrefix(" ") { starts.append(i + 1) }
        }
        return starts.enumerated().map { n, first in
            AnchorRange(anchor: "h:\(n + 1)", firstLine: first, lastLine: (n + 1 < starts.count ? starts[n + 1] - 1 : lines.count))
        }
    }

    /// The text without a leading frontmatter block.
    public static func body(_ text: String) -> String {
        guard text.hasPrefix("---\n"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) else { return text }
        return String(text[end.upperBound...].drop(while: { $0 == "\n" || $0 == "-" }))
    }

    public static func page(_ text: String, colors: (back: String, text: String, dim: String, rule: String)) -> String {
        """
        <!doctype html><meta charset="utf-8"><style>
        :root{color-scheme:light dark}
        body{margin:0;padding:22px 28px;background:\(colors.back);color:\(colors.text);font:14px/1.55 -apple-system,system-ui,sans-serif;max-width:720px}
        h1,h2,h3,h4{line-height:1.25;margin:1.2em 0 .4em} h1{font-size:1.7em} h2{font-size:1.35em} h3{font-size:1.12em}
        p,ul,ol,pre,table,blockquote{margin:.6em 0} code{font:12.5px ui-monospace,Menlo,monospace}
        pre{padding:10px 12px;border:1px solid \(colors.rule);border-radius:6px;overflow:auto}
        blockquote{margin-left:0;padding-left:12px;border-left:2px solid \(colors.rule);color:\(colors.dim)}
        table{border-collapse:collapse} td,th{border:1px solid \(colors.rule);padding:4px 8px;text-align:left}
        hr{border:0;border-top:1px solid \(colors.rule)} a{color:inherit}
        </style><body>\(html(ChatMarkdown.parse(body(text))))
        """
    }
}

/// The Markdown preview provider (read only, no bar). Renders the editor's buffer.
@MainActor
public final class MarkdownPreviewProvider: NSObject, PreviewProvider, WKNavigationDelegate {
    public let kind = PreviewKind.markdown
    public let webView: DuoWebView
    public var emit: ((PreviewEvent) -> Void)?
    public var view: NSView { webView }
    private var gate = RevisionGate()
    public private(set) var lastText: String?

    public override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = DuoWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
    }

    public nonisolated static func canPreview(file: String, frontmatter: [String: String]) -> Bool {
        ["md", "markdown"].contains((file as NSString).pathExtension.lowercased())
    }

    public func render(text: String, rev: Int) {
        guard gate.admit(rev) else { return }   // a render older than the newest is dropped
        lastText = text
        func hex(_ c: NSColor) -> String {
            var r = c
            webView.effectiveAppearance.performAsCurrentDrawingAppearance { r = c.usingColorSpace(.sRGB) ?? c }
            return String(format: "#%02X%02X%02X", Int(r.redComponent * 255), Int(r.greenComponent * 255), Int(r.blueComponent * 255))
        }
        let colors = (hex(DuoNSColor.pane), hex(DuoNSColor.text), hex(DuoNSColor.text2), hex(DuoNSColor.rule))
        // The HTML and the anchor map are made off the main thread (rule 6); a newer render that arrives
        // meanwhile wins, and this one is dropped at the gate on its way back.
        Task.detached(priority: .userInitiated) { [weak self] in
            let page = MarkdownPreviewHTML.page(text, colors: colors)
            let map = MarkdownPreviewHTML.anchorMap(text)
            await MainActor.run {
                guard let self, self.gate.newest == rev else { return }
                self.webView.loadHTMLString(page, baseURL: nil)
                self.emit?(.anchorMap(rev: rev, map))
            }
        }
    }

    public func reveal(anchor: String, reason: RevealReason) {
        guard anchor.hasPrefix("h:"), let n = Int(anchor.dropFirst(2)) else { return }
        webView.evaluateJavaScript("(document.querySelectorAll('h1,h2,h3,h4,h5,h6')[\(n - 1)]||{scrollIntoView(){}}).scrollIntoView({block:'start'})")
    }

    /// Links in a preview open in the browser; the preview itself never navigates.
    public func webView(_ w: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if action.navigationType == .linkActivated, let u = action.request.url { NSWorkspace.shared.open(u); return decisionHandler(.cancel) }
        decisionHandler(.allow)
    }
}

/// A web view shown as a pane's whole body (the preview side), re-parented like the editor's.
struct WebPreviewView: NSViewRepresentable {
    let web: NSView
    func makeNSView(context: Context) -> DocumentEditorView.EditorHost { DocumentEditorView.EditorHost() }
    func updateNSView(_ host: DocumentEditorView.EditorHost, context: Context) { host.show(web) }
}
