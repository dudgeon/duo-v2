import AppKit
import SwiftUI

// The task board (DL-148, DL-150, `task-board-handoff/`): placed as C, over the session list and
// the console, beside the right pane that keeps the selected card's note (board 4). Cards are
// read from the notes and their sessions' live state; nothing is stored for the board.

/// The board over the left and middle panes. `PaneSplit` shows it while `model.boardShown`.
struct TaskBoardPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Off screen it reads nothing (ENH-45): the split hides it, and this body is empty then.
        if model.boardShown, let project = model.currentProject?.name {
            let lanes = model.board(project)
            let total = lanes.reduce(0) { $0 + $1.count }
            let any = (model.fixture.tasks ?? []).contains { $0.project == project && $0.archived != true }
            VStack(spacing: 0) {
                BoardHeader(project: project, count: total)
                if any {
                    BoardLanes(project: project, lanes: lanes)
                } else {
                    EmptyBoard(project: project)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(DuoColor.pane)
        } else {
            Color.clear
        }
    }
}

// MARK: - The toolbar's switch

/// Sessions | Tasks (board 4): a 22-high segmented control after the project's name; the chosen
/// side on `selected`, semibold. Live projects only.
struct BoardSwitch: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.terminalsMode == .live, let project = model.currentProject?.name, model.currentProject?.isFolderOnly != true {
            let board = model.boardProjects.contains(project)
            HStack(spacing: 0) {
                side("Sessions", glyph: .term, on: !board) { model.showBoard(false, project: project) }  // action: task board
                Rectangle().fill(DuoColor.rule).frame(width: 1)
                side("Tasks", glyph: .board, on: board) { model.showBoard(true, project: project) }  // action: task board
            }
            .frame(height: DuoMetric.taskBoardSwitchHeight)
            .background(DuoColor.pane)
            .clipShape(RoundedRectangle(cornerRadius: DuoMetric.radiusControl))
            .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).strokeBorder(DuoColor.controlEdge, lineWidth: 1))
            .fixedSize()
        }
    }

    private func side(_ label: String, glyph: BoardGlyph.Kind, on: Bool, _ action: @escaping () -> Void) -> some View {
        HStack(spacing: 5) {
            BoardGlyph(glyph, color: on ? DuoColor.text : DuoColor.text2)
            Text(label).duoText(.control, weight: on ? .semibold : nil)
        }
        .foregroundStyle(on ? DuoColor.text : DuoColor.text2)
        .padding(.horizontal, DuoMetric.taskBoardSwitchPaddingX)
        .frame(maxHeight: .infinity)
        .background(on ? DuoColor.selected : Color.clear)
        .contentShape(Rectangle())
        .onActivate(action)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Header

/// `TASKS · n`, Filter tasks, Anyone ▾, + New task (board 4).
struct BoardHeader: View {
    @Environment(AppModel.self) private var model
    let project: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text("Tasks · \(count)").duoText(.sectionLabel).foregroundStyle(DuoColor.text2).fixedSize()
            HStack(spacing: 6) {
                BoardGlyph(.search)
                TextField("Filter tasks", text: Binding(get: { model.boardFilter }, set: { model.boardFilter = $0 }))
                    .textFieldStyle(.plain).duoText(.control).foregroundStyle(DuoColor.text)
            }
            .padding(.horizontal, 8)
            .frame(width: DuoMetric.taskBoardFilterWidth, height: DuoMetric.taskBoardControlHeight)
            .background(RoundedRectangle(cornerRadius: DuoMetric.radiusField).fill(DuoColor.pane))
            .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusField).strokeBorder(DuoColor.rule, lineWidth: 1))
            .padding(.leading, 8)
            OwnerPopup(project: project)
            Spacer(minLength: 0)
            SmallButton("+ New task") { model.newTask(in: project) }  // action: task new
        }
        .padding(.horizontal, DuoMetric.taskBoardHeaderPaddingX)
        .frame(height: DuoMetric.taskBoardHeaderHeight - 1)
        .overlay(alignment: .bottom) { Rectangle().fill(DuoColor.rule).frame(height: 1).offset(y: 1) }
        .padding(.bottom, 1)
    }
}

/// Anyone ▾: everyone's tasks, yours, or one owner's.
struct OwnerPopup: View {
    @Environment(AppModel.self) private var model
    let project: String

    var body: some View {
        let label = model.boardOwner.map { $0.isEmpty ? "Me" : $0 } ?? "Anyone"
        Menu {
            Button("Anyone") { model.boardOwner = nil }
            Button("Me") { model.boardOwner = "" }
            let owners = model.boardOwners(project)
            if !owners.isEmpty { Divider() }
            ForEach(owners, id: \.self) { o in Button(o) { model.boardOwner = o } }
        } label: {
            HStack(spacing: 6) {
                Text(label).duoText(.control).foregroundStyle(DuoColor.text)
                BoardGlyph(.updown)
            }
            .padding(.leading, 8).padding(.trailing, 6)
            .frame(height: DuoMetric.taskBoardControlHeight)
            .background(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).fill(DuoColor.pane))
            .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).strokeBorder(DuoColor.rule, lineWidth: 1))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Show tasks for \(label)")
    }
}

