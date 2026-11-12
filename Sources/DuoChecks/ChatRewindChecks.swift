@testable import DuoKit
import Foundation

// DL-338 (b): Duo working Claude Code's own /rewind menu (Q-507), against the real screens of 2.1.284 and 2.1.316
// (Fixtures/rewind/screens, F-667: the repo's mock API, three turns: hello, write A, write B).

private func rewindScreen(_ version: String, _ name: String) -> String {
    (try? String(contentsOf: repoRoot().appending(path: "Fixtures/rewind/screens/\(version)/\(name).txt"), encoding: .utf8)) ?? ""
}

/// The idle screen with `text` in the prompt (the last `❯` line is the input box).
private func rewindPrompt(_ version: String, _ text: String) -> String {
    var lines = rewindScreen(version, "00-after-turns").components(separatedBy: "\n")
    if let i = lines.lastIndex(where: { $0.hasPrefix("❯") }) { lines[i] = "❯\u{a0}" + text }
    return lines.joined(separator: "\n")
}

@MainActor func chatRewindChecks() {
    print("chat mode: rewind works Claude Code's /rewind menu, reading each screen (DL-338, Q-507)")
    for v in ["2.1.284", "2.1.316"] {
        let list = ChatRewindReader.read(rewindScreen(v, "01-rewind-list").components(separatedBy: "\n"))
        check(list == .list(selected: "(current)"), "\(v): the list reads, the cursor on (current) (\(String(describing: list)))")
        let up2 = ChatRewindReader.read(rewindScreen(v, "03-up2").components(separatedBy: "\n"))
        check(up2 == .list(selected: "write A"), "\(v): two Ups later the cursor is on “write A” (\(String(describing: up2)))")
        guard case .confirm(let prompt, let options, let code)? = ChatRewindReader.read(rewindScreen(v, "04-confirm").components(separatedBy: "\n")) else {
            check(false, "\(v): the confirmation reads"); continue
        }
        check(prompt == "write A" && code && options.map(\.n) == [1, 2, 3, 4, 5] && options[0].label == "Restore code and conversation" && options[0].cursor && options[1].label == "Restore conversation",
              "\(v): the confirmation: the prompt quoted, five options, code to put back (\(options.map(\.label)))")
        guard case .confirm(_, let down, _)? = ChatRewindReader.read(rewindScreen(v, "05-confirm-down").components(separatedBy: "\n")) else { check(false, "\(v): confirm after Down"); continue }
        check(down.first(where: \.cursor)?.label == "Restore conversation", "\(v): the cursor moves to “Restore conversation”")
        check(ChatRewindReader.read(rewindScreen(v, "00-after-turns").components(separatedBy: "\n")) == nil
              && ChatRewindReader.read(rewindScreen(v, "06-after-restore").components(separatedBy: "\n")) == nil, "\(v): an ordinary screen is not the menu")
    }
    check(ChatRewindReader.same("write A", "write  A") && ChatRewindReader.same("Compare the two refund fl…", "Compare the two refund flows in a table")
          && !ChatRewindReader.same("write B", "write A") && !ChatRewindReader.same("", ""), "a row matches its prompt, cut with … or not, never a different one")

    for v in ["2.1.284", "2.1.316"] {
        // A scripted TUI that is the real menu: each key moves to the screen the real run showed.
        func drive(code: Bool, tweak: ((String) -> String)? = nil) -> (ChatAnswerResult?, [String], ChatSession) {
            let tui = FakeTUI(rewindScreen(v, "00-after-turns"))
            var typed = ""
            var step = 0   // 0 idle, 1 list, 2 up1, 3 up2, 4 confirm, 5 confirm-down, 6 done
            let names = ["", "01-rewind-list", "02-up1", "03-up2", "04-confirm", "05-confirm-down"]
            func show(_ t: FakeTUI) { t.show(step == 0 ? rewindPrompt(v, typed) : step == 6 ? rewindPrompt(v, "write A") : tweak?(rewindScreen(v, names[step])) ?? rewindScreen(v, names[step])) }
            tui.react = { k, t in
                if k.hasPrefix("\u{1b}[200~") { typed = k.replacingOccurrences(of: "\u{1b}[200~", with: "").replacingOccurrences(of: "\u{1b}[201~", with: ""); show(t) }
                else if k == ChatKey.enter.bytes { if step == 0 { step = 1 } else if step == 3 { step = 4 } else if step == 4 || step == 5 { step = 6 }; show(t) }
                else if k == ChatKey.up.bytes, (1...2).contains(step) { step += 1; show(t) }
                else if k == ChatKey.down.bytes, step == 4 { step = 5; show(t) }
                else if k == ChatKey.up.bytes, step == 5 { step = 4; show(t) }
            }
            let chat = ChatSession(key: "rw-\(v)-\(code)", mode: .chat)
            chat.setVersion(v)
            chat.attach(tui)
            for (i, t) in ["hello", "write A", "write B"].enumerated() {
                chat.log.items.append(.you(ChatYou(id: "you-\(i)", uuid: "u\(i)", text: t)))
                chat.log.items.append(.claude(ChatTurn(id: "turn-\(i)", uuid: "a\(i)")))
            }
            var r: ChatAnswerResult?
            Task { r = await chat.rewind(toPrompt: "you-1", code: code) }
            spin(3.0)
            return (r, tui.keys, chat)
        }
        let (r, keys, chat) = drive(code: false)
        check(r?.ok == true, "\(v): rewind to “write A”, conversation only, succeeds (\(r?.why ?? "-"))")
        check(keys == ["\u{1b}[200~/rewind\u{1b}[201~", ChatKey.enter.bytes, ChatKey.up.bytes, ChatKey.up.bytes, ChatKey.enter.bytes, ChatKey.down.bytes, ChatKey.enter.bytes],
              "\(v): the keys: /rewind, Return, Up, Up, Return, Down, Return (\(keys.count) sends)")
        let prompts: [String] = chat.log.items.compactMap { if case .you(let y) = $0 { y.text } else { nil } }
        check(prompts == ["hello"], "\(v): the log drops “write A” and what came after (\(prompts))")
        check(chat.ui.composer == "write A", "\(v): the prompt waits in the composer (\(chat.ui.composer))")
        check(chat.log.items.contains { if case .note(let n) = $0 { n.text.hasPrefix("Rewound to before “write A”") } else { false } }, "\(v): a quiet line says where")

        let (rc, kc, _) = drive(code: true)
        check(rc?.ok == true && Array(kc.suffix(2)) == [ChatKey.enter.bytes, ChatKey.enter.bytes] && !kc.contains(ChatKey.down.bytes), "\(v): with the files, the first option (no Down) is taken (\(rc?.why ?? "-"))")

        // A screen it doesn't know stops the drive and leaves the terminal showing.
        let (rb, kb, cb) = drive(code: false) { $0.replacingOccurrences(of: "Restore conversation", with: "Restore thread") }
        check(rb?.ok == false && !kb.contains(ChatKey.enter.bytes + ChatKey.enter.bytes) && cb.fallback != nil,
              "\(v): an option it doesn’t know stops the drive and shows the terminal (\(rb?.why ?? "-"))")
        let (rw, _, cw) = drive(code: false) { $0.replacingOccurrences(of: "│ write A", with: "│ write B") }
        check(rw?.ok == false && cw.log.items.count == 6, "\(v): a confirmation quoting a different message stops it, and the log is untouched (\(rw?.why ?? "-"))")
    }

    // Busy: nothing is sent.
    let busyTUI = FakeTUI(rewindScreen("2.1.316", "00-after-turns").replacingOccurrences(of: "accept edits on (shift+tab to cycle)", with: "accept edits on · esc to interrupt"))
    let busy = ChatSession(key: "rw-busy", mode: .chat)
    busy.setVersion("2.1.316")
    busy.attach(busyTUI)
    busy.log.items.append(.you(ChatYou(id: "you-0", uuid: "u0", text: "hello")))
    var rb: ChatAnswerResult?
    Task { rb = await busy.rewind(toPrompt: "you-0", code: false) }
    spin(0.4)
    check(rb?.ok == false && busyTUI.keys.isEmpty, "while Claude works, rewind sends nothing (\(rb?.why ?? "-"))")

    // The sheet (board 3): files named when the turns changed some; Conversation only is the default every time.
    let sheet = ChatSession(key: "rw-sheet", mode: .chat)
    sheet.setVersion("2.1.316")
    sheet.log.items.append(.you(ChatYou(id: "y0", uuid: "u0", text: "Compare the two refund flows.")))
    var edits = ChatTurn(id: "t0", uuid: "a0")
    var edit = ChatToolStep(id: "s1", name: "Edit", verb: "Edit", object: "docs/refunds/flows.md", inputKey: "k1")
    edit.status = .done
    var bash = ChatToolStep(id: "s2", name: "Bash", verb: "Bash", object: "rm x", inputKey: "k2")
    bash.status = .done
    edits.segments = [.tools(id: "g", steps: [edit, bash, edit])]
    sheet.log.items.append(.claude(edits))
    sheet.log.items.append(.you(ChatYou(id: "y1", uuid: "u1", text: "Make it shorter.")))
    sheet.log.items.append(.claude(ChatTurn(id: "t1", uuid: "a1")))
    let facts = sheet.rewindFacts("y0")
    check(facts == ChatRewindFacts(turnsAfter: 2, files: ["docs/refunds/flows.md"]), "the sheet’s facts: the turns after and the files Edit/Write changed, Bash’s left out, none twice (\(String(describing: facts)))")
    let q = sheet.rewindQuestion("y0")
    check(q?.title == "Rewind to before this message?" && q?.quote == "Compare the two refund flows." && q?.radios?.selected == "conversation"
          && q?.radios?.options.map(\.title) == ["Conversation only", "Conversation and files"] && q?.items.map(\.path) == ["docs/refunds/flows.md"]
          && q?.choices.map(\.label) == ["Cancel", "Rewind"] && q?.choices.last?.isDefault == true, "it asks Conversation only first, names the file, and defaults to Rewind")
    check(sheet.rewindQuestion("y1")?.radios == nil && sheet.rewindQuestion("y1")?.paragraphs.first?.contains("No files change") == true, "a prompt after which no files changed: no choice, “No files change.”")
    check(sheet.rewindQuestion("t0") == nil && sheet.canRewind("y0"), "only a prompt can be rewound to")
    sheet.log.items.append(.you(ChatYou(id: "y2", uuid: nil, text: "not in the transcript yet")))
    check(!sheet.canRewind("y2") && sheet.rewindQuestion("y2") == nil, "a prompt the transcript doesn’t have yet can’t be")
}
