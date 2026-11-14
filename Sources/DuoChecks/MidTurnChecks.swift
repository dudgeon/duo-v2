import DuoControl
import DuoKit
import DuoSearch
import Foundation

// C-173, F-638: a message typed while a turn runs is an `attachment` of type `queued_command` with
// `origin.kind: human`, not a `user` entry. Every reader that asks what the user said counts it; a
// queued command from a task notification or a peer is not a prompt. Text here is invented.
@MainActor func midTurnChecks() throws {
    print("messages typed mid-turn (C-173, F-638)")
    let ts = { (m: Int) in "2026-11-09T10:\(String(format: "%02d", m)):00.000Z" }
    func user(_ text: String, _ m: Int) -> String {
        #"{"type":"user","uuid":"u\#(m)","sessionId":"s1","cwd":"/tmp/x","timestamp":"\#(ts(m))","message":{"role":"user","content":"\#(text)"},"origin":{"kind":"human"}}"#
    }
    func asst(_ text: String, _ m: Int) -> String {
        #"{"type":"assistant","uuid":"a\#(m)","sessionId":"s1","timestamp":"\#(ts(m))","message":{"role":"assistant","content":[{"type":"text","text":"\#(text)"}]}}"#
    }
    func queued(_ text: String, _ m: Int, origin: String) -> String {
        #"{"type":"attachment","uuid":"q\#(m)","sessionId":"s1","timestamp":"\#(ts(m))","attachment":{"type":"queued_command","prompt":"\#(text)","commandMode":"prompt","origin":\#(origin),"timestamp":"\#(ts(m))"}}"#
    }
    let human = #"{"kind":"human"}"#
    let notification = #"{"kind":"task-notification","producer":"session-task"}"#
    let peer = #"{"kind":"peer","name":"worker"}"#
    let lines = [user("Plan the garden beds", 1), asst("Here is a plan.", 2),
                 queued("Actually skip the tomatoes", 3, origin: human), asst("Skipped them.", 4),
                 queued("<task-notification>build done</task-notification>", 5, origin: notification),
                 queued("peer says hello", 6, origin: peer),
                 user("Thanks", 7), asst("You're welcome.", 8)]
    let dir = FileManager.default.temporaryDirectory.appending(path: "midturn-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appending(path: "s1.jsonl")
    try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)

    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    func pd(_ s: String) -> Date? { iso.date(from: s) }
    func rec(_ s: String) -> [String: Any] { (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] ?? [:] }
    check(MidTurnPrompt.text(rec(queued("fix the title", 3, origin: human))) == "fix the title", "a human queued_command is a prompt")
    check(MidTurnPrompt.text(rec(queued("x", 3, origin: notification))) == nil
          && MidTurnPrompt.text(rec(queued("x", 3, origin: peer))) == nil, "a task notification or a peer's queued_command is not")
    check(MidTurnPrompt.text(rec(user("hi", 1))) == nil && MidTurnPrompt.text(rec(queued("  ", 3, origin: human))) == nil,
          "a user entry is the ordinary path, and a blank queued prompt is nothing")

    // Search indexes it (SessionSource)
    let read = SessionSource.read(file.path)
    check(read.turns.count == 3, "search sees three turns: the first, the mid-turn message, the last (got \(read.turns.count))")
    check(read.turns.contains { $0.text.contains("Actually skip the tomatoes") && $0.text.contains("Skipped them.") },
          "the mid-turn message is a turn of its own with the reply that followed it")
    check(!read.turns.contains { $0.text.contains("build done") || $0.text.contains("peer says hello") }, "notifications and peer messages are not indexed as prompts")

    // The director's facts reader: when the user last typed
    let t1 = pd(ts(1))!, t3 = pd(ts(3))!
    let only = dir.appending(path: "s2.jsonl")
    try Data(([user("start", 1), asst("ok", 2), queued("change of plan", 3, origin: human)].joined(separator: "\n") + "\n").utf8).write(to: only)
    check(DirectorFactsReader.transcriptTail(only)?.turnStartedAt == t3, "the facts reader's turn start is the mid-turn message")
    let note = dir.appending(path: "s3.jsonl")
    try Data(([user("start", 1), asst("ok", 2), queued("done", 3, origin: notification)].joined(separator: "\n") + "\n").utf8).write(to: note)
    check(DirectorFactsReader.transcriptTail(note)?.turnStartedAt == t1, "…and a task notification is not")
    check(DirectorTranscript.userTurnSinceDirector(only, tag: "[director]") == t3, "userTurnSinceDirector sees a mid-turn message")
    check(DirectorTranscript.userTurnSinceDirector(note, tag: "[director]") == t1, "…and not a notification")

    // The chat feed
    let log = ChatLog()
    for l in lines { ChatIngest.record(rec(l), into: log, lastDeclined: nil) }
    let said = log.items.compactMap { item -> String? in if case .you(let y) = item { return y.text } else { return nil } }
    check(said.contains("Actually skip the tomatoes"), "the chat feed shows the mid-turn message as your message")
    check(!said.contains { $0.contains("peer says hello") }, "…and not a peer's")
}
