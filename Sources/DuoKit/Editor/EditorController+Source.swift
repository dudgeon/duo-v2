import Foundation
import WebKit

/// Source mode, per document (DL-167): the page keeps each document's mode with its editor state
/// (`duo.show(id, text, {source})` opens it in the remembered mode); this sends the remembered set and
/// flips the document on screen.
extension EditorController {
    /// The remembered set, to the page: it decides a document's mode when it is shown.
    func sendSourceModes() {
        guard pageReady, let data = try? JSONSerialization.data(withJSONObject: sourceModes), let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.duo && duo.sourceModes(\(json))")
    }

    /// The document on screen, now.
    func showSource(_ on: Bool) {
        guard pageReady else { return }
        webView.callAsyncJavaScript("return duo.setSource(on)", arguments: ["on": on], in: nil, in: .page, completionHandler: nil)
    }
}
