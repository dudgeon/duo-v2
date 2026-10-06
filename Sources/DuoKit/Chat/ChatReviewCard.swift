import AppKit
import SwiftUI

// Review cards (chat-mode-handoff `permission-edit`, `permission-bash`, `plan`, `question-*`):
// docked at the bottom in the composer's place while Claude waits on you, as the TUI's dialog
// replaces its prompt. Every option label is Claude Code's own, read from its screen; what's
// asked (the diff, the command, the plan, every question and preview) comes from the request.
// Each option shows its key; nothing is pre-selected; a click or a number key sends that key.

struct ChatReviewCard: View {
    @Environment(AppModel.self) private var model
    let chat: ChatSession

    var body: some View {
        let s = chat.screen
        VStack(alignment: .leading, spacing: 10) {
            switch s.kind {
            case .permission: ChatPermissionBody(chat: chat, screen: s)
            case .plan: ChatPlanBody(chat: chat, screen: s)
            case .question, .questionReview: ChatQuestionBody(chat: chat, screen: s)
            default: EmptyView()
            }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusReviewCard).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusReviewCard).strokeBorder(DuoColor.needsYou, lineWidth: 1.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Claude needs you")
    }
}

/// `● NEEDS YOU · EDIT FILE`, and anything at the right end.
struct ChatNeedsYouHeader<Trailing: View>: View {
    let what: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            StateGlyph(.needsYou)
            Text("NEEDS YOU").duoText(.sectionLabel).foregroundStyle(DuoColor.needsYou)
            Text("· " + what.uppercased()).duoText(.sectionLabel).foregroundStyle(DuoColor.text2)
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension ChatNeedsYouHeader where Trailing == EmptyView {
    init(what: String) { self.init(what: what) { EmptyView() } }
}

/// An option's key: 18 × 18, mono 11, on `ground`.
struct ChatKeyCap: View {
    let n: Int?
    var body: some View {
        Text(n.map(String.init) ?? "").font(Font(NSFont.monospacedSystemFont(ofSize: 11, weight: .regular))).foregroundStyle(DuoColor.text2)
            .frame(width: 18, height: 18)
            .background(RoundedRectangle(cornerRadius: DuoMetric.radiusChatInlineCode).fill(DuoColor.ground))
            .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusChatInlineCode).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
    }
}

/// One option: its key, its label (verbatim), an optional description; a 1 pt `controlEdge` box.
struct ChatOptionButton<Lead: View>: View {
    let n: Int?
    let label: String
    var note: String?
    var emphasised = false
    @ViewBuilder var lead: Lead
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ChatKeyCap(n: n).padding(.top, 1)
            lead
            VStack(alignment: .leading, spacing: 0) {
                Text(ChatInlineText.styled(label, style: .body)).duoText(.body).foregroundStyle(DuoColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let note, !note.isEmpty { Text(note).duoText(.chatMeta).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody)
            .strokeBorder(emphasised ? DuoColor.text : DuoColor.controlEdge, lineWidth: emphasised ? 1.5 : DuoMetric.borderHairline))
        .contentShape(Rectangle())
        .onActivate(action)  // action: session chat
        .accessibilityLabel(n.map { "\($0). \(label)" } ?? label)
    }
}

extension ChatOptionButton where Lead == EmptyView {
    init(n: Int?, label: String, note: String? = nil, emphasised: Bool = false, action: @escaping () -> Void) {
        self.init(n: n, label: label, note: note, emphasised: emphasised, lead: { EmptyView() }, action: action)
    }
}

/// `Cancel esc`: a button with its key, the key in `text2`.
struct ChatKeyedButton: View {
    let title: String
    let key: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Text("\(Text(title)) \(Text(key).foregroundStyle(DuoColor.text2))") }.buttonStyle(.duo)
            .accessibilityLabel(title)
    }
}

/// A field inside an option row (plan feedback, Type something, Notes), with its button.
struct ChatInlineField: View {
    let placeholder: String
    let text: Binding<String>
    let button: String
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .duoText(.body)
                .onSubmit(onSubmit)
            Button(button, action: onSubmit).buttonStyle(.duo)  // action: session chat
        }
    }
}

// MARK: - Permission

