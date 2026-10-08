import AppKit
import SwiftUI

// Chat mode's chrome (chat-mode-handoff `toggle`, `fallback`): the Terminal / Chat pill at the
// right end of the console tab strip, and the bar over the terminal when chat hands it over.

/// `>_`, 13×10 (handoff `toggle`).
struct TerminalMark: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 13, sy = r.height / 10
        var p = Path()
        p.move(to: .init(x: 1.5 * sx, y: 2 * sy)); p.addLine(to: .init(x: 5 * sx, y: 5 * sy)); p.addLine(to: .init(x: 1.5 * sx, y: 8 * sy))
        p.move(to: .init(x: 6.5 * sx, y: 8.5 * sy)); p.addLine(to: .init(x: 11.5 * sx, y: 8.5 * sy))
        return p
    }
}

/// A chat bubble, 13×11 (handoff `toggle`): a rounded box (1,1)–(12,8), r 1.5, its tail at the bottom left.
struct ChatBubbleMark: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 13, sy = r.height / 11
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { .init(x: x * sx, y: y * sy) }
        var p = Path()
        p.move(to: pt(2.5, 1)); p.addLine(to: pt(10.5, 1))
        p.addQuadCurve(to: pt(12, 2.5), control: pt(12, 1))
        p.addLine(to: pt(12, 6.5))
        p.addQuadCurve(to: pt(10.5, 8), control: pt(12, 8))
        p.addLine(to: pt(6, 8)); p.addLine(to: pt(3.5, 10)); p.addLine(to: pt(3.5, 8)); p.addLine(to: pt(2.5, 8))
        p.addQuadCurve(to: pt(1, 6.5), control: pt(1, 8))
        p.addLine(to: pt(1, 2.5))
        p.addQuadCurve(to: pt(2.5, 1), control: pt(1, 1))
        p.closeSubpath()
        return p
    }
}

/// The pill: two icon segments, 26×20 each, in a 1 pt `tuiInputBorder` box (handoff `toggle`).
/// It belongs to the selected Claude tab; a shell tab doesn't show it.
struct ChatToggle: View {
    @Environment(AppModel.self) private var model
    let key: String
    /// On the thin light strip over chat (DL-136): white, `controlEdge`, the shown one on `selected`, 22×16.
    var light = false

    var body: some View {
        let chat = model.chat(for: key)
        let showing: ChatViewMode = chat?.showsChat == true ? .chat : .terminal
        HStack(spacing: 0) {
            segment(.terminal, on: showing == .terminal) {
                TerminalMark().stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)).frame(width: 13, height: 10)
            }
            segment(.chat, on: showing == .chat) {
                ChatBubbleMark().stroke(style: StrokeStyle(lineWidth: 1.3, lineJoin: .round)).frame(width: 13, height: 11)
            }
        }
        // The light one's border is outside its segments (`bar-thin`: 22×16 inside a 1 border).
        .padding(light ? DuoMetric.borderHairline : 0)
        .background(light ? DuoColor.pane : .clear)
        .clipShape(RoundedRectangle(cornerRadius: DuoMetric.radiusControl))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).strokeBorder(light ? DuoColor.controlEdge : DuoColor.tuiInputBorder, lineWidth: DuoMetric.borderHairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show session as")
    }

    func segment(_ mode: ChatViewMode, on: Bool, @ViewBuilder icon: () -> some View) -> some View {
        let title = mode == .chat ? "Chat" : "Terminal"
        return icon()
            .foregroundStyle(light ? (on ? DuoColor.text : DuoColor.text2) : on ? DuoColor.consoleText : DuoColor.consoleText2)
            .frame(width: light ? 22 : 26, height: light ? 16 : 20)
            .background(on ? (light ? DuoColor.selected : DuoColor.consoleRule) : .clear)
            .contentShape(Rectangle())
            .onActivate { model.setChatMode(mode, for: key) }  // action: session chat
            .help(title)
            .accessibilityLabel(title)
            .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The light bar over the terminal when chat hands it over (handoff `fallback`): why, and Back to Chat.
struct ChatFallbackBar: View {
    @Environment(AppModel.self) private var model
    let chat: ChatSession
    let message: String
    var command: String?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Group {
                // The command in mono (`mono` 12 in the bar's 13/20), the rest as it reads (DL-143).
                if let command, message.hasPrefix(command) {
                    Text("\(Text(command).font(Font(NSFont.monospacedSystemFont(ofSize: DuoTextStyle.mono.spec.size, weight: .regular))))\(Text(String(message.dropFirst(command.count))))")
                } else {
                    Text(message)
                }
            }
            .duoText(.body).foregroundStyle(DuoColor.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button("Back to Chat") { model.backToChat(chat.key) }  // action: session chat
                .buttonStyle(.duo)
        }
        .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 12))
        .background(DuoColor.ground)
        .overlay(alignment: .bottom) { DuoColor.rule.frame(height: DuoMetric.borderHairline) }
        .accessibilityElement(children: .contain)
    }
}

