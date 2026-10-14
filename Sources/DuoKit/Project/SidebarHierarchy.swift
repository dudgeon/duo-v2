import SwiftUI

// The project pane's hierarchy (DL-174, session-glyphs-handoff 04): NEEDS YOU, TASKS, OTHER SESSIONS
// (Open, Today, This week, Earlier), then Archived. Built to screens/04-hierarchy.

extension AppModel {
    /// Where a time group's fold is kept in `expandedGroups`. Open, Today and This week start unfolded,
    /// so their key means "folded"; Earlier starts folded, as it did (DL-91), so its key means "unfolded".
    func timeGroupKey(project: String, _ id: String) -> String { id == "earlier" ? "\(project)/earlier" : "\(project)/fold/\(id)" }

    public func timeGroupFolded(project: String, _ id: String) -> Bool {
        let has = expandedGroups.contains(timeGroupKey(project: project, id))
        return id == "earlier" ? !has : has
    }

    func toggleTimeGroup(project: String, _ id: String) {
        let key = timeGroupKey(project: project, id)
        if expandedGroups.contains(key) { expandedGroups.remove(key) } else { expandedGroups.insert(key) }
    }

    /// Open tasks with no session in the project yet: they have no row of their own among the sessions, so
    /// they list as lines under TASKS (DL-93).
    func sessionlessTasks(_ project: String) -> [Fixture.TaskSummary] {
        let listed = Set(fixture.sessions(inProject: project).compactMap(\.sessionId))
        return (fixture.tasks ?? []).filter { $0.project == project && listedTask($0) && !$0.sessionIds.contains(where: listed.contains) }
    }
}

/// A section label with a + at its trailing end while the pointer is on it: TASKS (New task) and OTHER
/// SESSIONS (New Claude Code session). The + is always in the tree, so VoiceOver and `duo2` reach it, but
/// takes no room and shows only on hover.
struct SectionHeaderPlus: View {
    @Environment(AppModel.self) private var model
    let text: String
    var count: Int?
    let hoverKey: String
    let label: String
    let help: String
    /// TASKS carries the Explainer's frame and trigger (DL-172).
    var tasks = false
    let action: () -> Void

    var body: some View {
        let hovered = model.hoveredTaskRow == hoverKey
        let plus = Text("+")
            .font(.system(size: DuoMetric.rowActionGlyph))
            .foregroundStyle(DuoColor.text2)
            .frame(width: DuoMetric.rowActionSize, height: DuoMetric.rowActionSize)
            .contentShape(RoundedRectangle(cornerRadius: DuoMetric.rowActionRadius))
            .opacity(hovered ? 1 : 0)
            .allowsHitTesting(hovered)
            .accessibilityElement(children: .ignore)
            .onActivate(action)
            .help(help)
            .accessibilityLabel(label)
            .accessibilityHint(help)
        let head = SectionLabel(text: text, count: count)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) {
                if tasks { plus.explainerTrigger(.tasks, key: "tasks.fold-plus", origin: "tasks.fold-head") } else { plus }
            }
            .padding(EdgeInsets(top: 12, leading: DuoSpace.panePadding, bottom: 4, trailing: DuoSpace.panePadding))
            .background(DuoColor.pane)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { model.hoveredTaskRow = hoverKey } else if model.hoveredTaskRow == hoverKey { model.hoveredTaskRow = nil }
            }
        if tasks { head.explainerFrame("tasks.fold-head") } else { head }
    }
}

/// TASKS · n: a section, not a fold. The + is New task.
struct TasksHeader: View {
    @Environment(AppModel.self) private var model
    let project: String

    var body: some View {
        let n = (model.fixture.tasks ?? []).filter { $0.project == project && model.listedTask($0) }.count
        SectionHeaderPlus(text: "Tasks", count: n == 0 ? nil : n, hoverKey: "\(project)/tasks-head", label: "New task",
                          help: "Track a new task in this project", tasks: true) {
            model.newTask(in: project)  // action: task new
        }
    }
}

/// OTHER SESSIONS · n: the sessions in no task. The + is New Claude Code session.
struct OtherSessionsHeader: View {
    @Environment(AppModel.self) private var model
    let project: String
    let count: Int

    var body: some View {
        SectionHeaderPlus(text: "Other sessions", count: count, hoverKey: "\(project)/other-head", label: "New Claude Code session",
                          help: "Start a Claude Code session in this project") {
            model.newSession()  // action: session new
        }
    }
}

/// What follows the task rows: tasks with no session yet, the explainer line when there are no tasks at
/// all (DL-147), and + New task (DL-172).
struct TasksTail: View {
    @Environment(AppModel.self) private var model
    let project: String

    var body: some View {
        let tasks = model.sessionlessTasks(project)
        VStack(alignment: .leading, spacing: 0) {
            if model.projectHasNoTasks(project) {
                Text("Most sessions are for a task or a goal. Put them in a task and Duo keeps them together.")
                    .duoText(.control).foregroundStyle(DuoColor.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8 + DuoSpace.selectionInset).padding(.leading, 18).padding(.vertical, 4)
            }
            ForEach(tasks) { t in TaskLine(task: t, showsProject: false, headerColumns: true).transition(.listRow) }
            NewTaskRow(project: project)
        }
        .background(DuoColor.pane)
        .contextMenu { TaskTemplateItems(project: project) }
        .duoAnimation(.rowMove, value: tasks.map(\.id))
    }
}

/// A time group under OTHER SESSIONS: a fold row at the task rows' level, `rowGroup` 28: a chevron, the
/// name in `bodyEmphasis`, the count in `text2` at the trailing end.
struct TimeGroupRow: View {
    @Environment(AppModel.self) private var model
    let project: String
    let section: SidebarSection

    var body: some View {
        let folded = model.timeGroupFolded(project: project, section.id)
        HStack(spacing: DuoSpace.gapRowItems) {
            Chevron(direction: folded ? .right : .down).frame(width: 10)
            Text(section.title).duoText(.bodyEmphasis).lineLimit(1)
            Spacer(minLength: 8)
            Text("\(section.rows.count)").duoText(.body).foregroundStyle(DuoColor.text2)
        }
        .padding(.horizontal, 8 + DuoSpace.selectionInset)
        .frame(height: DuoMetric.rowGroup)
        .background(DuoColor.pane)
        .contentShape(Rectangle())
        .onActivate { withDuoAnimation(.fold) { model.toggleTimeGroup(project: project, section.id) } }  // action: view group
        .accessibilityLabel(folded ? "Show \(section.rows.count) \(section.title.lowercased()) sessions" : "Hide \(section.title.lowercased()) sessions")
    }
}
