import Foundation

/// The window states that match each design target (handoff §0.2). Fixture mode puts the window
/// into one of these so it can be captured and compared with `screens/<rawValue>.html`.
public enum TargetState: String, CaseIterable, Sendable {
    case overview
    case flowZoom1 = "flow-zoom-1"
    case project
    case flowZoom2 = "flow-zoom-2"
    case flowZoom3 = "flow-zoom-3"
    case flowZoom4 = "flow-zoom-4"

    @MainActor
    public func apply(to model: AppModel) {
        switch self {
        case .overview:
            allProjects(model, selected: "onboarding-v3/Copy review pass 2")
        case .flowZoom1:
            allProjects(model, selected: "onboarding-v3/Copy review pass 2")
            model.focusedTile = "checkout-redesign"
        case .project, .flowZoom2:
            insideCheckout(model)
        case .flowZoom3:
            insideCheckout(model)
            model.peekOpen = true
            model.peekSelection = model.needsYouElsewhere.first?.id
        case .flowZoom4:
            model.fixture = Self.afterCopyReviewAnswered(model.fixture)
            allProjects(model, selected: "checkout-redesign/PRD v2 edits")
        }
    }

    @MainActor
    private func allProjects(_ model: AppModel, selected: String) {
        model.altitude = .allProjects
        // The build-handoff targets draw the map: the Board (DL-142), whatever a new user would see.
        model.homeView = .board
        model.homeTab = "Morning triage"
        model.selectedActionSession = selected
        model.focusedTile = nil
        model.peekOpen = false
    }

    @MainActor
    private func insideCheckout(_ model: AppModel) {
        model.altitude = .project("checkout-redesign")
        model.selectedSidebarItem = "PRD v2"
        model.expandedGroups = ["PRD v2"]
        model.consoleTab = "PRD v2 edits"
        model.rightTab = "docs/prd-v2.md"
        model.selectedFile = "docs/prd-v2.md"
        model.peekOpen = false
    }

    /// flow-zoom-4: Copy review pass 2 was answered and is working again (handoff §6.1 step 4).
    static func afterCopyReviewAnswered(_ f: Fixture) -> Fixture {
        var f = f
        if let i = f.sessions.firstIndex(where: { $0.project == "onboarding-v3" && $0.name == "Copy review pass 2" }) {
            f.sessions[i].state = .working
            f.sessions[i].wait = "now"
            f.sessions[i].question = nil
        }
        f.counts.needsYou -= 1
        f.counts.working += 1
        return f
    }
}
