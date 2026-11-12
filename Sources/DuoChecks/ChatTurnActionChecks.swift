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
}
