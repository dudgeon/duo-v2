import SwiftUI

// The project pane's new rows (DL-217, DL-218; docs/design/sidebar-hierarchy-handoff/): PINNED's label with
// its Keep Running +, OPEN's label with its New session +, the Later fold, and the director's two-line slot.

/// PINNED · n. On hover the + is Keep Running: a menu of the open sessions not yet kept. The menu's look is
/// a stand-in (Q-207).
struct PinnedHeader: View {
    @Environment(AppModel.self) private var model
    let project: String
    let count: Int

    var body: some View {
        let hovered = model.hoveredTaskRow == "\(project)/pinned-head"
        let candidates = model.fixture.sessions(inProject: project).filter { model.hasOpenTerminal($0.tabKey) && !model.isKeepRunning($0.tabKey) }
        SectionLabel(text: "Pinned", count: count)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) {
                Menu {
                    ForEach(candidates) { s in
                        Button(s.name) { model.setKeepRunning(s.tabKey, true) }   // action: session keep-running
                    }
                } label: {
                    Text("+").font(.system(size: DuoMetric.rowActionGlyph)).foregroundStyle(DuoColor.text2)
                        .frame(width: DuoMetric.rowActionSize, height: DuoMetric.rowActionSize)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .opacity(hovered && !candidates.isEmpty ? 1 : 0)
                .allowsHitTesting(hovered && !candidates.isEmpty)
                .help("Keep a session running")
                .accessibilityLabel("Keep Running")
            }
            .padding(EdgeInsets(top: 12, leading: DuoSpace.panePadding, bottom: 4, trailing: DuoSpace.panePadding))
            .background(DuoColor.pane)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { model.hoveredTaskRow = "\(project)/pinned-head" } else if model.hoveredTaskRow == "\(project)/pinned-head" { model.hoveredTaskRow = nil }
            }
    }
}

/// OPEN · n: the + is New Claude Code session (it moved here from OTHER SESSIONS).
struct OpenHeader: View {
    @Environment(AppModel.self) private var model
    let project: String
    let count: Int

    var body: some View {
        SectionHeaderPlus(text: "Open", count: count, hoverKey: "\(project)/open-head", label: "New Claude Code session",
                          help: "Start a Claude Code session in this project") {
            model.newSession()  // action: session new
        }
    }
}

/// Later · n: a fold row among the tasks, `rowGroup` like the time groups (DL-217): a chevron, the name in
/// `bodyEmphasis`, the count in `text2`. Starts folded; Duo remembers per project.
struct LaterFoldRow: View {
    @Environment(AppModel.self) private var model
    let project: String
    let section: SidebarSection

    var body: some View {
        let folded = model.timeGroupFolded(project: project, "later")
        HStack(spacing: DuoSpace.gapRowItems) {
            Chevron(direction: folded ? .right : .down).frame(width: 10)
            Text("Later").duoText(.bodyEmphasis).lineLimit(1)
            Spacer(minLength: 8)
            Text("\(section.rows.count)").duoText(.body).foregroundStyle(DuoColor.text2)
        }
        .padding(.horizontal, 8 + DuoSpace.selectionInset)
        .frame(height: DuoMetric.rowGroup)
        .background(DuoColor.pane)
        .contentShape(Rectangle())
        .onActivate { withDuoAnimation(.fold) { model.toggleTimeGroup(project: project, "later") } }  // action: view group
        .accessibilityLabel("Later, \(section.rows.count) tasks, \(folded ? "folded" : "open")")
    }
}

/// The director's two-line slot (DL-218): the glyph top-aligned with the first line (name in
/// `bodyEmphasis`, the Keep Running pin, the wait); the second line in `control` `text2`. A replaced
/// director still open has its name in `text2`, "Replaced 2h ago" and Close.
struct DirectorSlotRow: View {
    @Environment(AppModel.self) private var model
    let row: SidebarRow
    let slot: SidebarRow.Slot

    var body: some View {
        let key = row.sessionKey
        let open = model.hasOpenTerminal(key)
        let kind = model.sessionKind(key: key, project: model.currentProject?.name ?? "")
        let replaced: Bool = { if case .replaced = slot { return true }; return false }()
        // Not open: the idle glyph and the last wait (DL-218 state 3).
        let state: SessionState = open || row.state == .needsYou ? row.state : .idle
        let narrow = model.sidebarWidth < 280
        HStack(alignment: .top, spacing: DuoSpace.gapRowItems) {
            Color.clear.frame(width: 10, height: 10)
            SessionGlyph(kind: kind, state: state).frame(height: 16)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DuoSpace.gapRowItems) {
                    Text(row.name).duoText(replaced ? .body : .bodyEmphasis).foregroundStyle(replaced ? DuoColor.text2 : DuoColor.text).lineLimit(1)
                    if row.pinned { KeepRunningPin(color: DuoColor.text2) }
                    Spacer(minLength: 8)
                    WaitLabel(text: state.waitText(row.wait, open: open))
                }
                .frame(height: 16)
                HStack(spacing: DuoSpace.gapRowItems) {
                    Text(second(narrow: narrow, open: open)).duoText(.control).foregroundStyle(DuoColor.text2).lineLimit(1)
                    Spacer(minLength: 8)
                    if replaced {
                        Button("Close") { model.closeConsoleTab(key) }.buttonStyle(.duo)   // action: session close
                    }
                }
                .frame(minHeight: 16)
            }
        }
        .padding(.leading, DuoSpace.panePadding - DuoSpace.selectionInset).padding(.trailing, DuoSpace.panePadding - DuoSpace.selectionInset)
        .padding(.vertical, 5)
        .background { RoundedRectangle(cornerRadius: DuoMetric.radiusSelection).fill(open ? DuoColor.activeTint : Color.clear) }
        .padding(.horizontal, DuoSpace.selectionInset)
        .background(DuoColor.pane)
        .contentShape(Rectangle())
        .onActivate { model.openConsoleTab(key) }  // action: session open
        .modifier(SessionOrganizeMenu(sessionKey: key))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(open: open))
        .accessibilityIdentifier("video.session.\(row.name)")
    }

    /// "Director · 2 workers", "Director · needs you · 2 workers", "Director · not open", "Replaced 2h ago".
    func second(narrow: Bool, open: Bool) -> String {
        switch slot {
        case .replaced(let ago): return ago.isEmpty ? "Replaced" : "Replaced \(ago) ago"
        case .director(let isOpen, let needsYou, let workers, let need, let projects):
            var parts: [String] = []
            if !narrow { parts.append("Director") }
            if needsYou { parts.append("needs you") } else if !isOpen && !open { parts.append("not open") }
            if let projects { parts.append("\(projects) project\(projects == 1 ? "" : "s")") }
            if projects != nil || workers > 0 { parts.append("\(workers) worker\(workers == 1 ? "" : "s")") }
            if need > 0 { parts.append("\(need) needs you") }
            return parts.joined(separator: " · ")
        }
    }

    func spoken(open: Bool) -> String {
        let kind = SessionGlyph.spokenKind(model.sessionKind(key: row.sessionKey, project: model.currentProject?.name ?? ""))
        switch slot {
        case .replaced(let ago): return "\(row.name), replaced director\(ago.isEmpty ? "" : ", \(ago) ago"), \(kind), \(row.state.spokenName)"
        case .director(_, _, let workers, _, _):
            return "\(row.name), director, \(kind), \(row.state.spokenName), \(workers) workers\(row.pinned ? ", kept running" : "")"
        }
    }
}
