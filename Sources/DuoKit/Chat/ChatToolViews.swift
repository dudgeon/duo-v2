import AppKit
import SwiftUI

// Tool steps on a dotted thread at the top of Claude's card (chat-mode-handoff `tools`): a bold
// verb and its object (files are links), a small open dot. Runs of steps fold to one line, opened
// in place to one line a step; a step opens to its output, diff or preview (DL-135, chat-polish-
// handoff). A failed tool says so in `diffDelText`; a step waiting on you is never folded.

/// The thread's rows: runs, and the steps and to-do line beside them.
struct ChatThread: View {
    let blocks: [ChatCardRow]
    let chat: ChatSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks) { b in
                switch b {
                case .run(let r): ChatRunView(run: r, chat: chat)
                case .step(let s): ChatToolStepView(step: s, chat: chat)
                case .todos(let s): ChatTodosView(step: s, chat: chat)
                default: EmptyView()
                }
            }
        }
        .padding(.leading, 6)
        .background(alignment: .leading) {
            DottedLine().stroke(DuoColor.controlEdge, style: StrokeStyle(lineWidth: 1.5, dash: [1.5, 2.5]))
                .frame(width: 1.5).padding(.leading, 6)
        }
    }
}

/// The open dot on the thread.
struct ChatThreadDot: View {
    var edge = DuoColor.controlEdge
    var body: some View {
        Circle().strokeBorder(edge, lineWidth: 1.5)
            .background(Circle().fill(DuoColor.pane))
            .frame(width: 10, height: 10).padding(.leading, 1.5)
    }
}

/// A run: `Ran 4 shell commands ›`; opened, a line a step (handoff `collapsed`, `expanded`, `mixed`).
struct ChatRunView: View {
    let run: ChatRun
    let chat: ChatSession

    var open: Bool { chat.ui.openRuns.contains(run.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                ChatThreadDot()
                Text(title).duoText(.chatMeta).foregroundStyle(DuoColor.text2).lineLimit(2)
                Spacer(minLength: 8)
                Text(open ? "⌄" : "›").duoText(.chatMeta).foregroundStyle(DuoColor.text2)
            }
            .frame(minHeight: 24)
            .padding(.leading, -5)
            .contentShape(Rectangle())
            .onActivate { chat.ui.openRuns.formSymmetricDifference([run.id]) }  // not an action: a fold
            .accessibilityElement(children: .combine)
            .accessibilityLabel(ChatRuns.line(run))
            .accessibilityValue(open ? "open" : "folded")
            if open {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(run.entries.enumerated()), id: \.offset) { _, e in
                        switch e {
                        case .step(let s): ChatToolStepView(step: s, chat: chat, nested: true)
                        case .thought(let id, let secs): ChatThinkingRow(id: id, seconds: secs, chat: chat).padding(.vertical, 4)
                        }
                    }
                }
                .padding(EdgeInsets(top: 0, leading: 18, bottom: 6, trailing: 0))
            } else if let s = run.running {
                // The step in progress, on one line beneath (handoff `mixed`).
                Text(s.object).duoText(.mono).foregroundStyle(DuoColor.text2).lineLimit(1).truncationMode(.tail)
                    .frame(minHeight: 24).padding(.leading, 18)
            }
        }
    }

    /// `**Searched** for 2 patterns, **read** 3 files` · files · `+6 −3` · `1 failed`.
    var title: AttributedString {
        var a = AttributedString()
        for (i, c) in ChatRuns.clauses(run).enumerated() {
            if i > 0 { a += AttributedString(", ") }
            var v = AttributedString(c.verb)
            v.font = .system(size: DuoTextStyle.chatMeta.spec.size, weight: .semibold)
            v.foregroundColor = DuoColor.text
            a += v + AttributedString(" " + c.rest)
        }
        if run.running != nil { a += AttributedString("…") }
        let files = ChatRuns.editedFiles(run)
        if !files.isEmpty {
            a += AttributedString(" · ")
            for (i, p) in files.enumerated() {
                if i > 0 { a += AttributedString(", ") }
                var link = AttributedString((p as NSString).lastPathComponent)
                link.foregroundColor = DuoColor.text
                link.underlineStyle = Text.LineStyle(pattern: .solid, color: DuoColor.controlEdge)
                link.link = ChatMarkdown.fileURL(p)
                a += link
            }
            let (adds, dels) = ChatRuns.editCounts(run)
            if adds > 0 { var x = AttributedString(" +\(adds)"); x.foregroundColor = DuoColor.diffAddText; a += x }
            if dels > 0 { var x = AttributedString(" −\(dels)"); x.foregroundColor = DuoColor.diffDelText; a += x }
        }
        if run.failed > 0 {
            a += AttributedString(" · ")
            var x = AttributedString("\(run.failed) failed"); x.foregroundColor = DuoColor.diffDelText; a += x
        }
        return a
    }
}

