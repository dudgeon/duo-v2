import AppKit
import SwiftUI

/// Push to GitHub (board 6, DL-149; the fork, board 7; without gh, board 8): what goes, the
/// message, the pull request, one button named for what it does.
struct PushSheet: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: PushForm

    var body: some View {
        VStack(alignment: .leading, spacing: DuoMetric.sheetRowGap) {
            Text("Push to GitHub").duoText(.bodyEmphasis)
            if form.mode == .fork {
                HStack(alignment: .top, spacing: DuoSpace.gapRowItems) {
                    LockMark().padding(.top, 4)
                    Text("\(Text("You can read \(form.repo.slug) but not push to it.").fontWeight(.semibold)) Duo will push your branch to your own copy of it on GitHub, \(Text(form.forkName).fontWeight(.semibold)) (a fork), and open the pull request into \(form.repo.slug) from there. The owners see the pull request; your fork is public if \(form.repo.slug) is.")
                        .duoText(.body).fixedSize(horizontal: false, vertical: true)
                }
                .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                .background(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).fill(DuoColor.pane))
                .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
            } else {
                Text(form.mode == .browser
                     ? "To \(Text(form.repo.slug).fontWeight(.semibold)), branch \(Text(form.branch).font(Self.mono)). Duo pushes with git and your Mac’s keychain; the pull request is written on GitHub’s page."
                     : "To \(Text(form.repo.slug).fontWeight(.semibold)), branch \(Text(form.branch).font(Self.mono))\(form.newOnGitHub ? " (new on GitHub)" : "").")
                    .duoText(.body).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true)
            }
            SheetRow("Changes") { changes }
            SheetRow("Message") {
                SheetField(text: form.message, focus: true, submit: { model.commitPush() }, cancel: model.cancelSheet) { form.message = $0 }
                    .id(form.message.isEmpty ? "empty" : "m")
            }
            if form.existingPR == nil { pullRequest }
            HStack(spacing: DuoSpace.gapButtonToButton) {
                Button("Ask Claude to Write These") { model.askClaudeToWritePush() }   // action: repo draft
                    .buttonStyle(.duo)
                Spacer(minLength: 0)
                Button("Cancel", action: model.cancelSheet).buttonStyle(.duo).keyboardShortcut(.cancelAction)
                Button(action: { model.commitPush() }) { Text(form.working ? "Pushing…" : form.button).fontWeight(.semibold) }   // action: repo push
                    .buttonStyle(DefaultSheetButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!form.canSend)
            }
            .padding(.top, 4)
        }
        .foregroundStyle(DuoColor.text)
        .padding(DuoMetric.sheetPadding)
        .frame(width: DuoMetric.sheetPushWidth - 2 * DuoMetric.borderHairline, alignment: .leading)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: DuoMetric.radiusPopover, bottomTrailingRadius: DuoMetric.radiusPopover).fill(DuoColor.ground))
        .padding([.horizontal, .bottom], DuoMetric.borderHairline)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: DuoMetric.radiusPopover, bottomTrailingRadius: DuoMetric.radiusPopover).fill(DuoColor.rule))
        .compositingGroup()
        .duoPopoverShadow()
        .onExitCommand { model.cancelSheet() }
        .accessibilityLabel("Push to GitHub")
    }

    static let mono = Font(NSFont.monospacedSystemFont(ofSize: DuoTextStyle.mono.spec.size, weight: .regular))

    private var changes: some View {
        let user = form.rows.filter { !$0.duo }, duo = form.rows.filter(\.duo)
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(user) { row($0) }
            if !duo.isEmpty {
                // Duo's own files in a repo Duo didn't copy (DL-157): unticked; a stand-in until drawn (Q-137).
                Text("Duo’s files").duoText(.control).foregroundStyle(DuoColor.text2).padding(.top, user.isEmpty ? 0 : 4)
                ForEach(duo) { row($0) }
            }
            let tail = [form.commitsAhead > 0 ? "\(user.isEmpty ? "" : "Plus ")\(form.commitsAhead) commit\(form.commitsAhead == 1 ? "" : "s") already made here." : nil,
                        duo.isEmpty ? "\(form.projectFileName) stays out." : nil].compactMap { $0 }.joined(separator: " ")
            if user.isEmpty && duo.isEmpty && form.commitsAhead == 0 {
                Text("Nothing changed: Duo pushes the branch as it is.").duoText(.control).foregroundStyle(DuoColor.text2)
            } else if !tail.isEmpty {
                Text(tail.prefix(1).uppercased() + tail.dropFirst()).duoText(.control).foregroundStyle(DuoColor.text2).padding(.top, 2)
            }
        }
        .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
    }

    private func row(_ r: PushForm.Row) -> some View {
        HStack(spacing: DuoSpace.gapRowItems) {
            Toggle(isOn: Binding(get: { r.ticked }, set: { v in if let i = form.rows.firstIndex(where: { $0.id == r.id }) { form.rows[i].ticked = v } })) {
                Text(r.path).font(Self.mono).lineLimit(1).truncationMode(.middle)
            }
            .toggleStyle(.checkbox)
            Spacer(minLength: 8)
            Text(r.stat).duoText(.control).foregroundStyle(DuoColor.text2).fixedSize()
        }
        .frame(height: 22)
    }

    private var pullRequest: some View {
        SheetRow("Pull request") {
            VStack(alignment: .leading, spacing: 6) {
                if form.mode == .browser {
                    Toggle(isOn: $form.openPR) { Text("Then open GitHub’s page for a pull request into \(Text(form.base).fontWeight(.semibold))") }
                        .toggleStyle(.checkbox).duoText(.body)
                    Text("Your browser opens with the title and description filled in; you press Create pull request there.")
                        .duoText(.control).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: DuoSpace.gapRowItems) {
                        Toggle(isOn: $form.openPR) { Text("Open a pull request into \(Text(form.repo.slug).fontWeight(.semibold))") }
                            .toggleStyle(.checkbox).duoText(.body)
                        // The base, as a popup (board 6): GitHub's branches, the default first.
                        PlacePopup(places: form.bases.map { HomePlace(label: $0, folder: URL(fileURLWithPath: "/" + $0)) },
                                   selected: HomePlace(label: form.base, folder: URL(fileURLWithPath: "/" + form.base)), folderMark: false) { form.base = $0.label }
                    }
                }
                if form.openPR {
                    TextEditor(text: $form.body)
                        .font(.system(size: DuoTextStyle.control.spec.size))
                        .scrollContentBackground(.hidden)
                        .padding(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                        .frame(height: DuoMetric.sheetPushBodyHeight)
                        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).fill(DuoColor.pane))
                        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
                    if form.mode != .browser {
                        Toggle("As a draft", isOn: $form.draft).toggleStyle(.checkbox).duoText(.body)
                    }
                }
            }
        }
    }
}

/// The lock board 4 draws before "read only" and "protected": a 10×11 stroke mark in `text2`.
struct LockMark: View {
    var body: some View {
        Canvas { ctx, _ in
            var body = Path(roundedRect: CGRect(x: 1.5, y: 4.8, width: 7, height: 5.4), cornerRadius: 1.2)
            body.move(to: CGPoint(x: 3.2, y: 4.8))
            body.addLine(to: CGPoint(x: 3.2, y: 3.3))
            body.addArc(center: CGPoint(x: 5, y: 3.3), radius: 1.8, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            body.addLine(to: CGPoint(x: 6.8, y: 4.8))
            ctx.stroke(body, with: .color(DuoColor.text2), lineWidth: 1.2)
        }
        .frame(width: 10, height: 11)
        .accessibilityHidden(true)
    }
}
