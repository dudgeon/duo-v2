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
        .coordinateSpace(name: ExplainerState.space)
        // Search (DL-76): over both altitudes, scrim and modal fading together, 120 ms in and 100 ms
        // out, without moving; none with Reduce Motion (DL-129).
        .overlay { if model.search.isOpen { SearchOverlay().transition(.opacity) } }
        // Duo's sheets (DL-100): Move into Home…, New project.
        .overlay { SheetOverlay() }
        // The Explainer (DL-172): above the panes, under nothing but the sheets' own scrim.
        .overlay(alignment: .topLeading) { ExplainerOverlay() }
        .animation((model.search.isOpen ? DuoMotionToken.scrimIn : .scrimOut).animation, value: model.search.isOpen)
        // Altitude change: cross-fade, 150 ms, ease-out; none with Reduce Motion (handoff §9).
        // Keyed on the altitude alone: a jump between projects fades the project up (projectShown)
        // and doesn't cross-fade one project's names into another's (DL-130).
        .duoAnimation(.altitude, value: model.altitude.isAllProjects)
        // The pane under everything; a window colour (DL-313) also paints the toolbar at real chroma: a band of
        // `ground` as tall as the toolbar (the safe area's top), whose own background steps aside meanwhile.
        .background {
            GeometryReader { g in
                ZStack(alignment: .top) {
                    Rectangle().fill(WindowTint.pane)
                    if model.windowColour != nil {
                        Rectangle().fill(WindowTint.ground).frame(height: g.safeAreaInsets.top)
                    }
                }
                .ignoresSafeArea()
            }
        }
        .toolbar { DuoToolbar() }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(model.windowColour != nil ? .hidden : .automatic, for: .windowToolbar)
        // The window's title is its project's (DL-311): the Window menu lists windows by it.
        .onChange(of: model.windowTitle, initial: true) { _, t in if model.window?.title != t { model.window?.title = t } }
        // Each window's colour, for every surface that takes it (WindowTint); nil under Classic.
        .environment(\.windowColour, model.windowColour)
    }
}

/// All projects (handoff §3.2): Home terminal · project map · action column.
struct AllProjectsLayout: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PaneSplit(
            panes: [
                .init(view: AnyView(HomePane().paneFocusRule(.left, onConsole: true)), width: DuoMetric.paneOverviewHome, minWidth: DuoMetric.paneMinHome,
                      collapsible: true, collapsed: model.leftCollapsedAllProjects),
                .init(view: AnyView(DimmedUnderSheet { ProjectMapPane() }.paneFocusRule(.middle)), width: nil, minWidth: DuoMetric.paneMinMap),
                .init(view: AnyView(ActionColumnPane().paneFocusRule(.right)), width: DuoMetric.paneOverviewActionColumn,
                      minWidth: DuoMetric.paneMinActionColumn, collapsible: true, collapsed: model.rightCollapsedAllProjects),
            ],
            dividerColors: [DuoNSColor.consoleRule, DuoNSColor.rule],
            paneBackgrounds: [DuoNSColor.console, model.tint(.pane), model.tint(.pane)],
            model: model,
            // Home in chat is light, its divider too (DL-142 (7), `home-chat` board 10): watched by
            // the split, never read here (F-208).
            liveColors: { m in
                let light = m.homeShowsChat && m.ownsHome   // Home's stand-in stays dark (board 10 B)
                return ([light ? DuoNSColor.rule : DuoNSColor.consoleRule, DuoNSColor.rule], [light ? m.tint(.strip) : DuoNSColor.console, m.tint(.pane), m.tint(.pane)])
            },
            onActivePane: { [weak model] i in model?.panePicked(DuoPane.allCases[i], allProjects: true) }
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
                .init(view: AnyView(ProjectSidebarPane().paneFocusRule(.left)), width: DuoMetric.paneProjectLeft,
                      minWidth: DuoMetric.paneMinSessionsAndFiles, collapsible: true, collapsed: model.leftCollapsedProject),
                .init(view: AnyView(ConsoleWithRail().paneFocusRule(.middle, onConsole: true)), width: nil, minWidth: DuoMetric.paneMinConsole),
                .init(view: AnyView(RightPane().paneFocusRule(.right)), width: model.videoRightWidth ?? DuoMetric.paneProjectRight,
                      minWidth: DuoMetric.paneMinRight, collapsible: true, collapsed: model.rightCollapsedProject),
            ],
            dividerColors: [DuoNSColor.rule, DuoNSColor.rule],
            paneBackgrounds: [model.tint(.pane), DuoNSColor.console, model.tint(.pane)],
            model: model,
            // The window's colour for the sidebar and right pane; watched by the split (F-208).
            liveColors: { m in ([DuoNSColor.rule, DuoNSColor.rule], [m.tint(.pane), DuoNSColor.console, m.tint(.pane)]) },
            // The task board (DL-148, C): over the session list and console; watched by the split.
            cover: (AnyView(TaskBoardPane().paneFocusRule(.middle)), { $0.boardShown }),
            onActivePane: { [weak model] i in
                guard let model else { return }
                model.panePicked(i == 0 && model.boardShown ? .middle : DuoPane.allCases[i], allProjects: false)   // the board covers the left
            },
            onHost: { [weak model] split in
                model?.splits.paneHost = split   // split view sets the right pane's width
                split.onResize = { [weak model] w in model?.splitWindowResized(w) }   // and folds the sidebar only while too narrow (DL-276)
                split.onPlaced = { [weak model] in model?.reconcileRoom() }   // a restored split's room, for this window (F-531)
            }
        )
    }
}

/// The console with the folded sidebar's rail on its leading edge, and the sidebar peeking over it
/// (split view, DL-276). A view of its own so the layout reads none of it (F-208).
struct ConsoleWithRail: View {
    var body: some View {
        HStack(spacing: 0) {
            SidebarRail()
            ConsolePane()
        }
        .overlay(alignment: .leading) { SidebarPeek().padding(.leading, DuoMetric.sidebarRail) }
    }
}