struct ChatPermissionBody: View {
    @Environment(AppModel.self) private var model
    let chat: ChatSession
    let screen: ChatScreen

    var body: some View {
        let req = chat.pendingRequest
        let label = screen.kindLabel ?? req?.tool ?? "Permission"
        ChatNeedsYouHeader(what: label)
        if let req, ["Edit", "MultiEdit", "Write"].contains(req.tool) {
            // The diff Claude asked to make, from the request (the TUI's own lines aren't needed).
            let step = ChatToolDescriber.step(id: "req", name: req.tool, input: req.input, cwd: chat.log.cwd)
            VStack(alignment: .leading, spacing: 0) {
                Text(step.object).duoText(.chatDiff).foregroundStyle(DuoColor.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                    .background(DuoColor.toolOutputFill)
                ChatDiffView(lines: chat.requestDiff ?? step.diff ?? [], framed: false)
            }
            .clipShape(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody))
            .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody).strokeBorder(DuoColor.selected, lineWidth: DuoMetric.borderHairline))
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).duoText(.chatBody, weight: .semibold).foregroundStyle(DuoColor.text)
                if let d = req?.input["description"] as? String { Text(d).duoText(.body).foregroundStyle(DuoColor.text2) }
            }
            let command = (req?.input["command"] as? String) ?? screen.body ?? ""
            if !command.isEmpty {
                Text(command).duoText(.mono).foregroundStyle(DuoColor.text).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .background(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody).fill(DuoColor.ground))
            }
        }
        Text(screen.title ?? "").duoText(.chatBody, weight: .semibold).foregroundStyle(DuoColor.text)
        VStack(spacing: 6) {
            ForEach(Array(screen.options.enumerated()), id: \.offset) { _, o in
                ChatOptionButton(n: o.n, label: Self.codePaths(o.label)) {
                    Task { await chat.answerOption(o.n ?? 0, label: o.label, sig: screen.sig) }
                }
            }
        }
        HStack(spacing: 6) {
            ChatKeyedButton(title: "Cancel", key: "esc") { Task { await chat.cancelDialog(sig: screen.sig) } }  // action: session chat
            if screen.amend {
                Button("Amend in Terminal…") { model.handOver(chat.key, "Amend Claude’s request here, then press Return. Chat comes back after.") }  // action: session chat
                    .buttonStyle(.duo)
            }
            Spacer(minLength: 8)
            Text("Your choice goes to Claude Code as its key.").duoText(.chatMeta).foregroundStyle(DuoColor.text2)
        }
    }

    /// A path inside a label reads as code (handoff `permission-bash`: `…/research`).
    static func codePaths(_ label: String) -> String {
        label.replacingOccurrences(of: #"(?<![`\w])(/[^\s`]+[^\s`.,])"#, with: "`$1`", options: .regularExpression)
    }
}

// MARK: - Plan

struct ChatPlanBody: View {
    @Environment(AppModel.self) private var model
    let chat: ChatSession
    let screen: ChatScreen

