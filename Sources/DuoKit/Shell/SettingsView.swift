import AppKit
import DuoControl
import Observation
import SwiftUI

/// What Settings shows that takes a moment to find out (Claude's version, the archive's size),
/// read off the main thread when the window opens.
@MainActor @Observable public final class SettingsInfo {
    public static let shared = SettingsInfo()
    public var version: String?
    public var archive: (bytes: Int64, sessions: Int)?
    public var revision = 0   // bumps when a setting changes, so the view rereads state.json

    public func refresh() {
        revision += 1
        let path = ClaudeLocator.resolve()
        let root = SessionArchive.root
        Task.detached(priority: .utility) {
            let v = path.flatMap(Self.claudeVersion)
            let a = Self.size(of: root)
            await MainActor.run { self.version = v; self.archive = a }
        }
    }

    nonisolated static func claudeVersion(_ path: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["--version"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let deadline = Date().addingTimeInterval(5)
        while p.isRunning, Date() < deadline { usleep(50_000) }
        if p.isRunning { p.terminate(); return nil }
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return text.split(separator: " ").first.map(String.init)
    }

    nonisolated static func size(of root: URL) -> (Int64, Int) {
        var bytes: Int64 = 0, sessions = 0
        let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey])
        while let u = e?.nextObject() as? URL {
            bytes += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            if u.pathExtension == "jsonl", u.deletingLastPathComponent() == root { sessions += 1 }
        }
        return (bytes, sessions)
    }
}

/// Settings (S3-1, DL-101; DB-10): one grouped pane on `ground`. Every row also has a duo2 verb
/// (`duo2 settings`, `home set`, `install`, `legacy`, `browser sites`).
public struct SettingsView: View {
    @Environment(AppModel.self) private var model
    let info = SettingsInfo.shared

    /// Off only for drawing it to an image (captures): ImageRenderer can't draw a scroll view.
    var scrolls = true

    public init(scrolls: Bool = true) { self.scrolls = scrolls }

    public var body: some View {
        Group {
            if scrolls { ScrollView { content } } else { content }
        }
        .frame(width: DuoMetric.settingsWidth)
        .frame(minHeight: 520)
        .background(DuoColor.ground)
        .foregroundStyle(DuoColor.text)
        .onAppear { info.refresh() }
    }