/// The turn's to-do list: `To-dos · 3 of 5 done`; opened, the checklist (handoff `todos`).
struct ChatTodosView: View {
    let step: ChatToolStep
    let chat: ChatSession

    var key: String { "todos-" + step.id }
    var open: Bool { chat.ui.toggled.contains(key) }

    var body: some View {
        let todos = step.todos ?? []
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                ChatThreadDot()
                Text("\(Text("To-dos").fontWeight(.semibold).foregroundStyle(DuoColor.text)) · \(ChatRuns.todoLine(todos))")
                    .duoText(.chatMeta).foregroundStyle(DuoColor.text2)
                Spacer(minLength: 8)
                Text(open ? "⌄" : "›").duoText(.chatMeta).foregroundStyle(DuoColor.text2)
            }
            .frame(minHeight: 24)
            .padding(.leading, -5)
            .contentShape(Rectangle())
            .onActivate { chat.ui.toggled.formSymmetricDifference([key]) }  // not an action: a fold
            .accessibilityElement(children: .combine)
            if open {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(todos.enumerated()), id: \.offset) { _, t in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(t.status == .inProgress ? DuoColor.text : DuoColor.controlEdge, lineWidth: 1.5)
                                .background(RoundedRectangle(cornerRadius: 3).fill(t.status == .completed ? DuoColor.controlEdge : .clear))
                                .frame(width: 11, height: 11)
                            Text(t.text).duoText(.body, weight: t.status == .inProgress ? .semibold : nil)
                                .foregroundStyle(t.status == .completed ? DuoColor.text2 : DuoColor.text)
                                .strikethrough(t.status == .completed, color: DuoColor.controlEdge)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(t.status == .completed ? "done" : t.status == .inProgress ? "in progress" : "to do")
                    }
                }
                .padding(EdgeInsets(top: 2, leading: 18, bottom: 8, trailing: 0))
            }
        }
    }
}

struct DottedLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: r.midX, y: r.minY)); p.addLine(to: .init(x: r.midX, y: r.maxY))
        return p
    }
}

struct ChatToolStepView: View {
    @Environment(AppModel.self) private var model
    let step: ChatToolStep
    let chat: ChatSession
    /// A step inside an opened run: one line, no dot, folded until clicked (DL-135).
    var nested = false

