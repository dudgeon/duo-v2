import Foundation

/// The new-session-handoff's states A to F as window states (DL-253, `chosen-placement-4.html`): the console with few
/// tabs and a Claude tab selected (`newsession-a`), with many (`-b`), a shell tab selected with its half hovered (`-c`), the
/// thin light strip over chat with few and many tabs (`-d`, `-e`), and Home with no tabs, the Claude half hovered (`-f`).
/// States A, C and F and the light strip's toggle sizes are classic-options' stand-ins (Q-325).
@MainActor
public enum NewSessionTargets {
    nonisolated public static let screens = ["newsession-a", "newsession-b", "newsession-c", "newsession-d", "newsession-e", "newsession-f"]

    static let project = "checkout-redesign"

    public static func apply(_ screen: String, to model: AppModel) {
        let s = String(screen.dropFirst("newsession-".count))
        (s == "f" ? TargetState.overview : TargetState.project).apply(to: model)
        var f = model.fixture
        let owner = s == "f" ? (f.home?.name ?? project) : project
        f.sessions.removeAll { $0.project == owner }
        f.groups.removeAll { $0.project == owner }
        f.tasks = (f.tasks ?? []).filter { $0.project != owner }
        var order: [String] = []
        func add(_ name: String, _ st: SessionState) {
            var x = Fixture.Session(name: name, project: owner, state: st, wait: "now")
            x.sessionId = name
            f.sessions.append(x)
            order.append(name)
        }
        let selected = "Auto-add decision"
        switch s {
        case "a": add("Tighten PRD goals", .idle); add("Prototype scan review", .idle)
        case "b": add("Tighten PRD goals", .idle); add("Prototype scan review", .idle); add(selected, .needsYou); add("Spine eval: global rollout", .idle)
            for n in ["Tax rules", "Checkout latency", "Cart abandonment", "Segment list query", "Nightly order export", "Refund copy review"] { add(n, .idle) }
        case "c": add("Tighten PRD goals", .idle)
        case "d": add("Tighten PRD goals", .idle); add(selected, .needsYou)
        case "e": add("Tighten PRD goals", .idle); add("Prototype scan review", .idle); add("Synthesis from interviews", .idle); add(selected, .needsYou); add("Spine eval: global rollout", .idle)
            for n in ["Tax rules", "Checkout latency", "Cart abandonment", "Segment list query", "Nightly order export", "Refund copy review"] { add(n, .idle) }
        default: break
        }
        model.fixture = f
        // The selected tab: a Claude session with a chat, in terminal (A, B) or chat (D, E).
        let tab = s == "a" ? "Tighten PRD goals" : s == "d" || s == "e" || s == "b" ? selected : nil
        model.fixtureActive = Set(order)
        model.parkedTabs = Set(order)
        if let tab {
            model.fixtureChats[tab] = ChatSession(key: tab, mode: s == "d" || s == "e" ? .chat : .terminal)
        }
        if s == "c" {
            let key = AppModel.shellPrefix + "zsh"
            model.shellTitles[key] = "zsh · shelf-scan"
            model.shellTabs[project] = [key]
            model.consoleTab = key
            model.hoveredPill = "new-shell"
        } else if s == "f" {
            model.hoveredPill = "new-claude"
            model.homeTab = nil
        } else if let tab {
            model.consoleTab = tab
            model.selectedSidebarItem = "\(project)/\(tab)"
        }
        if s != "f" { model.consoleTabOrder[project] = order }
    }
}
