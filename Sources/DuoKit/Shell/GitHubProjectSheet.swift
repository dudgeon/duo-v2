import AppKit
import SwiftUI

/// New project, From GitHub (board 1 and 2 A, DL-149): Repository, what Duo found, the branch,
/// then the New project sheet's own rows. A sheet of its own until the CX study's Start from
/// segment is built (DL-147, Q-139).
struct GitHubProjectSheet: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: GitHubProjectForm

    var body: some View {
        VStack(alignment: .leading, spacing: DuoMetric.sheetRowGap) {
            Text("New project from GitHub").duoText(.bodyEmphasis)
            Text("A project is one piece of work with an end, in its own folder. Duo copies the repository into Home on a branch of its own; nothing changes on GitHub until you push.")
                .duoText(.body).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true)
            SheetRow("Repository") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: DuoSpace.gapRowItems) {
                        SheetField(text: form.repoText, focus: true, submit: { model.lookUpRepo() }, cancel: model.cancelSheet) { t in
                            form.repoText = t
                            // Look it up once typing settles.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { if form.repoText == t { model.lookUpRepo() } }
                        }
                        .id(form.choices.isEmpty ? "repo" : "repo-\(form.repoText)")
                        chooser
                    }
                    Text("Paste a link from GitHub, or choose one of your repos.").duoText(.control).foregroundStyle(DuoColor.text2)
                }
            }
            if form.found != .empty { SheetRow("") { found } }
            if form.repo != nil, !form.branches.isEmpty { branchRows }
            SheetRow("Name") {
                SheetField(text: form.name, focus: false, submit: { model.commitGitHubProject() }, cancel: model.cancelSheet) { form.name = $0; form.nameTouched = true }
                    .id("name-\(form.nameTouched ? "typed" : form.name)")
            }
            SheetRow("Goal") {
                SheetField(text: form.goal, focus: false, submit: { model.commitGitHubProject() }, cancel: model.cancelSheet) { form.goal = $0 }
            }
            SheetRow("In", center: true) {
                HStack(spacing: DuoSpace.gapRowItems) {
                    PlacePopup(places: form.places, selected: form.into, folderMark: true) { form.into = $0 }
                    Text(AppModel.short(form.path)).duoText(.mono).foregroundStyle(DuoColor.text2).lineLimit(1).truncationMode(.middle)
                }
            }
            SheetRow("") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Start a Claude session in it", isOn: $form.startSession).toggleStyle(.checkbox).duoText(.body)
                    Toggle(isOn: $form.keepOutOfGit) {
                        Text("Keep \(Text("PROJECT.md").font(PushSheet.mono)) out of git (listed in \(Text(".git/info/exclude").font(PushSheet.mono)))")
                    }
                    .toggleStyle(.checkbox).duoText(.body)
                }
            }
            HStack(spacing: DuoSpace.gapButtonToButton) {
                if form.working {
                    ProgressView().controlSize(.small)
                    Text("Getting \(form.repo?.slug ?? "the repository")…").duoText(.control).foregroundStyle(DuoColor.text2)
                }
                Spacer(minLength: 0)
                Button("Cancel", action: model.cancelSheet).buttonStyle(.duo).keyboardShortcut(.cancelAction)
                Button(action: { model.commitGitHubProject() }) { Text("Create Project").fontWeight(.semibold) }   // action: project new
                    .buttonStyle(DefaultSheetButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!form.canCreate)
            }
            .padding(.top, 4)
        }
        .foregroundStyle(DuoColor.text)
        .padding(DuoMetric.sheetPadding)
        .frame(width: DuoMetric.sheetGithubWidth - 2 * DuoMetric.borderHairline, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusPopover - DuoMetric.borderHairline).fill(DuoColor.ground))
        .padding(DuoMetric.borderHairline)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusPopover).fill(DuoColor.rule))
        .compositingGroup()
        .duoPopoverShadow()
        .onExitCommand { model.cancelSheet() }
        .accessibilityLabel("New project from GitHub")
    }

    /// Choose…: the GitHub CLI's list, or why there's none (board 1).
    private var chooser: some View {
        Menu {
            if form.choices.isEmpty {
                Text(GitTool.ghPath == nil ? "Choosing needs the GitHub CLI: paste a link" : "Sign in to the GitHub CLI to choose: paste a link")
            } else {
                ForEach(form.choices, id: \.slug) { c in
                    let label = c.isPrivate ? "\(c.slug)  · private" : c.slug
                    Button(label) { form.repoText = c.slug; model.lookUpRepo() }   // not an action: picks a field's value
                }
            }
        } label: {
            Text("Choose…").duoText(.control).foregroundStyle(DuoColor.text)
                .padding(.horizontal, DuoSpace.buttonPadding.leading + DuoMetric.borderHairline)
                .frame(height: DuoMetric.sheetFieldHeight)
                .background(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).fill(DuoColor.pane))
                .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).strokeBorder(DuoColor.controlEdge, lineWidth: DuoMetric.borderHairline))
        }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    @ViewBuilder private var found: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch form.found {
            case .empty: EmptyView()
            case .looking: Text("Looking at \(form.repo?.slug ?? "it") on GitHub…").duoText(.control).foregroundStyle(DuoColor.text2)
            case .ok(let facts):
                Text("\(Text(form.repo?.slug ?? "").fontWeight(.semibold))  \(Text(facts).foregroundStyle(DuoColor.text2))").duoText(.body)
            case .readOnly(let fork):
                HStack(spacing: 6) { Text(form.repo?.slug ?? "").fontWeight(.semibold); LockMark(); Text("you can read it, not push to it").foregroundStyle(DuoColor.text2) }.duoText(.body)
                Text("Your work will go to your own copy of it, \(Text(fork).fontWeight(.semibold)) (a fork), when you first push. Nothing is made on your GitHub account until then.")
                    .duoText(.control).fixedSize(horizontal: false, vertical: true)
            case .unknown:
                Text("\(Text(form.repo?.slug ?? "").fontWeight(.semibold))  \(Text("Duo can’t tell what you can push until you share (no GitHub CLI sign-in)").foregroundStyle(DuoColor.text2))")
                    .duoText(.body).fixedSize(horizontal: false, vertical: true)
            case .problem(let title, let body):
                Text(title).duoText(.body, weight: .semibold)
                Text(body).duoText(.control).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true)
            }
            if let here = form.alreadyHere {
                Text("\(form.repo?.slug ?? "") is already on this Mac in \(here). This project gets its own copy.").duoText(.control).foregroundStyle(DuoColor.text2)
            }
            if let who = form.signedInAs { Text("Signed in to GitHub as \(who) (GitHub CLI).").duoText(.control).foregroundStyle(DuoColor.text2) }
        }
        .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
    }

    /// Board 2, A: a new branch for this work (default), or one that's there; each choice's field under it.
    private var branchRows: some View {
        SheetRow("Branch") {
            VStack(alignment: .leading, spacing: 6) {
                RadioRow(label: "A new branch for this work", on: !form.useExisting) { form.useExisting = false }
                if !form.useExisting {
                    HStack(spacing: DuoSpace.gapRowItems) {
                        SheetField(text: form.newBranch, focus: false, submit: { model.commitGitHubProject() }, cancel: model.cancelSheet) { form.newBranch = $0 }
                            .id("branch-\(form.repo?.slug ?? "")")
                        Text("from").duoText(.body).foregroundStyle(DuoColor.text2)
                        PlacePopup(places: form.branches.map { HomePlace(label: $0.name, folder: URL(fileURLWithPath: "/" + $0.name)) },
                                   selected: HomePlace(label: form.base, folder: URL(fileURLWithPath: "/" + form.base)), folderMark: false) { form.base = $0.label }
                    }
                    .padding(.leading, 22)
                }
                RadioRow(label: "A branch that’s already there", on: form.useExisting) { form.useExisting = true }
                if form.useExisting {
                    PlacePopup(places: form.branches.map { HomePlace(label: $0.name, folder: URL(fileURLWithPath: "/" + $0.name)) },
                               selected: HomePlace(label: form.existing ?? "Choose a branch", folder: URL(fileURLWithPath: "/")), folderMark: false) { form.existing = $0.label }
                        .padding(.leading, 22)
                    if let e = form.existing, e != form.base {
                        Text("Someone else’s branch? Your pushes join it, and any pull request from it. Duo says so again before you push.")
                            .duoText(.control).foregroundStyle(DuoColor.text2).padding(.leading, 22).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// A radio choice drawn as the sheets draw them: a 14 pt circle, the label at 8.
struct RadioRow: View {
    let label: String
    let on: Bool
    let pick: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle().strokeBorder(on ? Color.accentColor : DuoColor.controlEdge, lineWidth: on ? 4 : 1)
                .background(Circle().fill(DuoColor.pane)).frame(width: 14, height: 14)
            Text(label).duoText(.body)
        }
        .contentShape(Rectangle())
        .onActivate { pick() }  // not an action: picks a field's value
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}
