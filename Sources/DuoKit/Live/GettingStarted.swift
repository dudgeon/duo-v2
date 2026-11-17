import Foundation
import Observation

// Duo's first-run welcome (DL-348, first-run-welcome-handoff): the Getting started with Duo card at the top
// of All projects. Three optional steps tick on the real action, wherever it happens (a Duo button, ⌘T,
// duo2, Claude's own start through Duo's funnels). The card's state is Duo's (state.json), never a file the
// user owns. App state is an @Observable class (DL-30).

/// The card's three steps, in the order it teaches them. The director is a line, not a step (DL-348 (3)).
public enum GettingStartedStep: String, Codable, Sendable, CaseIterable {
    case project, session, task
}

/// What the card has recorded: where it is (showing, hidden, done) and, per ticked step, what was done.
public struct GettingStartedState: Codable, Sendable, Equatable {
    public enum Phase: String, Codable, Sendable { case showing, hidden, done }
    public var phase: Phase = .showing
    /// A ticked step and the line that says what was done (B2): the project and its folder, the session
    /// and its mode, the task and its project. A tick is kept; it never un-ticks.
    public var ticks: [String: String] = [:]

    public init(phase: Phase = .showing, ticks: [String: String] = [:]) { self.phase = phase; self.ticks = ticks }

    public func ticked(_ step: GettingStartedStep) -> Bool { ticks[step.rawValue] != nil }
    public var count: Int { GettingStartedStep.allCases.filter { ticked($0) }.count }
    public var allDone: Bool { count == GettingStartedStep.allCases.count }
}

/// What Duo's folder says about a new install (F-673): neither `chat.json` nor `state.json`.
public enum NewInstall {
    public static func detect(support: URL = DuoPaths.support) -> Bool {
        let fm = FileManager.default
        return !fm.fileExists(atPath: support.appending(path: "chat.json").path) && !fm.fileExists(atPath: support.appending(path: "state.json").path)
    }
}

/// The one card for the app (every window shows the same), kept in `state.json`.
@MainActor @Observable public final class GettingStarted {
    public static let shared = GettingStarted()

    /// nil: this install never had the card (an existing install); Help › Getting Started starts it.
    public private(set) var state: GettingStartedState?
    /// The Hide notice with Undo is up (8 s, DL-147's notice).
    public private(set) var noticeOpen = false
    /// The card's drawn width, so a narrow window drops the poster (Q-593).
    public var cardWidth: CGFloat = 0
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var url: URL = DuoPaths.state
    /// How long Hide's Undo stays (board B2).
    static let noticeFor: Duration = .seconds(8)

    public init(url: URL = DuoPaths.state) {
        self.url = url
        state = DuoState.load(url).gettingStarted
    }

    /// The card is on screen: showing, on a new install or after Help › Getting Started.
    public var visible: Bool { state?.phase == .showing }
    public var allDone: Bool { state?.allDone ?? false }
    public func ticked(_ step: GettingStartedStep) -> Bool { state?.ticked(step) ?? false }
    public func detail(_ step: GettingStartedStep) -> String? { state?.ticks[step.rawValue] }
    public var count: Int { state?.count ?? 0 }

    /// A new install gets the card once, at its first live launch, before anything else writes `state.json`.
    /// Writes `chat.json` first through ChatPrefs (so the chat default for a new install, DL-339, still sees
    /// no `state.json`), then the card. Returns whether this was a new install.
    @discardableResult
    public static func seedIfNewInstall(support: URL = DuoPaths.support) -> Bool {
        guard NewInstall.detect(support: support) else { return false }
        _ = ChatPrefs.load(support.appending(path: "chat.json"), state: support.appending(path: "state.json"))
        DuoState.update(support.appending(path: "state.json")) { $0.gettingStarted = GettingStartedState() }
        if support == DuoPaths.support { shared.reload() }
        return true
    }

    public func reload() { state = DuoState.load(url).gettingStarted }

    /// A step's real action happened. Ticks only while the card is on (showing) or hidden: a card that
    /// is Done, or never started, records nothing. Idempotent, and never un-ticks.
    public func tick(_ step: GettingStartedStep, detail: String) {
        guard var s = state, s.phase != .done, !s.ticked(step) else { return }
        s.ticks[step.rawValue] = detail
        save(s)
    }

    /// Hide (B2): the card goes, a notice with Undo stays 8 s. Duo's state says hidden at once.
    public func hide() {
        guard var s = state, s.phase == .showing else { return }
        s.phase = .hidden
        save(s)
        noticeOpen = true
        noticeTask?.cancel()
        noticeTask = Task { @MainActor in
            try? await Task.sleep(for: Self.noticeFor)
            guard !Task.isCancelled else { return }
            self.noticeOpen = false
        }
    }

    /// Undo on the notice: the card comes back as it was.
    public func undoHide() {
        guard var s = state, s.phase == .hidden else { return }
        noticeTask?.cancel(); noticeOpen = false
        s.phase = .showing
        save(s)
    }

    /// Done, after all three ticks: folds it away for good (Help › Getting Started still brings it back).
    public func done() {
        guard var s = state, s.allDone else { return }
        s.phase = .done
        save(s)
    }

    /// Help › Getting Started, `duo2 getting-started show`: the card is back, for anyone. On an install that
    /// never had it, the steps already done are ticked from what Duo can see (`inferred`).
    public func show(inferred: [GettingStartedStep: String] = [:]) {
        var s = state ?? GettingStartedState()
        if state == nil { for (step, detail) in inferred { s.ticks[step.rawValue] = detail } }
        s.phase = .showing
        noticeTask?.cancel(); noticeOpen = false
        save(s)
    }

    /// Checks and the harness: a state held in memory only, never written (the card's fixture states).
    public func hold(_ s: GettingStartedState?, notice: Bool = false) {
        noticeTask?.cancel()
        state = s
        noticeOpen = notice
    }

    private func save(_ s: GettingStartedState) {
        state = s
        DuoState.update(url) { $0.gettingStarted = s }
    }
}
