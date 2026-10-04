import SwiftUI

// All projects (handoff §3.2). Targets: screens/overview.html, flow-zoom-1.html, flow-zoom-4.html.

// MARK: - Home pane

/// The Home terminal pane: header, one tab per live Home session, then the terminal. The body is
/// Claude Code's own TUI (handoff §0.4), so it stays empty until terminals exist (Phase D).
struct HomePane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let home = model.fixture.home
        let tabs = home.map { model.tabSessions(inProject: $0.name) } ?? []
        VStack(spacing: 0) {
            HStack(spacing: DuoSpace.gapRowItems) {
                Text("★ \(home?.name ?? "home")")
                    .duoText(.bodyEmphasis)
                    .foregroundStyle(DuoColor.consoleText)
                Spacer(minLength: 8)
                Text(home?.path ?? "")
                    .duoText(.mono)
                    .foregroundStyle(DuoColor.consoleText2)
                    .lineLimit(1)
            }
            .padding(.horizontal, DuoSpace.panePadding)
            .frame(height: DuoMetric.tabStripHeight)
            ConsoleRule()

            HStack(spacing: 16) {
                ForEach(tabs) { s in
                    let active = s.tabKey == model.homeTab
                    HStack(spacing: DuoSpace.gapGlyphToLabel) {
                        StateGlyph(s.state, on: .console(active: active))
                        Text(s.name)
                            .duoText(active ? .monoActiveTab : .mono)
                            .foregroundStyle(active ? DuoColor.consoleText : DuoColor.consoleText2)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .onActivate { model.homeTab = s.tabKey }  // action: session open
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DuoSpace.panePadding)
            .frame(height: DuoMetric.homeSessionTabsHeight)
            ConsoleRule()

            if let home, let tab = model.homeTab, let t = model.terminal(project: home.name, session: tab) {
                TerminalSlot(session: t)
            } else {
                Color.clear
            }
        }
        .background(DuoColor.console)
    }
}

struct ConsoleRule: View {
    var body: some View { DuoColor.consoleRule.frame(height: 1) }
}

// MARK: - Project map

