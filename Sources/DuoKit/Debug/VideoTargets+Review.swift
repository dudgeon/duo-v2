import AppKit
import Foundation
import WebKit

/// The 0.2.21 release film (`video/films/release-0-2-21`), Review in Markdown (DL-236, DL-237): shelf-scan's PRD under review in
/// the right pane, step by step (`--state video-rv-<what>`, with `--fixture video/fixture/fixture.json`). Each state stands on
/// scene 7's project (`video-s7-tab-md`: the same window, tabs and Auto-add decision chat the intro ends on), with the PRD as
/// it is at that moment of the demo (`video/fixture/review/prd-v2.<stage>.md`, made by `make-review.py`) in a copy of the
/// project folder, and the editor and margin driven by their own functions (`duo.reviewAddComment`, `reviewActivate`,
/// the agent edit path, a hover over a mark). The @claude comment goes to Auto-add decision, the session on screen.
extension VideoTargets {
    nonisolated static let rvScreens = [
        // Comments: the margin, a new comment, a finished thread deleted.
        "video-rv-open", "video-rv-sel-onetap", "video-rv-compose-onetap-empty", "video-rv-compose-onetap-blank", "video-rv-compose-onetap", "video-rv-commented",
        "video-rv-c1-active", "video-rv-deleted",
        // @claude: the comment, the pill, Post, the turn in the chat, Claude's edit and reply.
        "video-rv-sel-glare", "video-rv-compose-glare-empty", "video-rv-compose-glare-blank", "video-rv-compose-glare", "video-rv-sent", "video-rv-working", "video-rv-replied",
        // Suggest Edits: on, Sam's change, accept one, reject one.
        "video-rv-suggest-on", "video-rv-typed", "video-rv-hover-s1", "video-rv-accepted", "video-rv-hover-s2", "video-rv-rejected",
        // Markup.
        "video-rv-menu", "video-rv-simple"]

    /// What one state is: the PRD's stage, the chat's recording, the @claude comment's delivery, the session's state.
    nonisolated struct RV {
        var stage: String, chat = "chat-s5", delivery: ReviewDelivery.State? = nil, working = false

        static func of(_ screen: String) -> RV {
            switch String(screen.dropFirst("video-rv-".count)) {
            case "commented", "c1-active": return .init(stage: "commented")
            case "deleted", "sel-glare", "compose-glare-empty", "compose-glare-blank", "compose-glare": return .init(stage: "deleted")
            case "sent": return .init(stage: "asked", chat: "chat-rv-sent", delivery: .sent)
            case "working": return .init(stage: "asked", chat: "chat-rv-working", delivery: .replying, working: true)
            case "replied": return .init(stage: "replied-before-edit", chat: "chat-rv-replied", delivery: .replied)
            case "suggest-on": return .init(stage: "suggest-on", chat: "chat-rv-replied", delivery: .replied)
            case "typed", "hover-s1": return .init(stage: "typed", chat: "chat-rv-replied", delivery: .replied)
            case "accepted", "hover-s2": return .init(stage: "accepted", chat: "chat-rv-replied", delivery: .replied)
            case "rejected", "menu", "simple": return .init(stage: "rejected", chat: "chat-rv-replied", delivery: .replied)
            default: return .init(stage: "open")
            }
        }
    }

    /// The fixture's folder, for the `video:rv-*` actions that read `review/stages.json`.
    static var rvDir: URL?

