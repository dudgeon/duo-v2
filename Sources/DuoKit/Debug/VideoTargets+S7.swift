import AppKit
import Foundation
import WebKit

/// The intro video's scene 7, the editor pane (`--state video-s7-<what>`): the right pane's four tabs, the PRD's hand edits, Send
/// Selection to Claude and what it brings back, and the two pickers (an element on the prototype, a shape on a slide). Each state
/// works on a copy of the fixture's project folder (the editor saves, and the fixture is never written), with the file as it is at
/// that moment of the story; the edits themselves are made by the editor's own commands (`duo.exec`, `insertAtCaret`, `agentEdit`).
extension VideoTargets {
    nonisolated static let mdTab = "docs/prd-v2.md", htmlTab = "prototype/scan-review.html"
    nonisolated static let pptxTab = "docs/team-review-oct15.pptx", docxTab = "docs/beta-interview-synthesis.docx"

    /// Which right-pane tab a scene 7 state shows, and which recording its chat is (all three continue chat-s5, in order).
    nonisolated struct S7 {
        /// What the chat's composer holds in a state: nothing (focused, before the selection is sent), only Duo's reference to the selection,
        /// or the reference and Sam's words (what's there just before Send).
        enum Composer { case none, empty, reference, full }
        var tab: String, chat: String, composer = Composer.none

        static func of(_ screen: String) -> S7 {
            let name = String(screen.dropFirst("video-s7-".count))
            switch name {
            case "tab-html": return .init(tab: VideoTargets.htmlTab, chat: "chat-s5")
            case "tab-pptx": return .init(tab: VideoTargets.pptxTab, chat: "chat-s5")
            case "tab-docx": return .init(tab: VideoTargets.docxTab, chat: "chat-s5")
            case "md-composer-empty": return .init(tab: VideoTargets.mdTab, chat: "chat-s5", composer: .empty)
            case "md-composer-ref": return .init(tab: VideoTargets.mdTab, chat: "chat-s5", composer: .reference)
            case "md-composer": return .init(tab: VideoTargets.mdTab, chat: "chat-s5", composer: .full)
            case "md-sent", "md-after": return .init(tab: VideoTargets.mdTab, chat: "chat-s7-md")
            case "html-pick": return .init(tab: VideoTargets.htmlTab, chat: "chat-s7-md")
            case "html-sent", "html-after": return .init(tab: VideoTargets.htmlTab, chat: "chat-s7-html")
            case "pptx-slide3", "pptx-pick": return .init(tab: VideoTargets.pptxTab, chat: "chat-s7-html")
            case "pptx-sent", "pptx-after": return .init(tab: VideoTargets.pptxTab, chat: "chat-s7-pptx")
            default: return .init(tab: VideoTargets.mdTab, chat: "chat-s5")   // tab-md and the hand edits
            }
        }
    }

    nonisolated static let boldPhrase = "Fewer than 3% wrong books"
    nonisolated static let linkPhrase = "review step"
    nonisolated static let linkURL = "../prototype/scan-review.html"
    nonisolated static let owenLine = "Owen (P8) stopped after two wrong books in two scans."
    nonisolated static let bulletLine = "- Do stewards want the glare warning before every scan, or only at glass-door boxes?"

    /// The PRD as it stands before each hand edit, derived from `s7/prd-v2.before.md` (the text after all four), going back.
    static func prdStage(_ name: String, before: String, original: String) -> String {
        let typed = before.replacingOccurrences(of: "\n" + bulletLine, with: "")
        let linked = typed.replacingOccurrences(of: "\n" + owenLine, with: "")
        let bold = linked.replacingOccurrences(of: "[\(linkPhrase)](\(linkURL))", with: linkPhrase)
        switch name {
        case "bold-sel", "bold": return original
        case "link-sel", "link": return bold
        case "typed": return linked
        case "bullet": return typed
        default: return before
        }
    }

