@testable import DuoKit
import Foundation

// DL-338, slice (a): what Copy puts on the clipboard for a turn (Q-509).

@MainActor func chatTurnActionChecks() {
    print("chat mode: Copy on a turn puts its words on the clipboard as Markdown (DL-338, Q-509)")
    var you = ChatYou(id: "you-1", text: "Compare the two flows.\n\n- in a table")
    check(ChatTurnCopy.markdown(you: you) == "Compare the two flows.\n\n- in a table", "your message copies as typed")
    you.images = [ChatImage(mediaType: "image/png", data: Data([1])), ChatImage(mediaType: "image/png", data: Data([2]))]
    check(ChatTurnCopy.markdown(you: you) == "[Image #1]\n[Image #2]\nCompare the two flows.\n\n- in a table", "its pictures copy as [Image #n]")

    var turn = ChatTurn(id: "t-1")
    turn.segments = [
        .thinking(id: "a", seconds: 3, text: "private thoughts"),
        .text(ChatText(id: "b", markdown: "First part.\n\n```swift\nlet x = 1\n```\n", streaming: false)),
        .tools(id: "c", steps: []),
        .text(ChatText(id: "d", markdown: "  Second part.  ", streaming: false)),
        .asked(id: "e", questions: [ChatAsked(header: "H", question: "Q?")]),
        .text(ChatText(id: "f", markdown: "   ", streaming: false)),
    ]
    check(ChatTurnCopy.markdown(turn: turn) == "First part.\n\n```swift\nlet x = 1\n```\n\nSecond part.",
          "Claude's text segments join by a blank line; no thinking, tool calls or questions (\(ChatTurnCopy.markdown(turn: turn).debugDescription))")
    check(ChatTurnCopy.markdown(item: .claude(ChatTurn(id: "t-2"))) == "", "a turn with no text copies nothing")
    check(ChatTurnCopy.markdown(item: .note(ChatNote(id: "n", text: "x"))) == nil, "a note is not a turn")

    // `duo2 session turns` and the verbs' turn references; the Chat menu's target (board 4).
    let chat = ChatSession(key: "turns", mode: .chat)
    chat.log.items = [.you(ChatYou(id: "y0", uuid: "aaaaaaaa-1111", text: "one\n  two")), .claude(ChatTurn(id: "t0", uuid: "bbbbbbbb-2222", segments: [.text(ChatText(id: "x", markdown: "reply", streaming: false))])),
                      .note(ChatNote(id: "n0", text: "quiet")), .you(ChatYou(id: "y1", uuid: "cccccccc-3333", text: "next")), .you(ChatYou(id: "q", text: "queued", queued: true))]
    let list = chat.turnList
    check(list.map(\.n) == [1, 2, 3] && list.map(\.role) == ["you", "claude", "you"] && list[0].preview == "one two" && list[1].preview == "reply",
          "turns are numbered from 1 in order: your messages and Claude’s replies, no notes, no queued message (\(list.map(\.preview)))")
    check(chat.turnID(for: "2") == "t0" && chat.turnID(for: "cccccccc") == "y1" && chat.turnID(for: "cccccccc-3333") == "y1"
          && chat.turnID(for: "9") == nil && chat.turnID(for: "ccc") == nil, "a turn is named by its number or its uuid (8 characters or more)")
    check(chat.menuTurnID == "y1" && chat.menuReplyID == nil, "the Chat menu acts on the latest message when none is selected")
    check(chat.turnActions(for: "y0") == [.copy, .rewind, .fork] && chat.turnActions(for: "t0") == [.copy, .fork] && chat.turnActions(for: "t1") == [], "the row: Copy, Rewind, Fork under your message; Copy, Fork under Claude’s; none under a note")
    chat.log.items.append(.you(ChatYou(id: "y9", text: "no id yet")))
    check(chat.turnActions(for: "y9") == [.copy], "a message the transcript has no id for yet offers Copy only")
    chat.ui.selectedTurn = "y0"
    check(chat.menuTurnID == "y0" && chat.menuReplyID == "t0", "and on the selected one, whose reply follows it")
    check(chat.copyTurn("t0") && chat.ui.copiedTurn == "t0" && !chat.copyTurn("n0"), "Copy marks the turn copied for 1.5 s; a note has nothing to copy")
}

// F-738: the pointer goes from a turn to its row's buttons without the row going. Fails with no band (the row outside the
// turn's frame, as `onHover` had it): the hover ends in the 4 pt between the turn and its row.
@MainActor func chatTurnHoverChecks() {
    print("chat mode: the pointer can go from a turn onto its row's buttons and click them (F-738)")
    let f = ChatTurnFrames()
    // Claude's reply A in two pieces (the last carries the row), the 16 pt gap, then your message B. A's row hangs 4 to 26 under A,
    // so its lower 10 pt lie over B's top.
    f.set("A|0", turn: "A", frame: CGRect(x: 0, y: 0, width: 400, height: 30), row: false)
    f.set("A|1", turn: "A", frame: CGRect(x: 0, y: 30, width: 400, height: 30), row: true)
    f.set("B", turn: "B", frame: CGRect(x: 0, y: 76, width: 400, height: 80), row: true)
    let rows: (String) -> Bool = { _ in true }
    var hover: String?
    var path: [String] = []
    for y in stride(from: 10.0, through: 85, by: 1) {   // down from A's first piece to Copy's foot (Copy: x 0 to 62, y 64 to 86)
        hover = f.turn(at: CGPoint(x: 30, y: y), current: hover, hasRow: rows)
        path.append(hover ?? "-")
    }
    check(path.allSatisfy { $0 == "A" }, "down from Claude's reply to its Copy, the reply stays hovered, so its row stays (\(path.joined()))")
    check(f.turn(at: CGPoint(x: 30, y: 90), current: hover, hasRow: rows) == "B", "past the row's foot, the next message is hovered")
    check(f.turn(at: CGPoint(x: 30, y: 80), current: "B", hasRow: rows) == "B", "up from the next message into the row's band over it, the message keeps the hover")
    check(f.turn(at: CGPoint(x: 30, y: 80), current: nil, hasRow: rows) == "B", "arriving on that band from outside, the message under it wins")
    check(f.turn(at: CGPoint(x: 30, y: 70), current: nil, hasRow: rows) == "A", "the gap under a turn is its own")
    check(f.turn(at: CGPoint(x: 30, y: 70), current: nil, hasRow: { $0 != "A" }) == nil, "a turn with no row (still being written) owns no band")
    check(f.turn(at: CGPoint(x: 30, y: 15), current: "B", hasRow: rows) == "A", "a turn's earlier piece is that turn")
    f.remove("A|1")
    check(f.turn(at: CGPoint(x: 30, y: 45), current: nil, hasRow: rows) == nil, "a piece gone from the feed is forgotten")
}