    var content: some View {
        let _ = info.revision
        let state = DuoState.load()
        return VStack(alignment: .leading, spacing: DuoMetric.settingsGroupGap) {
                group("Claude Code") { claudeRow(state) }
                group("Home") {
                    if let root = model.liveRoot {
                        let ps = model.fixture.projects.filter { !$0.isFolderOnly && model.isInHome($0.name) && $0.isHome != true }
                        let topics = Set(ps.compactMap(\.topic).filter { !$0.isEmpty }).count
                        row("Home folder", value: mono(AppModel.short(root.path)),
                            sub: "\(ps.count) project\(ps.count == 1 ? "" : "s")\(topics > 0 ? " in \(topics) topic folder\(topics == 1 ? "" : "s")" : "")") {
                            Button("Change…") { model.chooseHomeFolder() }.buttonStyle(.duo)
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([root]) }.buttonStyle(.duo)
                        }
                    } else {
                        row("Home folder", value: Text("None yet"), sub: "Home holds the projects you track. Duo lists every session either way.") {
                            Button("Choose Home Folder…") { model.chooseHomeFolder() }.buttonStyle(.duo)
                        }
                    }
                }
                group("Sessions") {
                    let a = info.archive
                    row("Archive", value: Text(a.map { "\(ByteCountFormatter.string(fromByteCount: $0.bytes, countStyle: .file)) · \($0.sessions) session\($0.sessions == 1 ? "" : "s")" } ?? "…"),
                        sub: "Copies of sessions Claude has cleaned up, so they still open. No size limit.") {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([SessionArchive.root]) }.buttonStyle(.duo)
                    }
                }
                group("Notifications") {
                    row("When a session needs you", value: VStack(alignment: .leading, spacing: 2) {
                        Toggle("Notify me while Duo is in the background", isOn: binding(\.notifyNeedsYou)).toggleStyle(.checkbox)
                        Toggle("Show the count on the Dock icon", isOn: binding(\.dockBadge)).toggleStyle(.checkbox)
                    }) { EmptyView() }
                }
                group("Claude outside Duo") {
                    let installed = Installer.manifest().consented
                    row("duo2 everywhere", value: Text(installed ? "Installed" : "Not installed"),
                        sub: installed ? "A Duo section in ~/.claude/CLAUDE.md, the duo2 skill, and duo2 on PATH, so any Claude session can use Duo."
                                       : "Duo’s own sessions still know duo2. Other sessions don’t.") {
                        if installed {
                            Button("Remove…") { model.uninstallCLI() }.buttonStyle(.duo)
                        } else {
                            Button("Install…") { model.installCLI() }.buttonStyle(.duo)
                        }
                    }
                    ruleLine
                    legacyRow(state)
                }
                group("Browser") {
                    let sites = AllowedSites.load()
                    row("Allowed sites", value: Text(sites.isEmpty ? "None" : sites.prefix(3).joined(separator: ", ") + (sites.count > 3 ? " and \(sites.count - 3) more" : "")),
                        sub: "Sites that open in a browser tab beside your notes. Others open in your browser.") {
                        Button("Edit…") { NSWorkspace.shared.open(AllowedSites.file) }.buttonStyle(.duo)
                    }
                }
            }
            .padding(.vertical, DuoMetric.settingsPaddingY)
            .padding(.horizontal, DuoMetric.settingsPaddingX)
    }

    @ViewBuilder func claudeRow(_ state: DuoState) -> some View {
        if let chosen = state.claudePath, !FileManager.default.isExecutableFile(atPath: chosen) {
            row("Claude Code", value: mono(AppModel.short(chosen)),
                sub: "This file isn’t a program Duo can run." + (ClaudeLocator.found().map { _ in " The one Duo finds by itself is used instead." } ?? "")) {
                Button("Use Found One") { model.setClaudePath(nil); info.refresh() }.buttonStyle(.duo)
                Button("Choose…") { model.chooseClaudePath(); info.refresh() }.buttonStyle(.duo)
            }
        } else if let path = ClaudeLocator.resolve() {
            row("Claude Code", value: mono(AppModel.short(path)),
                sub: [info.version, state.claudePath == nil ? "found automatically" : "chosen in Settings"].compactMap { $0 }.joined(separator: " · ")) {
                if state.claudePath != nil { Button("Use Found One") { model.setClaudePath(nil); info.refresh() }.buttonStyle(.duo) }
                Button("Choose…") { model.chooseClaudePath(); info.refresh() }.buttonStyle(.duo)
            }
        } else {
            row("Claude Code", value: Text("Not found").fontWeight(.semibold),
                sub: "Duo looks on your PATH, in ~/.local/bin and in /opt/homebrew/bin. Install Claude Code, or choose where it is.") {
                Button("Choose…") { model.chooseClaudePath(); info.refresh() }.buttonStyle(.duo)
            }
        }
    }

    @ViewBuilder func legacyRow(_ state: DuoState) -> some View {
        let found = LegacyDuo.detect()
        if !found.isEmpty {
            row("Legacy Duo", value: Text("Still loading into every session"),
                sub: found.map(\.what).joined(separator: ", ").capitalizedFirst + " describe legacy commands to Claude.") {
                Button("Disable…") { LegacyPrompt.disable(); info.refresh() }.buttonStyle(.duo)
            }
        } else if let backup = state.legacyBackup {
            let date = (try? URL(fileURLWithPath: backup).resourceValues(forKeys: [.creationDateKey]).creationDate).map { $0.formatted(.dateTime.month(.abbreviated).day()) }
            row("Legacy Duo", value: Text("Disabled\(date.map { " on \($0)" } ?? ""), backed up"),
                sub: "Legacy Duo’s hooks, skill and CLAUDE.md block no longer load into sessions.") {
                Button("Restore") { model.restoreLegacy(); info.refresh() }.buttonStyle(.duo)
            }
        } else {
            row("Legacy Duo", value: Text("Not installed"), sub: "Nothing of legacy Duo’s loads into sessions.") { EmptyView() }
        }
    }

    func binding(_ key: WritableKeyPath<DuoState, Bool>) -> Binding<Bool> {
        Binding(get: { DuoState.load()[keyPath: key] },
                set: { v in DuoState.update { $0[keyPath: key] = v }; info.revision += 1; model.updateDockBadge() })
    }

    func mono(_ s: String) -> Text { Text(s).font(Font(NSFont.monospacedSystemFont(ofSize: DuoTextStyle.mono.spec.size, weight: .regular))) }

    var ruleLine: some View { DuoColor.rule.frame(height: DuoMetric.borderHairline) }

    func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DuoSpace.gapGlyphToLabel) {
            SectionLabel(text: title).padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).fill(DuoColor.pane))
                .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
        }
    }

    func row<V: View, B: View>(_ label: String, value: V, sub: String? = nil, @ViewBuilder buttons: () -> B) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label).duoText(.body).frame(width: DuoMetric.settingsLabelColumn, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                value.duoText(.body)
                if let sub { Text(sub).duoText(.body).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: DuoSpace.gapButtonToButton) { buttons() }
        }
        .padding(.vertical, DuoMetric.settingsRowPaddingY)
        .padding(.horizontal, DuoMetric.settingsRowPaddingX)
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

extension AppModel {
    /// Settings › Claude Code › Choose… (LR-19).
    public func chooseClaudePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = true
        panel.showsHiddenFiles = true
        panel.prompt = "Use This Claude"
        panel.message = "Choose the claude program Duo should run."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setClaudePath(url.path)
    }

    /// Sets (or clears, with nil) the `claude` Duo runs.
    public func setClaudePath(_ path: String?) {
        DuoState.update { $0.claudePath = path }
        ClaudeLocator.forget()
        SettingsInfo.shared.refresh()
    }

    public func installCLI() {
        guard let dir = ChildEnvironment.cliDirectory else { return }
        Installer.recordConsent(true, cli: dir + "/duo2")
        _ = Installer.install(cli: dir + "/duo2")
        SettingsInfo.shared.refresh()
    }

    public func uninstallCLI() {
        confirm(title: "Remove duo2 from Claude sessions outside Duo?",
                detail: "Duo takes out the Duo section in ~/.claude/CLAUDE.md, the duo2 skill and the duo2 link on PATH (anything you edited stays). Duo’s own sessions still know duo2.",
                button: "Remove") { ok in
            guard ok else { return }
            _ = Installer.uninstall()
            SettingsInfo.shared.refresh()
        }
    }

    public func restoreLegacy() {
        guard let b = DuoState.load().legacyBackup else { return }
        do {
            try LegacyDuo.restore(from: URL(fileURLWithPath: b))
            DuoState.update { $0.legacyBackup = nil }
        } catch { info("Couldn’t restore legacy Duo: \(error.localizedDescription)") }
        SettingsInfo.shared.refresh()
    }
}