struct ProjectMapPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let f = model.fixture
        VStack(spacing: 0) {
            ScrollView {
                HStack(alignment: .top, spacing: DuoSpace.gapMapColumns) {
                    ForEach(Array(f.topics.enumerated()), id: \.element) { i, topic in
                        VStack(alignment: .leading, spacing: DuoSpace.gapTileToTile) {
                            SectionLabel(text: topic)
                            ForEach(f.projects(inTopic: topic)) { p in
                                ProjectTile(project: p)
                            }
                            if i == f.topics.count - 1 {
                                NewProjectTile()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .padding(DuoSpace.panePadding)
            }
            .scrollIndicators(.automatic)
            // Arrow keys move between tiles, Enter opens the focused one (handoff §6.3).
            .focusable()
            .focusEffectDisabled()
            .onMoveCommand { direction in
                switch direction {
                case .left: model.moveTileFocus(dx: -1, dy: 0)
                case .right: model.moveTileFocus(dx: 1, dy: 0)
                case .up: model.moveTileFocus(dx: 0, dy: -1)
                case .down: model.moveTileFocus(dx: 0, dy: 1)
                @unknown default: break
                }
            }
            .onKeyPress(.return) {
                guard let tile = model.focusedTile else { return .ignored }
                model.open(project: tile)
                return .handled
            }

            DuoColor.rule.frame(height: 1)
            HStack(spacing: DuoSpace.gapRowItems) {
                StateGlyph(.idle)
                Text("\(f.counts.idle) idle, resumable").duoText(.body)
                Chevron()
            }
            .foregroundStyle(DuoColor.text2)
            .padding(.horizontal, DuoSpace.panePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: DuoMetric.overviewFooterHeight)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(f.counts.idle) idle sessions, resumable")
        }
        .foregroundStyle(DuoColor.text)
        .background(DuoColor.pane)
    }
}

/// A project tile (handoff §5 `ProjectTile`): name, goal, health · next, then its live sessions.
struct ProjectTile: View {
    @Environment(AppModel.self) private var model
    let project: Fixture.Project

    var body: some View {
        let focused = model.focusedTile == project.name
        let sessions = model.fixture.liveSessions(inProject: project.name)
        VStack(alignment: .leading, spacing: DuoSpace.gapTileRows) {
            // flow-zoom-1 wraps both the name and the hint when the hint is shown, as CSS flex
            // shrinks them (the target wins over handoff §8's truncation proposal).
            FlexShrinkRow {
                Text(project.name).duoText(.bodyEmphasis)
                if focused {
                    // Non-breaking space: SwiftUI avoids a one-word last line ("Enter" / "to open");
                    // the target breaks "Enter to" / "open" (findings F-13).
                    Text("Enter\u{00A0}to open").duoText(.body).foregroundStyle(DuoColor.text2)
                }
            }
            if project.isFolderOnly {
                // A folder with Claude sessions but no PROJECT.md (DL-63).
                Text(project.path).duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1).truncationMode(.middle)
                Text(project.hasClaudeMD == true ? "Has CLAUDE.md · no project file" : "No project file")
                    .duoText(.body).foregroundStyle(DuoColor.text2)
            } else {
                Text(project.goal).duoText(.body).fixedSize(horizontal: false, vertical: true)
                Text([project.health, project.next].compactMap { $0 }.joined(separator: " · "))
                    .duoText(.body)
                    .foregroundStyle(DuoColor.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if sessions.isEmpty, project.isFolderOnly {
                let n = model.fixture.sessions(inProject: project.name).count
                Text("\(n) past session\(n == 1 ? "" : "s")")
                    .duoText(.body)
                    .foregroundStyle(DuoColor.text2)
                    .frame(height: DuoMetric.rowTileSession)
                    .padding(.top, 6)
            } else if sessions.isEmpty {
                Text("Nothing running")
                    .duoText(.body)
                    .foregroundStyle(DuoColor.text2)
                    .frame(height: DuoMetric.rowTileSession)
                    .padding(.top, 6)
            } else {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                    TileSessionRow(session: s, selected: model.selectedActionSession == s.id)
                        .padding(.top, i == 0 ? 6 : 0)
                        .contentShape(Rectangle())
                        .onActivate { model.open(project: project.name, session: s.name) }  // action: open
                        .modifier(SessionOrganizeMenu(sessionKey: s.tabKey))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bordered(DuoSpace.cardPadding, color: focused ? DuoColor.text : DuoColor.rule)
        .overlay {
            if focused {
                // The target's `box-shadow: 0 0 0 1px` ring outside the border: a 2 pt outline.
                RoundedRectangle(cornerRadius: DuoMetric.radiusCard + 1)
                    .strokeBorder(DuoColor.text, lineWidth: 1)
                    .padding(-1)
            }
        }
        .contentShape(Rectangle())
        .onActivate { model.open(project: project.name) }  // action: open
        .modifier(ProjectOrganizeMenu(project: project))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tileLabel(sessions))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.open(project: project.name) }
    }

    private func tileLabel(_ sessions: [Fixture.Session]) -> String {
        var parts = [project.name]
        if let h = project.health { parts.append(h.lowercased()) }
        for state in [SessionState.needsYou, .readyForReview, .working] {
            let n = sessions.filter { $0.state == state }.count
            if n > 0 { parts.append("\(n) \(state.spokenName)") }
        }
        return parts.joined(separator: ", ")
    }
}

/// A 24-high session row inside a tile: glyph, name, wait time (no time for ready for review).
struct TileSessionRow: View {
    let session: Fixture.Session
    var selected = false

    var body: some View {
        HStack(spacing: DuoSpace.gapRowItems) {
            StateGlyph(session.state)
            Text(session.name)
                .duoText(.body, weight: selected ? .semibold : nil)
                .lineLimit(1)
            Spacer(minLength: 8)
            if session.state != .readyForReview { WaitLabel(text: session.wait) }
        }
        .frame(height: DuoMetric.rowTileSession)
        .padding(.horizontal, selected ? 6 : 0)
        .background {
            if selected { RoundedRectangle(cornerRadius: DuoMetric.radiusSelection).fill(DuoColor.selected) }
        }
        .padding(.horizontal, selected ? -6 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.name), \(session.state.spokenName)\(session.wait.map { ", waiting \($0)" } ?? "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// `+ New project`: dashed, 38 high. The create-project flow is not designed (handoff §13).
struct NewProjectTile: View {
    var body: some View {
        Text("+ New project")
            .duoText(.body)
            .foregroundStyle(DuoColor.text2)
            .frame(maxWidth: .infinity)
            // 38 pt plus its 1 pt border on each side: CSS content-box (findings F-10).
            .frame(height: DuoMetric.newProjectTileHeight + 2 * DuoMetric.borderHairline)
            .overlay(
                RoundedRectangle(cornerRadius: DuoMetric.radiusCard)
                    .strokeBorder(DuoColor.controlEdge, style: StrokeStyle(lineWidth: 1, dash: DuoMetric.dashPattern))
            )
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Action column

struct ActionColumnPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let f = model.fixture
        let needsYou = f.needsYou
        let reviews = f.sessions.filter { $0.state == .readyForReview }
        ScrollView {
            VStack(alignment: .leading, spacing: DuoSpace.gapCardToCard) {
                if !needsYou.isEmpty {
                    SectionLabel(text: "Needs you", count: needsYou.count, needsYou: true)
                    ForEach(needsYou) { s in
                        if s.project == f.home?.name {
                            HomePointerCard(session: s)
                        } else {
                            NeedsYouCard(session: s, selected: model.selectedActionSession == s.id)
                        }
                    }
                }
                if !reviews.isEmpty {
                    SectionLabel(text: "Ready for review", count: reviews.count)
                        .padding(.top, needsYou.isEmpty ? 0 : 6)
                    ForEach(reviews) { s in ReviewCard(session: s) }
                }
            }
            .padding(DuoSpace.panePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(DuoColor.text)
        .background(DuoColor.pane)
    }
}

/// Glyph, name (semibold), optional suffix, wait time right-aligned.
struct CardHeader: View {
    let session: Fixture.Session
    var suffix: String?
    var showsWait = true

    var body: some View {
        HStack(spacing: DuoSpace.gapRowItems) {
            StateGlyph(session.state)
            Text(session.name).duoText(.bodyEmphasis).lineLimit(1)
            if let suffix { Text(suffix).duoText(.body).foregroundStyle(DuoColor.text2).fixedSize() }
            Spacer(minLength: 8)
            if showsWait { WaitLabel(text: session.wait) }
        }
    }
}

/// A session needing you (handoff §5 `ActionCard`). The question is shown verbatim. No reply
/// buttons: DL-29.
struct NeedsYouCard: View {
    @Environment(AppModel.self) private var model
    let session: Fixture.Session
    var selected = false

    var body: some View {
        VStack(alignment: .leading, spacing: DuoSpace.gapCardContent) {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(session: session)
                Text(session.project).duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1)
            }
            if let q = session.question {
                Text(q)
                    .duoText(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(QuestionBox(boxed: selected))
            }
            HStack(spacing: DuoSpace.gapButtonToButton) {
                Button("Open project") { model.open(project: session.project, session: session.name) }.buttonStyle(.duo)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bordered(DuoSpace.cardPadding,
                  color: selected ? DuoColor.text : DuoColor.rule,
                  width: selected ? DuoMetric.borderEmphasis : DuoMetric.borderHairline)
        .contentShape(Rectangle())
        .onActivate { model.selectedActionSession = session.id }  // action: view select
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(session.name), needs you, waiting \(session.wait ?? ""), \(session.project)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// On the selected card the question sits in a 1.5 pt `needsYou` box (handoff §3.2).
struct QuestionBox: ViewModifier {
    let boxed: Bool

    func body(content: Content) -> some View {
        if boxed {
            content.bordered(DuoSpace.questionBoxPadding, color: DuoColor.needsYou, width: DuoMetric.borderEmphasis)
        } else {
            content
        }
    }
}

/// A Home session needing you is a pointer, not a card: the Home terminal is already on screen.
struct HomePointerCard: View {
    @Environment(AppModel.self) private var model
    let session: Fixture.Session

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(session: session, suffix: session.project)
            Text("← Waiting in the Home terminal").duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bordered(DuoSpace.pointerCardPadding, color: DuoColor.controlEdge, dashed: true)
        .contentShape(Rectangle())
        .onActivate { model.homeTab = session.tabKey; model.focusHomeRequest += 1 }  // action: session open
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.name), needs you, waiting in the Home terminal")
    }
}

/// A session with a deliverable to review (handoff §3.2).
struct ReviewCard: View {
    @Environment(AppModel.self) private var model
    let session: Fixture.Session

    var body: some View {
        VStack(alignment: .leading, spacing: DuoSpace.gapTileRows) {
            CardHeader(session: session, showsWait: false)
            Text(session.project).duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1)
            if let summary = session.summary {
                Text(summary).duoText(.body).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: DuoSpace.gapButtonToButton) {
                Button("Review") { model.open(project: session.project, session: session.name, document: session.document) }
                    .buttonStyle(.duo)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bordered(DuoSpace.cardPadding)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(session.name), ready for review, \(session.project)")
    }
}


// MARK: - Organising (DL-63–DL-66), live mode only

/// Right-click a session: move it to a project. It can be dragged onto a project tile too.
struct SessionOrganizeMenu: ViewModifier {
    @Environment(AppModel.self) private var model
    let sessionKey: String

    func body(content: Content) -> some View {
        if model.terminalsMode == .live, let s = model.fixture.sessions.first(where: { $0.tabKey == sessionKey }), let id = s.sessionId {
            let payload = AppModel.dragPayload(session: id)
            content
                .contextMenu {
                    SendMenu { _ in model.sessionPayload(sessionKey) }
                    Button("Find Similar") { model.findSimilar(session: sessionKey) }
                    Divider()
                    Menu("Move to Project") {
                        ForEach(model.moveTargets(excluding: s.project)) { p in
                            Button(p.isFolderOnly ? "\(p.name) (folder)" : p.name) { model.moveSessions([id], to: p.name) }
                        }
                    }
                }
                .modifier(Lifted(active: model.dragging == payload))
                .onDrag({  // action: session move
                    model.beginDrag(payload)
                    return NSItemProvider(object: payload as NSString)
                }, preview: { DragCard(title: s.name, detail: s.project) })
        } else {
            content
        }
    }
}

/// Right-click a project or folder: merge it into another, or make a folder a project. Tiles
/// can be dragged onto each other, and take dropped sessions and projects (with a confirmation).
struct ProjectOrganizeMenu: ViewModifier {
    @Environment(AppModel.self) private var model
    let project: Fixture.Project

    func body(content: Content) -> some View {
        if model.terminalsMode == .live, project.isHome != true {
            let payload = AppModel.dragPayload(project: project.name)
            content
                .contextMenu {
                    SendMenu { _ in model.projectPayload(project.name) }
                    Divider()
                    if project.isFolderOnly {
                        Button("Make a Project") { model.makeProject(project.name) }
                    }
                    Menu(project.isFolderOnly ? "Merge Sessions Into" : "Merge Into") {
                        ForEach(model.moveTargets(excluding: project.name)) { p in
                            Button(p.isFolderOnly ? "\(p.name) (folder)" : p.name) { model.mergeProject(project.name, into: p.name) }
                        }
                    }
                }
                .modifier(Lifted(active: model.dragging == payload))
                .modifier(DropTarget(name: project.name))
                .onDrag({  // action: project merge
                    model.beginDrag(payload)
                    return NSItemProvider(object: payload as NSString)
                }, preview: { DragCard(title: project.name, detail: project.isFolderOnly ? project.path : project.goal) })
                .modifier(TakesDrops(name: project.name))
        } else if model.terminalsMode == .live {
            // Home takes drops (sessions move into Home) but isn't merged away.
            content.contextMenu { SendMenu { _ in model.projectPayload(project.name) } }
                .modifier(DropTarget(name: project.name))
                .modifier(TakesDrops(name: project.name))
        } else {
            content
        }
    }
}

// MARK: Drag and drop feel (Geoff, 2026-10-04: an opaque card with a shadow, motion when picked
// up and when it moves in, and a clear result; F-51)

/// What follows the pointer: the item as a white card with the popover shadow, so it reads
/// clearly over other tiles.
struct DragCard: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).duoText(.bodyEmphasis).foregroundStyle(DuoColor.text).lineLimit(1)
            if !detail.isEmpty { Text(detail).duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(2) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 190, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
        // The popover shadow token (0 12 32, the text colour at 22%).
        .shadow(color: DuoColor.text.opacity(0.22), radius: 16, x: 0, y: 12)
        .padding(24)  // room for the shadow inside the drag image
    }
}

/// The item left behind while it's being dragged: it sinks back, so the pick-up registers.
struct Lifted: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .opacity(active ? 0.35 : 1)
            .scaleEffect(active ? 0.96 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: active)
    }
}

/// A tile under a dragged item rises to meet it; a tile that just took a drop pulses.
struct DropTarget: ViewModifier {
    @Environment(AppModel.self) private var model
    let name: String

    func body(content: Content) -> some View {
        let hot = model.dropTarget == name && model.dragging != AppModel.dragPayload(project: name)
        let landed = model.landed == name
        content
            .overlay {
                RoundedRectangle(cornerRadius: DuoMetric.radiusCard + 1)
                    .strokeBorder(DuoColor.text, lineWidth: 2)
                    .padding(-1)
                    .opacity(hot ? 1 : 0)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DuoMetric.radiusCard)
                    .fill(DuoColor.selected)
                    .opacity(landed ? 0.5 : 0)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) {
                if landed {
                    Text(model.landedNote)
                        .duoText(.bodyEmphasis)
                        .foregroundStyle(DuoColor.text)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(DuoColor.pane))
                        .overlay(Capsule().strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
                        .padding(8)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .scaleEffect(hot ? 1.03 : 1)
            .shadow(color: DuoColor.text.opacity(hot ? 0.18 : 0), radius: 12, x: 0, y: 6)
            .animation(.spring(response: 0.28, dampingFraction: 0.68), value: hot)
            .animation(.easeOut(duration: 0.4), value: landed)
    }
}

/// Takes a dropped session or project (the confirmation follows; DL-66).
struct TakesDrops: ViewModifier {
    @Environment(AppModel.self) private var model
    let name: String

    func body(content: Content) -> some View {
        content.onDrop(of: [.plainText, .utf8PlainText], isTargeted: Binding(  // action: project merge
            get: { model.dropTarget == name },
            set: { on in
                if on { model.dropTarget = name } else if model.dropTarget == name { model.dropTarget = nil }
            })) { providers in
            DuoLog.write("drop on \(name): \(providers.count) item(s)")
            guard let item = providers.first else { return false }
            _ = item.loadObject(ofClass: NSString.self) { obj, err in
                if let err { DuoLog.write("drop on \(name): couldn't read it: \(err)") }
                guard let payload = obj as? String else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { model.handleDrop(payload, onto: name) } }
            }
            return true
        }
    }
}
