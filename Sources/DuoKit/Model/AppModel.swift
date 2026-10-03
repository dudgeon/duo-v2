import Foundation
import Observation

/// The two altitudes (handoff §2.3).
public enum Altitude: Equatable, Sendable {
    case allProjects
    case project(String)

    public var isAllProjects: Bool { self == .allProjects }
}

/// Window-level UI state. One instance per window; views read it from the environment.
@MainActor
@Observable
public final class AppModel {
    public var fixture: Fixture
    public var altitude: Altitude = .allProjects

    /// The left pane is collapsed independently at each altitude (handoff §3.1).
    public var leftCollapsedAllProjects = false
    public var leftCollapsedProject = false

    // All projects
    public var selectedActionSession: String?   // Session.id
    public var focusedTile: String?             // Project.name
    public var homeTab: String?                 // Session.name

    // Inside a project
    public var selectedSidebarItem: String?     // group name or Session.id
    public var expandedGroups: Set<String> = []
    public var consoleTab: String?              // Session.name
    public var rightTab: String?                // "Project", a group name, or a document path
    public var selectedFile: String?            // path relative to the project

    public var peekOpen = false

    public init(fixture: Fixture) {
        self.fixture = fixture
    }

    public var leftCollapsed: Bool {
        get { altitude.isAllProjects ? leftCollapsedAllProjects : leftCollapsedProject }
        set {
            if altitude.isAllProjects { leftCollapsedAllProjects = newValue } else { leftCollapsedProject = newValue }
        }
    }

    public var currentProject: Fixture.Project? {
        guard case .project(let name) = altitude else { return nil }
        return fixture.projects.first { $0.name == name }
    }

    /// Sessions needing you outside the current project: the toolbar chip's count (handoff §3.1).
    public var needsYouElsewhere: [Fixture.Session] {
        let here = currentProject?.name
        return fixture.needsYou.filter { $0.project != here }
    }
}