    var body: some View {
        let ui = chat.ui
        ChatNeedsYouHeader(what: screen.title ?? "Ready to code?") {
            if let path = chat.planPath {
                Text("Open plan in Duo").duoText(.chatMeta).foregroundStyle(DuoColor.text2).underline(color: DuoColor.controlEdge)
                    .onActivate { model.openChatLink(URL(fileURLWithPath: path), cwd: nil) }  // action: doc open
            }
        }
        // The whole plan (the TUI clips it), in a box that scrolls.
        ScrollView(.vertical) {
            ChatMarkdownView(blocks: ChatMarkdown.parse(chat.planText ?? ""), streaming: false, compact: true)
                .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
        }
        .frame(height: 196)
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody).strokeBorder(DuoColor.selected, lineWidth: DuoMetric.borderHairline))
        Text(screen.body ?? "").duoText(.body).foregroundStyle(DuoColor.text).fixedSize(horizontal: false, vertical: true)
        VStack(spacing: 6) {
            ForEach(Array(screen.options.enumerated()), id: \.offset) { _, o in
                if o.label.hasPrefix("Tell Claude what to change") {
                    HStack(alignment: .center, spacing: 10) {
                        ChatKeyCap(n: o.n)
                        Text(o.label).duoText(.body).foregroundStyle(DuoColor.text2).fixedSize()
                        DuoColor.rule.frame(width: DuoMetric.borderHairline, height: 20)
                        ChatInlineField(placeholder: "", text: Binding(get: { ui.planFeedback }, set: { ui.planFeedback = $0 }), button: "Send ⏎") {
                            let text = ui.planFeedback.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { return }
                            Task { if await chat.planFeedback(text, sig: screen.sig).ok { ui.planFeedback = "" } }
                        }
                    }
                    .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                    .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody)
                        .strokeBorder(ui.planFeedback.isEmpty ? DuoColor.controlEdge : DuoColor.text, lineWidth: ui.planFeedback.isEmpty ? DuoMetric.borderHairline : 1.5))
                } else {
                    ChatOptionButton(n: o.n, label: o.label) { Task { await chat.answerOption(o.n ?? 0, label: o.label, sig: screen.sig) } }
                }
            }
        }
        HStack(spacing: 6) {
            ChatKeyedButton(title: "Cancel", key: "esc") { Task { await chat.cancelDialog(sig: screen.sig) } }  // action: session chat
            Button("Approve with Feedback in Terminal…") {  // action: session chat
                model.handOver(chat.key, "Type your feedback on option 3 here, then press shift+tab to approve with it. Chat comes back after.")
            }.buttonStyle(.duo)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - AskUserQuestion

struct ChatQuestionBody: View {
    let chat: ChatSession
    let screen: ChatScreen

    var body: some View {
        let qs = chat.askedQuestions
        let index = chat.questionIndex(screen)
        let q = index.flatMap { $0 < qs.count ? qs[$0] : nil }
        let header = qs.count == 1 ? "Claude’s question" + ((qs[0]["header"] as? String).map { " · \($0)" } ?? "") : "Claude’s questions"
        ChatNeedsYouHeader(what: header)
        if qs.count > 1 { ChatQuestionTabs(chat: chat, screen: screen, index: index ?? 0) }
        if screen.kind == .questionReview {
            ChatReviewPage(chat: chat, screen: screen)
        } else if let q, let index {
            Text(q["question"] as? String ?? screen.question ?? "").duoText(.chatBody, weight: .semibold).foregroundStyle(DuoColor.text)
                .fixedSize(horizontal: false, vertical: true)
            if screen.preview { ChatPreviewOptions(chat: chat, screen: screen, question: q) }
            else { ChatQuestionOptions(chat: chat, screen: screen, question: q, index: index) }
            HStack(spacing: 6) {
                ChatKeyedButton(title: "Decline", key: "esc") { Task { await chat.ask(.decline, sig: screen.sig) } }  // action: session chat
                Button("Chat about this") { Task { await chat.ask(.chat, sig: screen.sig); chat.focusComposer += 1 } }  // action: session chat
                    .buttonStyle(.duo)
                Spacer(minLength: 8)
                Text(hint(q)).duoText(.chatMeta).foregroundStyle(DuoColor.text2)
            }
            .padding(.top, 10)
            .overlay(alignment: .top) { DuoColor.selected.frame(height: DuoMetric.borderHairline) }
        } else {
            Text(screen.question ?? "").duoText(.chatBody, weight: .semibold).foregroundStyle(DuoColor.text)
        }
    }

    func hint(_ q: ChatJSON) -> String {
        if screen.preview { return "Every layout at once; Claude Code shows one at a time" }
        if let v = screen.other?.value, !v.isEmpty { return "Your own answer, typed into Claude Code" }
        return screen.multi ? "Space toggles · ← → between questions" : "← → between questions"
    }
}

/// `‹ Back  ☒ Platforms  ☐ Timing  ✔ Submit`: a click goes to that question.
struct ChatQuestionTabs: View {
    let chat: ChatSession
    let screen: ChatScreen
    let index: Int

    var body: some View {
        let qs = chat.askedQuestions
        HStack(spacing: 4) {
            if index > 0 {
                Button("‹ Back") { Task { await chat.ask(.tab(index - 1), sig: screen.sig) } }  // action: session chat
                    .buttonStyle(.duo).padding(.trailing, 4)
            }
            ForEach(Array(qs.enumerated()), id: \.offset) { i, q in
                let label = q["header"] as? String ?? "Q\(i + 1)"
                let done = screen.tabs.first { $0.label == label }?.done ?? false
                tab((done ? "☒ " : "☐ ") + label, on: i == index) { Task { await chat.ask(.tab(i), sig: screen.sig) } }
            }
            tab("✔ Submit", on: index == qs.count) { Task { await chat.ask(.tab(qs.count), sig: screen.sig) } }
        }
    }

    func tab(_ title: String, on: Bool, _ go: @escaping () -> Void) -> some View {
        Text(title).duoText(.chatMeta, weight: on ? .semibold : nil).foregroundStyle(on ? DuoColor.text : DuoColor.text2)
            .padding(EdgeInsets(top: 3, leading: 9, bottom: 3, trailing: 9))
            .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusPill).strokeBorder(on ? DuoColor.text : .clear, lineWidth: DuoMetric.borderHairline))
            .contentShape(Rectangle())
            .onActivate(go)  // action: session chat
    }
}

