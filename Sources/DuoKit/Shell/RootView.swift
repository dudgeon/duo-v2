import SwiftUI

/// The window's content: both altitudes, kept alive side by side so zooming never tears down a
/// pane (and later its terminals). Only the active altitude is visible and hit-testable.
public struct RootView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        ZStack {
            AllProjectsLayout()
                .opacity(model.altitude.isAllProjects ? 1 : 0)
                .allowsHitTesting(model.altitude.isAllProjects)
                .accessibilityHidden(!model.altitude.isAllProjects)
            ProjectLayout()
                .opacity(model.altitude.isAllProjects ? 0 : 1)
                // Project to project (DL-130): down at once, then up over `altitude`.
                .opacity(model.projectShown)
                .transaction(value: model.projectShown) { t in if model.projectShown == 0 { t.animation = nil } }
                .allowsHitTesting(!model.altitude.isAllProjects)
                .accessibilityHidden(model.altitude.isAllProjects)
        }
        // Search (DL-76): over both altitudes, scrim and modal fading together, 120 ms in and 100 ms
        // out, without moving; none with Reduce Motion (DL-129).
        .overlay { if model.search.isOpen { SearchOverlay().transition(.opacity) } }
        // Duo's sheets (DL-100): Move into Home…, New project.
        .overlay { SheetOverlay() }
        .animation((model.search.isOpen ? DuoMotionToken.scrimIn : .scrimOut).animation, value: model.search.isOpen)
        // Altitude change: cross-fade, 150 ms, ease-out; none with Reduce Motion (handoff §9).
        // Keyed on the altitude alone: a jump between projects fades the project up (projectShown)
        // and doesn't cross-fade one project's names into another's (DL-130).
        .duoAnimation(.altitude, value: model.altitude.isAllProjects)
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
                .init(view: AnyView(DimmedUnderSheet { ProjectMapPane() }), width: nil, minWidth: DuoMetric.paneMinMap),
                .init(view: AnyView(ActionColumnPane()), width: DuoMetric.paneOverviewActionColumn,
                      minWidth: DuoMetric.paneMinActionColumn, collapsible: true, collapsed: model.rightCollapsedAllProjects),
            ],
            dividerColors: [DuoNSColor.consoleRule, DuoNSColor.rule],
            paneBackgrounds: [DuoNSColor.console, DuoNSColor.pane, DuoNSColor.pane],
            model: model,
            // Home in chat is light, its divider too (DL-142 (7), `home-chat` board 10): watched by
            // the split, never read here (F-208).
            liveColors: { m in
                let light = m.homeShowsChat
                return ([light ? DuoNSColor.rule : DuoNSColor.consoleRule, DuoNSColor.rule], [light ? DuoNSColor.ground : DuoNSColor.console, DuoNSColor.pane, DuoNSColor.pane])
            }
        )
    }
}

/// A pane dimmed while a Duo sheet is up. Its own view, so the split's panes capture nothing that
/// changes: PaneSplit sets each pane's root view once (F-208).
struct DimmedUnderSheet<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder var content: Content

    var body: some View {
        content.opacity(model.sheetIsUp ? DuoMetric.sheetDimmedOpacity : 1)
            .animation((model.sheetIsUp ? DuoMotionToken.scrimIn : .scrimOut).animation, value: model.sheetIsUp)
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
                      minWidth: DuoMetric.paneMinRight, collapsible: true, collapsed: model.rightCollapsedProject),
            ],
            dividerColors: [DuoNSColor.rule, DuoNSColor.rule],
            paneBackgrounds: [DuoNSColor.pane, DuoNSColor.console, DuoNSColor.pane],
            model: model,
            // The task board (DL-148, C): over the session list and console; watched by the split.
            cover: (AnyView(TaskBoardPane()), { $0.boardShown })
        )
    }
}
