import DuoKit
import Foundation

// Known-failing checks from the askq-fallback test session (F-243, docs/plan/spikes/askq-fallback.md): real
// Claude Code screens that chat mode sends to the terminal today. Each line says what chat should do; a fix
// makes them pass, and then they move into `chatChecks()`. `DUO_CHECKS=askq-fallback swift run DuoChecks`.

@MainActor func askqFallbackChecks() throws {
    print("chat mode: real screens that fall back to the terminal today (askq-fallback, F-243)")
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
}
