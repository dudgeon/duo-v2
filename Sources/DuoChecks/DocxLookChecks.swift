import AppKit
import DuoKit
import DuoSearch
import Foundation

// DL-233: the Word viewer draws Google Docs' defaults where a document says nothing, and draws tracked changes and
// comments right in all four Markup views. Rendered by the real web view on the fixtures in
// docs/design/docx-viewer-handoff/fixture/{look,markup} (make_markup.py).
@MainActor func docxLookChecks() throws {
    print("the Word viewer: Google Docs defaults, tracked changes and comments (DL-233)")
    _ = NSApplication.shared
    let fx = repoRoot().appending(path: "docs/design/docx-viewer-handoff/fixture")
    let viewer = DocxViewer(resources: repoRoot().appending(path: "Vendor/docx-viewer"))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = viewer.webView

    func wait(_ s: TimeInterval) { let until = Date().addingTimeInterval(s); while Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) } }
    func settle(_ file: URL) -> Bool {
        var done = false
        viewer.open(file)
        viewer.whenSettled { done = true }
        let until = Date().addingTimeInterval(40)
        while !done, Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        return done && viewer.state == .ready
    }
    /// Runs a function body in the page and waits for its result.
    func js(_ body: String) -> Any? {
        var out: Any??
        viewer.inspect(body) { out = .some($0) }
        let until = Date().addingTimeInterval(20)
        while out == nil, Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        return out ?? nil
    }
    func near(_ a: Any?, _ b: Double, _ tol: Double = 0.05) -> Bool { ((a as? Double) ?? (a as? Int).map(Double.init)).map { abs($0 - b) <= tol } ?? false }

    // How a paragraph (found by its class, or the first plain one) reads: the font and colour on its text, the
    // spacing on the paragraph, in points. Line spacing is a multiple of the text's own size.
    let probe = """
        const sel = { normal: 'p:not([class])', title: 'p.docx_title', subtitle: 'p.docx_subtitle', h1: 'p.docx_heading1', h2: 'p.docx_heading2',
                      h3: 'p.docx_heading3', h4: 'p.docx_heading4', h5: 'p.docx_heading5', h6: 'p.docx_heading6' };
        const out = {};
        for (const [k, s] of Object.entries(sel)) {
          const p = document.querySelector('#host ' + s); if (!p) continue;
          const t = p.querySelector('span') || p, c = getComputedStyle(t), pc = getComputedStyle(p);
          out[k] = { family: c.fontFamily, size: parseFloat(c.fontSize) * 0.75, color: c.color, weight: c.fontWeight, italic: c.fontStyle === 'italic',
                     line: parseFloat(c.lineHeight) / parseFloat(c.fontSize), before: parseFloat(pc.marginTop) * 0.75, after: parseFloat(pc.marginBottom) * 0.75 };
        }
        return out;
        """
    func look(_ file: String) -> [String: [String: Any]] { (js(probe) as? [String: [String: Any]]) ?? [:] }
    let grey = "rgb(102, 102, 102)", dark = "rgb(67, 67, 67)", black = "rgb(0, 0, 0)"

    func googleScale(_ l: [String: [String: Any]], _ name: String, bodyFont: Bool = true) {
        let fam = { (k: String) in (l[k]?["family"] as? String ?? "") }
        if bodyFont {
            check(fam("normal").hasPrefix("Arial") && near(l["normal"]?["size"], 11) && near(l["normal"]?["line"], 1.15, 0.01), "\(name): normal text is Arial 11 pt at 1.15 (\(l["normal"] ?? [:]))")
        }
        let want: [(String, Double, Double, Double, String?)] = [("title", 26, 0, 3, nil), ("subtitle", 15, 0, 16, grey), ("h1", 20, 20, 6, nil), ("h2", 16, 18, 6, nil),
                                                                  ("h3", 14, 16, 4, dark), ("h4", 12, 14, 4, grey), ("h5", 11, 12, 4, grey), ("h6", 11, 12, 4, grey)]
        for (k, size, before, after, colour) in want {
            let r = l[k] ?? [:]
            check(near(r["size"], size) && near(r["before"], before) && near(r["after"], after) && (colour == nil || r["color"] as? String == colour) && near(r["weight"].flatMap { Double("\($0)") }, 400),
                  "\(name): \(k) is \(Int(size)) pt, \(Int(before)) before and \(Int(after)) after\(colour.map { ", " + ($0 == grey ? "#666666" : "#434343") } ?? ""), regular weight (\(r))")
        }
        check(l["h6"]?["italic"] as? Bool == true, "\(name): Heading 6 is italic")
        check(l["title"]?["color"] as? String == black && l["h1"]?["color"] as? String == black, "\(name): Title and Heading 1 are black")
    }

    // ---- Part 1: the defaults
    let noStyles = fx.appending(path: "look/No styles.docx")
    guard settle(noStyles) else { check(false, "No styles.docx is drawn (\(viewer.state))"); return }
    let none = look("No styles")
    googleScale(none, "a document with no styles")
    check(!(none["normal"]?["family"] as? String ?? "").lowercased().contains("times"), "…and nothing falls to the browser's serif")

    guard settle(fx.appending(path: "look/Google export.docx")) else { check(false, "Google export.docx is drawn (\(viewer.state))"); return }
    googleScale(look("Google export"), "Google Docs' own export")

    // A document's own styles win: Georgia 12 at 1.5, Verdana headings in its colours; only Heading 3 on (which it leaves out) is Google's.
    guard settle(fx.appending(path: "look/Own fonts.docx")) else { check(false, "Own fonts.docx is drawn (\(viewer.state))"); return }
    let own = look("Own fonts")
    check((own["normal"]?["family"] as? String ?? "").hasPrefix("Georgia") && near(own["normal"]?["size"], 12) && near(own["normal"]?["line"], 1.5, 0.01) && near(own["normal"]?["after"], 12),
          "its own body wins: Georgia 12 pt, 1.5 lines, 12 pt after (\(own["normal"] ?? [:]))")
    check((own["title"]?["family"] as? String ?? "").hasPrefix("Verdana") && near(own["title"]?["size"], 24) && own["title"]?["color"] as? String == "rgb(112, 48, 160)",
          "its own Title wins: Verdana 24 pt in its purple (\(own["title"] ?? [:]))")
    check((own["h1"]?["family"] as? String ?? "").hasPrefix("Verdana") && near(own["h1"]?["size"], 18) && near(own["h1"]?["before"], 24) && own["h1"]?["color"] as? String == "rgb(192, 0, 0)",
          "its own Heading 1 wins: Verdana 18 pt, 24 before, its red (\(own["h1"] ?? [:]))")
    check(near(own["h3"]?["size"], 14) && own["h3"]?["color"] as? String == dark && near(own["subtitle"]?["size"], 15),
          "a style it leaves out (Heading 3, Subtitle) is Google's (\(own["h3"] ?? [:]))")

    // Word's own: Calibri 11, 1.08, Calibri Light headings in Word's blue. Calibri isn't on a Mac without Office, and must not fall to serif.
    guard settle(fx.appending(path: "look/Word defaults.docx")) else { check(false, "Word defaults.docx is drawn (\(viewer.state))"); return }
    let word = look("Word defaults")
    check((word["normal"]?["family"] as? String ?? "").hasPrefix("Calibri") && near(word["normal"]?["size"], 11) && near(word["normal"]?["line"], 1.08, 0.01) && near(word["normal"]?["after"], 8),
          "Word's own body wins: Calibri 11 pt, 1.08 lines, 8 pt after (\(word["normal"] ?? [:]))")
    check(near(word["title"]?["size"], 28) && near(word["h1"]?["size"], 16) && word["h1"]?["color"] as? String == "rgb(47, 84, 150)" && near(word["h1"]?["before"], 12),
          "Word's own Title and Heading 1 win (\(word["h1"] ?? [:]))")
    check(near(word["h3"]?["size"], 14) && word["h3"]?["color"] as? String == dark, "a Heading 3 Word's file leaves out is Google's")
    let widths = js("""
        const w = (f) => { const c = document.createElement('canvas').getContext('2d'); c.font = '40px ' + f; return c.measureText('Handwriting quickly mmmm').width; };
        for (const f of ['Calibri', 'Calibri Light', 'Aptos', 'Cambria', 'Segoe UI']) await document.fonts.load('40px "' + f + '"');
        return { serif: w('serif'), times: w('"Times New Roman"'), arial: w('Arial'), georgia: w('Georgia'), calibri: w('"Calibri", serif'), light: w('"Calibri Light", serif'),
                 aptos: w('"Aptos", serif'), cambria: w('"Cambria", serif'), segoe: w('"Segoe UI", serif') };
        """) as? [String: Double] ?? [:]
    let installed = FileManager.default.fileExists(atPath: "/Applications/Microsoft Word.app")
    check(installed || (widths["calibri"] != widths["serif"] && widths["light"] != widths["serif"] && widths["aptos"] != widths["serif"] && widths["segoe"] != widths["serif"]),
          "a font the Mac lacks (Calibri, Calibri Light, Aptos, Segoe UI) is drawn in the stand-in, not the browser's serif (\(widths))")
    check(installed || (near(widths["calibri"], widths["arial"] ?? -1, 0.01) && near(widths["cambria"], widths["georgia"] ?? -1, 0.01)), "…Arial for Calibri, Georgia for Cambria")

    // ---- Part 2: tracked changes and comments, in each view
    struct Case { var file: String, people: [String], rows: Int, comments: Int, resolved: Set<String>, replies: Set<String> }
    // What the document holds, written from make_markup.py (and checked against the file by Docx.inventory).
    let word2 = Case(file: "markup/Word markup.docx", people: ["Dana Writer", "Morgan Editor", "Riley Reviewer"], rows: 2, comments: 9, resolved: ["3", "4"], replies: ["1", "2", "4"])
    let google = Case(file: "markup/Google suggestions.docx", people: ["Dana Writer", "Morgan Editor", "Riley Reviewer"], rows: 0, comments: 4, resolved: ["2", "3"], replies: ["1", "3"])
    func visible(_ mode: String) -> String { (js("window.__duo.markup({ mode: '\(mode)' }); await new Promise(r => setTimeout(r, 50)); return document.getElementById('host').innerText;") as? String) ?? "" }
    func count(_ s: String, _ of: String) -> Int { s.components(separatedBy: of).count - 1 }

    for c in [word2, google] {
        let file = fx.appending(path: c.file), name = (c.file as NSString).lastPathComponent
        guard settle(file) else { check(false, "\(name) is drawn (\(viewer.state))"); continue }
        let inv = Docx.inventory(file)
        // Docx.inventory counts runs' revisions; the viewer also counts an inserted or deleted table row.
        check(viewer.changeCount == inv.changes + c.rows, "\(name): the viewer finds all \(inv.changes + c.rows) tracked changes the file holds (\(viewer.changeCount))")
        check(viewer.comments.count == c.comments && inv.comments == c.comments, "\(name): all \(c.comments) comments (\(viewer.comments.count))")
        check(viewer.people.map(\.name) == c.people, "\(name): three people, in order (\(viewer.people.map(\.name)))")
        check(Set(viewer.comments.filter(\.resolved).map(\.id)) == c.resolved, "\(name): resolved threads are \(c.resolved.sorted()) (\(viewer.comments.filter(\.resolved).map(\.id)))")
        check(Set(viewer.comments.filter(\.reply).map(\.id)) == c.replies, "\(name): replies are threaded under their comment: \(c.replies.sorted()) (\(viewer.comments.filter(\.reply).map(\.id)))")
        check(viewer.comments.allSatisfy { !$0.paragraph.isEmpty }, "\(name): every comment knows its paragraph")
        let cards = js("return [...document.querySelectorAll('#host .duo-card')].map(c => ({ thread: c.dataset.thread, text: c.innerText.replace(/\\s+/g, ' '), resolved: !!c.closest('.duo-resolved'), previous: c.closest('.duo-resolved,.duo-card')?.previousElementSibling?.textContent ?? '' }))") as? [[String: Any]] ?? []
        let threads = c.comments - c.replies.count
        check(cards.count == threads, "\(name): one card per thread (\(cards.count) of \(threads))")
        check(cards.filter { $0["resolved"] as? Bool == true }.count == c.resolved.filter { !c.replies.contains($0) }.count, "\(name): a resolved thread is folded")
        // Every reply's text is inside its parent's card, after it.
        for r in viewer.comments where r.reply {
            let parent = cards.first { ($0["text"] as? String ?? "").contains(r.text) }
            check(parent != nil && (parent?["text"] as? String ?? "").range(of: r.author) != nil, "\(name): reply “\(r.text)” is in its thread's card")
        }
        // Each card sits under the paragraph its comment ends in.
        for card in cards {
            let id = card["thread"] as? String ?? ""
            guard let cm = viewer.comments.first(where: { $0.id == id }) else { continue }
            let under = js("const c = document.querySelector('#host [data-thread=\"\(id)\"]'); const e = c.closest('.duo-resolved') || c; let p = e.previousElementSibling; while (p && !p.matches('p[data-office-target]')) p = p.previousElementSibling; return p?.dataset.officeTarget ?? ''") as? String ?? ""
            let paraWithEnd = js("const e = document.querySelector('#host .docx-comment-anchor[data-docx-change-id=\"\(id)\"]'); return e?.closest('p')?.dataset.officeTarget ?? ''") as? String ?? ""
            check(!paraWithEnd.isEmpty && under == paraWithEnd, "\(name): the card for “\(cm.text.prefix(24))…” is under the paragraph its range ends in")
        }

        // The four views.
        let all = visible("all"), simple = visible("simple"), none = visible("none"), original = visible("original")
        if c.file.hasPrefix("markup/Word") {
            let inserted = ["these words", "(a third author)", "This whole paragraph was inserted by Dana.", "A list item Riley added.", "North", "Kale", "four"]
            let deleted = ["some old words", "This whole paragraph was deleted by Morgan.", "South", "Leeks", "three"]
            check(inserted.allSatisfy { all.contains($0) } && deleted.allSatisfy { all.contains($0) }, "\(name): All Markup shows every insertion and every deletion")
            check(inserted.allSatisfy { simple.contains($0) && none.contains($0) } && deleted.allSatisfy { !simple.contains($0) && !none.contains($0) },
                  "\(name): Simple and No Markup show the insertions and none of the deletions")
            check(inserted.allSatisfy { !original.contains($0) } && deleted.allSatisfy { original.contains($0) }, "\(name): Original shows every deletion and no insertion (rows and paragraphs too)")
            let moved = "This paragraph was moved down by Morgan."
            check(count(all, moved) == 2 && count(simple, moved) == 1 && count(none, moved) == 1 && count(original, moved) == 1, "\(name): a moved paragraph shows twice in All, once in the others (\(count(all, moved)), \(count(simple, moved)), \(count(none, moved)), \(count(original, moved)))")
            check(original.range(of: "First in order.\n\nThis paragraph was moved down") != nil && none.range(of: "Second in order.\n\nThis paragraph was moved down") != nil, "\(name): …at its old place in Original, its new place in No Markup")
            let q = "The volunteers planted forty rows"
            check(all.contains(q) && simple.contains("Is “forty” right?") && !none.contains("Is “forty” right?") && !original.contains("Is “forty” right?") && all.contains("Is “forty” right?"), "\(name): comments show in All and Simple, not in No Markup or Original")
            check(simple.contains("Why was this cut?"), "\(name): a comment on deleted text keeps its card")
            check(visible("all").contains("Resolved · Morgan Editor: This heading reads oddly."), "\(name): a resolved thread is one folded line")
        } else {
            check(all.contains("canshould") && all.contains("late April") && all.contains("A whole sentence Dana wants removed."), "\(name): All Markup shows Google's insertions and deletions")
            check(simple.contains("should go in earlier") && !simple.contains("can") && simple.contains("late April") && !simple.contains("Dana wants removed"), "\(name): Simple shows the suggestions accepted")
            check(!original.contains("should") && original.contains("can go in earlier") && !original.contains("late") && original.contains("Dana wants removed") && original.contains("in April."), "\(name): Original shows the text before the suggestions")
            check(none.contains("should go in earlier") && !none.contains("Should this say") , "\(name): No Markup is the accepted text with no comments")
        }

        // What each view looks like: colours per person, strikes, bars, formatting.
        _ = js("window.__duo.markup({ mode: 'all' })")
        let marks = js("""
            const colour = (v) => { const e = document.createElement('span'); e.style.color = 'var(' + v + ')'; document.body.append(e); const c = getComputedStyle(e).color; e.remove(); return c; };
            const names = [\(viewer.people.map { "'\($0.name)'" }.joined(separator: ","))];
            const out = {};
            for (const [i, n] of names.entries()) {
              const want = colour('--duo-review-author-' + (i + 1));
              const ins = document.querySelector('#host ins[data-docx-change-author="' + n + '"]'), del = document.querySelector('#host del[data-docx-change-author="' + n + '"]');
              out[n] = { want, ins: ins && getComputedStyle(ins).color, insLine: ins && getComputedStyle(ins).textDecorationLine, del: del && getComputedStyle(del).color, delLine: del && getComputedStyle(del).textDecorationLine };
            }
            return out;
            """) as? [String: [String: Any]] ?? [:]
        for (n, m) in marks {
            check((m["ins"] as? String).map { $0 == m["want"] as? String } ?? true && (m["del"] as? String).map { $0 == m["want"] as? String } ?? true,
                  "\(name): \(n)'s insertions and deletions are in their colour (\(m))")
            check((m["insLine"] as? String).map { $0.contains("underline") } ?? true && (m["delLine"] as? String).map { $0.contains("line-through") } ?? true, "\(name): \(n)'s insertions are underlined and deletions struck")
        }
        _ = js("window.__duo.markup({ mode: 'simple' })")
        let plain = js("""
            const ins = [...document.querySelectorAll('#host ins')].map(e => getComputedStyle(e)), bars = [...document.querySelectorAll('#host p.duo-changed')].filter(p => getComputedStyle(p).display !== 'none').map(p => getComputedStyle(p, '::before').width);
            return { plainIns: ins.every(c => c.textDecorationLine === 'none'), bars: bars.length, barWidth: bars[0] ?? '' };
            """) as? [String: Any] ?? [:]
        check(c.file.hasPrefix("markup/Google") || js("return [...document.querySelectorAll('#host p[data-docx-format-change]')].every(p => p.classList.contains('duo-changed'))") as? Bool == true, "\(name): a paragraph whose formatting changed has its bar in Simple Markup too")
        check(plain["plainIns"] as? Bool == true && (plain["bars"] as? Int ?? 0) > 0 && plain["barWidth"] as? String == "2px", "\(name): Simple Markup has no colours or underlines, and a 2 pt bar by each changed paragraph (\(plain))")
        _ = js("window.__duo.markup({ mode: 'original' })")
        let orig = js("""
            const d = [...document.querySelectorAll('#host del')].map(e => ({ w: e.getBoundingClientRect().width, line: getComputedStyle(e).textDecorationLine, colour: getComputedStyle(e).color, parent: getComputedStyle(e.parentElement).color }));
            return { allVisible: d.length > 0 && d.every(x => x.w > 0), plain: d.every(x => x.line === 'none' && x.colour === x.parent) };
            """) as? [String: Any] ?? [:]
        check(orig["allVisible"] as? Bool == true && orig["plain"] as? Bool == true, "\(name): in Original the deleted text is back as plain text (\(orig))")
        _ = js("window.__duo.markup({ mode: 'all' })")
    }

    // A formatting change: the new formatting in All, the old in Original.
    if settle(fx.appending(path: "markup/Word markup.docx")) {
        let weights = ["all", "original"].map { mode in
            js("window.__duo.markup({ mode: '\(mode)' }); const e = [...document.querySelectorAll('#host [data-docx-format-change] ')].find(x => x.textContent === 'this phrase bold'); return getComputedStyle(e).fontWeight") as? String ?? ""
        }
        check(weights == ["700", "400"], "a bold added by a formatting change is bold in All and plain in Original (\(weights))")
        let dots = js("window.__duo.markup({ mode: 'all' }); const e = document.querySelector('#host span[data-docx-format-change]'); return getComputedStyle(e).borderBottomStyle") as? String
        check(dots == "dotted", "…marked with a dotted underline in All")
        let dateLine = js("return document.querySelector('#host .duo-date').textContent") as? String ?? ""
        check(dateLine.hasPrefix("· ") && dateLine.contains(" Sep") && !dateLine.contains("Sept"), "a comment's date reads “1 Sep”, as the boards write it (\(dateLine))")
        check(viewer.blocked.isEmpty, "the page's policy blocked nothing (\(viewer.blocked))")
    }
    wait(0.1)
}