/// A 22-high bordered button (`+ New task`, board 4).
struct SmallButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }

    var body: some View {
        Text(title).duoText(.control).foregroundStyle(DuoColor.text)
            .padding(.horizontal, 10)
            .frame(height: DuoMetric.taskBoardControlHeight)
            .background(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).fill(DuoColor.pane))
            .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).strokeBorder(DuoColor.controlEdge, lineWidth: 1))
            .contentShape(Rectangle())
            .onActivate(action)
            .accessibilityLabel(title.replacingOccurrences(of: "+ ", with: ""))
    }
}

// MARK: - Lanes

/// The lanes, in steps (board 8): all of them from 900 up; under 900 Done folds into a 34-wide
/// strip; when a lane would be under 150 (or the board under 640), lanes keep 200 and scroll.
struct BoardLanes: View {
    @Environment(AppModel.self) private var model
    let project: String
    let lanes: [TaskBoard.Lane]

    var body: some View {
        GeometryReader { geo in
            let pad = DuoMetric.taskBoardLanesPadding
            let gap = DuoMetric.taskBoardLaneGap
            let inner = geo.size.width - pad.leading - pad.trailing
            let doneKey = "\(project)/board-done-open"
            let folds = geo.size.width < DuoMetric.taskBoardFoldsBelow && lanes.count > 1 && lanes.contains { $0.status == "done" }
            let shown = folds ? lanes.filter { $0.status != "done" } : lanes
            let adding = model.addingColumn
            // + Add Column after the lanes (board 12): a + until it's clicked, then the name field.
            let addRoom = (adding != nil ? DuoMetric.taskBoardAddColumnWidth : DuoMetric.taskBoardAddColumnIdle) + gap
            let stripRoom = (folds ? DuoMetric.taskBoardDoneStripWidth + gap : 0) + addRoom
            let n = CGFloat(max(1, shown.count))
            let even = (inner - stripRoom - gap * (n - 1)) / n
            let scrolls = geo.size.width < DuoMetric.taskBoardScrollsBelow || even < DuoMetric.taskBoardLaneMin
            let width = scrolls ? DuoMetric.taskBoardLaneScrollWidth : floor(even)
            let row = HStack(alignment: .top, spacing: gap) {
                ForEach(shown) { lane in LaneView(project: project, lane: lane).frame(width: width).environment(\.boardLaneWidth, width) }
                if folds, let done = lanes.first(where: { $0.status == "done" }) {
                    DoneStrip(lane: done) { model.expandedGroups.insert(doneKey) }
                }
                AddColumn(project: project)
            }
            .padding(pad)
            .frame(minWidth: geo.size.width, maxHeight: .infinity, alignment: .topLeading)
            Group {
                if scrolls {
                    ScrollView(.horizontal, showsIndicators: true) { row.frame(height: geo.size.height) }
                } else {
                    row
                }
            }
            // The folded Done, opened: a lane over the others at the right (board 8, step 2).
            .overlay(alignment: .topTrailing) {
                if folds, model.expandedGroups.contains(doneKey), let done = lanes.first(where: { $0.status == "done" }) {
                    LaneView(project: project, lane: done, onClose: { model.expandedGroups.remove(doneKey) })
                        .frame(width: max(width, DuoMetric.taskBoardLaneScrollWidth))
                        .environment(\.boardLaneWidth, max(width, DuoMetric.taskBoardLaneScrollWidth))
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).fill(DuoColor.pane))
                        .duoPopoverShadow()
                        .padding(.top, pad.top - 6).padding(.trailing, pad.trailing - 6).padding(.bottom, pad.bottom - 6)
                }
            }
        }
    }
}

/// + Add Column (board 12): a + after the lanes; clicked (or Add Column After…), a dashed box
/// with the name field. Return adds the column, Esc or an empty name doesn't.
struct AddColumn: View {
    @Environment(AppModel.self) private var model
    let project: String

