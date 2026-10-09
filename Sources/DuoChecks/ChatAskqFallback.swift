import DuoKit
import Foundation

// The askq-fallback test session's screens (F-243, F-244, docs/plan/spikes/askq-fallback.md): real Claude Code
// screens that chat mode used to send to the terminal. Run by `chatChecks()`; on their own with
// `DUO_CHECKS=askq-fallback swift run DuoChecks`.

@MainActor func askqFallbackChecks() throws {
    print("chat mode: dialogs that used to fall back to the terminal (askq-fallback, F-243, F-244)")
    // An option's description with a line that starts "N. " (a numbered list in the description, or a
    // wrapped one) is read as an extra option row: the numbering is no longer 1…n, so a version that isn't
    // one of the verified ones (every 2.1.x but 291 to 293) sends the dialog to the terminal.
    for (file, version, labels) in [
        ("desc-numbered-2.1.295.txt", "2.1.295", ["Phased", "All at once"]),
        ("desc-numbered-2.1.219.txt", "2.1.219", ["`tomli` (Recommended)", "serde — 日本語 ✅", "Roll our own"]),
    ] {
        let text = spikeScreen("askq-fallback/\(file)")
        let s = ChatScreenReader.read(text, cols: 87)
        check(s.kind == .question, "\(file): read as a question (\(s.kind))")
        check(s.options.map(\.label) == labels, "\(file): its options are the ones Claude asked, not the description's numbered lines (\(s.options.map(\.label)))")
        check(ChatScreenReader.wellFormed(s), "\(file): read whole")
        let chat = ChatSession(key: "askq-\(file)", mode: .chat)
        chat.setVersion(version)
        chat.attach(FakeTUI(text))
        check(chat.dialogsVerified && chat.fallback?.message.contains("doesn’t read like") != true,
              "\(file): answered from chat on \(version), not sent to the terminal (\(chat.fallback?.message ?? "no fallback"))")
    }
    // 2.1.295's permission dialog for a read outside the working directories: its question is
    // "Allow this read outside the working directories?", not "Do you want to …?", so it reads as unknown.
    let read = ChatScreenReader.read(spikeScreen("askq-fallback/read-outside-2.1.295.txt"), cols: 87)
    check(read.kind == .permission && read.options.map(\.n) == [1, 2, 3, 4], "read-outside-2.1.295.txt: read as a permission with its four options (\(read.kind))")

    // A description's numbered lines are notes, wherever they sit: the screens' indent column and the 1…n count tell them apart.
    let desc = ChatScreenReader.read(spikeScreen("askq-fallback/desc-numbered-2.1.295.txt"), cols: 87)
    check(desc.options.first?.note.contains("3. Third-party") == true, "the description's numbered line stays as its option's note")
    func ask(_ rows: [String]) -> ChatScreen {
        ChatScreenReader.read(([" ☐ Q", "", "Pick one?", ""] + rows + ["───────────────────────────────────────────────────────────────────────────────────────",
                                "  Chat about this", "", "Enter to select · ↑/↓ to navigate · Esc to cancel"]).joined(separator: "\n"), cols: 87)
    }
    let c1 = ask(["❯ 1. A", "     Steps:", "     1. install", "     2. import", "  2. B", "     fine", "  3. Type something."])
    check(c1.options.map(\.label) == ["A", "B"] && ChatScreenReader.wellFormed(c1), "a description numbered 1. and 2. does not restart the count (\(c1.options.map(\.label)))")
    let c2 = ask(["  1. A", "     2. looks like a row but is deeper", "❯ 2. B", "  3. Type something."])
    check(c2.options.map(\.label) == ["A", "B"], "the cursor's column is the number's column, whichever row holds it")
    let c3 = ask((1...11).map { "  \($0). Option \($0)" } + ["  12. Type something."])
    check(c3.options.count == 11 && ChatScreenReader.wellFormed(ask(["❯ 1. A", "  2. B", "  3. Type something."])), "two-digit numbers are rows")
    // Permission titles in 2.1.295's binary: each reads as a permission dialog.
    for q in ["Allow this read outside the working directories?", "Allow external CLAUDE.md file imports?", "Trust this directory?",
              "Do you want to allow Claude to fetch this content?", "Do you want to allow this connection?"] {
        let p = ChatScreenReader.read([" Title", "─────────────────────────", " body", "", " \(q)", " ❯ 1. Yes", "   2. No", "", " Esc to cancel"].joined(separator: "\n"), cols: 87)
        check(p.kind == .permission && p.title == q && p.options.count == 2, "'\(q)' reads as a permission (\(p.kind))")
    }
}
