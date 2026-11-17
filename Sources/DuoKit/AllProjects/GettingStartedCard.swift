import AppKit
import DuoControl
import SwiftUI

/// The Getting started with Duo card (DL-348, first-run-welcome-handoff B1 and B2): at the top of All projects,
/// three optional steps that tick on the real action, the director as a line, the intro film's poster, Hide.
/// Done after three ticks folds it away; Hide leaves a notice with Undo for 8 s. Help › Getting Started brings it back.
struct GettingStartedSlot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let g = GettingStarted.shared
        Group {
            if g.visible {
                GettingStartedCard()
            } else if g.noticeOpen {
                GettingStartedNotice()
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// The card: `gs` in B1, a one-row "That's the basics" when all three are done (B2).
struct GettingStartedCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let g = GettingStarted.shared
        Group {
            if g.allDone { done } else { steps }
        }
        .padding(EdgeInsets(top: 14 + DuoMetric.borderHairline, leading: 16 + DuoMetric.borderHairline, bottom: 14 + DuoMetric.borderHairline, trailing: 16 + DuoMetric.borderHairline))
        .background(RoundedRectangle(cornerRadius: DuoMetric.gettingStartedRadius).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.gettingStartedRadius).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { GettingStarted.shared.cardWidth = $0 }
        .accessibilityLabel("Getting started with Duo, \(g.count) of 3")
        .accessibilityIdentifier("getting-started")
    }

    // MARK: Three steps

    private var steps: some View {
        let g = GettingStarted.shared
        return Group {
            if g.cardWidth >= 640 || g.cardWidth == 0 {
                HStack(alignment: .top, spacing: 20) { left.frame(maxWidth: .infinity, alignment: .leading); poster }
            } else {
                left   // narrow: the poster goes (Q-593)
            }
        }
        .animation(nil, value: g.count)
    }

    private var left: some View {
        let g = GettingStarted.shared
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Getting started with Duo").duoText(.title).foregroundStyle(DuoColor.text)
                Text("\(g.count) of 3 · all optional").duoText(.control).foregroundStyle(DuoColor.text2)
                Spacer(minLength: 8)
                SmallButton("Hide") { GettingStarted.shared.hide() }  // action: getting-started hide
            }
            .padding(.bottom, 6)
            Text("Duo keeps your Claude Code sessions in projects, beside the files they work on. Every session already on this Mac is listed below.")
                .duoText(.body).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
            stepRow(.project, name: "Open a project, or make one", line: "A project is a folder with a _PROJECT.md. Sessions started in it belong to it.") {
                if !g.ticked(.project) { SmallButton("Make a project…") { model.showNewProject() } }  // action: project new
            }
            stepRow(.session, name: "Start a session", line: "One conversation with Claude. It shows as Chat or as Terminal; switch on its tab.") {
                if !g.ticked(.session) { SmallButton("New session") { model.newSession() } }  // action: session new
            }
            stepRow(.task, name: "Make a task", line: "A note for one piece of work. It gathers the sessions working on it.") {
                if !g.ticked(.task), let p = model.gettingStartedTaskProject { SmallButton("Make a task…") { model.newTask(in: p) } }  // action: task new
            }
            directorLine
        }
    }

    /// One step: the box (22 column), its name and line, its buttons at the right. Ticked, the name is struck through
    /// in `text2` and the line says what was done; only step 2 keeps Show me (B2).
    private func stepRow<Buttons: View>(_ step: GettingStartedStep, name: String, line: String, @ViewBuilder buttons: () -> Buttons) -> some View {
        let g = GettingStarted.shared
        let ticked = g.ticked(step)
        let said = g.detail(step).map { GettingStartedWords.line(step, detail: $0) } ?? line
        return VStack(spacing: 0) {
            DuoColor.selected.frame(height: DuoMetric.borderHairline)
            HStack(alignment: .top, spacing: 8) {
                StepBox(ticked: ticked).frame(width: 22, alignment: .leading).padding(.top, 3)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).duoText(ticked ? .body : .bodyEmphasis).strikethrough(ticked).foregroundStyle(ticked ? DuoColor.text2 : DuoColor.text)
                    Text(said).duoText(.body).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    buttons()
                    if !ticked || step == .session { SmallButton("Show me") { model.gettingStartedShowMe(step) } }  // action: explain
                }
                .padding(.top, 1)
            }
            .padding(.vertical, 7)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name), \(ticked ? "done" : "not yet")")
    }

    /// The director is a line to know about, never a step: ○, no box, no count (Q-534).
    private var directorLine: some View {
        VStack(spacing: 0) {
            DuoColor.selected.frame(height: DuoMetric.borderHairline)
            HStack(alignment: .top, spacing: 8) {
                Text("○").duoText(.body).foregroundStyle(DuoColor.text2).frame(width: 22, alignment: .leading)
                (Text("Later, a director. ").fontWeight(.semibold)
                    + Text("When you run several sessions at once, one session can hand out the work, start the others and check what comes back. Ask any session to “be the director”."))
                    .font(.system(size: DuoTextStyle.body.spec.size)).lineSpacing(DuoTextStyle.body.spec.lineHeight - DuoTextStyle.body.spec.size - 3).foregroundStyle(DuoColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    SmallButton("Watch the director film") { NSWorkspace.shared.open(DuoLinks.directorFilm) }  // not an action: opens the film, as Help › Watch the Director Film (DL-339)
                    SmallButton("Explain") { model.explainOpen(.director) }  // action: explain
                }
                .padding(.top, 1)
            }
            .padding(.vertical, 7)
        }
    }

    private var poster: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 8) {
                ZStack {
                    Circle().strokeBorder(DuoColor.consoleText, lineWidth: 1.5)
                    Path { p in p.move(to: CGPoint(x: 14, y: 11)); p.addLine(to: CGPoint(x: 24, y: 17)); p.addLine(to: CGPoint(x: 14, y: 23)); p.closeSubpath() }
                        .fill(DuoColor.consoleText)
                }
                .frame(width: 34, height: 34)
                Text("Watch the intro film").duoText(.control).foregroundStyle(DuoColor.consoleText)
            }
            .frame(width: DuoMetric.gettingStartedPosterWidth, height: DuoMetric.gettingStartedPosterHeight)
            .background(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).fill(DuoColor.console))
            .contentShape(Rectangle())
            .onActivate { NSWorkspace.shared.open(DuoLinks.introFilm) }  // not an action: opens the film, as Help › Watch the Intro Film (DL-339)
            .accessibilityLabel("Watch the intro film")
            Text("9 min 34 s · what Duo is for").duoText(.control, lineHeight: 16).foregroundStyle(DuoColor.text2)
            Text("Help › Getting Started brings this back.").duoText(.control, lineHeight: 16).foregroundStyle(DuoColor.text2)
        }
        .frame(width: DuoMetric.gettingStartedPosterWidth, alignment: .leading)
    }

    // MARK: All three done

    private var done: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                StepBox(ticked: true)
                Text("That’s the basics").duoText(.title).foregroundStyle(DuoColor.text)
                Text("The guide has the rest: documents, Home, what needs you, getting around.").duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1)
                Spacer(minLength: 8)
                SmallButton("Open the guide") { NSWorkspace.shared.open(DuoLinks.guide) }  // not an action: opens the guide, as Help › Duo Guide (DL-339)
                SmallButton("Done") { GettingStarted.shared.done() }  // action: getting-started done
            }
            (Text("Later, a director. ").fontWeight(.semibold).foregroundStyle(DuoColor.text)
                + Text("When there’s more running than you want to watch: Help › Explain › Director.").foregroundStyle(DuoColor.text2))
                .font(.system(size: DuoTextStyle.body.spec.size)).padding(.leading, 24)
        }
    }
}

