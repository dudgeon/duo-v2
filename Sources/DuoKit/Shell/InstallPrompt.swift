import AppKit
import DuoControl

/// Asks once whether Duo may install what lets Claude sessions outside Duo use `duo2` (DL-75),
/// naming every change; asks again only when that list changes. Then keeps it current at every
/// launch (DL-74). Declining leaves Duo working: its own sessions get the primer directly.
@MainActor
public enum InstallPrompt {
    public static func run(cli: String) {
        // An isolated instance (its own support folder) neither asks nor refreshes, and so asks
        // nothing about legacy Duo either: its targets are the user's real files (C-28, F-113).
        if let why = Installer.refusal { return FileHandle.standardError.write(Data("install: skipped. \(why)\n".utf8)) }
        if Installer.needsConsent(cli: cli) {
            // Duo's own sheet (S3-3, DL-101), naming every change and where it goes (DL-75).
            SheetCenter.shared.ask(DuoQuestion(
                title: "Let Claude sessions outside Duo use it?",
                paragraphs: ["Duo’s own sessions already know duo2. To let any Claude session on this Mac use it, Duo would:"],
                items: Installer.plannedItems(cli: cli).map { .init(what: $0.what, path: $0.path) },
                note: "Duo keeps these current each time it starts and leaves anything you edit alone. Settings › duo2 everywhere › Remove takes them all out.",
                choices: [.init(label: "Not Now", isCancel: true) { Installer.recordConsent(false, cli: cli); refresh(cli: cli); LegacyPrompt.run() },
                          .init(label: "Install", isDefault: true) { Installer.recordConsent(true, cli: cli); refresh(cli: cli); LegacyPrompt.run() }]))
            return
        }
        refresh(cli: cli)
        askDirectorName(cli: cli)
        LegacyPrompt.run()
    }

    /// DL-222: the shared skill is `director`, and a personal skill hides a project skill of the same
    /// name. Asks once, naming the project skills; until the answer the skill is installed as `duo-director`.
    static func askDirectorName(cli: String) {
        guard Installer.needsDirectorNameAnswer(), let hidden = Installer.directorNameQuestion() else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        SheetCenter.shared.ask(DuoQuestion(
            title: "Name Duo’s director skill “director”?",
            paragraphs: ["Duo’s director skill is named `director`, so `/director` reaches it. A skill of yours with the same name would be hidden by it:"],
            items: hidden.map { .init(what: "Project skill", path: $0.path.replacingOccurrences(of: home, with: "~")) },
            note: "Keep duo-director leaves yours as it is and installs Duo’s as `duo-director`. `duo2 install --director-name director` changes your mind later.",
            choices: [.init(label: "Keep duo-director", isCancel: true) { Installer.recordDirectorName(allowed: false); refresh(cli: cli) },
                      .init(label: "Use director", isDefault: true) { Installer.recordDirectorName(allowed: true); refresh(cli: cli) }]))
    }

    static func refresh(cli: String) {
        let report = Installer.install(cli: cli)
        if !report.lines.isEmpty { FileHandle.standardError.write(Data(("install: " + report.lines.joined(separator: " | ") + "\n").utf8)) }
    }
}

/// Legacy Duo's global instructions (DL-39, S3-3): at launch, a sheet lists what it found, by
/// path; Disable backs each up first. Not Now asks again only when what it finds changes. Restore
/// is in Settings (and `duo2 legacy restore`).
@MainActor
public enum LegacyPrompt {
    static var backupRoot: URL { ControlEndpoint.file.deletingLastPathComponent().appending(path: "backups") }

    public static func run() {
        let found = LegacyDuo.detect()
        guard !found.isEmpty else { return }
        let key = found.map { $0.what + $0.path }.joined(separator: "|")
        guard DuoState.load().legacyDismissed != key else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        SheetCenter.shared.ask(DuoQuestion(
            title: "Legacy Duo is still teaching Claude its commands",
            paragraphs: ["These load into every Claude session, Duo’s included, and describe legacy Duo’s commands, which no longer work:"],
            items: found.map { .init(what: $0.what.prefix(1).uppercased() + $0.what.dropFirst(), path: $0.path.replacingOccurrences(of: home, with: "~")) },
            note: "Disabling backs each one up first. Settings › Legacy Duo › Restore puts them back.",
            choices: [.init(label: "Not Now", isCancel: true) { DuoState.update { $0.legacyDismissed = key } },
                      .init(label: "Disable", isDefault: true) { disable() }]))
    }

    /// Disables with a backup; says what couldn't be moved, if anything.
    public static func disable() {
        let before = LegacyDuo.detect()
        var why = ""
        do {
            let b = try LegacyDuo.disable(backupRoot: backupRoot)
            DuoState.update { $0.legacyBackup = b.path; $0.legacyDismissed = nil }
        } catch { why = error.localizedDescription }
        let left = LegacyDuo.detect()
        guard !left.isEmpty else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let done = before.filter { b in !left.contains { $0.path == b.path && $0.what == b.what } }.map(\.what)
        SheetCenter.shared.ask(DuoQuestion(
            title: "Legacy Duo is partly disabled",
            paragraphs: done.isEmpty ? [] : ["Disabled and backed up: \(done.joined(separator: ", "))."],
            note: "Couldn’t change " + left.map { "`\($0.path.replacingOccurrences(of: home, with: "~"))`" }.joined(separator: ", ") + (why.isEmpty ? "" : ": \(why)") + ". It still loads into sessions.",
            choices: [.init(label: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(left.map { URL(fileURLWithPath: $0.path) }) },
                      .init(label: "OK", isDefault: true, isCancel: true) {}]))
    }
}