    var failed: Bool { if case .failed = step.status { return true }; return false }
    /// A running background agent: its own line, never folded (handoff `agents`).
    var agentRunning: Bool { step.agent.map { !$0.finished } ?? false }
    /// Folded until clicked; a failed step in a run shows its error (handoff `failed`). A step
    /// waiting on you stays folded: the card below shows what's asked.
    var open: Bool {
        if step.status == .needsYou || agentRunning { return false }
        if nested { return failed != chat.ui.toggled.contains(step.id) }
        return step.agent == nil ? step.foldsByDefault == chat.ui.toggled.contains(step.id) : chat.ui.toggled.contains(step.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: nested ? 8 : 10) {
                if !nested { dot }
                Text(title).duoText(.chatMeta).foregroundStyle(DuoColor.text2).lineLimit(nested ? 1 : 2).truncationMode(.tail)
                Spacer(minLength: 8)
                trailing
            }
            .frame(minHeight: 24)
            .padding(.leading, nested ? 0 : -5)
            .contentShape(Rectangle())
            .onActivate { chat.ui.toggled.formSymmetricDifference([step.id]) }  // not an action: a fold
            .accessibilityElement(children: .combine)
            if open { stepBody.padding(EdgeInsets(top: 2, leading: nested ? 0 : 18, bottom: 8, trailing: 0)) }
        }
    }

    @ViewBuilder var dot: some View {
        if step.status == .needsYou {
            Circle().fill(DuoColor.needsYou).frame(width: 10, height: 10).padding(.leading, 1.5)
        } else {
            ChatThreadDot(edge: failed ? DuoColor.diffDelText : agentRunning ? DuoColor.text : DuoColor.controlEdge)
        }
    }

    /// `**Read** research/interviews.md · 214 lines`, as one attributed line. In a run, a command
    /// leads with Claude's description of it, then the command's first line.
    var title: AttributedString {
        if nested, step.name == "Bash" {
            let cmd = step.object.components(separatedBy: "\n").first ?? step.object
            var c = AttributedString(cmd)
            c.font = Font(NSFont.monospacedSystemFont(ofSize: DuoTextStyle.mono.spec.size, weight: .regular))
            guard let what = step.summary else { c.foregroundColor = DuoColor.text; return c }
            var a = AttributedString(what)
            a.font = .system(size: DuoTextStyle.chatMeta.spec.size, weight: .semibold)
            a.foregroundColor = DuoColor.text
            c.foregroundColor = DuoColor.text2
            return a + AttributedString(" ") + c
        }
        // In a run, an MCP tool leads with its server: `**claude-in-chrome** navigate · stripe.com/…` (handoff `tools`).
        let mcp = step.name.components(separatedBy: "__")
        let server = nested && mcp.count >= 3 && mcp[0] == "mcp" ? mcp[1] : nil
        var a = AttributedString(server ?? step.verb)
        a.font = .system(size: DuoTextStyle.chatMeta.spec.size, weight: .semibold)
        a.foregroundColor = DuoColor.text
        if server != nil {
            var x = AttributedString(" " + step.verb + (step.object.isEmpty ? "" : " · ")); x.foregroundColor = DuoColor.text2; a += x
        }
        var obj = AttributedString((server == nil ? " " : "") + step.object)
        switch step.objectKind {
        case .path, .url:
            obj = AttributedString(" ")
            let first = step.others.isEmpty ? step.object : String(step.object.prefix { $0 != "," })
            for (i, part) in ([(first, step.path)] + step.others).enumerated() {
                if i > 0 { var sep = AttributedString(", "); sep.foregroundColor = DuoColor.text2; obj += sep }
                var link = AttributedString(part.0)
                link.foregroundColor = DuoColor.text
                link.underlineStyle = Text.LineStyle(pattern: .solid, color: DuoColor.controlEdge)
                if step.objectKind == .path, let p = part.1 { link.link = ChatMarkdown.fileURL(p) }
                if step.objectKind == .url, let u = part.1.flatMap(URL.init(string:)) { link.link = u }
                obj += link
            }
        case .code:
            obj.font = Font(NSFont.monospacedSystemFont(ofSize: DuoTextStyle.mono.spec.size, weight: .regular))
            obj.foregroundColor = DuoColor.text2
        case .quoted, .plain:
            obj.foregroundColor = DuoColor.text2
        }
        a += obj
        if let ag = step.agent {
            // `Agent Survey cross-check · finished · 2m 14s · 18 tool uses` (handoff `agents`).
            var parts = [ag.finished ? "finished" : (ag.background ? "running in the background" : "running")]
            if let t = ag.seconds { parts.append(t >= 60 ? "\(t / 60)m \(t % 60)s" : "\(t)s") }
            if ag.finished, let n = ag.toolUses { parts.append("\(n) tool use\(n == 1 ? "" : "s")") }
            var x = AttributedString(" · " + parts.joined(separator: " · ")); x.foregroundColor = DuoColor.text2; a += x
            return a
        }
        if let d = step.detail { var x = AttributedString(" · " + d); x.foregroundColor = DuoColor.text2; a += x }
        if step.status == .needsYou { return a }
        if let n = step.adds, n > 0 { var x = AttributedString(" +\(n)"); x.foregroundColor = DuoColor.diffAddText; a += x }
        if let n = step.dels, n > 0 { var x = AttributedString(" −\(n)"); x.foregroundColor = DuoColor.diffDelText; a += x }
        return a
    }

    @ViewBuilder var trailing: some View {
        switch step.status {
        case .needsYou: Text("needs you").duoText(.chatMeta, weight: .semibold).foregroundStyle(DuoColor.needsYou)
        case .failed(let exit): Text(exit.map { "failed · exit \($0)" } ?? "failed").duoText(.chatMeta).foregroundStyle(DuoColor.diffDelText)
        case .declined: Text("not allowed").duoText(.chatMeta).foregroundStyle(DuoColor.text2)
        case .interrupted: Text("interrupted").duoText(.chatMeta).foregroundStyle(DuoColor.text2)
        case _ where agentRunning:
            Text("Manage in Terminal…").duoText(.chatMeta).foregroundStyle(DuoColor.text).underline(color: DuoColor.controlEdge)
                .onActivate { model.handOver(chat.key, "Manage Claude’s agents here (↓ opens them). Chat comes back after.") }  // action: session chat
        default:
            Text(open ? "⌄" : "›").duoText(.chatMeta).foregroundStyle(DuoColor.text2)
        }
    }

    @ViewBuilder var stepBody: some View {
        if failed {
            Text(step.error ?? "").duoText(.chatDiff).foregroundStyle(DuoColor.diffDelText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 7, leading: 11, bottom: 7, trailing: 11))
                .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody).strokeBorder(DuoColor.toolErrorEdge, lineWidth: DuoMetric.borderHairline))
                .textSelection(.enabled)
        } else if let diff = step.diff {
            ChatDiffView(lines: diff, cut: (step.id, chat))
        } else if let out = step.output {
            ChatOutputView(id: step.id, lines: out, chat: chat)
        } else if let agent = step.agent {
            ChatAgentBox(agent: agent, chat: chat)
        } else if let preview = step.preview, !preview.isEmpty {
            Text(preview.joined(separator: "\n")).duoText(.chatDiff).foregroundStyle(DuoColor.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                .background(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody).fill(DuoColor.toolOutputFill))
                .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody).strokeBorder(DuoColor.selected, lineWidth: DuoMetric.borderHairline))
        }
    }
}

