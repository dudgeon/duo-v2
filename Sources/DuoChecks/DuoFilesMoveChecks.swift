import DuoControl
import DuoKit
import Foundation

// DL-259 (2), Q-330: the old PROJECT.md / HOME.md move to the underscore names, quietly, with git mv
// where git tracks them, and what pointed at them follows. A sandbox in the temporary folder only.

private func write(_ url: URL, _ text: String) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? text.write(to: url, atomically: true, encoding: .utf8)
}
private func read(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }

@MainActor func duoFilesMoveChecks() throws {
    print("Duo's files: PROJECT.md and HOME.md move to the underscore names (DL-259, Q-330)")
    let sand = FileManager.default.temporaryDirectory.appending(path: "duo-move-\(getpid())").resolvingSymlinksInPath()
    try? FileManager.default.removeItem(at: sand)
    defer { try? FileManager.default.removeItem(at: sand) }
    let cfg = sand.appending(path: "gitconfig")
    write(cfg, "[user]\n\tname = Tester\n\temail = t@example.com\n[init]\n\tdefaultBranch = main\n")
    setenv("GIT_CONFIG_GLOBAL", cfg.path, 1); setenv("GIT_CONFIG_NOSYSTEM", "1", 1)
    defer { unsetenv("GIT_CONFIG_GLOBAL"); unsetenv("GIT_CONFIG_NOSYSTEM") }

    let home = sand.appending(path: "Home")
    let alpha = home.appending(path: "work/alpha"), beta = home.appending(path: "beta"), both = home.appending(path: "both")
    write(home.appending(path: "HOME.md"), "---\ntype: home\n---\n# Home\n")
    write(home.appending(path: "projects.md"), "- [[work/alpha/PROJECT|Alpha]]\n- [[HOME]] and [[beta/PROJECT.md]]\n- [Beta](beta/PROJECT.md \"brief\")\n")
    // alpha: a repo that tracks its PROJECT.md.
    write(alpha.appending(path: "PROJECT.md"), "---\ngoal: Ship\n---\n# Alpha\n")
    write(alpha.appending(path: "CLAUDE.md"), "# alpha\n\nSee @PROJECT.md for the brief. Mentions PROJECT.md in prose.\n")
    write(alpha.appending(path: ".claude/CLAUDE.md"), "@../PROJECT.md\n")
    write(alpha.appending(path: "docs/a.md"), "[brief](../PROJECT.md#goal) [[PROJECT#Goal]] [[PROJECT|the brief]] ![x](https://example.com/PROJECT.md) [other](../docs/PROJECT.md)\n")
    _ = GitTool.git(["init", "-q"], in: alpha); _ = GitTool.git(["add", "."], in: alpha); _ = GitTool.git(["commit", "-qm", "init"], in: alpha)
    // beta: untracked, no repo. both: has the new name already.
    write(beta.appending(path: "PROJECT.md"), "---\ngoal: Beta\n---\n")
    write(beta.appending(path: "notes/n.md"), "Up: [[PROJECT]]. Home: [[HOME]].\n")
    write(both.appending(path: "PROJECT.md"), "old\n"); write(both.appending(path: "_PROJECT.md"), "new\n")
    write(both.appending(path: "n.md"), "[[PROJECT]]\n")

    let r = DuoFilesMove.run(folders: [alpha, beta, both], home: home)
    let names = Set(r.moved.map { $0.to.deletingLastPathComponent().lastPathComponent + "/" + $0.to.lastPathComponent })
    check(names == ["alpha/_PROJECT.md", "beta/_PROJECT.md", "Home/_HOME.md"], "the old names move; a folder that has the new name already is left as it is (\(names.sorted()))")
    check(read(both.appending(path: "PROJECT.md")) == "old\n" && read(both.appending(path: "n.md")) == "[[PROJECT]]\n", "…its files and links untouched")
    let st = GitTool.git(["status", "--porcelain"], in: alpha).out
    check(st.contains("R  PROJECT.md -> _PROJECT.md"), "in a repo it's git mv: one rename, history follows (\(st.split(separator: "\n").first ?? ""))")
    check(!FileManager.default.fileExists(atPath: beta.appending(path: "PROJECT.md").path) && read(beta.appending(path: "_PROJECT.md")).contains("Beta"), "outside git, a plain rename")
    check(read(alpha.appending(path: "CLAUDE.md")) == "# alpha\n\nSee @_PROJECT.md for the brief. Mentions PROJECT.md in prose.\n", "CLAUDE.md's @PROJECT.md import follows; prose stays")
    check(read(alpha.appending(path: ".claude/CLAUDE.md")) == "@../_PROJECT.md\n", ".claude/CLAUDE.md's import follows, relative to it as Claude reads it")
    check(read(alpha.appending(path: "docs/a.md")) == "[brief](../_PROJECT.md#goal) [[_PROJECT#Goal]] [[_PROJECT|the brief]] ![x](https://example.com/PROJECT.md) [other](../docs/PROJECT.md)\n",
          "Markdown and Obsidian links to it follow, headings and aliases kept; a URL and another file's link don't")
    check(read(home.appending(path: "projects.md")) == "- [[work/alpha/_PROJECT|Alpha]]\n- [[_HOME]] and [[beta/_PROJECT.md]]\n- [Beta](beta/_PROJECT.md \"brief\")\n",
          "Home's notes: path links from the vault and [[HOME]] follow")
    check(read(beta.appending(path: "notes/n.md")) == "Up: [[_PROJECT]]. Home: [[_HOME]].\n", "a bare [[PROJECT]] is the nearest project's")
    check(ProjectDiscovery.found(at: alpha, root: nil)?.project.goal == "Ship" && DuoFiles.homeFile(in: home)?.lastPathComponent == "_HOME.md", "still the same project and Home")
    let again = DuoFilesMove.run(folders: [alpha, beta, both], home: home)
    check(again.moved.isEmpty && again.edited.isEmpty, "a second run does nothing")
    // F-186: a lower-case project.md answers to PROJECT.md on this disk, but it isn't Duo's file.
    let lower = home.appending(path: "lower")
    write(lower.appending(path: "project.md"), "notes\n")
    check(DuoFilesMove.run(folders: [lower], home: nil).moved.isEmpty, "a project.md (lower case) is never renamed")
}