/// Checkboxes or radios, each with its description; Type something; Next.
struct ChatQuestionOptions: View {
    let chat: ChatSession
    let screen: ChatScreen
    let question: ChatJSON
    let index: Int

    var body: some View {
        let asked = question["options"] as? [ChatJSON] ?? []
        let ui = chat.ui
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(screen.options.enumerated()), id: \.offset) { i, o in
                let full = i < asked.count ? asked[i]["label"] as? String ?? o.label : o.label
                let desc = i < asked.count ? asked[i]["description"] as? String : o.note
                ChatOptionButton(n: o.n, label: full, note: desc, lead: {
                    ChatChoiceMark(multi: screen.multi, on: screen.multi ? o.checked == true : o.selected).padding(.top, 3)
                }) { Task { await chat.ask(screen.multi ? .toggle(full) : .pick(full), sig: screen.sig) } }
            }
            if let other = screen.other {
                let draft = Binding(get: { ui.other[index] ?? other.value ?? "" }, set: { ui.other[index] = $0 })
                let typed = !(other.value ?? "").isEmpty || !(ui.other[index] ?? "").isEmpty
                HStack(alignment: .center, spacing: 10) {
                    ChatKeyCap(n: other.n)
                    ChatChoiceMark(multi: screen.multi, on: screen.multi ? other.checked == true : typed)
                    ChatInlineField(placeholder: "Type something", text: draft, button: screen.multi ? "Add" : "Answer ⏎") {
                        let text = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        Task { if await chat.ask(.other(text), sig: screen.sig).ok { ui.other[index] = nil } }
                    }
                }
                .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody)
                    .strokeBorder(typed && !screen.multi ? DuoColor.text : DuoColor.controlEdge, lineWidth: typed && !screen.multi ? 1.5 : DuoMetric.borderHairline))
            }
            if screen.multi, screen.rows.contains(where: { $0.kind == .next || $0.kind == .submit }) {
                ChatKeyedButton(title: screen.rows.contains { $0.kind == .submit } ? "Submit" : "Next", key: "⏎") {  // action: session chat
                    Task { await chat.ask(.next, sig: screen.sig) }
                }
            }
        }
    }
}

/// A checkbox (multi-select) or a radio (single), 14 × 14.
struct ChatChoiceMark: View {
    let multi: Bool
    let on: Bool
    var body: some View {
        Group {
            if multi {
                ZStack {
                    RoundedRectangle(cornerRadius: DuoMetric.radiusChatCheckbox).fill(on ? DuoColor.text : DuoColor.pane)
                    RoundedRectangle(cornerRadius: DuoMetric.radiusChatCheckbox).strokeBorder(on ? DuoColor.text : DuoColor.controlEdge, lineWidth: 1.5)
                    if on { Checkmark().stroke(DuoColor.pane, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)).frame(width: 8, height: 6) }
                }
            } else {
                Circle().strokeBorder(on ? DuoColor.text : DuoColor.controlEdge, lineWidth: on ? 4 : 1.5)
            }
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }
}