/// An edit's diff: line numbers, `diffDel` and `diffAdd` fills.
struct ChatDiffView: View {
    let lines: [ChatDiffLine]
    var framed = true
    /// In the chat, a long diff shows its first 12 lines and `Show n more lines` (DL-135).
    var cut: (id: String, chat: ChatSession)?
    static let shown = 12

    var hidden: Int {
        guard let cut, !cut.chat.ui.fullOutput.contains(cut.id) else { return 0 }
        return max(0, lines.count - Self.shown)
    }

    var body: some View {
        if hidden > 0, let cut {
            VStack(alignment: .leading, spacing: 4) {
                ChatDiffView(lines: Array(lines.prefix(Self.shown)), framed: framed)
                Text("Show \(hidden) more line\(hidden == 1 ? "" : "s")").duoText(.chatMeta, lineHeight: DuoTextStyle.chatDiff.spec.lineHeight).foregroundStyle(DuoColor.text)
                    .underline(color: DuoColor.controlEdge)
                    .onActivate { cut.chat.ui.fullOutput.insert(cut.id) }  // not an action: shows more of what's drawn
            }
        } else if framed {
            // CSS draws the border outside the rows: 1 pt more each side than strokeBorder.
            rows.clipShape(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody)).padding(DuoMetric.borderHairline)
                .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody).strokeBorder(DuoColor.selected, lineWidth: DuoMetric.borderHairline))
        } else { rows }
    }

    var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(l.number.map(String.init) ?? "").foregroundStyle(DuoColor.controlEdge).frame(width: 28, alignment: .trailing)
                    Text((l.kind == .add ? "+ " : l.kind == .del ? "− " : "") + l.text)
                        .foregroundStyle(l.kind == .add ? DuoColor.diffAddText : l.kind == .del ? DuoColor.diffDelText : DuoColor.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .duoText(.chatDiff)
                .padding(EdgeInsets(top: i == 0 ? 2 : 0, leading: 0, bottom: i == lines.count - 1 || (i == 0 && l.kind == .context) ? 2 : 0, trailing: 10))
                .background(l.kind == .add ? DuoColor.diffAddFill : l.kind == .del ? DuoColor.diffDelFill : .clear)
            }
        }
        .textSelection(.enabled)
    }
}

/// A command and its output, long output cut with `Show n more lines`.
struct ChatOutputView: View {
    let id: String
    let lines: [String]
    let chat: ChatSession
    static let shown = 3

