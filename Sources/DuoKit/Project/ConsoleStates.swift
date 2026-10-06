import AppKit
import DuoControl
import SwiftUI

/// What the console says when there's no terminal to show (surfaces-handoff DB-3): one layout
/// for every case, in Duo's own type at the top left of the dark pane.
public enum ConsoleEmpty: Equatable, Sendable {
    /// History exists: resume the last session first, or start fresh.
    case noneOpen(project: String, last: String?, lastKey: String?)
    /// Nothing has run in this project, or in this folder that isn't one (DL-110).
    case never(project: String, isFolder: Bool)
    /// Claude Code isn't installed, or Duo couldn't find it.
    case notFound
    /// The session is live in another app (LR-8): explain, offer a fork, never end it.
    case elsewhere(session: String, sessionId: String, app: String, since: String?)
    /// The session's folder is gone (LR-18).
    case folderMissing(path: String, nearest: String)
    /// The Home pane with no session (DL-54: only after the last Home tab closes).
    case homeNone
    /// No Home folder chosen yet (DL-84): sessions are all listed on the map; Home waits.
    case noHome

    var title: String {
        switch self {
        case .noneOpen(let p, _, _): "No session open in \(p)"
        case .never(let p, _): "No session in \(p)"
        case .notFound: "Duo can't find Claude Code"
        case .elsewhere(let s, _, let app, _): "\(s) is open in \(app)"
        case .folderMissing: "This session's folder is missing"
        case .homeNone: "No Home session"
        case .noHome: "Choose a Home folder"
        }
    }

    var body: String {
        switch self {
        case .noneOpen: "Pick up where you left off, or start fresh in this folder."
        case .never(_, let isFolder): "Nothing has run in this \(isFolder ? "folder" : "project") yet."
        case .notFound: "It looked in the usual install folders and on your login shell's PATH. Install Claude Code, or point Duo at it in Settings."
        case .elsewhere(_, _, _, let since):
            "It has been running there\(since.map { " since \($0)" } ?? ""), so Duo won't start a second copy of it. Finish there and look again, or carry on here as a fork: a new session with the same history."
        case .folderMissing(let path, let nearest): "\(path). Starting it will use the nearest folder that still exists, \(nearest)."
        case .homeNone: "Home is where asks get sorted and sent to projects."
        case .noHome: "Every Claude Code session on this Mac is already on the map, grouped by the folder it ran in. Home is the folder for the projects you track: Duo keeps their columns first, and Home's own session sorts what comes in."
        }
    }
}

extension AppModel {
    /// The console's message for a project with no terminal to show, or nil when one is showing.
    public func consoleEmpty(project: String) -> ConsoleEmpty? {
        if let forced = fixtureConsole { return forced }
        if terminalsMode == .live, ClaudeLocator.resolve() == nil { return .notFound }
        if let key = consoleTab, let s = fixture.sessions(inProject: project).first(where: { $0.tabKey == key }), let id = s.sessionId {
            if liveElsewhere.contains(id) {
                let b = Beacon.readAll().first { $0.sessionId == id }
                return .elsewhere(session: s.name, sessionId: id, app: b.map { AppOwning.name(ofPID: $0.pid) } ?? "another app",
                                  since: b.flatMap { AppOwning.started(pid: $0.pid) })
            }
            return nil
        }
        if let folder = liveFolders[project], !FileManager.default.fileExists(atPath: folder.path) {
            var near = folder.deletingLastPathComponent()
            while !FileManager.default.fileExists(atPath: near.path), near.path != "/" { near.deleteLastPathComponent() }
            return .folderMissing(path: folder.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"),
                                  nearest: near.lastPathComponent)
        }
        // Resume offers the most recently used session (it offered the first listed, F-67).
        let past = fixture.sessions(inProject: project).sorted { WaitTime($0.wait) < WaitTime($1.wait) }
        if let last = past.first {
            return .noneOpen(project: project, last: last.name, lastKey: last.tabKey)
        }
        return .never(project: project, isFolder: fixture.projects.first { $0.name == project }?.isFolderOnly == true)
    }

    /// Resume as a Fork (DB-3): a new session with the same history, here, under a Duo-minted id.
    public func resumeAsFork(_ sessionId: String, in project: String) {
        guard let folder = liveFolders[project] else { return }
        let new = UUID().uuidString.lowercased()
        var index = SessionIndex.load(project: folder)
        index.sessions.append(.init(sessionId: new, provenance: "forked-from:\(sessionId)"))
        try? index.save(project: folder)
        _ = terminals.session(new, command: .forkClaude(from: sessionId, sessionID: new), cwd: folder.path)
        consoleTab = new
        refreshLive()
    }

    /// The ended bar's Resume: the same tab, the session resumed (DB-3).
    public func resumeEnded(_ key: String) {
        terminals.forget(key)
        endedRevision += 1
        if let project = currentProject?.name { _ = terminal(project: project, session: key) }
    }
}

/// The owning app of a process, for "open in ‹app›" (DB-3), and when it started.
enum AppOwning {
    static func name(ofPID pid: Int32) -> String {
        var p = pid
        for _ in 0..<12 {
            if let app = NSRunningApplication(processIdentifier: p), let n = app.localizedName { return n }
            let parent = ppid(p)
            if parent <= 1 { break }
            p = parent
        }
        return "another app"
    }

    static func ppid(_ pid: Int32) -> Int32 {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return 0 }
        return info.kp_eproc.e_ppid
    }

    static func started(pid: Int32) -> String? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let t = info.kp_proc.p_un.__p_starttime
        let d = Date(timeIntervalSince1970: TimeInterval(t.tv_sec))
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(d) ? "H:mm" : "MMM d, H:mm"
        return f.string(from: d)
    }
}

