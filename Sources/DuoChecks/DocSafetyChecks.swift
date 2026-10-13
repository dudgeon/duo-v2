import DuoKit
import Foundation

// C-81, DL-175: the editor's bridge, web-process recovery and what local pages may load.

private func matches(_ pattern: String, in text: String) -> [String] {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = text as NSString
    return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
}

@MainActor func docSafetyChecks() throws {
    print("document safety (C-81, DL-175)")
    let js = (try? String(contentsOf: repoRoot().appending(path: "Vendor/codemirror/src/duo-editor.js"), encoding: .utf8)) ?? ""
    check(!js.isEmpty, "the editor page's source is found")

    // Every kind the page posts is decoded by Swift, and every kind Swift decodes is posted: a prefix test
    // once dropped "propertiesFolded" without a sound.
    let posted = Set(matches(#"\bpost\("(\w+)""#, in: js))
    let decoded = Set(EditorMessage.allCases.map(\.rawValue))
    check(posted.subtracting(decoded).isEmpty, "every message the page posts is in EditorMessage (missing: \(posted.subtracting(decoded).sorted()))")
    check(decoded.subtracting(posted).isEmpty, "every EditorMessage is posted by the page (unused: \(decoded.subtracting(posted).sorted()))")
    let index = SourceIndex()
    let editorSwift = index.files.first { $0.path.hasSuffix("Editor/DocumentEditor.swift") }?.text ?? ""
    check(!editorSwift.contains(#"hasPrefix("property")"#), "the bridge doesn't route by a name prefix")

    // Every duo.<name>( Swift calls exists on window.duo.
    var exported = Set<String>()
    if let r = js.range(of: "\nwindow.duo = {") {
        let body = js[r.upperBound...]
        let end = body.range(of: "\n};")?.lowerBound ?? body.endIndex
        exported = Set(matches(#"(?m)^  (\w+)\s*[:,(]"#, in: String(body[..<end])))
    }
    check(exported.count > 20, "window.duo's names are read (\(exported.count))")
    var called = Set<String>()
    for f in index.files where f.path.hasPrefix("DuoKit/") { called.formUnion(matches(#"(?<![\w.])duo\.(\w+)\("#, in: f.text)) }
    check(called.subtracting(exported).isEmpty, "every duo.<name>( Swift calls is on window.duo (missing: \(called.subtracting(exported).sorted()))")

    // A WebContent process that dies is reloaded, in every web view Duo owns.
    for type in ["EditorController", "HTMLViewer", "DeckViewer", "DocxViewer", "WebTab"] {
        let bodies = index.declarations(of: type)
        check(!bodies.isEmpty && bodies.contains { $0.body.contains("webViewWebContentProcessDidTerminate") },
              "\(type) handles its web content process terminating")
    }

    // DL-175: the editor page's CSP allows https images and no remote script, style, frame or request.
    let html = (try? String(contentsOf: repoRoot().appending(path: "Vendor/codemirror/dist/editor.html"), encoding: .utf8)) ?? ""
    let csp = matches(#"Content-Security-Policy" content="([^"]*)""#, in: html).first ?? ""
    check(csp.contains("default-src 'none'") && csp.contains("img-src https: data: blob:"), "the editor page has a CSP that allows https images")
    check(!csp.contains("script-src *") && !csp.contains("unsafe-eval") && csp.contains("connect-src 'none'") && csp.contains("frame-src 'none'"),
          "and no remote script, eval, request or frame")
    check(!csp.contains("http:") && !csp.contains("img-src *"), "and no plain http")

    // DL-175: local HTML loads nothing remote.
    if let data = HTMLViewer.remoteBlockRules.data(using: .utf8), let rules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
        let types = rules.flatMap { (($0["trigger"] as? [String: Any])?["resource-type"] as? [String]) ?? [] }
        check(["image", "style-sheet", "script", "font", "fetch", "websocket", "media"].allSatisfy(types.contains), "the local-page rule list blocks images, styles, scripts, fonts, fetches, sockets and media")
        check(rules.contains { ($0["trigger"] as? [String: Any])?["load-context"] as? [String] == ["child-frame"] }, "and remote frames")
        check(rules.allSatisfy { ($0["action"] as? [String: String])?["type"] == "block" }, "every rule blocks")
    } else { check(false, "the local-page rule list is JSON") }
    let viewer = index.declarations(of: "HTMLViewer").map(\.body).joined()
    check(viewer.contains("compileContentRuleList") && viewer.contains("rulesReady"), "the HTML viewer compiles the rules and waits for them before loading a page")

    // The task menus and the duo2 task verbs wait for the editor's save before rewriting a note.
    let menu = index.files.first { $0.path.hasSuffix("Model/AppModel+TaskMenu.swift") }?.text ?? ""
    check(menu.contains("afterNoteSaved(project: project, path: path) { [weak self] in\n            if let link = self?.taskLink")
          && menu.contains("model.afterNoteSaved(project: project, path: path) { if let why = model.unarchiveTask")
          && menu.contains("self?.afterNoteSaved(project: project, path: path) { if let self { report(self.archiveTask(project: project, path: path, sessions: true))")
          && menu.contains("afterNoteSaved(project: hit.project, path: hit.path) { [weak self] in self?.taskMenuVerbNow"),
          "Copy Link, Archive, Unarchive and the duo2 rename/archive/unarchive/link verbs wait for the open note's save")

    // Save re-evaluates once the editor first shows a document (the editor is unobserved).
    let commands = index.files.first { $0.path.hasSuffix("Navigation/Commands.swift") }?.text ?? ""
    check(commands.contains("case .save: model.terminalsMode == .live && model.editorOpened"), "Save depends on the observed editorOpened flag")
}
