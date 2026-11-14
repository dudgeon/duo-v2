import Foundation

// The question Duo asks before a rewind, on its own sheet (DL-338, Q-506; never a system alert, F-54).

/// What a rewind to before a prompt takes out, from the log.
public struct ChatRewindFacts: Equatable, Sendable {
    /// Claude's turns after the prompt.
    public var turnsAfter: Int
    /// The files Claude's own Edit and Write tools changed in them (Bash's changes aren't tracked, F-652), in order.
    public var files: [String]
}

extension ChatSession {
    /// Whether the prompt `id` can be rewound to: a typed prompt the transcript has (Claude Code names it by its uuid).
    public func canRewind(_ id: String) -> Bool {
        guard case .you(let y)? = log.items.first(where: { $0.id == id }) else { return false }
        return !y.queued && y.uuid != nil
    }

    public func rewindFacts(_ id: String) -> ChatRewindFacts? {
        guard let at = log.items.firstIndex(where: { $0.id == id }), case .you = log.items[at] else { return nil }
        var turns = 0
        var files: [String] = []
        for item in log.items[(at + 1)...] {
            guard case .claude(let t) = item else { continue }
            turns += 1
            for seg in t.segments {
                guard case .tools(_, let steps) = seg else { continue }
                for s in steps where ["Edit", "Write", "MultiEdit", "NotebookEdit"].contains(s.name) && s.status == .done {
                    let f = s.path ?? s.object
                    if !f.isEmpty, !files.contains(f) { files.append(f) }
                }
            }
        }
        return ChatRewindFacts(turnsAfter: turns, files: files)
    }

    /// The sheet for rewinding to before the prompt `id`, as drawn on the canvas (board 3). Nil when it can't be asked.
    public func rewindQuestion(_ id: String, preferCode: Bool = false, completion: (@MainActor (ChatAnswerResult?) -> Void)? = nil) -> DuoQuestion? {
        guard canRewind(id), case .you(let y)? = log.items.first(where: { $0.id == id }), let facts = rewindFacts(id) else { return nil }
        let after = facts.turnsAfter == 0 ? "" : facts.turnsAfter == 1 ? " and the turn after it" : " and the \(facts.turnsAfter) turns after it"
        var q = DuoQuestion(title: "Rewind to before this message?", choices: [])
        q.quote = y.text
        q.paragraphs = ["This message\(after) leave\(after.isEmpty ? "s" : "") the conversation. The message comes back to your composer\(facts.files.isEmpty ? ". No files change." : " to change and send.")"]
        var radios: DuoQuestion.Radios?
        if !facts.files.isEmpty {
            let n = facts.files.count
            radios = DuoQuestion.Radios(options: [
                .init(value: "conversation", title: "Conversation only", sub: "Files stay as they are now."),
                .init(value: "files", title: "Conversation and files", sub: "Undo Claude’s changes since then in \(n) file\(n == 1 ? "" : "s"):"),
            ], selected: preferCode ? "files" : "conversation")
            q.radios = radios
            q.items = facts.files.map { DuoQuestion.Item(what: "", path: $0) }
            q.note = "Changes made by commands Claude ran, or by you, aren’t undone. Other sessions in this folder lose their later changes to these files."
            q.noteIsSmall = true
        }
        q.choices = [
            .init(label: "Cancel", isCancel: true, action: { completion?(nil) }),
            .init(label: "Rewind", isDefault: true, action: { [weak self] in
                let code = radios?.selected == "files"
                Task { @MainActor in
                    let r = await self?.rewind(toPrompt: id, code: code) ?? .refused("the chat is gone")
                    completion?(r)
                }
            }),
        ]
        return q
    }

    /// Shows the rewind sheet (the row's Rewind, the Chat menu, `duo2 session rewind`). False when there's nothing to ask.
    @discardableResult
    public func askRewind(_ id: String, preferCode: Bool = false, completion: (@MainActor (ChatAnswerResult?) -> Void)? = nil) -> Bool {
        guard screen.kind != .busy, let q = rewindQuestion(id, preferCode: preferCode, completion: completion) else { return false }
        SheetCenter.shared.ask(q)
        return true
    }
}
