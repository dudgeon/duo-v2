import DuoKit
import DuoSearch
import Foundation

// F-302: Duo never walks into a folder macOS guards with a privacy prompt (F-28, F-53). Every file
// that lists or walks folders, or asks Spotlight, either goes through ProtectedFolders (or the file
// tree's `unlisted`, which does) or is named here with why it can't reach one. A new walk that does
// neither fails, so the rule can't be bypassed by adding code somewhere else.

/// Files that list folders without the rule, and why that's safe. Keys are paths under `Sources/`.
let walkGuardExempt: [String: String] = [
    "DuoKit/Chat/ChatSignal.swift": "the mod's own copy, in Duo's support folder",
    "DuoKit/Claude/ClaudeStorage.swift": "Claude's config folder (~/.claude/projects)",
    "DuoKit/Editor/HTMLViewer.swift": "one listing of the open page's own folder",
    "DuoKit/Live/Beacons.swift": "Claude's sessions folder",
    "DuoKit/Live/FileActions.swift": "the templates folders of a project and Home",
    "DuoKit/Live/Inventory.swift": "Claude's config folder",
    "DuoKit/Live/Migrator.swift": "Claude's config folder and Duo's support folder",
    "DuoKit/Live/ProjectDiscovery.swift": "skips ProtectedFolders.paths (its `protected`) below the root",
    "DuoKit/Live/SessionArchive.swift": "Duo's archive in its support folder",
    "DuoKit/Live/TaskContext.swift": "one listing of a project's tasks folder",
    "DuoKit/Live/TaskNotes.swift": "one listing of a project's tasks folder",
    "DuoKit/Model/AppModel+Organize.swift": "one listing of a folder being emptied",
    "DuoKit/Shell/SettingsView.swift": "the size of Claude's config folder",
    "DuoSearch/SessionSource.swift": "Claude's config folder",
    "duo2/main.swift": "Duo's archive in its support folder",
]

func walkGuardChecks() {
    print("privacy prompts: every walk goes through ProtectedFolders (F-302)")
    let apis = try! NSRegularExpression(pattern: #"enumerator\(at|enumerator\(atPath|subpathsOfDirectory|contentsOfDirectory|NSMetadataQuery|MDQuery|mdfind|CSSearchQuery"#)
    let index = SourceIndex()
    var walkers: [String] = []
    for f in index.files where !f.path.hasPrefix("DuoChecks/") {
        let ns = f.text as NSString
        guard apis.firstMatch(in: f.text, range: NSRange(location: 0, length: ns.length)) != nil else { continue }
        walkers.append(f.path)
        let guarded = f.text.contains("ProtectedFolders.") || f.text.contains("unlisted(")
        check(guarded || walkGuardExempt[f.path] != nil,
              "\(f.path) lists folders: it uses ProtectedFolders, or is in walkGuardExempt with why it's safe")
    }
    check(walkers.count > 10, "the scan found the walks (\(walkers.count) files)")
    for path in walkGuardExempt.keys.sorted() where !walkers.contains(path) {
        check(false, "\(path) is in walkGuardExempt but no longer lists folders: take it out")
    }

    let home = FileManager.default.homeDirectoryForCurrentUser
    // Depth 1 lists home without entering anything, so the check itself can't raise a prompt.
    let top = Set(MissingFolders.walk(home, depth: 1).map { $0.standardizedFileURL.path })
    check(top.isDisjoint(with: ProtectedFolders.paths), "finding a moved folder never enters Music, Pictures, Documents…")
    check(MissingFolders.places(for: home.appending(path: "gone-\(UUID().uuidString)/x").path, roots: [home]).isEmpty
          && MissingFolders.places(for: "/Users/gone-\(UUID().uuidString)/x", roots: [URL(fileURLWithPath: "/")]).isEmpty,
          "a moved folder is never looked for from home, /Users or /")
    check(PropertyCorpus.markdownFiles(in: home, limit: 10).isEmpty && ReferenceIndex.scan(home, limit: 10).isEmpty,
          "property suggestions and task references never walk home")
    check(ProtectedFolders.skip(URL(fileURLWithPath: "/Volumes"), root: URL(fileURLWithPath: "/")),
          "walks stay out of /Volumes (network shares prompt)")

    print("terminal processes are responsible for themselves (DL-185)")
    let l = ChildEnvironment.launch("/bin/zsh", args: ["-l"], argv0: "-zsh", exec: "/X/duo-exec")
    check(l.executable == "/X/duo-exec" && l.args == ["/bin/zsh", "-zsh", "-l"] && l.execName == nil,
          "a terminal starts through duo-exec, with the program, its argv0 and its arguments")
    let plain = ChildEnvironment.launch("/c/claude", args: ["--resume", "x"], exec: nil)
    check(plain.executable == "/c/claude" && plain.args == ["--resume", "x"], "without duo-exec it starts the program directly")
    let sibling = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appending(path: "duo-exec").path
    let built = repoRoot().appending(path: "build/Duo.app/Contents/Library/Exec/duo-exec").path
    guard let exec = [sibling, built].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
        print("  (duo-exec isn't built: `swift build --product duo-exec` runs the live check)")
        return
    }
    func responsible(viaExec: Bool) -> (pid: Int32, responsible: Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: viaExec ? exec : "/bin/sleep")
        p.arguments = viaExec ? ["/bin/sleep", "sleep", "2"] : ["2"]
        guard (try? p.run()) != nil else { return (0, -2) }
        usleep(300_000)
        defer { p.terminate(); p.waitUntilExit() }
        return (p.processIdentifier, responsibility_get_pid_responsible_for_pid(p.processIdentifier))
    }
    let direct = responsible(viaExec: false), disclaimed = responsible(viaExec: true)
    check(direct.responsible != direct.pid, "a child started directly counts its parent's app as responsible (\(direct.responsible))")
    check(disclaimed.responsible == disclaimed.pid, "a child started through duo-exec is responsible for itself (\(disclaimed.pid))")
}

@_silgen_name("responsibility_get_pid_responsible_for_pid")
func responsibility_get_pid_responsible_for_pid(_ pid: Int32) -> Int32
