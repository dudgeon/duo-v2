import AppKit
import DuoControl
import DuoSearch
import Foundation

// The comment margin of the Word and PowerPoint viewers (DL-337): what its cards do. Post, Reply, Close and Keep, Reopen and Delete
// write the file's comment parts through the same `OfficeComments` calls `duo2 comment …` makes (the original is kept first,
// `Office backups`), the viewer redraws, and a comment that names @claude goes to a session when it is posted, as in Markdown
// (DL-236 10A). The margin page itself is the PDF viewer's and Markdown's (`SideMargin`).
extension AppModel {
    /// The viewers' margins that are on screen: the Word document or the deck in the right pane.
    var visibleOfficeMargins: [OfficeMargin] {
        var out: [OfficeMargin] = []
        if let v = visibleDocx, v.url != nil { out.append(v.office) }
        if let d = visibleDeck, d.pageURL != nil { out.append(d.office) }
        return out
    }

    func wireOfficeMargin(_ o: OfficeMargin, reload: @escaping () -> Void, focus: @escaping () -> Void) {
        o.margin.onAction = { [weak self, weak o] op, body in
            guard let self, let o else { return }
            self.officeMarginAction(o, reload: reload, focus: focus, op, body)
        }
    }

    /// What the margin page reported.
    func officeMarginAction(_ o: OfficeMargin, reload: @escaping () -> Void, focus: @escaping () -> Void, _ op: String, _ body: [String: Any]) {
        let id = body["id"] as? String
        switch op {
        case "post": officePost(o, text: body["text"] as? String ?? "", reload: reload)
        case "cancel": o.cancelCompose()
        case "reply": if let id { officeReply(o, thread: id, text: body["text"] as? String ?? "", reload: reload) }
        case "close": if let id { officeResolve(o, thread: id, closed: true, reload: reload) }
        case "reopen": if let id { officeResolve(o, thread: id, closed: false, reload: reload) }
        case "delete": if let id { officeDelete(o, thread: id, reload: reload) }
        case "showClosed": o.showClosed = body["value"] as? Bool ?? false
        case "active": o.lightAnchor(id)
        case "hover": o.hoverAnchor(id)
        case "escaped": focus()
        case "send", "retry": if let id { officeSend(o, thread: id) }
        case "pill": officePillMenu(o, thread: id ?? "", x: body["x"] as? Double ?? 0, y: body["y"] as? Double ?? 0)
        case "crashed": pushOfficeReviewState(); o.push()
        default: break
        }
    }

    /// Writes through `OfficeComments`, redraws the viewer, and says why if it can't.
    @discardableResult
    private func officeWrite(_ o: OfficeMargin, reload: () -> Void, _ body: (URL) throws -> OfficeComments.Written) -> OfficeComments.Written? {
        guard let url = o.fileURL() else { return nil }
        do {
            let w = try body(url)
            o.refresh()   // the threads, at once; the viewer redraws and the anchors follow
            reload()
            return w
        } catch { info("\(error)"); return nil }
    }

    /// The composer's Post: the call `comment add` makes, on the selection (its `--at` candidates in turn), and a comment that names
    /// @claude goes to a session now (DL-236 10A).
    @discardableResult
    func officePost(_ o: OfficeMargin, text: String, reload: () -> Void) -> String? {
        guard let c = o.composing else { return nil }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        o.composed()
        var wrote: OfficeComments.Written?
        var lastError = ""
        for at in c.at {
            guard let url = o.fileURL() else { break }
            do { wrote = try OfficeComments.add(url, at: at, author: NSUserName(), text: text, backups: Self.officeBackups); break }
            catch { lastError = "\(error)" }
        }
        guard let w = wrote, let url = o.fileURL() else { if !lastError.isEmpty { info(lastError) }; return nil }
        o.refresh(); reload()
        o.pendingActive = w.id
        if Self.namesClaude(text) { officeSendThread(url, thread: w.id, o) }
        return w.id
    }

