import DuoKit
import Foundation

// DL-167 step 4: Swift is the one writer of a task note's properties and lists. Every edit is a
// `TaskNotes.NoteEdit`; a closed note gets `TaskNotes.apply` written to its file, an open note gets
// the same string as a plain transaction (`EditorController.applyNoteEdit`; the scripted case in
// scripts/check-editor-host.sh proves the page lands the same bytes). These cases pin the string,
// byte for byte, for the shapes the JavaScript copies got wrong (F-249 to F-251: `sessions: []`,
// `key: `, the task-box space).

@MainActor func noteEditChecks() throws {
    print("task-note property writes, byte for byte (DL-167 step 4)")
    let id1 = "aaaaaaaa-1111-4222-8333-444444444444", id2 = "bbbbbbbb-1111-4222-8333-444444444444"
    let link = TaskNotes.link(title: "Draft", id: id2)
    let body = "\n# Plan\n\n- [ ] first\n"

    // sessions: [] (a new task) becomes a block list; the rest is untouched
    let empty = "---\ntitle: \"Plan\"\nstatus: open\nsessions: []\n---\n" + body
    check(TaskNotes.apply(.addSession(link: link), to: empty) ==
          "---\ntitle: \"Plan\"\nstatus: open\nsessions:\n  - \"[Draft](duo2://session/\(id2))\"\n---\n" + body, "a link into `sessions: []` makes a block list, byte for byte")
    // an existing block list grows by one line after the last item
    let one = "---\nsessions:\n  - \"[A](duo2://session/\(id1))\"\nowner: me\n---\n" + body
    check(TaskNotes.apply(.addSession(link: link), to: one) ==
          "---\nsessions:\n  - \"[A](duo2://session/\(id1))\"\n  - \"[Draft](duo2://session/\(id2))\"\nowner: me\n---\n" + body, "a link after the last item of a block list")
    check(TaskNotes.apply(.addSession(link: TaskNotes.link(title: "again", id: id1)), to: one) == nil, "a session already linked changes nothing")
    // no frontmatter at all
    check(TaskNotes.apply(.addSession(link: link), to: "# Plan\n") == "---\nsessions:\n  - \"[Draft](duo2://session/\(id2))\"\n---\n# Plan\n", "a note without frontmatter gets one holding the list")
    // CRLF keeps its endings
    let crlf = "---\r\nsessions: []\r\n---\r\n# Plan\r\n"
    check(TaskNotes.apply(.addSession(link: link), to: crlf) == "---\r\nsessions:\r\n  - \"[Draft](duo2://session/\(id2))\"\r\n---\r\n# Plan\r\n", "CRLF stays CRLF")

    // status and completed together
    let open = "---\nstatus: open\n---\n" + body
    check(TaskNotes.apply(.status("done", completed: "2026-10-09"), to: open) == "---\nstatus: done\ncompleted: 2026-10-09\n---\n" + body, "done adds completed: before the fence")
    check(TaskNotes.apply(.status("open", completed: nil), to: "---\nstatus: done\ncompleted: 2026-10-09\n---\n" + body) == open, "reopening removes completed: and restores the note")
    check(TaskNotes.apply(.status("open", completed: nil), to: open) == nil, "the same status again changes nothing")
    check(TaskNotes.apply(.status(nil, completed: nil), to: "---\nstatus: done\n---\nx\n") == "---\n---\nx\n", "a removed key leaves no `key: ` behind")

    // references
    let ref = "[Plan](../docs/plan.md)"
    check(TaskNotes.apply(.addReference(link: ref), to: open) == "---\nstatus: open\nreferences:\n  - \"[Plan](../docs/plan.md)\"\n---\n" + body, "a first reference makes the list before the fence")
    let two = "---\nreferences:\n  - \"[Plan](../docs/plan.md)\"\n  - \"[B](b.md)\"\n---\n" + body
    check(TaskNotes.apply(.addReference(link: ref), to: two) == nil, "a reference to the same target isn't added twice")
    check(TaskNotes.apply(.removeReference(target: "../docs/plan.md"), to: two) == "---\nreferences:\n  - \"[B](b.md)\"\n---\n" + body, "Remove from Task drops that line only")
    check(TaskNotes.apply(.removeReference(target: "b.md"), to: "---\nstatus: open\nreferences:\n  - \"[B](b.md)\"\n---\n" + body) == open, "the last reference takes its key with it")
    check(TaskNotes.apply(.removeReference(target: "nope.md"), to: two) == nil, "removing what isn't there changes nothing")
}