/// The step's box: 14, `controlEdge` 1.5 and radius 3; ticked it is filled `text` with a white check (B2).
struct StepBox: View {
    let ticked: Bool
    var body: some View {
        let size = DuoMetric.gettingStartedBox
        ZStack {
            if ticked {
                RoundedRectangle(cornerRadius: 3).fill(DuoColor.text)
                Path { p in p.move(to: CGPoint(x: 2, y: 5.2)); p.addLine(to: CGPoint(x: 4.2, y: 7.3)); p.addLine(to: CGPoint(x: 8, y: 2.8)) }
                    .stroke(DuoColor.pane, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 10, height: 10)
            } else {
                RoundedRectangle(cornerRadius: 3).strokeBorder(DuoColor.controlEdge, lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// What Hide leaves for 8 s: a one-line notice with Undo (B2, DL-147's notice).
struct GettingStartedNotice: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Getting started hidden.").duoText(.body).foregroundStyle(DuoColor.text2)
            Text("Help › Getting Started brings it back.").duoText(.body).foregroundStyle(DuoColor.text2)
            Spacer(minLength: 8)
            Button("Undo") { GettingStarted.shared.undoHide() }.buttonStyle(DuoButtonStyle(compact: true))  // action: getting-started undo
        }
        .padding(.horizontal, 10)
        .frame(height: DuoMetric.gettingStartedNoticeHeight)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
        .accessibilityIdentifier("getting-started-notice")
    }
}

extension AppModel {
    /// The project "Make a task…" works in: the one on screen, else the one last used (B2); nil with none (then only Show me).
    var gettingStartedTaskProject: String? {
        if let p = currentProject, !p.isFolderOnly, p.isHome != true { return p.name }
        return fixture.projects.first(where: { !$0.isFolderOnly && $0.isHome != true })?.name
    }
}
