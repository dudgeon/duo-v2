import SwiftUI

/// The window's content: both altitudes, kept alive side by side so zooming never tears down a
/// pane (and later its terminals). Only the active altitude is visible and hit-testable.
public struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        ZStack {
            AllProjectsLayout()
                .opacity(model.altitude.isAllProjects ? 1 : 0)
                .allowsHitTesting(model.altitude.isAllProjects)
                .accessibilityHidden(!model.altitude.isAllProjects)
            ProjectLayout()
                .opacity(model.altitude.isAllProjects ? 0 : 1)
                .allowsHitTesting(!model.altitude.isAllProjects)
                .accessibilityHidden(model.altitude.isAllProjects)
        }
        // Search (DL-76): over both altitudes, scrim and modal; a short fade, none with Reduce Motion.
        .overlay { if model.search.isOpen { SearchOverlay().transition(.opacity) } }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: model.search.isOpen)
        // Altitude change: cross-fade, 150 ms, ease-out; none with Reduce Motion (handoff §9).
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: model.altitude)
        .background(DuoColor.pane)
        .toolbar { DuoToolbar() }
        .toolbar(removing: .title)
    }
}

/// All projects (handoff §3.2): Home terminal · project map · action column.
struct AllProjectsLayout: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PaneSplit(
            panes: [
                .init(view: AnyView(HomePane()), width: DuoMetric.paneOverviewHome, minWidth: DuoMetric.paneMinHome,
                      collapsible: true, collapsed: model.leftCollapsedAllProjects),
                .init(view: AnyView(ProjectMapPane()), width: nil, minWidth: 400),
                .init(view: AnyView(ActionColumnPane()), width: DuoMetric.paneOverviewActionColumn,
                      minWidth: DuoMetric.paneMinActionColumn, collapsible: true),
            ],
            dividerColors: [DuoNSColor.consoleRule, DuoNSColor.rule],
            paneBackgrounds: [DuoNSColor.console, DuoNSColor.pane, DuoNSColor.pane],
            model: model
        )
    }
}

/// Inside a project (handoff §3.3): sessions over files · console · right pane.
struct ProjectLayout: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PaneSplit(
            panes: [
                .init(view: AnyView(ProjectSidebarPane()), width: DuoMetric.paneProjectLeft,
                      minWidth: DuoMetric.paneMinSessionsAndFiles, collapsible: true, collapsed: model.leftCollapsedProject),
                .init(view: AnyView(ConsolePane()), width: nil, minWidth: DuoMetric.paneMinConsole),
                .init(view: AnyView(RightPane()), width: DuoMetric.paneProjectRight,
                      minWidth: DuoMetric.paneMinRight, collapsible: true),
            ],
            dividerColors: [DuoNSColor.rule, DuoNSColor.rule],
            paneBackgrounds: [DuoNSColor.pane, DuoNSColor.console, DuoNSColor.pane],
            model: model
        )
    }
}