    func officeReply(_ o: OfficeMargin, thread: String, text: String, reload: () -> Void) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let url = o.fileURL(), officeWrite(o, reload: reload, { try OfficeComments.reply($0, to: thread, author: NSUserName(), text: text, backups: Self.officeBackups) }) != nil else { return }
        if Self.namesClaude(text) { officeSendThread(url, thread: thread, o) }
    }

    func officeResolve(_ o: OfficeMargin, thread: String, closed: Bool, reload: () -> Void) {
        officeWrite(o, reload: reload) { try OfficeComments.resolve($0, thread: thread, resolved: closed, backups: Self.officeBackups) }
    }

    /// Delete on the active card, as Markdown's: at once; `comment undo` (⌘Z) brings it back from the copy kept before.
    func officeDelete(_ o: OfficeMargin, thread: String, reload: () -> Void) {
        officeWrite(o, reload: reload) { try OfficeComments.delete($0, thread: thread, backups: Self.officeBackups) }
    }

    func officeSend(_ o: OfficeMargin, thread: String) {
        guard let url = o.fileURL() else { return }
        officeSendThread(url, thread: thread, o)
    }

    private func officeSendThread(_ url: URL, thread: String, _ o: OfficeMargin) {
        sendReviewComment(url, thread: thread) { [weak self, weak o] r in
            o?.refresh()
            self?.pushOfficeReviewState()
            if !r.ok { self?.info(r.text) }
        }
    }

    /// The pill's menu: the project's sessions, as Markdown's.
    private func officePillMenu(_ o: OfficeMargin, thread id: String, x: Double, y: Double) {
        guard let url = o.fileURL() else { return }
        let sessions = fixture.sessions.filter { $0.sessionId != nil && ($0.project == currentProject?.name) }
        guard !sessions.isEmpty else { return }
        let menu = NSMenu()
        for s in sessions {
            let item = NSMenuItem(title: "\(s.name) · \(reviewSessionStatus(s))", action: nil, keyEquivalent: "")
            item.representedObject = s.tabKey
            menu.addItem(item)
        }
        let delegate = ReviewPillMenu { [weak self, weak o] key in
            guard let self, let s = sessions.first(where: { $0.tabKey == key }) else { return }
            self.bindReviewSession(url, to: s)
            if let d = self.reviewDeliveries[Self.reviewKey(url, id)], d.state == .notDelivered || d.state == .queued {
                self.sendReviewComment(url, thread: id, to: s) { [weak o] _ in o?.refresh() }
            } else { self.pushOfficeReviewState() }
        }
        for item in menu.items { item.target = delegate; item.action = #selector(ReviewPillMenu.pick(_:)) }
        reviewPillMenu = delegate
        menu.popUp(positioning: nil, at: NSPoint(x: x, y: y), in: o.margin.webView)
    }

    /// The deliveries of the file showing, and the first-guess session of the pill, pushed into the margin page.
    func pushOfficeReviewState() {
        for o in visibleOfficeMargins {
            guard let url = o.fileURL() else { continue }
            let prefix = url.resolvingSymlinksInPath().standardizedFileURL.path + "#"
            var map: [String: Any] = [:]
            for (k, d) in reviewDeliveries where k.hasPrefix(prefix) {
                let s = session(tabKey: d.session)
                map[String(k.dropFirst(prefix.count))] = ["state": d.state.rawValue, "name": d.sessionName, "status": s.map(reviewSessionStatus) ?? "not running",
                                                         "at": Self.clock(d.at), "why": d.why as Any, "session": d.session]
            }
            let first = reviewTarget(url, thread: "")
            let def: [String: Any] = first.map { ["name": $0.name, "status": reviewSessionStatus($0), "session": $0.tabKey] } ?? ["name": "New Session", "status": "", "session": ""]
            o.margin.setDelivery(map, def)
        }
    }

    /// Add Comment (the Edit menu, ⌥⌘M): the composer opens in the margin level with the selection.
    public func composeOfficeComment() -> Bool {
        guard let o = visibleOfficeMargins.first else { return false }
        o.compose { [weak self] ok in if ok { self?.pushOfficeReviewState() } }
        return true
    }
}
