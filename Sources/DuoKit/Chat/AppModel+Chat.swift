import DuoControl
import Foundation

extension AppModel {
    /// `duo2 session chat [id] on|off|toggle`, `--default last|chat|terminal`, `answer [id] <option|cancel>`
    /// (Q-53, DL-120). With no id, the session on screen.
    func chatVerb(_ inv: Invocation, _ req: ControlRequest, _ done: @escaping @MainActor (Reply) -> Void) {
        let usage = "usage: \(ActionID.sessionChat.action.usage)"
        if let d = inv.flags["default"] {
            switch d {
            case "last": chats.setDefault(nil); return done(.ok("New sessions open in the mode used last (now \(chats.prefs.last.rawValue))."))
            case "chat", "terminal": chats.setDefault(ChatViewMode(rawValue: d)); return done(.ok("New sessions open in \(d == "chat" ? "chat" : "the terminal")."))
            default: return done(.fail(usage))
            }
        }
        var words = inv.positional
        let answering = words.first == "answer"
        if answering { words.removeFirst() }
        let verbs: Set<String> = ["on", "off", "toggle"]
        // The id comes first when given; the session on screen otherwise.
        var key = visibleSessionId
        if let first = words.first, !verbs.contains(first), !(answering && words.count == 1) {
            guard let s = findSession(first, in: nil) else { return done(.fail("no session '\(first)'")) }
            key = s.tabKey
            words.removeFirst()
        }
        guard let key else { return done(.fail("no Claude session is on screen; name one")) }
        let name = consoleTitle(key)
        if answering {
            guard let option = words.first else { return done(.fail(usage)) }
            guard let chat = chats.existing(key) ?? fixtureChats[key] else { return done(.fail("\(name) has no chat yet: open it in Duo first")) }
            return chatAnswer(chat, option: option, done)
        }
        guard let verb = words.first, verbs.contains(verb) else {
            let c = chats.existing(key) ?? fixtureChats[key]
            let mode = c?.mode ?? chats.prefs.mode(for: key)
            let showing = c?.showsChat == true ? "chat" : "the terminal"
            let why = c?.fallback.map { " (\($0.message))" } ?? ""
            return done(.ok("\(name): \(mode.rawValue) mode, showing \(showing)\(why).",
                            ["mode": mode.rawValue, "showing": c?.showsChat == true ? "chat" : "terminal", "screen": c?.screen.kind.rawValue ?? "-"]))
        }
        guard terminals.existing(key) != nil || fixtureChats[key] != nil else { return done(.fail("\(name) isn't running in Duo; open it first")) }
        let current = (chats.existing(key) ?? fixtureChats[key])?.mode ?? chats.prefs.mode(for: key)
        let mode: ChatViewMode = verb == "on" ? .chat : verb == "off" ? .terminal : (current == .chat ? .terminal : .chat)
        if let f = fixtureChats[key] { f.mode = mode; f.fallback = nil } else { setChatMode(mode, for: key) }
        done(.ok("\(name) shows as \(mode == .chat ? "chat" : "the terminal"). Nothing was sent to the session."))
    }

    /// `duo2 session chat answer`: a review card's option, pressed only after the same screen check
    /// the card makes (phase 3).
    func chatAnswer(_ chat: ChatSession, option: String, _ done: @escaping @MainActor (Reply) -> Void) {
        let s = chat.reread()
        guard chat.cardUp else {
            return done(.fail(s.kind == .unknown || !chat.dialogsVerified || !chat.requestAgrees
                ? "Claude Code's dialog isn't one chat mode can answer (\(s.kind.rawValue)); answer it in the terminal"
                : "no dialog is waiting (\(s.kind.rawValue))"))
        }
        let reply: @MainActor (ChatAnswerResult, String) -> Void = { r, what in
            done(r.ok ? .ok("Pressed \(what) in Claude Code, after checking the same dialog was still up.") : .fail("Nothing sent: \(r.why ?? "refused")."))
        }
        if option == "cancel" || option == "esc" {
            Task { reply(s.kind == .question || s.kind == .questionReview ? await chat.ask(.decline, sig: s.sig) : await chat.cancelDialog(sig: s.sig), "Esc") }
            return
        }
        guard let n = Int(option) else { return done(.fail("usage: \(ActionID.sessionChat.action.usage)")) }
        switch s.kind {
        case .permission, .plan:
            guard let o = s.options.first(where: { $0.n == n }) else { return done(.fail("there's no option \(n): \(s.options.map { "\($0.n ?? 0). \($0.label)" }.joined(separator: ", "))")) }
            if o.label.hasPrefix("Tell Claude what to change") { return done(.fail("option \(n) takes text: answer it in Duo or the terminal")) }
            Task { reply(await chat.answerOption(n, label: o.label, sig: s.sig), "\(n) (\(o.label))") }
        case .questionReview:
            guard let o = s.options.first(where: { $0.n == n }) else { return done(.fail("there's no option \(n)")) }
            Task { reply(await chat.ask(o.label == "Cancel" ? .cancelReview : .submit, sig: s.sig), o.label) }
        case .question:
            let qs = chat.askedQuestions, qi = chat.questionIndex(s) ?? 0
            let asked = qi < qs.count ? qs[qi]["options"] as? [ChatJSON] ?? [] : []
            guard let row = s.rows.first(where: { $0.n == n }) else { return done(.fail("there's no option \(n)")) }
            switch row.kind {
            case .option:
                let i = s.options.firstIndex(of: row) ?? 0
                let label = i < asked.count ? asked[i]["label"] as? String ?? row.label : row.label
                Task { reply(await chat.ask(s.multi ? .toggle(label) : .pick(label), sig: s.sig), label) }
            case .chat: Task { reply(await chat.ask(.chat, sig: s.sig), "Chat about this") }
            default: done(.fail("option \(n) takes text: answer it in Duo or the terminal"))
            }
        default: done(.fail("no dialog is waiting"))
        }
    }
}