/// Every option's preview side by side (the TUI shows one at a time), and Notes.
struct ChatPreviewOptions: View {
    let chat: ChatSession
    let screen: ChatScreen
    let question: ChatJSON

    var body: some View {
        let asked = question["options"] as? [ChatJSON] ?? []
        let ui = chat.ui
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(screen.options.enumerated()), id: \.offset) { i, o in
                let a = i < asked.count ? asked[i] : [:]
                let label = a["label"] as? String ?? o.label
                VStack(alignment: .leading, spacing: 6) {
                    Text(a["preview"] as? String ?? "").duoText(.chatPreview).foregroundStyle(DuoColor.text)
                        .fixedSize()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusChatPreviewCode).fill(DuoColor.ground))
                        .clipped()
                    HStack(alignment: .top, spacing: 6) {
                        ChatKeyCap(n: o.n)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(label + (o.selected ? " ✔" : "")).duoText(.body, weight: .semibold).foregroundStyle(DuoColor.text)
                            if let d = a["description"] as? String { Text(d).duoText(.chatMeta).foregroundStyle(DuoColor.text2) }
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusChatCodeBlock)
                    .strokeBorder(o.cursor ? DuoColor.text : DuoColor.controlEdge, lineWidth: o.cursor ? 1.5 : DuoMetric.borderHairline))
                .contentShape(Rectangle())
                .onActivate {  // action: session chat
                    let notes = ui.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task { await chat.ask(notes.isEmpty ? .pick(label) : .notes(label, notes), sig: screen.sig) }
                }
                .accessibilityLabel("\(o.n ?? i + 1). \(label)")
            }
        }
        HStack(spacing: 8) {
            Text("Notes").duoText(.body).foregroundStyle(DuoColor.text2)
            DuoColor.rule.frame(width: DuoMetric.borderHairline, height: 20)
            ChatInlineField(placeholder: "", text: Binding(get: { ui.notes }, set: { ui.notes = $0 }), button: "Choose with Notes ⏎") {
                let notes = ui.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let focus = screen.options.firstIndex(where: \.cursor), !notes.isEmpty else { return }
                let label = focus < asked.count ? asked[focus]["label"] as? String ?? screen.options[focus].label : screen.options[focus].label
                Task { if await chat.ask(.notes(label, notes), sig: screen.sig).ok { ui.notes = "" } }
            }
        }
        .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody).strokeBorder(DuoColor.controlEdge, lineWidth: DuoMetric.borderHairline))
    }
}

/// Review your answers, then Submit answers / Cancel (Cancel declines).
struct ChatReviewPage: View {
    let chat: ChatSession
    let screen: ChatScreen

    var body: some View {
        Text("Review your answers").duoText(.chatBody, weight: .semibold).foregroundStyle(DuoColor.text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.pairs(screen.answers ?? "").enumerated()), id: \.offset) { _, p in
                VStack(alignment: .leading, spacing: 0) {
                    Text(p.question).duoText(.body).foregroundStyle(DuoColor.text)
                    Text("→ " + p.answer).duoText(.body, weight: .semibold).foregroundStyle(DuoColor.text)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody).strokeBorder(DuoColor.selected, lineWidth: DuoMetric.borderHairline))
        Text("Ready to submit your answers?").duoText(.body).foregroundStyle(DuoColor.text)
        VStack(spacing: 6) {
            ForEach(Array(screen.options.enumerated()), id: \.offset) { _, o in
                ChatOptionButton(n: o.n, label: o.label) {
                    Task { await chat.ask(o.label == "Cancel" ? .cancelReview : .submit, sig: screen.sig) }
                }
            }
        }
    }

    /// The TUI's review lines: `● question` then `→ answer`.
    static func pairs(_ text: String) -> [(question: String, answer: String)] {
        var out: [(String, String)] = []
        var q = ""
        for l in text.components(separatedBy: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) where !l.isEmpty {
            if l.hasPrefix("→") { out.append((q, String(l.dropFirst()).trimmingCharacters(in: .whitespaces))); q = "" }
            else { q = (q.isEmpty ? "" : q + " ") + l.replacingOccurrences(of: #"^[●•]\s*"#, with: "", options: .regularExpression) }
        }
        return out
    }
}
