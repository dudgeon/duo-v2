import Foundation

/// The first-run-welcome-handoff targets as window states (`--state B1-allprojects-fresh`, DL-348): All projects, List, on
/// the home-evolution boards' sessions, with the Getting started card as B1 and B2 draw it. The card's state is held in
/// memory only, never written. `--then getting-started:<…>` changes it, `--then show-me:session` and
/// `--then explain:<id>` draw B3 and X2.
@MainActor
public enum GettingStartedTargets {
    nonisolated public static let screens = ["B1-allprojects-fresh", "B2-one-of-three", "B2-two-of-three", "B2-all-done", "B2-hidden", "B2-board"]

    public static func apply(_ screen: String, to model: AppModel) {
        HomeListTargets.apply("list-1440", to: model)
        if screen == "B2-board" { model.homeView = .board; model.boardGroup = .folder }
        switch screen {
        case "B1-allprojects-fresh": hold("0")
        case "B2-one-of-three": hold("1")
        case "B2-two-of-three", "B2-board": hold("2")
        case "B2-all-done": hold("3")
        default: hold("notice")   // B2-hidden: the Hide notice, with Undo
        }
    }

    /// The card at 0 to 3 ticks, hidden (the card gone), the Hide notice (Undo), or none (an install that never had it).
    /// Ticks say what B2 draws: the project and its folder, the session and its mode, the task.
    public static func hold(_ word: String) {
        let ticks: [(GettingStartedStep, String)] = [(.project, "q4-plan · ~/work/q4-plan"), (.session, "chat|Outline the Q4 plan"), (.task, "Draft the Q4 plan · q4-plan")]
        let g = GettingStarted.shared
        switch word {
        case "none": g.hold(nil)
        case "hidden": g.hold(GettingStartedState(phase: .hidden))
        case "notice": g.hold(GettingStartedState(phase: .hidden), notice: true)
        default:
            let n = Int(word) ?? 0
            g.hold(GettingStartedState(phase: .showing, ticks: Dictionary(uniqueKeysWithValues: ticks.prefix(n).map { ($0.0.rawValue, $0.1) })))
        }
    }
}
