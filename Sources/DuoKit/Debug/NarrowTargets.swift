import Foundation

/// The narrow-handoff targets as window states (`--state narrow-…`, DL-129), captured at 1280×800
/// with `--window 1280x800` (`WINDOW=1280x800 scripts/check-ui.sh narrow-project …`).
@MainActor
public enum NarrowTargets {
    nonisolated public static let screens = ["narrow-project", "narrow-project-hidden", "narrow-project-min",
                                             "narrow-overview", "narrow-overview-hidden", "narrow-search"]

    public static func apply(_ screen: String, to model: AppModel) {
        switch screen {
        case "narrow-project", "narrow-project-hidden", "narrow-project-min":
            TargetState.project.apply(to: model)
            model.rightCollapsedProject = screen == "narrow-project-hidden"
            // The right pane dragged wide: the console stops at its 480 minimum (300 | 480 | 500).
            if screen == "narrow-project-min" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { FixtureHarness.perform("right-width:500", on: model) }
            }
        case "narrow-search":
            moreTopics(model)
            SearchTargets.apply("search-overview", to: model)
        default:
            TargetState.overview.apply(to: model)
            moreTopics(model)
            model.rightCollapsedAllProjects = screen == "narrow-overview-hidden"
        }
    }

    /// The board's map: two more topics and a project directly in Home, so six groups pack two
    /// (or three) across.
    static func moreTopics(_ model: AppModel) {
        var f = model.fixture
        guard !f.projects.contains(where: { $0.name == "vendor-review" }) else { return }
        let home = f.projects.first { $0.isHome == true }?.path ?? "~/work/home"
        f.topics = [""] + f.topics + ["Research", "Ops"]   // "": directly in Home (DL-83)
        f.projects += [
            .init(name: "vendor-review", topic: "", path: home + "/vendor-review", goal: "Pick a fraud-scoring vendor", health: "On track"),
            .init(name: "buyer-interviews", topic: "Research", path: "~/work/research/buyer-interviews", goal: "Six buyer interviews, synthesised", health: "On track"),
            .init(name: "q4-planning", topic: "Ops", path: "~/work/ops/q4-planning", goal: "Q4 plan signed off by staff", health: "At risk", next: "Draft due Oct 9"),
        ]
        model.fixture = f
    }
}