    /// A copy of the project folder for this state, with the PRD, prototype and deck as they are at that point of the story.
    static func s7Scratch(copyOf folder: URL, dir: URL, screen: String) -> URL? {
        let fm = FileManager.default
        let name = String(screen.dropFirst("video-s7-".count))
        let root = fm.temporaryDirectory.appending(path: "duo-video-s7-\(name)")
        try? fm.removeItem(at: root)
        let copy = root.appending(path: folder.lastPathComponent)
        do { try fm.createDirectory(at: root, withIntermediateDirectories: true); try fm.copyItem(at: folder, to: copy) } catch { return nil }
        let s7 = dir.appending(path: "s7")
        let prd = copy.appending(path: mdTab)
        if let before = try? String(contentsOf: s7.appending(path: "prd-v2.before.md"), encoding: .utf8),
           let original = try? String(contentsOf: prd, encoding: .utf8), name.hasPrefix("md-") || ["bold-sel", "bold", "link-sel", "link", "typed", "bullet"].contains(name) {
            try? prdStage(name, before: before, original: original).write(to: prd, atomically: true, encoding: .utf8)
        }
        func replace(_ file: String, with source: String) {
            let to = copy.appending(path: file)
            try? fm.removeItem(at: to)
            try? fm.copyItem(at: s7.appending(path: source), to: to)
        }
        if name == "html-after" { replace(htmlTab, with: "scan-review.after.html") }
        if name == "pptx-after" { replace(pptxTab, with: "team-review-oct15.after.pptx") }
        return copy
    }

    /// The `--then` actions a scene 7 state needs once its window exists (the editor and the viewers are web views).
    nonisolated static func s7Actions(_ screen: String, dir: URL) -> [String] {
        let name = String(screen.dropFirst("video-s7-".count))
        let selectBold = "video:select=\(boldPhrase)", selectLink = "video:select=\(linkPhrase)"
        let fix = "html-pick:body > div > div > div > div:nth-child(1) > div:nth-child(3) > div:nth-child(4) > div:nth-child(4) > button"
        switch name {
        case "tab-md", "tab-html", "tab-pptx", "tab-docx": return []
        case "bold-sel": return [selectBold, "video:measure=editor"]
        case "bold": return [selectBold, "video:exec=bold", "video:caret-eol=Q1. Auto-add", "video:measure=editor"]
        case "link-sel": return [selectLink, "video:measure=editor"]
        case "link": return [selectLink, "video:exec=link", "video:insert=\(linkURL)", "video:caret-eol=[\(linkPhrase)]", "video:caret-eol=Q1. Auto-add", "video:measure=editor"]
        case "typed": return ["video:caret-eol=[\(linkPhrase)]", "video:insert=\n\(owenLine)", "video:measure=editor"]
        case "bullet": return ["video:caret-eol=Q2. Do we keep", "video:insert=\n\(bulletLine)", "video:caret-eol=Q1. Auto-add", "video:measure=editor"]
        case "md-sel", "md-sent": return ["video:lines=14-17", "video:measure=editor"]
        case "md-composer-empty": return ["video:lines=14-17", "video:measure=editor", "wait:1", "video:focus=composer"]
        case "md-composer-ref": return ["video:lines=14-17", "video:measure=editor", "wait:1", "video:focus=composer", "video:measure=composer"]
        case "md-composer": return ["video:lines=14-17", "video:measure=editor", "wait:1", "video:measure=composer"]
        case "md-after":
            return ["video:agentedit=\(dir.appending(path: "chat-s7-md/transcript.jsonl").path)|toolu_m5", "video:caret-eol=Q1. Auto-add", "video:measure=editor"]
        case "html-pick": return ["wait:1.5", fix, "video:measure=html"]
        case "html-sent", "html-after": return ["wait:1.5", "video:measure=html"]
        case "pptx-slide3", "pptx-sent", "pptx-after": return ["wait:3", "slide-go:3", "wait:1", "video:measure=slide"]
        case "pptx-pick": return ["wait:3", "slide-go:3", "wait:1", "slide-pick:3/7", "video:measure=slide"]
        default: return []
        }
    }

    // MARK: `--then video:<what>`

