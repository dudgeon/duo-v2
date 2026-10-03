import SwiftUI

/// The unified compact toolbar (handoff §3.1). The system draws the frame and material; the
/// contents and their order match the targets.
struct DuoToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            SidebarToggle()
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .navigation) {
            if model.altitude.isAllProjects {
                AllProjectsTitle()
            } else {
                ProjectBreadcrumb()
            }
        }
        .sharedBackgroundVisibility(.hidden)

        // The target pushes the Jump field to the trailing edge (`margin-left: auto`).
        ToolbarSpacer(.flexible)

        ToolbarItem(placement: .primaryAction) {
            JumpField()
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

struct SidebarToggle: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.leftCollapsed.toggle()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 14))
                .foregroundStyle(DuoColor.text2)
        }
        .buttonStyle(.plain)
        .help(model.leftCollapsed ? "Show sidebar" : "Hide sidebar")
        .accessibilityLabel("Toggle sidebar")
    }
}

/// `All projects` then the four counts, gap 16 (handoff §3.1).
struct AllProjectsTitle: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let c = model.fixture.counts
        HStack(spacing: DuoSpace.gapToolbarOverview) {
            Text("All projects").duoText(.bodyEmphasis).foregroundStyle(DuoColor.text)
            Count(state: .needsYou, text: "\(c.needsYou) need you")
            Count(state: .readyForReview, text: "\(c.readyForReview) to review")
            Count(state: .working, text: "\(c.working) working")
            Count(state: .idle, text: "\(c.idle) idle")
        }
        .fixedSize()
    }

    struct Count: View {
        let state: SessionState
        let text: String

        var body: some View {
            HStack(spacing: DuoSpace.gapGlyphToLabel) {
                StateGlyph(state)
                Text(text)
                    .duoText(.body, weight: state == .needsYou ? .semibold : nil)
                    .foregroundStyle(state == .needsYou ? DuoColor.needsYou : state == .idle ? DuoColor.text2 : DuoColor.text)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// `All projects` › project name › needs-you chip, gap 8 (handoff §3.1).
struct ProjectBreadcrumb: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: DuoSpace.gapToolbarProject) {
            Button {
                model.zoomOut()
            } label: {
                Text("All projects")
                    .duoText(.body)
                    .underline(color: DuoColor.controlEdge)
                    .foregroundStyle(DuoColor.text2)
            }
            .buttonStyle(.plain)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DuoColor.text2)
                .accessibilityHidden(true)
            Text(model.currentProject?.name ?? "").duoText(.bodyEmphasis).foregroundStyle(DuoColor.text)
            NeedsYouChip()
                .padding(.leading, 8)
        }
        .fixedSize()
    }
}

/// Count of sessions needing you outside this project. Hidden at zero (handoff §3.1).
struct NeedsYouChip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let count = model.needsYouElsewhere.count
        if count > 0 {
            let open = model.peekOpen
            Button {
                model.togglePeek()
            } label: {
                HStack(spacing: DuoSpace.gapGlyphToLabel) {
                    Circle()
                        .fill(open ? DuoColor.onNeedsYou : DuoColor.needsYou)
                        .frame(width: DuoMetric.glyph, height: DuoMetric.glyph)
                    Text("\(count) need you").duoText(.chip)
                }
                .foregroundStyle(open ? DuoColor.onNeedsYou : DuoColor.needsYou)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: DuoMetric.radiusControl)
                        .fill(open ? DuoColor.needsYou : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DuoMetric.radiusControl)
                        .strokeBorder(DuoColor.needsYou, lineWidth: DuoMetric.borderEmphasis)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(get: { model.peekOpen }, set: { model.peekOpen = $0 }), arrowEdge: .bottom) {
                PeekView().environment(model)
            }
            .accessibilityLabel("\(count) sessions need you in other projects")
        }
    }
}

/// The jump field (handoff §3.1). The ⌘K palette it opens is not designed yet (§13), so for now
/// it is the field's look with no action.
struct JumpField: View {
    var body: some View {
        HStack(spacing: DuoSpace.gapGlyphToLabel) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
            Text("Jump to a project, group or session")
                .duoText(.body)
            Spacer(minLength: 4)
            Text("⌘K").duoText(.body)
        }
        .foregroundStyle(DuoColor.text2)
        .padding(.horizontal, 8)
        .frame(width: DuoMetric.jumpFieldWidth, height: DuoMetric.jumpFieldHeight)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusField).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusField).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jump to a project, group or session")
        .accessibilityAddTraits(.isSearchField)
    }
}