    var body: some View {
        if model.addingColumn != nil {
            VStack(alignment: .leading, spacing: 6) {
                Color.clear.frame(height: DuoMetric.taskBoardLaneHeaderHeight)
                VStack(alignment: .leading, spacing: 6) {
                    InlineNameField(name: "", font: DuoTextStyle.control.spec.nsFont, placeholder: "Column name") { name in
                        let after = model.addingColumn
                        model.addingColumn = nil
                        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        if let why = model.addColumn(name, after: after?.isEmpty == false ? after : nil, project: project) { model.info(why) }  // action: task column
                    }
                    .padding(.horizontal, 6)
                    .frame(height: DuoMetric.taskBoardControlHeight)
                    .background(RoundedRectangle(cornerRadius: DuoMetric.radiusField).fill(DuoColor.pane))
                    .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusField).strokeBorder(DuoColor.rule, lineWidth: 1))
                    Text("Return adds it · Esc").duoText(.control).foregroundStyle(DuoColor.text2)
                }
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).strokeBorder(DuoColor.controlEdge, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            }
            .frame(width: DuoMetric.taskBoardAddColumnWidth)
        } else {
            VStack(spacing: 0) {
                Color.clear.frame(height: DuoMetric.taskBoardLaneHeaderHeight + DuoMetric.taskBoardCardGap)
                Text("+").font(.system(size: DuoMetric.rowActionGlyph)).foregroundStyle(DuoColor.text2)
                    .frame(width: DuoMetric.taskBoardAddColumnIdle, height: DuoMetric.rowActionSize)
                    .contentShape(Rectangle())
                    .onActivate { model.addingColumn = "" }  // action: task column
                    .help("Add Column")
                    .accessibilityLabel("Add Column")
            }
        }
    }
}

/// Done folded into a strip (board 5): a chevron and `DONE · n` turned on its side.
struct DoneStrip: View {
    let lane: TaskBoard.Lane
    let open: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Chevron(direction: .right).frame(width: 8, height: 10)
            Text("\(lane.title) · \(lane.count)").duoText(.sectionLabel).foregroundStyle(DuoColor.text2)
                .fixedSize().rotationEffect(.degrees(90)).frame(width: 16, height: 80)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .frame(width: DuoMetric.taskBoardDoneStripWidth)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).fill(DuoColor.ground))
        .contentShape(Rectangle())
        .onActivate(open)  // action: task board
        .accessibilityLabel("Show \(lane.title), \(lane.count) tasks")
    }
}

/// One lane: its header, then its cards on `ground`; an empty lane says what a drop there does.
struct LaneView: View {
    @Environment(AppModel.self) private var model
    let project: String
    let lane: TaskBoard.Lane
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DuoMetric.taskBoardCardGap) {
            HStack(spacing: 6) {
                Text("\(lane.title) · \(lane.count)").duoText(.sectionLabel)
                    .foregroundStyle(DuoColor.text2).lineLimit(1)
                Spacer(minLength: 0)
                if model.hoveredLane == lane.status || lane.extra {
                    LaneMenu(project: project, lane: lane)
                }
                if let onClose {
                    Chevron(direction: .down).frame(width: 10, height: 8).contentShape(Rectangle()).onActivate(onClose)  // action: task board
                        .accessibilityLabel("Fold \(lane.title)")
                }
            }
            .padding(.horizontal, 4)
            .frame(height: DuoMetric.taskBoardLaneHeaderHeight)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { model.hoveredLane = lane.status } else if model.hoveredLane == lane.status { model.hoveredLane = nil }
            }
            .contextMenu { LaneMenuItems(project: project, lane: lane) }
            let hot = model.boardDropLane == lane.status && model.dragging?.hasPrefix("duo-card:\(project)/") == true
            let moving = hot ? model.dragging.flatMap { model.card(fromPayload: $0, project: project) } : nil
            let incoming = moving.flatMap { p in model.fixture.tasks?.first { $0.project == project && $0.path == p } }
            let comesFrom = incoming.map { TaskBoard.key($0.status) == lane.status } ?? true
            let slot = (incoming != nil && !comesFrom) ? TaskBoard.slot(of: .init(task: incoming!, urgent: nil), in: lane) : nil
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: DuoMetric.taskBoardCardGap) {
                    ForEach(Array(lane.cards.enumerated()), id: \.element.id) { i, c in
                        if i == slot { DropSlot(task: incoming!) }
                        TaskCard(card: c)
                    }
                    if let slot, slot >= lane.cards.count { DropSlot(task: incoming!) }
                    if lane.cards.isEmpty && lane.earlier.isEmpty && lane.dropped.isEmpty && slot == nil {
                        Text("Drop a task here to mark it \(lane.title.lowercased())")
                            .duoText(.control).foregroundStyle(DuoColor.text2).multilineTextAlignment(.center)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusCard)
                                .strokeBorder(DuoColor.controlEdge, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    }
                    if lane.status == "done" {
                        BoardFold(project: project, name: "earlier", label: "Earlier", cards: lane.earlier)
                        BoardFold(project: project, name: "dropped", label: "Dropped", cards: lane.dropped)
                    }
                }
                .padding(DuoMetric.taskBoardLaneBodyPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // The lane under a dragged card: `selected` with a dashed edge (board 7).
            .background(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).fill(hot && !comesFrom ? DuoColor.selected : DuoColor.ground))
            .overlay {
                if hot && !comesFrom {
                    RoundedRectangle(cornerRadius: DuoMetric.radiusCard).strokeBorder(DuoColor.controlEdge, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
        }
        .onDrop(of: [.plainText, .utf8PlainText], delegate: LaneDrop(model: model, project: project, status: lane.status))  // action: task status
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(lane.title), \(lane.count) tasks")
    }
}