    /// One scripted editor or viewer action for a scene 7 state (`video:<verb>=<argument>`).
    static func act(_ spec: String, on model: AppModel) {
        let kv = spec.split(separator: "=", maxSplits: 1).map(String.init)
        let verb = kv.first ?? "", arg = kv.count > 1 ? kv[1] : ""
        let e = model.editor
        func js(_ code: String, _ args: [String: Any] = [:]) {
            // A background launch's window isn't key, and CodeMirror shows its selection only with focus: key it (this never activates the app).
            e.webView.window?.makeKey()
            e.webView.window?.makeFirstResponder(e.webView)
            e.run("duo.focus(); " + code, args) { v in FileHandle.standardError.write(Data("video:\(verb): \(String(describing: v ?? "nil"))\n".utf8)) }
        }
        switch verb {
        case "select": js("const t = duo.text(), i = t.indexOf(s); if (i < 0) return 'not found'; duo.select(i, i + s.length); return i", ["s": arg])
        case "lines":
            let r = arg.split(separator: "-").compactMap { Int($0) }
            js("return duo.selectLines(a, b)", ["a": r.first ?? 1, "b": r.last ?? 1])
        case "exec": js("return duo.exec(n)", ["n": arg])
        case "insert": js("return duo.insertAtCaret(t)", ["t": arg])
        case "caret-eol": js("const t = duo.text(), i = t.indexOf(s); if (i < 0) return 'not found'; let e = t.indexOf('\\n', i); if (e < 0) e = t.length; duo.select(e); return e", ["s": arg])
        case "agentedit":
            let f = arg.split(separator: "|").map(String.init)
            guard f.count == 2, let text = try? String(contentsOfFile: f[0], encoding: .utf8) else { return }
            for line in text.split(separator: "\n") {
                guard let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                      let content = (o["message"] as? [String: Any])?["content"] as? [[String: Any]],
                      let use = content.first(where: { $0["type"] as? String == "tool_use" && $0["id"] as? String == f[1] }),
                      let input = use["input"] as? [String: Any] else { continue }
                js("return JSON.stringify(duo.agentEdit(e, null))", ["e": [input]])
                return
            }
        case "focus":   // the composer's focus ring, drawn while the editor keeps the keyboard (a blurred editor would hide its selection, which the frame shows)
            if let key = model.consoleTab { model.chat(for: key)?.ui.composerFocused = true }
        case "dump": js("return duo.text()")
        case "notecontext": model.pushNoteContext()   // scene 10: the sessions the note's links name, as the snapshot tells the editor
        case "selectheading": model.editor.selectHeading(path: arg)   // scene 10: New Task's note, its name selected
        case "measure": measure(arg, model)
        default: FileHandle.standardError.write(Data("video: unknown action \(spec)\n".utf8))
        }
    }

    /// Names the on-screen frames of things inside web views (the editor's text, the page's button, the slide's shape) for
    /// `--then anchors:`, which adds them to the accessibility tree's: `video.editor.*`, `video.html.fix`, `video.slide.shape`.
    static func measure(_ what: String, _ model: AppModel) {
        func take(_ wv: WKWebView, _ code: String, _ names: [String: String]) {
            wv.callAsyncJavaScript(code, arguments: [:], in: nil, in: .page) { r in
                MainActor.assumeIsolated {
                    guard case .success(let v) = r, let d = v as? [String: Any], let w = wv.window else { return }
                    let place: (String, [Double]) -> Void = { id, a in
                        guard a.count == 4 else { return }
                        let z = wv.pageZoom, height = w.frame.height
                        let base = wv.convert(NSRect(x: a[0] * z, y: a[1] * z, width: a[2] * z, height: a[3] * z), to: nil)
                        Anchors.web[id] = CGRect(x: base.minX, y: height - base.maxY, width: base.width, height: base.height)
                    }
                    for (key, id) in names {
                        if let a = d[key] as? [Double] { place(id, a) }
                        else if let list = d[key] as? [[Double]] { for (i, a) in list.enumerated() { place("\(id).\(i + 1)", a) } }
                    }
                    FileHandle.standardError.write(Data("video:measure: \(Anchors.web.keys.sorted())\n".utf8))
                }
            }
        }
        switch what {
        case "editor":
            take(model.editor.webView, editorMeasureJS, ["bold": "video.editor.bold", "link": "video.editor.link", "owen": "video.editor.owen",
                                                          "bullet": "video.editor.bullet", "heard": "video.editor.heard", "change": "video.editor.change",
                                                          "changes": "video.editor.change"])
        case "composer": measureComposer(model)
        case "note":
            take(model.editor.webView, noteMeasureJS, ["goal": "video.tasknote.goal", "sessions": "video.tasknote.sessions",
                                                       "body": "video.tasknote.body", "props": "video.tasknote.props"])
        case "html":
            take(model.htmlViewer.webView, """
                const el = document.querySelector('button.fix'); if (!el) return {};
                const r = el.getBoundingClientRect(); return { fix: [r.left, r.top, r.width, r.height] };
                """, ["fix": "video.html.fix"])
        case "slide":
            take(model.deckViewer.webView, """
                const el = document.querySelector('[data-slide-index="2"] [data-duo-shape-id="7"]'); if (!el) return {};
                const r = el.getBoundingClientRect(); return { shape: [r.left, r.top, r.width, r.height] };
                """, ["shape": "video.slide.shape"])
        default: break
        }
    }

