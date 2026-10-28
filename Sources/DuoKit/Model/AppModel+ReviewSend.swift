import AppKit
import DuoControl
import Foundation

/// @claude in a comment (DL-236 9A, 10A; research §6; target markdown-review-handoff `margin-claude`): a comment that
/// names @claude goes to a session when its author posts it, never on its own from the file (C-112). Delivery is
/// Duo's state, not the file's: queued, sent, replying, replied, not delivered. The text goes in through
/// `guardedSubmit`, the idle-and-empty-prompt guard of `duo2 director send` (DL-199), so a person's draft is never
/// typed into; the turn is plain text, so it pastes on the work Mac's 2.1.219 too.
public struct ReviewDelivery: Equatable, Sendable {
    public enum State: String, Sendable { case queued, sent, replying, replied, notDelivered = "not-delivered" }
    public var state: State
    /// The session's tab key (its id when it has one) and name.
    public var session: String
    public var sessionName: String
    public var at: Date
    public var why: String?
    /// How many of Claude's comments the thread had when it went: a new one is the reply.
    public var claudeBefore: Int
    public var turn: String
}

extension AppModel {
    static func reviewKey(_ url: URL, _ thread: String) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path + "#" + thread }

    // MARK: Which session

    /// The first guess (DL-236 9A): the session this thread went to, the one chosen last for this document, the one that
    /// last edited it through Duo, the one on screen; else nil (New Session).
    func reviewTarget(_ url: URL, thread: String) -> Fixture.Session? {
        let doc = url.resolvingSymlinksInPath().standardizedFileURL.path
        func session(_ key: String?) -> Fixture.Session? { key.flatMap { k in fixture.sessions.first { $0.tabKey == k || $0.sessionId == k } } }
        return session(Review.firstGuess(thread: reviewDeliveries[Self.reviewKey(url, thread)]?.session, document: DuoState.load().reviewSessions[doc],
                                         lastEditor: reviewLastEditor[doc], onScreen: visibleSessionId))
    }

    /// What the pill says about a session: "at prompt", "working", "needs you", or "not running".
    func reviewSessionStatus(_ s: Fixture.Session) -> String {
        switch workerFacts(s).run {
        case .idle: "at prompt"
        case .working: "working"
        case .needsYou: "needs you"
        case .stopped: "not running"
        }
    }

    func bindReviewSession(_ url: URL, to s: Fixture.Session) {
        let doc = url.resolvingSymlinksInPath().standardizedFileURL.path, key = s.tabKey
        DuoState.update { $0.reviewSessions[doc] = key }
    }

    // MARK: The turn

    /// The turn for a thread (`Review.turn`), with its line in the text as it is now.
    func reviewTurn(url: URL, thread t: Review.Thread, text: String) -> String {
        let at = t.anchorRange?.location ?? t.range.location
        let line = (text as NSString).substring(to: at).components(separatedBy: "\n").count
        return Review.turn(path: displayPath(url), line: line, thread: t)
    }

    // MARK: Sending

    /// Sends a thread's comment to `target` (or the first guess). `done` says what happened, for the verb.
    func sendReviewComment(_ url: URL, thread id: String, to chosen: Fixture.Session? = nil, done: @escaping @MainActor (Reply) -> Void) {
        reviewText(url) { [self] text in
            guard let text, let t = Review.parse(text).thread(id) else { return done(.fail("no thread #\(id) in \(displayPath(url))")) }
            guard t.comments.contains(where: \.mentionsClaude) else { return done(.fail("#\(id) doesn't name @claude: nothing to send")) }
            guard let s = chosen ?? reviewTarget(url, thread: id) else {
                return done(.fail("no session to send it to: pick one with --to <session>, or start a session in the project"))
            }
            let key = Self.reviewKey(url, id)
            let turn = reviewTurn(url: url, thread: t, text: text)
            let before = t.comments.filter { $0.author == "claude" }.count
            bindReviewSession(url, to: s)
            attemptReviewSend(key: key, url: url, session: s, turn: turn, claudeBefore: before, done: done)
        }
    }

    private func setDelivery(_ key: String, _ d: ReviewDelivery) {
        reviewDeliveries[key] = d
        pushReviewState()
    }

    func attemptReviewSend(key: String, url: URL, session s: Fixture.Session, turn: String, claudeBefore: Int, done: (@MainActor (Reply) -> Void)? = nil) {
        func state(_ st: ReviewDelivery.State, _ why: String? = nil) -> ReviewDelivery {
            ReviewDelivery(state: st, session: s.tabKey, sessionName: s.name, at: Date(), why: why, claudeBefore: claudeBefore, turn: turn)
        }
        let facts = workerFacts(s)
        let rung = SendLadder.choose(director: ClientCaps(), worker: facts, duoRunning: true)
        switch rung {
        case .duoSubmit:
            guardedSubmit(key: s.tabKey, message: turn, directedBy: "review", director: "review", onTask: true) { [self] refusal, typed in
                if let refusal {
                    if typed {   // Typed but not sent: it stays in the prompt, as ⌘D leaves it.
                        setDelivery(key, state(.notDelivered, "Pasted into \(s.name), not sent (\(refusal))"))
                        done?(.ok("Pasted into \(s.name), not sent (\(refusal)); it is left in its prompt."))
                    } else {
                        setDelivery(key, state(.queued, refusal))
                        done?(.ok("Queued: \(s.name) isn't ready (\(refusal)). Duo sends it at its next idle, with an empty prompt."))
                    }
                } else {
                    setDelivery(key, state(.sent))
                    done?(.ok("Sent to \(s.name)."))
                }
            }
        case .duoResume:
            let folder = liveFolders[s.project] ?? url.deletingLastPathComponent()
            if let why = resumeWithPrompt(s, prompt: turn, folder: folder) {
                setDelivery(key, state(.notDelivered, "\(s.name) can't be resumed here (\(why))"))
                done?(.ok("Not delivered: \(s.name) can't be resumed here (\(why)). Pick another with --to."))
            } else {
                setDelivery(key, state(.sent))
                done?(.ok("\(s.name) was stopped: Duo reopened it with the comment as its next prompt."))
            }
        case .queued:
            setDelivery(key, state(.queued, "\(s.name) is busy"))
            done?(.ok("Queued: \(s.name) is busy. Duo sends it at its next idle, with an empty prompt."))
        default:
            // It runs outside Duo, or can't be reached: nothing here types into it.
            setDelivery(key, state(.notDelivered, "\(s.name) isn't reachable from Duo"))
            done?(.ok("Not delivered: \(s.name) isn't reachable from Duo. Pick another with --to, or send the document yourself."))
        }
    }

    /// Each refresh: queued comments go when their session is ready; sent ones become replying when it turns
    /// working, and replied when a comment of Claude's appears in the thread.
    public func deliverReviewComments() {
        guard !reviewDeliveries.isEmpty else { return }
        for (key, d) in reviewDeliveries {
            guard let s = fixture.sessions.first(where: { $0.tabKey == d.session }) else { continue }
            let parts = key.components(separatedBy: "#")
            guard parts.count == 2 else { continue }
            let url = URL(fileURLWithPath: parts[0]), thread = parts[1]
            switch d.state {
            case .queued where !reviewSending.contains(key):
                let run = workerFacts(s).run
                guard run == .idle || run == .stopped else { continue }
                reviewSending.insert(key)
                attemptReviewSend(key: key, url: url, session: s, turn: d.turn, claudeBefore: d.claudeBefore)
                reviewSending.remove(key)
            case .sent, .replying:
                reviewText(url) { [weak self] text in
                    guard let self, let text, let t = Review.parse(text).thread(thread) else { return }
                    let claude = t.comments.filter { $0.author == "claude" }.count
                    var next = d
                    if claude > d.claudeBefore { next.state = .replied }
                    else if d.state == .sent, self.workerFacts(s).run == .working { next.state = .replying }
                    if next != d { self.setDelivery(key, next) }
                }
            default: break
            }
        }
    }

    // MARK: What the page shows

    /// The deliveries of the document showing, and each @claude thread's pill, pushed into the page.
    func pushReviewState() {
        guard let e = editorIfLoaded, let url = e.url, showingMarkdownDocument else { return }
        let prefix = url.resolvingSymlinksInPath().standardizedFileURL.path + "#"
        var map: [String: Any] = [:]
        for (k, d) in reviewDeliveries where k.hasPrefix(prefix) {
            let s = fixture.sessions.first { $0.tabKey == d.session }
            map[String(k.dropFirst(prefix.count))] = ["state": d.state.rawValue, "name": d.sessionName, "status": s.map(reviewSessionStatus) ?? "not running",
                                                     "at": Self.clock(d.at), "why": d.why as Any, "session": d.session]
        }
        let first = reviewTarget(url, thread: "")
        let def: [String: Any] = first.map { ["name": $0.name, "status": reviewSessionStatus($0), "session": $0.tabKey] } ?? ["name": "New Session", "status": "", "session": ""]
        e.run("return duo.setDelivery(m, d)", ["m": map, "d": def]) { _ in }
    }

    static func clock(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d) }

    /// A margin action: Post of an @claude comment, Send, Retry on a comment from the file, or the pill.
    func reviewDeliveryAction(_ op: String, _ body: [String: Any]) {
        guard let e = editorIfLoaded, let url = e.url, let id = body["id"] as? String else { return }
        switch op {
        case "send", "retry":
            sendReviewComment(url, thread: id) { _ in }
        case "pill":
            let sessions = fixture.sessions.filter { $0.sessionId != nil && ($0.project == currentProject?.name) }
            let menu = NSMenu()
            for s in sessions {
                let item = NSMenuItem(title: "\(s.name) · \(reviewSessionStatus(s))", action: nil, keyEquivalent: "")
                item.representedObject = s.tabKey
                menu.addItem(item)
            }
            guard !sessions.isEmpty else { return }
            let delegate = ReviewPillMenu { [weak self] key in
                guard let self, let s = sessions.first(where: { $0.tabKey == key }) else { return }
                self.bindReviewSession(url, to: s)
                // A comment not sent yet, or not delivered, goes to the one picked; one sent stays where it is.
                if let d = self.reviewDeliveries[Self.reviewKey(url, id)], d.state == .notDelivered || d.state == .queued {
                    self.sendReviewComment(url, thread: id, to: s) { _ in }
                } else { self.pushReviewState() }
            }
            for item in menu.items { item.target = delegate; item.action = #selector(ReviewPillMenu.pick(_:)) }
            reviewPillMenu = delegate   // keeps it alive while the menu is up
            let x = body["x"] as? Double ?? 0, y = body["y"] as? Double ?? 0
            menu.popUp(positioning: nil, at: NSPoint(x: x, y: y), in: e.webView)
        default: break
        }
    }
}

final class ReviewPillMenu: NSObject {
    let chose: (String) -> Void
    init(_ chose: @escaping (String) -> Void) { self.chose = chose }
    @objc func pick(_ item: NSMenuItem) { if let k = item.representedObject as? String { chose(k) } }
}