/// A lane's ⋯ (board 12): Move Left, Move Right, Add Column After…, Remove Column…; Keep as
/// Column on a lane for a status that isn't a column.
struct LaneMenu: View {
    let project: String
    let lane: TaskBoard.Lane

    var body: some View {
        Menu { LaneMenuItems(project: project, lane: lane) } label: {
            Text("···").font(.system(size: 11, weight: .bold)).foregroundStyle(DuoColor.text2)
                .frame(width: 22, height: 18)
                .background(RoundedRectangle(cornerRadius: 4).fill(DuoColor.selected))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("\(lane.title) column menu")
    }
}

struct LaneMenuItems: View {
    @Environment(AppModel.self) private var model
    let project: String
    let lane: TaskBoard.Lane

    var body: some View {
        if lane.extra {
            Button("Keep as Column") { if let why = model.keepColumn(lane.status, project: project) { model.info(why) } }  // action: task column
        } else {
            let lanes = model.boardLanes(project)
            let i = lanes.firstIndex(of: lane.status) ?? 0
            Button("Move Left") { if let why = model.moveColumn(lane.status, by: -1, project: project) { model.info(why) } }  // action: task column
                .disabled(i == 0)
            Button("Move Right") { if let why = model.moveColumn(lane.status, by: 1, project: project) { model.info(why) } }  // action: task column
                .disabled(i >= lanes.count - 1)
            Divider()
            Button("Add Column After…") { model.addingColumn = lane.status }  // action: task column
            Divider()
            Button("Remove Column…") { model.askRemoveColumn(lane.status, project: project) }  // action: task column
                .disabled(TaskBoard.fixedLanes.contains(lane.status))
        }
    }
}

/// Takes a card dropped on a lane: Set Status to the lane's (board 7). Dragging within a lane does
/// nothing: order is computed (DL-148 (3)).
struct LaneDrop: DropDelegate {
    let model: AppModel
    let project: String
    let status: String

    @MainActor func validateDrop(info: DropInfo) -> Bool { model.dragging?.hasPrefix("duo-card:\(project)/") == true }
    @MainActor func dropEntered(info: DropInfo) { model.boardDropLane = status }
    @MainActor func dropExited(info: DropInfo) { if model.boardDropLane == status { model.boardDropLane = nil } }
    @MainActor func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    @MainActor func performDrop(info: DropInfo) -> Bool {
        let payload = model.dragging
        model.boardDropLane = nil
        model.dragging = nil
        guard let payload, let path = model.card(fromPayload: payload, project: project) else { return false }
        if let why = model.moveCard(project: project, path: path, to: status) { model.info(why) }
        return true
    }
}

/// Makes a view a drop target for cards, as `status`; nil leaves it alone.
struct DropsAs: ViewModifier {
    @Environment(AppModel.self) private var model
    let project: String
    let status: String?

    func body(content: Content) -> some View {
        if let status {
            content.onDrop(of: [.plainText, .utf8PlainText], delegate: LaneDrop(model: model, project: project, status: status))  // action: task status
        } else {
            content
        }
    }
}

/// Where a dragged card will land: a dashed slot at its computed place in the lane (board 7).
struct DropSlot: View {
    let task: Fixture.TaskSummary

    var body: some View {
        Text(task.due.flatMap(TaskBoard.short).map { "lands here: due \($0)" } ?? "lands here")
            .duoText(.control).foregroundStyle(DuoColor.text2)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).strokeBorder(DuoColor.controlEdge, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }
}

/// The lifted card under the pointer (board 7): the popover shadow, tilted 1.5°.
struct CardDragImage: View {
    let title: String
    let width: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: DuoMetric.taskBoardTitleGap) {
            TaskBox().padding(.top, 4)
            Text(title).duoText(.cardTitle).foregroundStyle(DuoColor.text).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DuoMetric.taskBoardCardPadding)
        .frame(width: width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).strokeBorder(DuoColor.rule, lineWidth: 1))
        .duoPopoverShadow()
        .rotationEffect(.degrees(MotionSettings.shared.reduce ? 0 : -1.5))
        .padding(24)
    }
}

/// `› Earlier · n` and `› Dropped · n` under Done (board 4), folded until clicked.
struct BoardFold: View {
    @Environment(AppModel.self) private var model
    let project: String
    let name: String
    let label: String
    let cards: [TaskBoard.Card]

    var body: some View {
        if !cards.isEmpty {
            let key = "\(project)/board-\(name)"
            let open = model.expandedGroups.contains(key)
            VStack(alignment: .leading, spacing: DuoMetric.taskBoardCardGap) {
                HStack(spacing: 8) {
                    Chevron(direction: open ? .down : .right).frame(width: 10)
                    Text("\(label) · \(cards.count)").duoText(.control).foregroundStyle(DuoColor.text2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                .frame(height: 24)
                .contentShape(Rectangle())
                .onActivate { withDuoAnimation(.fold) { if open { model.expandedGroups.remove(key) } else { model.expandedGroups.insert(key) } } }  // action: view group
                .accessibilityLabel(open ? "Hide \(label.lowercased()) tasks" : "Show \(cards.count) \(label.lowercased()) tasks")
                // Dropped has no lane: a card dropped on its fold is dropped (board 7).
                .modifier(DropsAs(project: project, status: name == "dropped" ? "dropped" : nil))
                if open { ForEach(cards) { c in TaskCard(card: c) } }
            }
        }
    }
}

// MARK: - A card

/// A task as a card (boards 6 and 11): box and title; a line of what's known about it; its
/// sessions as rows under a hairline, each a click away.
struct TaskCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.boardLaneWidth) private var laneWidth
    let card: TaskBoard.Card