    var body: some View {
        let all = chat.ui.fullOutput.contains(id)
        let visible = all ? lines : Array(lines.prefix(Self.shown))
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.offset) { i, l in
                Text(l).duoText(.chatDiff).foregroundStyle(i == 0 && l.hasPrefix("$ ") ? DuoColor.text2 : DuoColor.text)
                    .lineLimit(1).truncationMode(.tail)
            }
            if !all, lines.count > Self.shown {
                let n = lines.count - Self.shown
                Text("Show \(n) more line\(n == 1 ? "" : "s")").duoText(.chatMeta, lineHeight: DuoTextStyle.chatDiff.spec.lineHeight).foregroundStyle(DuoColor.text)
                    .underline(color: DuoColor.controlEdge)
                    .padding(.top, 4)
                    .onActivate { chat.ui.fullOutput.insert(id) }  // not an action: shows more of what's drawn
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 6 + 1, leading: 10 + 1, bottom: 6 + 1, trailing: 10 + 1))
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody).fill(DuoColor.toolOutputFill))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody).strokeBorder(DuoColor.selected, lineWidth: DuoMetric.borderHairline))
    }
}

/// A background agent: its final message, time and tool count; the agents manager is the TUI's.
struct ChatAgentBox: View {
    @Environment(AppModel.self) private var model
    let agent: ChatAgentResult
    let chat: ChatSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !agent.message.isEmpty {
                Text(ChatMarkdown.inline(agent.message)).duoText(.body).foregroundStyle(DuoColor.text).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Text(summary).duoText(.chatMeta).foregroundStyle(DuoColor.text2)
                Spacer(minLength: 8)
                Button("Manage in Terminal…") { model.handOver(chat.key, "Manage Claude’s agents here (↓ opens them). Chat comes back after.") }  // action: session chat
                    .buttonStyle(.duo)
            }
        }
        .padding(EdgeInsets(top: 9, leading: 13, bottom: 9, trailing: 13))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody).strokeBorder(DuoColor.selected, lineWidth: DuoMetric.borderHairline))
    }

    var summary: String {
        var parts = [agent.finished ? "Finished" : "Running"]
        if let s = agent.seconds { parts.append(s >= 60 ? "\(s / 60)m \(s % 60)s" : "\(s)s") }
        if let n = agent.toolUses { parts.append("\(n) tool use\(n == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}

extension AppModel {
    /// A link in the chat: a file opens in Duo's editor (at its line); a web link as Duo opens links.
    public func openChatLink(_ url: URL, cwd: String?) {
        guard url.scheme == "duo-file" else { return openLink(url.absoluteString) }
        var path = (url.path as NSString).expandingTildeInPath
        if !path.hasPrefix("/"), let base = cwd ?? projectFolder?.path { path = (base as NSString).appendingPathComponent(path) }
        let line = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "line" }?.value.flatMap(Int.init)
        let file = URL(fileURLWithPath: path).standardizedFileURL
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        guard let tab = openFile(at: file) else { NSWorkspace.shared.open(file); return }
        if let line { editor.revealLine(tab: tab, line: line) }
    }

    /// Chat hands the terminal over for something only the TUI does (Amend, the agents manager).
    public func handOver(_ key: String, _ message: String) {
        guard let c = chat(for: key) else { return }
        c.fallBack(.handedOver(message))
        focusTerminal(key)
    }
}

extension EditorController {
    /// Selects a line once `tab` is the open document (a file link in chat: `flows.md:42`).
    func revealLine(tab: String, line: Int, tries: Int = 20) {
        let path = AppModel.isOutsideFile(tab) ? String(tab.dropFirst(AppModel.outsideFilePrefix.count)) : tab
        guard url?.path.hasSuffix("/" + path) == true || url?.path == path else {
            if tries > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { MainActor.assumeIsolated { self.revealLine(tab: tab, line: line, tries: tries - 1) } } }
            return
        }
        run("return window.duo && duo.selectLines ? duo.selectLines(a, a) : false", ["a": line]) { ok in
            if ok == nil, tries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { MainActor.assumeIsolated { self.revealLine(tab: tab, line: line, tries: tries - 1) } }
            }
        }
    }
}
