import AppKit
import SwiftUI

/// The repo state in the Files block (B, DL-149; every repo project, DL-157): the branch at the
/// right of the FILES header, then one fact and at most one button (board 5).
struct RepoBranchLabel: View {
    let view: RepoView

    var body: some View {
        HStack(spacing: 4) {
            BranchMark()
            Text(view.status.branch ?? view.status.head.map { "at \($0)" } ?? "no commits yet")
                .duoText(.control, weight: .semibold)
                .lineLimit(1).truncationMode(.middle)
        }
        .foregroundStyle(DuoColor.text)
        .help(view.status.origin.map { "\($0.slug), branch \(view.status.branch ?? "detached")" } ?? "A git repository with no GitHub remote")
    }
}

struct RepoFactLine: View {
    @Environment(AppModel.self) private var model
    let view: RepoView

    var body: some View {
        let line = RepoLine.of(view)
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                if let busy = view.busy {
                    Text(busy)
                } else {
                    switch line.glyph {
                    case .up: ArrowMark(up: true)
                    case .down: ArrowMark(up: false)
                    case .lock: LockMark()
                    case .none: EmptyView()
                    }
                    if let pr = line.prLink {
                        let rest = line.fact.replacingOccurrences(of: "PR #\(pr)", with: "").trimmingCharacters(in: .whitespaces)
                        Text("PR #\(pr)").underline()
                            .onActivate { model.openRepoOnGitHub(pr: true) }   // action: repo open
                        Text(rest)
                    } else {
                        Text(line.fact).fontWeight(line.strong ? .semibold : .regular)
                            .foregroundStyle(line.strong ? DuoColor.text : DuoColor.text2)
                    }
                }
            }
            .duoText(.control)
            .foregroundStyle(DuoColor.text2)
            .lineLimit(1)
            .contentShape(Rectangle())
            .onActivate { model.repoDetailsShown = true }  // not an action: shows the details popover (duo2 repo status)
            .popover(isPresented: Binding(get: { model.repoDetailsShown }, set: { model.repoDetailsShown = $0 }), arrowEdge: .bottom) { RepoDetails(view: view) }
            Spacer(minLength: 2)
            if let a = line.action, view.busy == nil {
                Button(a.rawValue) { model.repoAction(a) }   // action: repo push
                    .buttonStyle(DuoButtonStyle(compact: true))
                    .fixedSize()
            }
        }
        .frame(minHeight: 22)
        .contextMenu { RepoMenu(view: view) }
    }
}

/// Every fact that holds, and the steps (board 4 C's popover; for B it opens from the line).
struct RepoDetails: View {
    @Environment(AppModel.self) private var model
    let view: RepoView

    var body: some View {
        let line = RepoLine.of(view)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) { BranchMark(); Text(view.status.branch ?? "detached").duoText(.control, weight: .semibold) }
            Text(subtitle).duoText(.control).foregroundStyle(DuoColor.text2)
            if !line.all.isEmpty { Text(line.all.joined(separator: " · ")).duoText(.control) }
            HStack(spacing: 6) {
                if view.status.origin != nil {
                    Button("Push…") { model.showPush() }.buttonStyle(.duo)   // action: repo push
                    Button("Get Latest") { model.getLatest(from: nil) }.buttonStyle(.duo)   // action: repo latest
                    Button("Open on GitHub") { model.openRepoOnGitHub() }.buttonStyle(.duo)   // action: repo open
                }
            }
        }
        .padding(12)
        .frame(width: 330, alignment: .leading)
    }

    private var subtitle: String {
        guard let o = view.status.origin else { return "A git repository with no GitHub remote" }
        var parts = [o.slug]
        if view.status.branch != view.base { parts.append("from \(view.base)") }
        switch view.access?.sign {
        case .noGH?: parts.append("no GitHub CLI")
        case .signedOut?: parts.append("signed out")
        default:
            if view.access?.readOnly == true { parts.append("read only") }
            else if view.access?.canPush == true { parts.append("you can push") }
        }
        return parts.joined(separator: " · ")
    }
}