    var body: some View {
        let t = card.task
        // Just dropped on Done: ticked, struck through and grey while it holds (DL-130).
        let completing = model.boardHeld[t.id] != nil
        let closed = ["done", "dropped"].contains(TaskBoard.key(t.status)) || completing
        let dragged = model.dragging == AppModel.dragPayload(card: t.project, path: t.path)
        let selected = model.rightTab == t.path && !model.rightCollapsed
        let hovered = model.hoveredCard == t.id
        let sessions = model.cardSessions(t)
        VStack(alignment: .leading, spacing: DuoMetric.taskBoardCardLineGap) {
            HStack(alignment: .top, spacing: DuoMetric.taskBoardTitleGap) {
                TaskBox(checked: closed).padding(.top, 4)
                // Broken greedily, as the screens' browser does: SwiftUI balances short paragraphs (F-219).
                let room = laneWidth - 2 * DuoMetric.taskBoardLaneBodyPadding - DuoMetric.taskBoardCardPadding.leading - DuoMetric.taskBoardCardPadding.trailing - DuoMetric.taskBoardMetaIndent - (hovered && !closed ? 18 : 0)
                Text(GreedyLines.wrap(t.title, width: room, font: DuoTextStyle.cardTitle.spec.withWeight(closed ? .regular : nil).nsFont))
                    .duoText(.cardTitle, weight: closed ? .regular : nil)
                    .foregroundStyle(closed ? DuoColor.text2 : DuoColor.text)
                    .strikethrough(completing)
                    .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                if hovered && !closed {
                    NewSessionInTaskButton(project: t.project, path: t.path).frame(height: 18)
                }
            }
            CardMeta(task: t)
            if !sessions.isEmpty { CardSessions(task: t, sessions: sessions) }
        }
        .padding(DuoMetric.taskBoardCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).fill(dragged ? Color.clear : DuoColor.pane))
        .overlay {
            // Its place while it's dragged: a dashed ghost (board 7).
            if dragged {
                RoundedRectangle(cornerRadius: DuoMetric.radiusCard).strokeBorder(DuoColor.controlEdge, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            } else {
                RoundedRectangle(cornerRadius: DuoMetric.radiusCard).strokeBorder(selected ? DuoColor.text : DuoColor.rule, lineWidth: 1)
            }
        }
        .opacity(dragged ? 0.55 : 1)
        .contentShape(Rectangle())
        .onDrag({  // action: task status
            let payload = AppModel.dragPayload(card: t.project, path: t.path)
            model.beginDrag(payload)
            return NSItemProvider(object: payload as NSString)
        }, preview: { CardDragImage(title: t.title, width: max(laneWidth - 2 * DuoMetric.taskBoardLaneBodyPadding, 160)) })
        .onHover { inside in
            if inside { model.hoveredCard = t.id } else if model.hoveredCard == t.id { model.hoveredCard = nil }
        }
        .onActivate { model.selectCard(project: t.project, path: t.path) }  // action: doc open
        // Files or folders dropped on a card become its references (DL-150, board 13).
        // File URLs only, so a card dragged over it still lands on the lane.
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in  // action: task reference
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.isFileURL else { return }
                    DispatchQueue.main.async { MainActor.assumeIsolated { if let why = model.addReference(project: t.project, path: t.path, file: url) { model.info(why) } } }
                }
            }
            return !providers.isEmpty
        }
        .contextMenu { TaskMenuItems(model: model, project: t.project, path: t.path) }   // DL-115
        .accessibilityElement(children: .contain)
        .accessibilityLabel(CardMeta.spoken(t, user: model.fixture.user))
    }
}

/// Line 2 (board 6): `waiting on …`, the owner when it isn't you, the due date (overdue in `text`
/// semibold), `done …`, and the page mark with the references' count (board 13). Missing fields
/// leave no gap.
struct CardMeta: View {
    @Environment(AppModel.self) private var model
    let task: Fixture.TaskSummary

