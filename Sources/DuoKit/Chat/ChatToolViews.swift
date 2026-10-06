import AppKit
import SwiftUI

// Tool steps on a dotted thread at the top of Claude's card (chat-mode-handoff `tools`): a bold
// verb and its object (files are links), a small open dot; Read, Search and Fetch fold to one line;
// an edit opens to its diff, a command to its output; a failed tool says so in `diffDelText`.

struct ChatToolThread: View {
    let steps: [ChatToolStep]
    let chat: ChatSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(steps) { s in ChatToolStepView(step: s, chat: chat) }
        }
        .padding(.leading, 6)
        .background(alignment: .leading) {
            DottedLine().stroke(DuoColor.controlEdge, style: StrokeStyle(lineWidth: 1.5, dash: [1.5, 2.5]))
                .frame(width: 1.5).padding(.leading, 6)
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

    /// A step waiting on you stays folded: the card below shows what's asked.
    var open: Bool { step.status != .needsYou && step.foldsByDefault == chat.ui.toggled.contains(step.id) }
    var failed: Bool { if case .failed = step.status { return true }; return false }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                dot
                Text(title).duoText(.chatMeta).foregroundStyle(DuoColor.text2).lineLimit(2)
                Spacer(minLength: 8)
                trailing
            }
            .frame(minHeight: 24)
            .padding(.leading, -5)
            .contentShape(Rectangle())
            .onActivate { chat.ui.toggled.formSymmetricDifference([step.id]) }  // not an action: a fold
            .accessibilityElement(children: .combine)
            if open || failed { stepBody.padding(EdgeInsets(top: 2, leading: 18, bottom: 8, trailing: 0)) }
        }
    }

    @ViewBuilder var dot: some View {
        if step.status == .needsYou {
            Circle().fill(DuoColor.needsYou).frame(width: 10, height: 10).padding(.leading, 1.5)
        } else {
            Circle().strokeBorder(failed ? DuoColor.diffDelText : DuoColor.controlEdge, lineWidth: 1.5)
                .background(Circle().fill(DuoColor.pane))
                .frame(width: 10, height: 10).padding(.leading, 1.5)
        }
    }

    /// `**Read** research/interviews.md · 214 lines`, as one attributed line.
    var title: AttributedString {
        var a = AttributedString(step.verb)
        a.font = .system(size: DuoTextStyle.chatMeta.spec.size, weight: .semibold)
        a.foregroundColor = DuoColor.text
        var obj = AttributedString(" " + step.object)
        switch step.objectKind {
        case .path, .url:
            obj = AttributedString(" ")
            var link = AttributedString(step.object)
            link.foregroundColor = DuoColor.text
            link.underlineStyle = Text.LineStyle(pattern: .solid, color: DuoColor.controlEdge)
            if step.objectKind == .path, let p = step.path { link.link = ChatMarkdown.fileURL(p) }
            if step.objectKind == .url, let u = step.path.flatMap(URL.init(string:)) { link.link = u }
            obj += link
        case .code:
            obj.font = Font(NSFont.monospacedSystemFont(ofSize: DuoTextStyle.mono.spec.size, weight: .regular))
            obj.foregroundColor = DuoColor.text2
        case .quoted, .plain:
            obj.foregroundColor = DuoColor.text2
        }
        a += obj
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
        default:
            Text(open ? "⌄" : "›").duoText(.chatMeta).foregroundStyle(DuoColor.text2)
        }
    }

    @ViewBuilder var stepBody: some View {
        if failed {
            Text(step.error ?? "").duoText(.chatDiff).foregroundStyle(DuoColor.diffDelText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody).strokeBorder(DuoColor.toolErrorEdge, lineWidth: DuoMetric.borderHairline))
                .textSelection(.enabled)
        } else if let diff = step.diff {
            ChatDiffView(lines: diff)
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
    var body: some View {
        if framed {
            rows.clipShape(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody))
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
                .padding(EdgeInsets(top: i == 0 ? 2 : 0, leading: 0, bottom: i == lines.count - 1 ? 2 : 0, trailing: 10))
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
                Text("Show \(n) more line\(n == 1 ? "" : "s")").duoText(.chatMeta).foregroundStyle(DuoColor.text)
                    .underline(color: DuoColor.controlEdge)
                    .padding(.top, 4)
                    .onActivate { chat.ui.fullOutput.insert(id) }  // not an action: shows more of what's drawn
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
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
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
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