extension AppModel {
    /// The selected console tab is a Claude tab showing chat: the strip over it is thin and light (DL-136).
    var consoleShowsChat: Bool {
        guard let key = consoleTab, !isShell(key), let c = chat(for: key) else { return false }
        return c.showsChat
    }

    /// A tab's chat, live or a fixture target's.
    public func chat(for key: String) -> ChatSession? { chats.existing(key) ?? fixtureChats[key] }

    /// The toggle and `duo2 session chat on|off`: the user's choice, kept (DL-119 §5). Switching
    /// sends nothing to the session (Q-53, DL-120).
    public func setChatMode(_ mode: ChatViewMode, for key: String) {
        if let f = fixtureChats[key] { f.mode = mode; f.fallback = nil; return }
        chats.setMode(mode, for: key)
        if let t = terminals.existing(key) { attachChat(t) }
        if mode == .terminal { focusTerminal(key) }
    }

    /// Back to Chat: chat now; a screen it still can't show brings the terminal back after the grace.
    public func backToChat(_ key: String) {
        guard let c = chat(for: key) else { return }
        if c.mode != .chat { return setChatMode(.chat, for: key) }
        c.backToChat()
    }

    /// A chat on screen (ENH-45): Home's tab at All projects, or the console's tab in a project.
    func chatIsShown(_ key: String) -> Bool {
        altitude.isAllProjects ? homeTab == key : consoleTab == key
    }

    /// The chat for a Claude terminal: made on first use, reading that terminal's screen.
    @discardableResult
    public func attachChat(_ t: TerminalSession) -> ChatSession? {
        switch t.command {
        case .shell: return nil
        default: break
        }
        let c = chats.session(t.key, home: isHomeTerminal(t))
        c.isShown = { [weak self, key = t.key] in self?.chatIsShown(key) ?? true }
        if (c.terminal as? LiveChatTerminal)?.view !== t.view { c.attach(LiveChatTerminal(t.view)) }
        // Live sessions are keyed by their id; demo and fixture terminals have no hooks to read.
        if terminalsMode == .live { c.follow(sessionId: t.key, cwd: t.cwd) }
        // The composer hands over through `duo2 compose` when this build has it (F-112).
        if let bin = ChildEnvironment.cliDirectory, ChatComposer.editorCommand(cli: bin + "/duo2") != nil { c.composeDir = ChatComposer.dir }
        c.launchId = t.command.launchId
        if c.cliVersion == nil, let path = ClaudeLocator.resolve() {
            ClaudeVersion.of(path) { [weak c] v in c?.setVersion(v) }
        }
        return c
    }

    /// A Home session's terminal (DL-142 (6)): it runs in Home's folder, or is one of Home's tabs. The
    /// folder decides for one just started, before any snapshot lists it.
    func isHomeTerminal(_ t: TerminalSession) -> Bool {
        guard let h = fixture.home else { return false }
        let folder = liveFolders[h.name]?.path ?? (h.path as NSString).expandingTildeInPath
        let std: (String) -> String = { URL(fileURLWithPath: $0).standardizedFileURL.path }
        return std(t.cwd) == std(folder) || tabSessions(inProject: h.name).contains { $0.tabKey == t.key }
    }

    /// The terminal takes the keyboard again, at its latest line (Q-53).
    func focusTerminal(_ key: String) {
        guard let v = terminals.existing(key)?.view else { return }
        DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
    }
}

/// The console's body for a Claude tab: the chat, or the terminal with the fallback bar over it.
/// The terminal keeps running either way; switching re-parents nothing and restarts nothing.
struct ConsoleChatBody: View {
    @Environment(AppModel.self) private var model
    let chat: ChatSession
    let terminal: TerminalSession?

    var body: some View {
        if chat.showsChat {
            ChatPane(chat: chat)
        } else {
            VStack(spacing: 0) {
                if chat.mode == .chat, let f = chat.fallback { ChatFallbackBar(chat: chat, message: f.message, command: f.command) }
                if let terminal { TerminalSlot(session: terminal) } else { ChatTerminalStandIn(chat: chat) }
            }
        }
    }
}

/// Fixture mode has no live terminal: the targets' terminal is Claude Code's own and exempt from
/// the comparison, so its last read screen stands in, in the terminal's type.
struct ChatTerminalStandIn: View {
    let chat: ChatSession
    var body: some View {
        Text(chat.fixtureScreenText ?? "")
            .font(.system(size: DuoTextStyle.mono.spec.size, design: .monospaced))
            .foregroundStyle(DuoColor.consoleText)
            .lineLimit(nil).fixedSize()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            .clipped()
            .background(DuoColor.console)
    }
}