    var body: some View {
        let t = task
        let user = model.fixture.user
        let closed = ["done", "dropped"].contains(TaskBoard.key(t.status))
        let items = Self.items(t, user: user)
        if !items.isEmpty {
            FlowRow(spacing: 10, lineSpacing: 4) {
                if let w = t.waitingOn { Text("waiting on \(TaskBoard.plain(w))").lineLimit(1) }
                if let o = t.owner, !TaskBoard.isYou(o, user: user) {
                    HStack(spacing: 4) { BoardGlyph(.person); Text(TaskBoard.plain(o)).lineLimit(1) }
                }
                if !closed, let due = t.due, let short = TaskBoard.short(due) {
                    if TaskBoard.overdue(t) {
                        HStack(spacing: 4) { BoardGlyph(.calendar, color: DuoColor.text); Text("\(short) · overdue").fontWeight(.semibold) }
                            .foregroundStyle(DuoColor.text)
                    } else {
                        HStack(spacing: 4) { BoardGlyph(.calendar); Text(short) }
                    }
                }
                if closed, let c = t.completed, let short = TaskBoard.short(c) { Text("\(TaskBoard.key(t.status) == "dropped" ? "dropped" : "done") \(short)") }
                if let n = t.references, n > 0 { HStack(spacing: 4) { BoardGlyph(.page); Text("\(n)") }.help("\(n) reference\(n == 1 ? "" : "s")") }
            }
            .duoText(.control)
            .foregroundStyle(DuoColor.text2)
            .padding(.leading, DuoMetric.taskBoardMetaIndent)
        }
    }

    static func items(_ t: Fixture.TaskSummary, user: String) -> [String] {
        var out: [String] = []
        let closed = ["done", "dropped"].contains(TaskBoard.key(t.status))
        if let w = t.waitingOn { out.append("waiting on \(TaskBoard.plain(w))") }
        if let o = t.owner, !TaskBoard.isYou(o, user: user) { out.append("owner \(TaskBoard.plain(o))") }
        if !closed, let d = t.due, let s = TaskBoard.short(d) { out.append(TaskBoard.overdue(t) ? "due \(s), overdue" : "due \(s)") }
        if closed, let c = t.completed, let s = TaskBoard.short(c) { out.append("done \(s)") }
        if let n = t.references, n > 0 { out.append("\(n) reference\(n == 1 ? "" : "s")") }
        return out
    }

    /// VoiceOver's name for a card (board 7): "Pricing page copy, Open, due Oct 18".
    static func spoken(_ t: Fixture.TaskSummary, user: String) -> String {
        ([t.title, TaskBoard.title(TaskBoard.key(t.status))] + items(t, user: user)).joined(separator: ", ")
    }
}

/// S1 (board 11): under a hairline, a Sessions label with the session mark, then a filled row per
/// session (glyph, title, wait; up to 3, then "+n more"). Hover: `selected` and the open arrow; a
/// click opens the session.
struct CardSessions: View {
    @Environment(AppModel.self) private var model
    let task: Fixture.TaskSummary
    let sessions: [Fixture.Session]

    var body: some View {
        let shown = sessions.prefix(Int(DuoMetric.taskBoardSessionRowsMax))
        VStack(alignment: .leading, spacing: DuoMetric.taskBoardSessionRowGap) {
            HStack(spacing: 5) {
                BoardGlyph(.bubble)
                Text("Sessions").font(.system(size: 11)).foregroundStyle(DuoColor.text2)
            }
            .frame(height: 14)
            .padding(.leading, 2)
            ForEach(Array(shown), id: \.id) { s in row(s) }
            if sessions.count > shown.count {
                Text("+\(sessions.count - shown.count) more").duoText(.control).foregroundStyle(DuoColor.text2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onActivate { model.selectCard(project: task.project, path: task.path) }  // action: doc open
            }
        }
        .padding(.top, DuoMetric.taskBoardSessionsRule)
        .overlay(alignment: .top) { Rectangle().fill(DuoColor.selected).frame(height: 1) }
        .padding(.top, DuoMetric.taskBoardSessionsTop - DuoMetric.taskBoardCardLineGap)
    }

    private func row(_ s: Fixture.Session) -> some View {
        let id = s.sessionId ?? ""
        let key = "\(task.id)#\(id)"
        let hovered = model.hoveredCardSession == key
        let needs = s.state == .needsYou
        return HStack(spacing: 6) {
            StateGlyph(s.state)
            Text(s.name).duoText(.control, weight: needs ? .semibold : nil)
                .foregroundStyle(needs ? DuoColor.needsYou : DuoColor.text).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            if let w = s.state.waitText(s.wait, open: model.isRunning(id)) {
                Text(w).duoText(.control).foregroundStyle(DuoColor.text2).lineLimit(1).fixedSize()
            }
            if hovered { BoardGlyph(.jump, color: DuoColor.text).padding(.leading, 4) }
        }
        .padding(.horizontal, 6)
        .frame(height: DuoMetric.taskBoardSessionRowHeight)
        .background(RoundedRectangle(cornerRadius: 4).fill(hovered ? DuoColor.selected : DuoColor.ground))
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { model.hoveredCardSession = key } else if model.hoveredCardSession == key { model.hoveredCardSession = nil }
        }
        .onActivate { model.openCardSession(id, project: task.project) }  // action: session open
        .contextMenu {
            Button("Open Session") { model.openCardSession(id, project: task.project) }  // action: session open
            Button("Copy Link") { model.copySessionLink(s.tabKey) }  // action: session link
        }
        .help("Open \(s.name)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session \(s.name), \(s.state.spokenName). Opens it.")
    }
}