    /// What Sam types after Duo's reference to the selection (the end of `chat-s7-md/composer.txt`).
    nonisolated static let samWords = "Update this with the latest tester feedback in research/feedback"

    /// `video.composer.text`: the rect where Sam's words sit in the composer (window points, top-left origin), the same in the state before
    /// he types (the line after Duo's reference, as wide as his words will be) and the one with them there (their own glyph box).
    static func measureComposer(_ model: AppModel) {
        guard let key = model.consoleTab, let v = model.chat(for: key)?.composerView, let w = v.window,
              let layout = v.layoutManager, let container = v.textContainer else { return }
        let ns = v.string as NSString
        let found = ns.range(of: samWords)
        var r: NSRect
        if found.location != NSNotFound {
            r = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: found, actualCharacterRange: nil), in: container)
        } else {
            // The line after the reference: the layout's extra line fragment (the text ends in a newline), else the last line's.
            let line = layout.extraLineFragmentRect.isEmpty ? layout.lineFragmentUsedRect(forGlyphAt: max(0, layout.numberOfGlyphs - 1), effectiveRange: nil) : layout.extraLineFragmentRect
            let size = (samWords as NSString).size(withAttributes: [.font: ComposerTextView.font])
            r = NSRect(x: container.lineFragmentPadding, y: line.minY, width: ceil(size.width), height: line.height)
        }
        let origin = v.textContainerOrigin
        r = r.offsetBy(dx: origin.x, dy: origin.y)
        let base = v.convert(r, to: nil)
        Anchors.web["video.composer.text"] = CGRect(x: base.minX, y: w.frame.height - base.maxY, width: base.width, height: base.height)
        FileHandle.standardError.write(Data("video:measure: video.composer.text \(Anchors.web["video.composer.text"]!)\n".utf8))
    }

    /// Text-range rects in the editor's page: each phrase's own glyph box (a DOM range over the line's text), the What we heard
    /// paragraph as the union of its lines' text, and Claude's highlighted changes (`.duo-added`), as one box and one per line.
    static let editorMeasureJS = """
        const lines = [...document.querySelectorAll('.cm-line')];
        const rects = (rs) => rs.filter((r) => r.width > 0 && r.height > 0);
        const box = (rs) => { rs = rects(rs); if (!rs.length) return null;
          const l = Math.min(...rs.map((r) => r.left)), t = Math.min(...rs.map((r) => r.top)), rr = Math.max(...rs.map((r) => r.right)), b = Math.max(...rs.map((r) => r.bottom));
          return [l, t, rr - l, b - t]; };
        const flat = (line) => { const nodes = []; let s = ''; const w = document.createTreeWalker(line, NodeFilter.SHOW_TEXT);
          for (let n; (n = w.nextNode());) { nodes.push([n, s.length]); s += n.data; } return { nodes, s }; };
        const find = (needle) => { for (const l of lines) { const { nodes, s } = flat(l), i = s.indexOf(needle); if (i < 0) continue; const j = i + needle.length; let a = null, b = null;
            for (const [n, o] of nodes) { if (!a && i < o + n.data.length) a = [n, i - o]; if (j <= o + n.data.length) { b = [n, j - o]; break; } }
            if (!a || !b) continue; const r = document.createRange(); r.setStart(a[0], a[1]); r.setEnd(b[0], b[1]); return box([...r.getClientRects()]); } return null; };
        const textBox = (l) => { const r = document.createRange(); r.selectNodeContents(l); return [...r.getClientRects()]; };
        const block = (from, to) => { const a = lines.findIndex((l) => l.textContent.includes(from)), b = lines.findIndex((l) => l.textContent.includes(to));
          if (a < 0 || b < 0) return null; return box(lines.slice(a, b + 1).flatMap(textBox)); };
        const added = [...document.querySelectorAll('.duo-added')];
        const perLine = new Map(); for (const el of added) { const l = el.closest('.cm-line'); perLine.set(l, (perLine.get(l) || []).concat([...el.getClientRects()])); }
        return { bold: find('Fewer than 3% wrong books'), link: find('review step'), owen: find('Owen (P8) stopped after two wrong books in two scans.'),
                 bullet: find('Do stewards want the glare warning before every scan, or only at glass-door boxes?'),
                 heard: block('Three of eight testers', 'Owen (P8) stopped'),
                 change: box(added.flatMap((el) => [...el.getClientRects()])), changes: [...perLine.values()].map(box).filter(Boolean) };
        """
}
