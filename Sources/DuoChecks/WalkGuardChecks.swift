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
    "DuoKit/Model/AppModel+Director.swift": "one listing of a project's tasks folder (a director's tasks)",
    "DuoControl/Director.swift": "Claude's sessions folder (the caller's beacon)",
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
}