// MARK: - Empty

/// No tasks yet (board 8): centred in the board, a title, the explainer, + New task and a hint.
/// The copy is board 8's, approved for the CX study (DL-147); Q-141 keeps it in step with that study.
struct EmptyBoard: View {
    @Environment(AppModel.self) private var model
    let project: String

    var body: some View {
        VStack(spacing: 8) {
            Text("No tasks yet").duoText(.bodyEmphasis).foregroundStyle(DuoColor.text)
            Text("Most sessions are for a task or a goal. Put them in a task and Duo keeps them together, so you can come back to the work by what it’s for. A task can have many sessions; a session doesn’t need one.")
                .duoText(.body).foregroundStyle(DuoColor.text2).multilineTextAlignment(.center)
                .frame(maxWidth: 380).fixedSize(horizontal: false, vertical: true)
            SmallButton("+ New task") { model.newTask(in: project) }.padding(.top, 4)  // action: task new
            Text("or drag a session here").duoText(.control).foregroundStyle(DuoColor.text2).padding(.top, 2)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The width a lane gives its cards, for their titles' line breaks.
struct BoardLaneWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
extension EnvironmentValues {
    var boardLaneWidth: CGFloat {
        get { self[BoardLaneWidthKey.self] }
        set { self[BoardLaneWidthKey.self] = newValue }
    }
}

/// Line breaks as CSS makes them: as many words as fit, then the next line (F-219). SwiftUI on
/// macOS 26 balances a short paragraph's lines instead ("Analytics / events spec" where the
/// screens draw "Analytics events / spec").
enum GreedyLines {
    static func wrap(_ text: String, width: CGFloat, font: NSFont) -> String {
        guard width > 0 else { return text }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        func w(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: attrs).width }
        var lines: [String] = [], line = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
            let next = line.isEmpty ? word : line + " " + word
            if !line.isEmpty, w(next) > width { lines.append(line); line = word } else { line = next }
        }
        lines.append(line)
        return lines.joined(separator: "\n")
    }
}

// MARK: - Glyphs

/// The board's marks, drawn from the boards' SVGs (`task-board-study/canvas/make.py`).
struct BoardGlyph: View {
    enum Kind { case term, board, bubble, jump, calendar, person, search, updown, page, folder, globe }
    let kind: Kind
    var color: Color = DuoColor.text2

    init(_ kind: Kind, color: Color = DuoColor.text2) { self.kind = kind; self.color = color }

    var size: CGSize {
        switch kind {
        case .term, .bubble: CGSize(width: 13, height: kind == .term ? 10 : 11)
        case .board, .folder: CGSize(width: 12, height: 10)
        case .search, .globe: CGSize(width: 11, height: 11)
        case .updown: CGSize(width: 7, height: 10)
        case .page: CGSize(width: 10, height: 12)
        default: CGSize(width: 10, height: 10)
        }
    }

    /// The SVG's viewBox.
    var box: CGSize {
        switch kind {
        case .search, .globe: CGSize(width: 12, height: 12)
        default: size
        }
    }

