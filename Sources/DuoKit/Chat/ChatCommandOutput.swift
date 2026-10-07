import Foundation

// What a slash command printed (chat-slash-handoff `output`, `context`; DL-143, Q-105): Claude
// Code's `<local-command-stdout>`, read from the transcript. One line is a quiet line under your
// bubble; several lines are an output block; `/context` is drawn as a bar from the lines it prints.
// Every word and number is Claude Code's own, read at run time.

/// A command's result, as chat shows it.
public struct ChatResult: Equatable, Sendable {
    public enum Body: Equatable, Sendable {
        /// One line: a quiet line led by the elbow.
        case line(String)
        /// Several lines, verbatim: an output block.
        case block([String])
        /// `/context`, read.
        case context(ChatContextUsage)
    }
    public var id: String
    public var body: Body
    public var time: Date?

    /// For logs and the harness: the text as it reads.
    public var summary: String {
        switch body {
        case .line(let l): l
        case .block(let b): b.joined(separator: "\n")
        case .context(let c): "Context usage \(c.model ?? "") \(c.used) / \(c.total) tokens · \(c.percent)% · " + c.categories.map { "\($0.name) · \($0.amount)" }.joined(separator: ", ")
        }
    }
}

/// `/context` as its lines say it: the model, the total, the categories in screen order.
public struct ChatContextUsage: Equatable, Sendable {
    public struct Category: Equatable, Sendable {
        public var name: String
        /// As printed: `1.4k`, `100`, `197k`.
        public var amount: String
        /// Percent of the window.
        public var share: Double
        /// `Free space`: shown in the legend, not in the bar.
        public var free: Bool
    }
    public var model: String?
    /// The model's full id, the name's tooltip.
    public var modelId: String?
    public var used: String
    public var total: String
    public var percent: String
    public var categories: [Category]
    /// `13 skills · 1.5k tokens`, from under `Skills · /skills`.
    public var skills: String?
}

public enum ChatCommandOutput {
    /// Colour and style codes out: `/context` prints its grid in colour, and the transcript keeps them.
    public static func plain(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
    }

    /// A `<local-command-stdout>` body as chat shows it; nil when there's nothing to show.
    public static func body(_ raw: String) -> ChatResult.Body? {
        let text = plain(raw)
        if let c = context(text) { return .context(c) }
        var lines = text.components(separatedBy: "\n").map { $0.chatTrimEnd }
        while lines.first?.chatTrim.isEmpty == true { lines.removeFirst() }
        while lines.last?.chatTrim.isEmpty == true { lines.removeLast() }
        guard !lines.isEmpty else { return nil }
        if lines.count == 1 {
            let l = lines[0].chatTrim
            // Claude Code marks names as code (`Haiku 4.5`); the line reads as plain words (the board).
            return l == "(no content)" ? nil : .line(l.replacingOccurrences(of: "`", with: ""))
        }
        // A common left margin goes, spacing inside is kept (the block is verbatim).
        let margin = lines.filter { !$0.chatTrim.isEmpty }.map { $0.prefix { $0 == " " }.count }.min() ?? 0
        return .block(lines.map { String($0.dropFirst(min(margin, $0.prefix { $0 == " " }.count))) })
    }

    /// The grid's glyphs, and the spaces between them, at the start of a line.
    static let grid = #"^[\s⛀⛁⛂⛃⛶⛝⛞⛉⛊⛋⛌⛍⛏⛐]+"#

    /// `/context`'s lines read; nil when they aren't its shape.
    public static func context(_ text: String) -> ChatContextUsage? {
        let lines = text.components(separatedBy: "\n").map { $0.replacingOccurrences(of: grid, with: "", options: .regularExpression).chatTrimEnd }
        guard let head = lines.firstIndex(where: { $0.chatTrim == "Context Usage" }) else { return nil }
        var model: String?, modelId: String?, total: (String, String, String)?
        var cats: [ChatContextUsage.Category] = []
        var skills: String?
        var inCategories = false, inSkills = false
        for l in lines[(head + 1)...] {
            let t = l.chatTrim
            if t.isEmpty { inCategories = false; continue }
            if let m = t.chatMatch(#"^([\d.]+[kKmM]?)\s*/\s*([\d.]+[kKmM]?) tokens \(([\d.]+)%\)$"#) {
                total = (m[1] ?? "", m[2] ?? "", m[3] ?? ""); continue
            }
            if t.hasPrefix("Estimated usage by category") { inCategories = true; continue }
            if inCategories, let m = t.chatMatch(#"^(.+?): ([\d.]+[kKmM]?)(?: tokens)? \(([\d.]+)%\)$"#) {
                let name = m[1] ?? ""
                cats.append(.init(name: name, amount: m[2] ?? "", share: Double(m[3] ?? "") ?? 0, free: name == "Free space"))
                continue
            }
            if t.hasPrefix("Skills · ") { inSkills = true; continue }
            if inSkills, t.hasPrefix("└") {
                skills = String(t.dropFirst()).chatTrim; inSkills = false; continue
            }
            if total == nil, cats.isEmpty, !t.contains(" ·") {
                if model == nil { model = t } else if modelId == nil, !t.contains(" ") { modelId = t }
            }
        }
        guard let total, !cats.isEmpty else { return nil }
        return ChatContextUsage(model: model, modelId: modelId, used: total.0, total: total.1, percent: total.2, categories: cats, skills: skills)
    }
}

extension ChatLog {
    /// A command's printed output, under the command (DL-143).
    func commandResult(_ raw: String, time: Date?) {
        guard let body = ChatCommandOutput.body(raw) else { return }
        items.append(.result(ChatResult(id: newID("result"), body: body, time: time)))
    }
}