/// A button on the console (DB-3): the standard size and radius, 1 `consoleText2` border, no fill.
struct ConsoleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .duoText(.control)
            .foregroundStyle(DuoColor.consoleText)
            .lineLimit(1)
            .padding(.horizontal, DuoSpace.buttonPadding.leading + DuoMetric.borderHairline)
            .padding(.vertical, DuoSpace.buttonPadding.top + DuoMetric.borderHairline)
            .background(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).fill(configuration.isPressed ? DuoColor.consoleText2.opacity(0.2) : .clear))
            .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).strokeBorder(DuoColor.consoleText2, lineWidth: DuoMetric.borderHairline))
            .contentShape(Rectangle())
    }
}

/// The message itself: title 13 semibold, body 13/20 `consoleText2` (440 wide at most), buttons.
struct ConsoleMessage: View {
    @Environment(AppModel.self) private var model
    let state: ConsoleEmpty
    var inHome = false

    var body: some View {
        VStack(alignment: .leading, spacing: DuoMetric.consoleMessageGap) {
            Text(state.title).duoText(.bodyEmphasis).foregroundStyle(DuoColor.consoleText)
            Text(state.body).duoText(.body).foregroundStyle(DuoColor.consoleText2)
                .frame(maxWidth: inHome ? 300 : DuoMetric.consoleMessageMaxTextWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) { buttons }
                .buttonStyle(ConsoleButtonStyle())
                .padding(.top, DuoMetric.consoleMessageButtonsTop)
            if state == .noHome {
                Text("You can choose one later from File › Choose Home Folder….").duoText(.control).foregroundStyle(DuoColor.consoleText2)
                    .padding(.top, 14)
            }
        }
        .padding(inHome ? DuoMetric.consoleMessagePaddingHome
                 : EdgeInsets(top: DuoMetric.consoleMessagePadding, leading: DuoMetric.consoleMessagePadding,
                              bottom: DuoMetric.consoleMessagePadding, trailing: DuoMetric.consoleMessagePadding))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder var buttons: some View {
        switch state {
        case .noneOpen(let project, let last, let key):
            if let last, let key {
                Button("Resume \(last)") { model.openConsoleTab(key) }.keyboardShortcut(.defaultAction)
            }
            Button("Start Claude here") { model.open(project: project); model.newSession() }
        case .never(let project, _):
            Button("Start Claude here") { model.open(project: project); model.newSession() }.keyboardShortcut(.defaultAction)
        case .notFound:
            Button("Open Settings…") { model.info("Settings isn't built yet: it's waiting on its design (DB-10). Install Claude Code, then Look Again.") }
            Button("Look Again") { ClaudeLocator.forget(); model.refreshLive(); model.endedRevision += 1 }.keyboardShortcut(.defaultAction)
        case .elsewhere(_, let id, _, _):
            Button("Look Again") { model.refreshLive() }.keyboardShortcut(.defaultAction)
            Button("Resume as a Fork") { if let p = model.currentProject?.name { model.resumeAsFork(id, in: p) } }
        case .folderMissing(_, let nearest):
            Button("Start in \(nearest)") { model.newSession() }.keyboardShortcut(.defaultAction)
            Button("Locate Folder…") { model.info("Locating a moved folder is waiting on its design (DB-8).") }
        case .noHome:
            Button("Choose Home Folder…") { model.chooseHomeFolder() }.keyboardShortcut(.defaultAction)
            Button("Not Now") { model.dismissHomePrompt() }
        case .homeNone:
            Button("Start Claude in Home") { if let h = model.fixture.home?.name { model.homeTab = model.newSession(in: h) } }
                .keyboardShortcut(.defaultAction)
        }
    }
}

/// Under a session that has ended (DB-3): what happened, Resume (the default) and Close Tab. For a
/// shell that failed (DB-4): New Shell and Close Tab.
struct ConsoleEndedBar: View {
    @Environment(AppModel.self) private var model
    let key: String
    let message: String
    let shell: Bool

    init(session: TerminalSession, name: String) {
        key = session.key
        if case .shell = session.command { shell = true } else { shell = false }
        let at = session.ended.map { DateFormatter.localizedString(from: $0.at, dateStyle: .none, timeStyle: .short) } ?? ""
        let status = session.ended?.status ?? 0
        message = shell ? "The shell exited with an error (exit \(status))."
            : status != 0 ? "Claude quit unexpectedly at \(at) (exit \(status))." : "\(name) ended at \(at)."
    }

    init(key: String, message: String, shell: Bool = false) { self.key = key; self.message = message; self.shell = shell }

    var body: some View {
        VStack(spacing: 0) {
            ConsoleRule()
            HStack(spacing: 10) {
                Text(message).duoText(.body).foregroundStyle(DuoColor.consoleText).lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    if shell { Button("New Shell") { model.newShell() } }
                    else { Button("Resume") { model.resumeEnded(key) }.keyboardShortcut(.defaultAction) }
                    Button("Close Tab") { if model.isShell(key) { model.closeShell(key) } else { model.closeSession(key) } }
                }
                .buttonStyle(ConsoleButtonStyle())
            }
            .padding(.horizontal, DuoMetric.consoleBarPadding)
            .frame(height: DuoMetric.consoleBarHeight - DuoMetric.borderHairline)
        }
        .background(DuoColor.console)
    }
}

extension AppModel {
    /// A console tab's title: the session's name, or a shell's command (DB-4).
    public func consoleTitle(_ key: String) -> String {
        fixture.sessions.first { $0.tabKey == key }?.name ?? shellTitles[key] ?? "zsh"
    }
}