    /// The glyph's strokes in its viewBox, each with its width.
    var paths: [(Path, CGFloat)] {
        var out: [(Path, CGFloat)] = []
        switch kind {
        case .term:
            out.append((Path { $0.move(to: .init(x: 1.5, y: 2)); $0.addLine(to: .init(x: 5, y: 5)); $0.addLine(to: .init(x: 1.5, y: 8)) }, 1.5))
            out.append((Path { $0.move(to: .init(x: 6.5, y: 8.5)); $0.addLine(to: .init(x: 11.5, y: 8.5)) }, 1.5))
        case .board:
            out.append((Path(roundedRect: CGRect(x: 1, y: 1, width: 4, height: 8), cornerRadius: 1), 1.2))
            out.append((Path(roundedRect: CGRect(x: 7, y: 1, width: 4, height: 5), cornerRadius: 1), 1.2))
        case .bubble:
            out.append((Path { p in
                p.move(to: .init(x: 2.5, y: 1)); p.addLine(to: .init(x: 10.5, y: 1))
                p.addQuadCurve(to: .init(x: 12, y: 2.5), control: .init(x: 12, y: 1))
                p.addLine(to: .init(x: 12, y: 6.5))
                p.addQuadCurve(to: .init(x: 10.5, y: 8), control: .init(x: 12, y: 8))
                p.addLine(to: .init(x: 6, y: 8)); p.addLine(to: .init(x: 3.5, y: 10)); p.addLine(to: .init(x: 3.5, y: 8))
                p.addLine(to: .init(x: 2.5, y: 8))
                p.addQuadCurve(to: .init(x: 1, y: 6.5), control: .init(x: 1, y: 8))
                p.addLine(to: .init(x: 1, y: 2.5))
                p.addQuadCurve(to: .init(x: 2.5, y: 1), control: .init(x: 1, y: 1))
            }, 1.3))
        case .jump:
            out.append((Path { $0.move(to: .init(x: 3.5, y: 1.5)); $0.addLine(to: .init(x: 8.5, y: 1.5)); $0.addLine(to: .init(x: 8.5, y: 6.5)) }, 1.4))
            out.append((Path { $0.move(to: .init(x: 8.5, y: 1.5)); $0.addLine(to: .init(x: 1.5, y: 8.5)) }, 1.4))
        case .calendar:
            out.append((Path(roundedRect: CGRect(x: 1, y: 1.8, width: 8, height: 7.2), cornerRadius: 1.5), 1.2))
            out.append((Path { $0.move(to: .init(x: 1, y: 4)); $0.addLine(to: .init(x: 9, y: 4)); $0.move(to: .init(x: 3.3, y: 0.8)); $0.addLine(to: .init(x: 3.3, y: 2.8)); $0.move(to: .init(x: 6.7, y: 0.8)); $0.addLine(to: .init(x: 6.7, y: 2.8)) }, 1.2))
        case .person:
            out.append((Path(ellipseIn: CGRect(x: 3, y: 1.4, width: 4, height: 4)), 1.2))
            out.append((Path { $0.move(to: .init(x: 1.5, y: 9)); $0.addCurve(to: .init(x: 5, y: 6.1), control1: .init(x: 1.9, y: 7.1), control2: .init(x: 3.3, y: 6.1)); $0.addCurve(to: .init(x: 8.5, y: 9), control1: .init(x: 6.7, y: 6.1), control2: .init(x: 8.1, y: 7.1)) }, 1.2))
        case .search:
            out.append((Path(ellipseIn: CGRect(x: 1.4, y: 1.4, width: 7.2, height: 7.2)), 1.3))
            out.append((Path { $0.move(to: .init(x: 7.8, y: 7.8)); $0.addLine(to: .init(x: 11, y: 11)) }, 1.3))
        case .updown:
            out.append((Path { p in
                p.move(to: .init(x: 1, y: 3.5)); p.addLine(to: .init(x: 3.5, y: 1)); p.addLine(to: .init(x: 6, y: 3.5))
                p.move(to: .init(x: 1, y: 6.5)); p.addLine(to: .init(x: 3.5, y: 9)); p.addLine(to: .init(x: 6, y: 6.5))
            }, 1.2))
        case .page:
            out.append((Path { p in
                p.move(to: .init(x: 1.5, y: 1.5)); p.addLine(to: .init(x: 6, y: 1.5)); p.addLine(to: .init(x: 8.5, y: 4))
                p.addLine(to: .init(x: 8.5, y: 10.5)); p.addLine(to: .init(x: 1.5, y: 10.5)); p.closeSubpath()
                p.move(to: .init(x: 6, y: 1.5)); p.addLine(to: .init(x: 6, y: 4)); p.addLine(to: .init(x: 8.5, y: 4))
            }, 1.1))
        case .folder:
            out.append((Path { p in
                p.move(to: .init(x: 1, y: 2.2)); p.addQuadCurve(to: .init(x: 2.2, y: 1), control: .init(x: 1, y: 1))
                p.addLine(to: .init(x: 4.5, y: 1)); p.addLine(to: .init(x: 5.7, y: 2.3)); p.addLine(to: .init(x: 9.8, y: 2.3))
                p.addQuadCurve(to: .init(x: 11, y: 3.5), control: .init(x: 11, y: 2.3)); p.addLine(to: .init(x: 11, y: 7.8))
                p.addQuadCurve(to: .init(x: 9.8, y: 9), control: .init(x: 11, y: 9)); p.addLine(to: .init(x: 2.2, y: 9))
                p.addQuadCurve(to: .init(x: 1, y: 7.8), control: .init(x: 1, y: 9)); p.closeSubpath()
            }, 1.1))
        case .globe:
            out.append((Path(ellipseIn: CGRect(x: 1.2, y: 1.2, width: 9.6, height: 9.6)), 1.1))
            out.append((Path { p in
                p.move(to: .init(x: 1.2, y: 6)); p.addLine(to: .init(x: 10.8, y: 6))
                p.move(to: .init(x: 6, y: 1.2)); p.addCurve(to: .init(x: 6, y: 10.8), control1: .init(x: 7.6, y: 2.6), control2: .init(x: 7.6, y: 9.4))
                p.move(to: .init(x: 6, y: 1.2)); p.addCurve(to: .init(x: 6, y: 10.8), control1: .init(x: 4.4, y: 2.6), control2: .init(x: 4.4, y: 9.4))
            }, 1.1))
        }
        return out
    }

    var body: some View {
        Canvas { ctx, rect in
            ctx.scaleBy(x: rect.width / box.width, y: rect.height / box.height)
            for (p, w) in paths { ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)) }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}
