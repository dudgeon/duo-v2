import DuoControl
import DuoKit
import DuoSearch
import Foundation

// F-656: after /rewind, Claude Code keeps the removed turns in the transcript as a dead branch (the next
// prompt's parentUuid points at the record before the rewound turn). Chat, search and every reader of
// "what turns does this session have" follow the live branch, not file order.
//
// fixtures/rewind/rewound-session.jsonl is a real transcript: Claude Code 2.1.316 run with `claude -p` on the
// repo's mock API (scripts/director-harness/mock-api.mjs), four prompts (invented text: Alpha, Bravo,
// Charlie, then Delta after `--resume-session-at` Alpha's reply, which is the rewind's shape), trimmed to the
// record kinds chat reads and with the attachment bodies and request blobs dropped.
@MainActor func rewindChecks() throws {
    print("a rewound transcript: the live branch only (F-656)")
    let fixture = repoRoot().appending(path: "fixtures/rewind/rewound-session.jsonl")
    let data = try Data(contentsOf: fixture)
    let records = ChatIngest.lines(data)
    func prompts(_ log: ChatLog) -> [String] { log.items.compactMap { if case .you(let y) = $0 { y.text } else { nil } } }
    func replies(_ log: ChatLog) -> [String] {
        log.items.compactMap { item -> String? in
            guard case .claude(let t) = item else { return nil }
            return t.segments.compactMap { if case .text(let x) = $0 { x.markdown } else { nil } }.joined()
        }
    }

    // What file order shows (the bug): all four prompts.
    let raw = ChatLog()
    for r in records { ChatIngest.record(r, into: raw) }
    check(prompts(raw) == ["Alpha question", "Bravo question", "Charlie question", "Delta question"],
          "the fixture has the dead branch in file order: Alpha, Bravo, Charlie, then Delta")

    let dead = LiveBranch.deadPrompts(records)
    check(dead.count == 2 && dead.allSatisfy { i in
        (records[i]["message"] as? [String: Any])?["content"] as? String == "Bravo question" || (records[i]["message"] as? [String: Any])?["content"] as? String == "Charlie question"
    }, "the removed prompts are Bravo and Charlie (got \(dead.count))")

    // What chat opens with.
    var off: ChatLog?
    Task { off = await ChatFeedProbe.replayOffMain(data) }
    let until = Date().addingTimeInterval(5)
    while off == nil, Date() < until { spin(0.01) }
    check(off.map(prompts) == ["Alpha question", "Delta question"], "chat shows Alpha and Delta, not the rewound turns (got \(off.map(prompts) ?? []))")
    check(off.map(replies) == ["Reply to alpha.", "Reply to delta."], "…and only their replies (got \(off.map(replies) ?? []))")

    // The feed's turns keep their transcript uuids (the hover actions will name a turn by them).
    func uuid(ofPrompt text: String) -> String? {
        records.first { ($0["message"] as? [String: Any])?["content"] as? String == text && $0["type"] as? String == "user" }?["uuid"] as? String
    }
    func uuid(ofReplyTo text: String) -> String? {
        guard let at = records.firstIndex(where: { $0["uuid"] as? String == uuid(ofPrompt: text) }) else { return nil }
        // The reply's last assistant record: up to the next typed prompt in file order.
        var found: String?
        for r in records[(at + 1)...] {
            if r["type"] as? String == "user", LiveBranch.isPrompt(r) { break }
            if r["type"] as? String == "assistant" { found = r["uuid"] as? String }
        }
        return found
    }
    var you: [ChatYou] = [], turns: [ChatTurn] = []
    for item in off?.items ?? [] {
        if case .you(let y) = item { you.append(y) }
        if case .claude(let t) = item { turns.append(t) }
    }
    check(you.map(\.uuid) == [uuid(ofPrompt: "Alpha question"), uuid(ofPrompt: "Delta question")] && you.allSatisfy { $0.uuid != nil },
          "each of your messages carries its record's uuid")
    check(turns.map(\.uuid) == [uuid(ofReplyTo: "Alpha question"), uuid(ofReplyTo: "Delta question")] && turns.allSatisfy { $0.uuid != nil },
          "each reply carries its last assistant record's uuid")

    // Search follows the live branch too.
    let dir = FileManager.default.temporaryDirectory.appending(path: "rewind-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appending(path: "s.jsonl")
    try data.write(to: file)
    let read = SessionSource.read(file.path)
    check(read.turns.count == 2 && !read.turns.contains { $0.text.contains("Bravo") || $0.text.contains("Charlie") },
          "search indexes two turns, not the rewound ones (got \(read.turns.count))")

    // The chat after a rewind that happens while it is open: the removed turns leave.
    let cfg = dir.appending(path: "config")
    let cwdDir = dir.appending(path: "work")
    try FileManager.default.createDirectory(at: cwdDir, withIntermediateDirectories: true)
    let was = getenv("CLAUDE_CONFIG_DIR").map { String(cString: $0) }
    setenv("CLAUDE_CONFIG_DIR", cfg.path, 1)
    defer { if let was { setenv("CLAUDE_CONFIG_DIR", was, 1) } else { unsetenv("CLAUDE_CONFIG_DIR") } }
    let sid = "rewind-\(UUID().uuidString.prefix(8))"
    let folder = ClaudeStorage.projects.appending(path: ClaudeStorage.encode(cwdDir.realPath))
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    let cut = lines.firstIndex { $0.contains("Delta question") } ?? lines.count
    let live = folder.appending(path: sid + ".jsonl")
    try Data((lines[..<cut].joined(separator: "\n") + "\n").utf8).write(to: live)
    let store = ChatStore(persist: false)
    let chat = store.session("rewind-tab")
    chat.follow(sessionId: sid, cwd: cwdDir.path)
    let t1 = Date().addingTimeInterval(5)
    while prompts(chat.log).count < 3, Date() < t1 { spin(0.02) }
    check(prompts(chat.log) == ["Alpha question", "Bravo question", "Charlie question"], "before the rewind chat shows all three (got \(prompts(chat.log)))")
    let h = try FileHandle(forWritingTo: live)
    try h.seekToEnd()
    try h.write(contentsOf: Data((lines[cut...].joined(separator: "\n") + "\n").utf8))
    try h.close()
    let t2 = Date().addingTimeInterval(8)
    while prompts(chat.log) != ["Alpha question", "Delta question"], Date() < t2 { spin(0.02) }
    check(prompts(chat.log) == ["Alpha question", "Delta question"] && replies(chat.log) == ["Reply to alpha.", "Reply to delta."],
          "the next prompt after a rewind removes the rewound turns from an open chat (got \(prompts(chat.log)))")
    chat.feedStop()

    print("live branch: records that are not a rewind stay")
    func u(_ id: String, _ parent: String?, _ text: String) -> [String: Any] {
        ["type": "user", "uuid": id, "parentUuid": parent as Any, "message": ["role": "user", "content": text]]
    }
    func a(_ id: String, _ parent: String?, tool: String? = nil) -> [String: Any] {
        ["type": "assistant", "uuid": id, "parentUuid": parent as Any,
         "message": ["content": [tool.map { ["type": "tool_use", "id": $0, "name": "Bash", "input": ["command": "ls"]] } ?? ["type": "text", "text": "ok \(id)"]]]]
    }
    func r(_ id: String, _ parent: String, tool: String) -> [String: Any] {
        ["type": "user", "uuid": id, "parentUuid": parent, "toolUseResult": ["stdout": "x"],
         "message": ["content": [["type": "tool_result", "tool_use_id": tool, "content": "x"]]]]
    }
    // Two tool calls at once: their results hang off sibling records, only one of which the chain passes through.
    let parallel = [u("u1", nil, "one"), a("a1", "u1", tool: "t1"), a("a2", "a1", tool: "t2"), r("r1", "a1", tool: "t1"), r("r2", "a2", tool: "t2"),
                    a("a3", "r2"), u("u2", "a3", "two"), a("a4", "u2")]
    check(LiveBranch.deadPrompts(parallel).isEmpty && LiveBranch.filter(parallel).count == parallel.count,
          "parallel tool results off the chain are not a rewound branch")
    // A compaction: the boundary's logical parent is gone from the file; the turns before it stay.
    let boundary: [String: Any] = ["type": "system", "subtype": "compact_boundary", "uuid": "c1", "parentUuid": NSNull(), "logicalParentUuid": "gone"]
    let compacted = [u("u1", nil, "one"), a("a1", "u1"), u("u2", "a1", "two"), a("a2", "u2"), boundary, u("u3", "c1", "three"), a("a3", "u3")]
    check(LiveBranch.deadPrompts(compacted).isEmpty, "turns before a compaction are not a rewound branch")
    // Rewound to the very first prompt: a second root.
    let toStart = [u("u1", nil, "old first"), a("a1", "u1"), u("u2", "a1", "old second"), a("a2", "u2"), u("n1", nil, "new first"), a("b1", "n1")]
    check(LiveBranch.filter(toStart).compactMap { ($0["message"] as? [String: Any])?["content"] as? String }.contains("old first") == false
          && LiveBranch.filter(toStart).count == 2, "a rewind to before the first prompt leaves only the new branch")
    // A message typed mid-turn is not itself a rewind, and doesn't make the next prompt look like one.
    let mid: [String: Any] = ["type": "attachment", "uuid": "m1", "parentUuid": "a1",
                              "attachment": ["type": "queued_command", "prompt": "also this", "origin": ["kind": "human"]]]
    let withMid = [u("u1", nil, "one"), a("a1", "u1"), mid, a("a2", "a1"), u("u2", "a2", "two"), a("a3", "u2")]
    check(LiveBranch.deadPrompts(withMid).isEmpty, "a message typed mid-turn stays")
    var track = LiveBranch.Tracker(withMid)
    check(track.add(u("u9", "a3", "again")) == false, "a prompt after the last reply is not a rewind")
    track = LiveBranch.Tracker(withMid)
    var track2 = LiveBranch.Tracker(withMid)
    check(track.add(u("u9", "a1", "rewound")) && track2.add(u("u9", "u1", "rewound")),
          "a prompt whose parent is before the last prompt (even by a record or two) is a rewind")
    track = LiveBranch.Tracker(withMid)
    check(track.add(mid) == false, "…and a message typed mid-turn never is")
}