/// The repo line's menu (board 9).
struct RepoMenu: View {
    @Environment(AppModel.self) private var model
    let view: RepoView

    var body: some View {
        if view.status.origin != nil {
            Button("Push to GitHub…") { model.showPush() }   // action: repo push
            Button("Get Latest") { model.getLatest(from: nil) }   // action: repo latest
            if let b = Optional(view.base), view.status.branch != b {
                Button("Bring In Changes from \(b)") { model.getLatest(from: b) }   // action: repo update
            }
            Divider()
            Button("Open on GitHub") { model.openRepoOnGitHub() }   // action: repo open
            if let pr = view.pr { Button("Open Pull Request #\(pr)") { model.openRepoOnGitHub(pr: true) } }   // action: repo open
            Divider()
        }
        Button("Copy Branch Name") { model.copyBranchName() }   // action: repo status
    }
}

/// What a push says when it's done (board 6), at the foot of the Files block until used or 8 s pass.
struct RepoNoticeView: View {
    @Environment(AppModel.self) private var model
    let notice: RepoNotice

    var body: some View {
        HStack(spacing: DuoSpace.gapRowItems) {
            Text(notice.text).duoText(.control).fixedSize(horizontal: false, vertical: true)
            if let b = notice.button, let u = notice.url {
                Button(b) { NSWorkspace.shared.open(u); model.repoNotice = nil }.buttonStyle(.duo).fixedSize()   // action: repo open
            }
        }
        .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 8))
        .background(RoundedRectangle(cornerRadius: 8).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DuoColor.controlEdge, lineWidth: DuoMetric.borderHairline))
        .duoPopoverShadow()
        .transition(.notice)
        .task(id: notice.at) {
            try? await Task.sleep(for: .seconds(8))
            if model.repoNotice == notice { model.repoNotice = nil }
        }
    }
}

/// Board 4's branch mark: two nodes joined, 10×12, `text2`.
struct BranchMark: View {
    var body: some View {
        Canvas { ctx, _ in
            let c = GraphicsContext.Shading.color(DuoColor.text2)
            for (x, y) in [(2.5, 2.2), (2.5, 9.8), (7.5, 3.6)] {
                ctx.stroke(Path(ellipseIn: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)), with: c, lineWidth: 1.2)
            }
            var p = Path()
            p.move(to: CGPoint(x: 2.5, y: 3.7)); p.addLine(to: CGPoint(x: 2.5, y: 8.3))
            p.move(to: CGPoint(x: 7.5, y: 5.1)); p.addCurve(to: CGPoint(x: 2.5, y: 8.3), control1: CGPoint(x: 7.5, y: 7.3), control2: CGPoint(x: 2.5, y: 6.7))
            ctx.stroke(p, with: c, lineWidth: 1.2)
        }
        .frame(width: 10, height: 12)
        .accessibilityHidden(true)
    }
}

/// ↑ to push, ↓ new on GitHub: 8×10, `text2`.
struct ArrowMark: View {
    let up: Bool
    var body: some View {
        Canvas { ctx, _ in
            var p = Path()
            if up {
                p.move(to: CGPoint(x: 4, y: 9)); p.addLine(to: CGPoint(x: 4, y: 1.8))
                p.move(to: CGPoint(x: 1.2, y: 4.5)); p.addLine(to: CGPoint(x: 4, y: 1.6)); p.addLine(to: CGPoint(x: 6.8, y: 4.5))
            } else {
                p.move(to: CGPoint(x: 4, y: 1)); p.addLine(to: CGPoint(x: 4, y: 8.2))
                p.move(to: CGPoint(x: 1.2, y: 5.5)); p.addLine(to: CGPoint(x: 4, y: 8.4)); p.addLine(to: CGPoint(x: 6.8, y: 5.5))
            }
            ctx.stroke(p, with: .color(DuoColor.text2), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 8, height: 10)
        .accessibilityHidden(true)
    }
}