    static func applyReview(_ screen: String, _ model: AppModel) {
        applyS4S5("video-s7-tab-md", to: model)
        guard let v = model.fixture.videoS2, let base = model.fixture.baseDir else { return }
        let dir = URL(fileURLWithPath: base)
        rvDir = dir
        let spec = RV.of(screen)
        let project = v.project ?? "shelf-scan"
        let fm = FileManager.default
        // A copy of the project's folder with the PRD at this stage (the editor saves; the fixture is never written).
        let root = fm.temporaryDirectory.appending(path: "duo-video-\(screen.dropFirst("video-".count))")
        try? fm.removeItem(at: root)
        let folder = root.appending(path: dir.appending(path: v.folder).lastPathComponent)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        try? fm.copyItem(at: dir.appending(path: v.folder).standardizedFileURL, to: folder)
        let prd = folder.appending(path: mdTab)
        try? fm.removeItem(at: prd)
        try? fm.copyItem(at: dir.appending(path: "review/prd-v2.\(spec.stage).md"), to: prd)
        model.liveFolders[project] = folder
        model.videoDemoFolder = folder
        model.rightTab = mdTab; model.selectedFile = mdTab
        // Comments and suggestions are signed by Sam, the demo's person, not the Mac's account (DL-236 11).
        EditorController.reviewerOverride = "sam"
        // Auto-add decision, at its prompt (or working on the comment); the chat carries on from where the intro left it.
        if let i = model.fixture.sessions.firstIndex(where: { $0.project == project && $0.name == autoAdd }) {
            model.fixture.sessions[i].state = spec.working ? .working : .idle
            model.fixture.sessions[i].wait = spec.working ? "now" : "1m"
            model.fixture.sessions[i].liveProcess = true   // running, so the pill says "at prompt" (or "working"), not "not running"
            let key = model.fixture.sessions[i].tabKey
            model.fixtureChats[key] = s6Chat(dir.appending(path: spec.chat), cwd: v.cwd, picked: false, key: key)
            if let d = spec.delivery {
                let at = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 9, minute: 52)) ?? Date()
                model.reviewDeliveries[AppModel.reviewKey(prd, "c4")] = ReviewDelivery(state: d, session: key, sessionName: autoAdd, at: at, why: nil, claudeBefore: 0, turn: "")
            }
        }
    }

    /// The `--then` actions a review state needs once the editor has the PRD.
    nonisolated static func rvActions(_ screen: String) -> [String] {
        let name = String(screen.dropFirst("video-rv-".count))
        let settle = ["wait:2", "video:rv-push", "video:caret-eol=Q2. Do we keep"]   // the caret off the title, so its # stays hidden
        let measure = ["wait:0.6", "video:rv-measure"]
        switch name {
        case "sel-onetap": return settle + ["video:rv-select=oneTap"] + measure
        case "compose-onetap-empty": return settle + ["video:rv-select=oneTap", "video:rv-compose", "wait:0.4"] + measure
        case "compose-onetap-blank": return settle + ["video:rv-select=oneTap", "video:rv-compose", "wait:0.4", "video:rv-blank"] + measure
        case "compose-onetap": return settle + ["video:rv-select=oneTap", "video:rv-compose", "wait:0.4", "video:rv-type=oneTap"] + measure
        case "commented": return settle + ["review-active:c3"] + measure
        case "c1-active": return settle + ["review-active:c1"] + measure
        case "sel-glare": return settle + ["video:rv-select=glare"] + measure
        case "compose-glare-empty": return settle + ["video:rv-select=glare", "video:rv-compose", "wait:0.4"] + measure
        case "compose-glare-blank": return settle + ["video:rv-select=glare", "video:rv-compose", "wait:0.4", "video:rv-blank"] + measure
        case "compose-glare": return settle + ["video:rv-select=glare", "video:rv-compose", "wait:0.4", "video:rv-type=claude"] + measure
        case "sent", "working": return settle + ["review-active:c4"] + measure
        case "replied": return settle + ["video:rv-claude-edit", "wait:0.8", "review-active:c4"] + measure
        case "hover-s1": return settle + ["wait:0.6", "video:rv-hover=s1", "wait:0.4", "video:rv-hover=s1", "wait:1.2"] + measure
        case "hover-s2": return settle + ["wait:0.6", "video:rv-hover=s2", "wait:0.4", "video:rv-hover=s2", "wait:1.2"] + measure
        case "menu": return settle + ["review-menu:markup", "wait:0.5"] + measure
        case "simple": return settle + ["verb:doc markup simple", "wait:0.8"] + measure
        default: return settle + measure
        }
    }

    /// One `video:rv-*` action (`act` sends them here).
    static func rvAct(_ verb: String, _ arg: String, on model: AppModel) {
        let e = model.editor
        let stages = rvDir.flatMap { try? Data(contentsOf: $0.appending(path: "review/stages.json")) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        func text(_ group: String) -> String { (stages[group] as? [String: Any])?[arg] as? String ?? arg }
        func js(_ code: String, _ args: [String: Any] = [:]) {
            e.webView.window?.makeKey()
            e.webView.window?.makeFirstResponder(e.webView)
            e.run(code, args) { v in FileHandle.standardError.write(Data("video:\(verb): \(String(describing: v ?? "nil"))\n".utf8)) }
        }
        switch verb {
        case "rv-push": model.pushReviewState()
        case "rv-select": js("duo.focus(); const t = duo.text(), i = t.indexOf(s); if (i < 0) return 'not found'; duo.select(i, i + s.length); return i", ["s": text("anchors")])
        case "rv-compose": js("return duo.reviewAddComment()")
        case "rv-type":   // the composer's field holding the comment, as typed (its input event shows To and the pill for @claude)
            js("const f = document.querySelector('.duo-mg-composer textarea'); if (!f) return 'no composer'; f.value = s; f.dispatchEvent(new Event('input', {bubbles: true})); f.focus(); return s.length", ["s": text("comments")])
        case "rv-blank":   // the field once typing has begun: its placeholder gone, nothing in it yet (the typing wipe draws the text)
            js("const f = document.querySelector('.duo-mg-composer textarea'); if (!f) return 'no composer'; f.placeholder = ''; f.focus(); return true")
        case "rv-hover":   // the pointer over a suggestion: its label (Accept, Reject, Reply) opens as it does on a hover
            js("""
               const el = document.querySelector('[data-rv="' + i + '"].duo-rv-ins') || document.querySelector('[data-rv="' + i + '"]'); if (!el) return 'no mark';
               const r = el.getClientRects()[0], o = {clientX: r.left + r.width / 2, clientY: r.top + r.height / 2, bubbles: true};
               el.dispatchEvent(new MouseEvent('mouseover', o)); el.dispatchEvent(new MouseEvent('mousemove', o)); return 'at ' + Math.round(r.left) + ',' + Math.round(r.top) + ' tips=' + document.querySelectorAll('.duo-rv-tip').length
               """, ["i": arg])
        case "rv-claude-edit":   // Claude's Edit of the glare line, through the agent path, so it carries Claude's highlight (DL-186)
            if let g = stages["glareEdit"] as? [String: Any] {
                js("duo.focus(); return JSON.stringify(duo.agentEdit(e, null))", ["e": [["old_string": g["old_string"] ?? "", "new_string": g["new_string"] ?? "", "replace_all": false]]])
            }
        case "rv-measure": rvMeasure(model, stages: stages)
        default: FileHandle.standardError.write(Data("video: unknown action \(verb)\n".utf8))
        }
    }

    /// `video.rv.*`: the marks, cards, buttons and label in the editor, in window points (`--then anchors:` adds them).
    static func rvMeasure(_ model: AppModel, stages: [String: Any]) {
        let wv = model.editor.webView
        let needles = (stages["anchors"] as? [String: String]) ?? [:]
        let code = editorMeasureJS.components(separatedBy: "return { bold:").first! + """
            const el = (q) => { const x = document.querySelector(q); return x ? box([...x.getClientRects()]) : null; };
            const all = (q) => box([...document.querySelectorAll(q)].flatMap((x) => [...x.getClientRects()]));
            const out = {};
            for (const [k, s] of Object.entries(needles)) out['text.' + k] = find(s);
            for (const id of ['s1', 's2', 's3']) out['mark.' + id] = all('[data-rv="' + id + '"]');
            for (const id of ['c1', 'c2', 'c3', 'c4']) { out['hl.' + id] = all('.duo-rv-hl[data-rv="' + id + '"]'); out['card.' + id] = el('.duo-mg-card[data-thread="' + id + '"]'); }
            out['composer'] = el('.duo-mg-composer'); out['composer.field'] = el('.duo-mg-composer textarea');
            out['composer.post'] = el('.duo-mg-composer button[data-op="post"]'); out['composer.pill'] = el('.duo-mg-composer .duo-mg-pill');
            out['card.pill'] = el('.duo-mg-open .duo-mg-pill'); out['card.status'] = el('.duo-mg-open .duo-mg-status');
            out['card.reply'] = el('.duo-mg-open .duo-mg-reply'); out['card.close'] = el('.duo-mg-open button[data-op="close"]');
            out['card.delete'] = el('.duo-mg-open button[data-op="delete"]'); out['card.verbs'] = el('.duo-mg-open .duo-mg-verbs');
            out['foot'] = el('.duo-mg-foot'); out['margin'] = el('.duo-mg');
            out['tip'] = el('.duo-rv-tip'); const tb = [...document.querySelectorAll('.duo-rv-tip button')];
            out['tip.accept'] = tb[0] ? box([...tb[0].getClientRects()]) : null; out['tip.reject'] = tb[1] ? box([...tb[1].getClientRects()]) : null;
            out['added'] = all('.duo-added');
            return out;
            """
        wv.callAsyncJavaScript(code, arguments: ["needles": needles], in: nil, in: .page) { r in
            MainActor.assumeIsolated {
                guard case .success(let v) = r, let d = v as? [String: Any], let w = wv.window else { return }
                for (k, a) in d {
                    guard let a = a as? [Double], a.count == 4 else { continue }
                    let z = wv.pageZoom
                    let base = wv.convert(NSRect(x: a[0] * z, y: a[1] * z, width: a[2] * z, height: a[3] * z), to: nil)
                    Anchors.web["video.rv.\(k)"] = CGRect(x: base.minX, y: w.frame.height - base.maxY, width: base.width, height: base.height)
                }
                FileHandle.standardError.write(Data("video:rv-measure: \(Anchors.web.keys.filter { $0.hasPrefix("video.rv.") }.sorted())\n".utf8))
            }
        }
    }
}
