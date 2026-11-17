import AppKit
import DuoControl
import Foundation

// The Getting started with Duo card's actions (DL-348): the ticks the real actions send, Show me, and what
// Help › Getting Started and `duo2 getting-started` do. The card's state is `GettingStarted.shared`.

extension AppModel {
    // MARK: Ticks

    /// A project was opened or made (step 1). Home and plain folders aren't "a project" the user made or opened.
    func tickGettingStarted(project name: String, folder: URL? = nil) {
        guard GettingStarted.shared.state != nil,
              let p = fixture.projects.first(where: { $0.name == name }) ?? (folder == nil ? nil : Fixture.Project(name: name, path: folder!.path, goal: "")),
              p.isHome != true, !p.isFolderOnly else { return }
        let path = folder?.path ?? liveFolders[name]?.path ?? p.path
        GettingStarted.shared.tick(.project, detail: "\(name) · \(Self.tilde(path))")
    }

    /// A Claude session was started (step 2), in chat or terminal. The line keeps its first name and its mode.
    func tickGettingStarted(session id: String, name: String?) {
        guard GettingStarted.shared.state != nil else { return }
        let mode = ChatPrefs.load().mode(for: id) == .chat ? "chat" : "terminal"
        GettingStarted.shared.tick(.session, detail: "\(mode)|\(name ?? "")")
    }

    /// The steps already done on an install that never had the card, seen from what Duo lists now (Help › Getting Started).
    var gettingStartedInferred: [GettingStartedStep: String] {
        var out: [GettingStartedStep: String] = [:]
        if let p = fixture.projects.first(where: { $0.isHome != true && !$0.isFolderOnly }) { out[.project] = "\(p.name) · \(Self.tilde(liveFolders[p.name]?.path ?? p.path))" }
        if !fixture.sessions.isEmpty { out[.session] = "\(ChatPrefs.load().last == .chat ? "chat" : "terminal")|" }
        if let t = (fixture.tasks ?? []).first { out[.task] = "\(t.title) · \(t.project)" }
        return out
    }

    // MARK: Help › Getting Started, Hide, Undo, Done

    /// Help › Getting Started, `duo2 getting-started show`: All projects, with the card.
    public func showGettingStarted() {
        GettingStarted.shared.show(inferred: gettingStartedInferred)
        if !altitude.isAllProjects { zoomOut() }
    }

    /// What `duo2 getting-started state` prints.
    public var gettingStartedReport: String {
        let g = GettingStarted.shared
        guard let s = g.state else { return "Not started on this install. `duo2 getting-started show` brings the card." }
        let lines = GettingStartedStep.allCases.map { step -> String in
            let detail = s.ticks[step.rawValue].map { GettingStartedWords.line(step, detail: $0) }
            return "  \(step.rawValue): " + (detail.map { "done · \($0)" } ?? "not yet")
        }
        return (["Getting started: \(s.phase.rawValue), \(s.count) of 3."] + lines).joined(separator: "\n")
    }

    // MARK: Show me (B3)

    /// The project Show me goes into: the one on screen, else the one last used, else Home.
    private var showMeProject: String? {
        if let p = currentProject, !p.isFolderOnly { return p.name }
        if let p = listSelectedProject ?? boardFocusedProject, fixture.projects.contains(where: { $0.name == p && !$0.isFolderOnly }) { return p }
        if let s = fixture.sessions.first(where: { s in fixture.projects.contains { $0.name == s.project && !$0.isFolderOnly } }) { return s.project }
        return fixture.projects.first(where: { !$0.isFolderOnly })?.name
    }

    /// Show me on a step: takes you where the control is and opens its explainer there. Esc closes it and
    /// goes back to where you were (B3). It never starts or changes anything but a first session, when step 2
    /// has none to show.
    public func gettingStartedShowMe(_ step: GettingStartedStep) {
        switch step {
        case .project:
            explainOpen(.projects)
        case .session:
            guard let name = showMeProject else { return info("Make a project first, then Show me has a session to point at.") }
            let was = altitude
            if currentProject?.name != name { open(project: name) }
            if fixture.liveSessions(inProject: name).isEmpty && tabSessions(inProject: name).isEmpty, let sid = newSession(in: name) { consoleTab = sid }
            if was.isAllProjects { explainer.onEscape = { [weak self] in self?.zoomOut() } }
            // The pill is drawn once the tab is; give the layout a beat.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in MainActor.assumeIsolated { self?.explainOpen(.modes) } }
        case .task:
            guard let name = showMeProject else { return info("Make a project first, then Show me has tasks to point at.") }
            let was = altitude
            if currentProject?.name != name { open(project: name) }
            if was.isAllProjects { explainer.onEscape = { [weak self] in self?.zoomOut() } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in MainActor.assumeIsolated { self?.explainOpen(.tasks) } }
        }
    }
}

/// The card's words for a ticked step (B2): what was done.
public enum GettingStartedWords {
    /// The line under a ticked step's name.
    public static func line(_ step: GettingStartedStep, detail: String) -> String {
        switch step {
        case .project, .task:
            return detail
        case .session:
            let parts = detail.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let chat = parts.first == "chat"
            let name = parts.count > 1 ? parts[1] : ""
            let where_ = chat ? "in Chat. Terminal is one click on its tab." : "in Terminal. Chat is one click on its tab."
            return name.isEmpty ? "Started \(where_)" : "“\(name)” · \(where_)"
        }
    }
}
