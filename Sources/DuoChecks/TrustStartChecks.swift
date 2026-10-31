import DuoControl
import DuoKit
import Foundation

// F-444: Claude Code's folder trust question at a session's start, in chat mode. It used to read as an unknown
// screen and show the terminal; now chat reads it, Duo asks with its trust sheet, and the answer goes to Claude
// Code's own screen. Nothing trusts a folder without the user's answer.

@MainActor func trustStartChecks() throws {
    print("chat mode: Claude Code's folder question at a session's start (F-444)")
    let dir284 = "trust-2.1.284/", dir311 = "trust-2.1.311/"
    let fresh = "/private/tmp/sample/fresh"

    // The reader, on 2.1.284 and 2.1.311.
    do {
        for (file, path, cols) in [(dir284 + "start-100x34.txt", fresh, 100), (dir311 + "start-100x34.txt", fresh, 100),
                                   (dir284 + "start-git-subfolder-100x34.txt", "/private/tmp/sample/repo/sub", 100),
                                   (dir284 + "start-long-path-60x34.txt", "/private/tmp/sample/a-rather-long-folder-name/with-another-level/and-a-third-one", 60)] {
            let s = ChatScreenReader.read(spikeScreen(file), cols: cols)
            check(s.kind == .trust && ChatScreenReader.wellFormed(s) && ChatScreenReader.samePath(s.title ?? "", path)
                  && s.rows.map(\.label) == ["No, exit", "Yes, I trust this folder"] && s.rows.first?.cursor == true,
                  "\(file): the trust question, its folder and both choices, No selected (\(s.kind), \(s.title ?? "nil"))")
        }
        let yes = ChatScreenReader.read(spikeScreen(dir311 + "start-cursor-on-yes-100x34.txt"))
        check(yes.kind == .trust && yes.rows.last?.cursor == true && yes.sig == ChatScreenReader.read(spikeScreen(dir311 + "start-100x34.txt")).sig,
              "↓ moves the cursor to Yes; the question's signature stays the same")
        check(!ChatScreenReader.samePath("/private/tmp/sample/fresh", "/private/tmp/sample/fresh-copy") && !ChatScreenReader.samePath("", ""),
              "a different folder, or none, is never the same path")
        let old = ChatScreenReader.read(spikeScreen("real-cli-login-2.1.291/01-trust-folder-unknown.txt"))
        check(old.kind == .trust && ChatScreenReader.wellFormed(old), "2.1.291's recorded trust prompt reads too")
    }

    // Chat: no fallback; the app is asked once per question; another folder's question, or an unreadable version, goes to the terminal.
    func chat(_ version: String = "2.1.284", screen: String = spikeScreen("trust-2.1.284/start-100x34.txt"), mode: ChatViewMode = .chat,
              answer: Bool = true) -> (ChatSession, FakeTUI, () -> [String]) {
        let tui = FakeTUI(spikeScreen("tour-2.1.284/01-markdown.txt"))
        let c = ChatSession(key: "trust-\(UUID().uuidString.prefix(6))", mode: mode)
        c.persistsFallbackLog = false
        var asked: [String] = []
        c.onTrustQuestion = { p in asked.append(p); return answer }
        c.setVersion(version)
        c.attach(tui)
        tui.show(screen)
        spin(0.2)
        return (c, tui, { asked })
    }
    do {
        let (c, tui, asked) = chat()
        spin(1.8)
        check(c.screen.kind == .trust && c.fallback == nil && c.showsChat && asked() == [fresh],
              "the question in chat: no fallback; Duo is asked about the session's folder (\(asked()), \(c.lastFallback?.rule ?? "none"))")
        tui.show(tui.text + "\n"); spin(0.2)
        check(asked().count == 1, "a repaint doesn't ask again")
        let (o, _, _) = chat(answer: false)
        check(o.lastFallback?.rule == "trust-other-folder" && !o.showsChat, "a question about another folder: the terminal")
        let (t, _, tAsked) = chat(mode: .terminal)
        check(tAsked().isEmpty && t.fallback == nil, "in terminal mode Claude Code's own question is on screen: nothing asked")
        let (u, _, uAsked) = chat("2.0.1")
        check(uAsked().isEmpty && u.lastFallback?.rule == "trust-unreadable", "on a CLI chat can't trust: the terminal, nothing asked")
    }

    // The answer: re-read, move the cursor, Return. Yes takes ↓ then Return; No, already selected, Return alone.
    do {
        func answering() -> (ChatSession, FakeTUI) {
            let (c, tui, _) = chat()
            tui.react = { k, t in
                if k == ChatKey.down.bytes { t.show(spikeScreen("trust-2.1.311/start-cursor-on-yes-100x34.txt")) }
                if k == ChatKey.up.bytes { t.show(spikeScreen("trust-2.1.284/start-100x34.txt")) }
                if k == ChatKey.enter.bytes { t.show(spikeScreen("tour-2.1.284/01-markdown.txt")) }
            }
            return (c, tui)
        }
        var r: ChatAnswerResult?
        let (c, tui) = answering()
        Task { r = await c.answerTrust(true, path: fresh) }
        spin(1.5)
        check(r?.ok == true && tui.keys == [ChatKey.down.bytes, ChatKey.enter.bytes] && c.fallback == nil, "Trust Folder: ↓ to “Yes, I trust this folder”, then Return (\(tui.keys))")
        r = nil
        let (n, ntui) = answering()
        Task { r = await n.answerTrust(false, path: fresh) }
        spin(1.5)
        check(r?.ok == true && ntui.keys == [ChatKey.enter.bytes], "Don’t Trust: Return on “No, exit” (\(ntui.keys))")
        r = nil
        let (w, wtui) = answering()
        Task { r = await w.answerTrust(true, path: "/private/tmp/sample/other") }
        spin(1.0)
        check(r?.ok == false && wtui.keys.isEmpty, "a sheet about another folder sends nothing (\(r?.why ?? "-"))")
    }

    // The sheet (DL-229's surface; words are Q-338's stand-in).
    do {
        let q = AppModel.trustStartQuestion(folder: fresh, home: "/Users/sample", config: URL(fileURLWithPath: "/Users/sample/.claude.json")) { _ in }
        check(q.title == "Trust “fresh” for Claude Code?" && q.items.map(\.path) == [fresh, "projects › …/fresh › hasTrustDialogAccepted: true"]
              && q.choices.map(\.label) == ["Don’t Trust", "Trust Folder"] && q.choices[0].isCancel && q.choices[1].isDefault,
              "the sheet names the folder and the one key Claude Code records; Don’t Trust cancels, Trust Folder is the default")
        let home = AppModel.trustStartQuestion(folder: "/Users/sample", home: "/Users/sample") { _ in }
        check(home.items.count == 1 && home.paragraphs.last?.contains("one session at a time") == true, "the home folder: no key, and it asks again next session")
        let root = FileManager.default.temporaryDirectory.appending(path: "duo-trust-\(UUID().uuidString.prefix(6))")
        let sub = root.appending(path: "checkout/api")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        _ = run("/usr/bin/git", ["-C", root.appending(path: "checkout").path, "init", "-q"])
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = AppModel.trustStartQuestion(folder: ClaudeTrust.realPath(sub.path), home: "/Users/sample") { _ in }
        check(repo.title == "Trust “api” for Claude Code?" && repo.items.last?.path == "projects › …/checkout › hasTrustDialogAccepted: true",
              "in a repository's subfolder, the key is the repository's top folder, as Claude Code records it (\(repo.items.last?.path ?? ""))")
    }

    // The app: only the session's own folder is asked about; the default answer goes to Claude's screen.
    do {
        let (c, tui, _) = chat()
        tui.react = { k, t in
            if k == ChatKey.down.bytes { t.show(spikeScreen("trust-2.1.311/start-cursor-on-yes-100x34.txt")) }
            if k == ChatKey.enter.bytes { t.show(spikeScreen("tour-2.1.284/01-markdown.txt")) }
        }
        let model = AppModel(fixture: try repoFixture())
        let before = SheetCenter.shared.queue.count
        check(!model.askTrustAtStart(c, folder: "/private/tmp/sample/other", path: fresh) && SheetCenter.shared.queue.count == before,
              "a question about a folder that isn't the session's: no sheet")
        var said: String?
        let asked = model.askTrustAtStart(c, folder: fresh, path: fresh) { said = $0 }
        check(asked && SheetCenter.shared.queue.count == before + 1, "the session's own folder: the sheet")
        // Answer it as the sheet's Return would: the queue's current question is this one when nothing else waits.
        if before == 0, let q = SheetCenter.shared.current, let yes = q.choices.first(where: \.isDefault) { SheetCenter.shared.answer(yes) }
        spin(1.5)
        check(said == "trusted " + fresh && tui.keys == [ChatKey.down.bytes, ChatKey.enter.bytes], "Trust Folder gives Claude Code its yes (\(said ?? "nothing"))")
    }
}
