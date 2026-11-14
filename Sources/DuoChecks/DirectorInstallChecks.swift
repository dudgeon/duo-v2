import DuoControl
import Foundation

/// The director skill's install and update paths (Geoff, Q-512, 2026-11-13): a new Duo version
/// rewrites it, a deleted copy comes back, a user's edit is left alone and doctor says so, a
/// read-only folder is skipped and said, and an isolated run touches nothing outside its root.
@MainActor func directorInstallChecks() throws {
    print("installer: the director skill installs and updates (Q-512)")
    let fm = FileManager.default
    let cli = "/x/Duo.app/Contents/Helpers/duo2"
    let saved = Installer.testRoot
    let top = fm.temporaryDirectory.appending(path: "dinst-\(UUID().uuidString.prefix(6))")
    let envs = ["DUO_SUPPORT_DIR", "CLAUDE_CONFIG_DIR"]
    let was = envs.map { ($0, getenv($0).map { String(cString: $0) }) }
    defer {
        Installer.testRoot = saved
        for (k, v) in was { if let v { setenv(k, v, 1) } else { unsetenv(k) } }
        for name in ["readonly/claude/skills"] { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: top.appending(path: name).path) }
        try? fm.removeItem(at: top)
    }
    func fresh(_ name: String) throws {
        let root = top.appending(path: name)
        try fm.createDirectory(at: root.appending(path: "claude"), withIntermediateDirectories: true)
        Installer.testRoot = root
        Installer.recordConsent(true, cli: cli)
    }
    func file() -> URL { Installer.directorSkillFile }
    func read(_ u: URL) -> String? { try? String(contentsOf: u, encoding: .utf8) }
    func doctor(_ prefix: String) -> String? { Installer.status(cli: nil).first { $0.hasPrefix(prefix) } }

    // A new Duo version: what an older Duo wrote (hash on record) is rewritten, and doctor calls it older until then.
    try fresh("update")
    _ = Installer.install(cli: cli)
    let old = "---\nname: director\n---\nolder Duo's director skill\n", oldStub = "---\nname: duo-director\n---\nolder stub\n"
    try Data(old.utf8).write(to: file()); try Data(oldStub.utf8).write(to: Installer.directorAliasFile)
    var m = Installer.manifest(); m.directorSkillHash = Installer.hash(old); m.directorAliasHash = Installer.hash(oldStub); Installer.save(m)
    check(doctor("Director skill:")?.contains("from an older Duo (updates at launch)") == true && doctor("Old name duo-director:")?.contains("from an older Duo") == true,
          "doctor: a copy from an older Duo says it updates at launch")
    let ru = Installer.install(cli: cli)
    check(read(file()) == DirectorSkill.text() && read(Installer.directorAliasFile) == DirectorSkill.aliasText() && ru.lines.contains("Director skill: updated."),
          "a new Duo version rewrites the skill and the stub")
    check(doctor("Director skill:")?.hasPrefix("Director skill: current") == true, "and doctor says current")

    // A user-edited copy, then a new version: still theirs, said by doctor, and by the install report.
    let mine = old + "my edit\n"
    try Data(mine.utf8).write(to: file()); m = Installer.manifest(); m.directorSkillHash = Installer.hash(old); Installer.save(m)
    let re = Installer.install(cli: cli)
    check(read(file()) == mine && re.lines.contains("Director skill: edited by you, left alone.") && doctor("Director skill:")?.contains("edited by you") == true,
          "a user-edited copy survives a new version and doctor says it's theirs")

    // A deleted copy comes back at the next launch (the folder too).
    try fresh("deleted")
    _ = Installer.install(cli: cli)
    try fm.removeItem(at: file().deletingLastPathComponent())
    check(doctor("Director skill:") == "Director skill: not installed.", "doctor: a deleted copy is 'not installed'")
    let rd = Installer.install(cli: cli)
    check(read(file()) == DirectorSkill.text() && rd.lines.contains("Director skill: written."), "a deleted copy is written again at the next launch")

    // A read-only skills folder: skipped and said, the rest carried on, and nothing claimed as Duo's.
    try fresh("readonly")
    let skills = Installer.claudeDir.appending(path: "skills")
    try fm.createDirectory(at: skills, withIntermediateDirectories: true)
    try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: skills.path)
    let rr = Installer.install(cli: cli)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: skills.path)
    check(!fm.fileExists(atPath: file().path) && rr.lines.contains { $0.hasPrefix("Director skill: skipped.") }
          && (try? fm.destinationOfSymbolicLink(atPath: Installer.link.path)) == cli && Installer.manifest().directorSkillHash == nil,
          "a read-only skills folder: skipped, said, the link still made, nothing recorded as Duo's (\(rr.lines))")
    check(Installer.status(cli: nil).contains { $0.hasPrefix("Skipped at the last install") && $0.contains("Director skill") }, "doctor says what was skipped")
    _ = Installer.install(cli: cli)
    check(read(file()) == DirectorSkill.text(), "fixed, the next launch writes it")

    // Isolated runs: refuse without DUO_INSTALL_ROOT; with it, write only inside it. CLAUDE_CONFIG_DIR moves a real install's folder.
    let support = top.appending(path: "support")
    try fm.createDirectory(at: support, withIntermediateDirectories: true)
    setenv("DUO_SUPPORT_DIR", support.path, 1)
    Installer.testRoot = nil
    check(Installer.refusal != nil, "an isolated instance (own support folder) is refused")
    if Installer.refusal != nil {
        check(Installer.install(cli: cli).lines.first?.hasPrefix("Not installed:") == true, "install says so and writes nothing")
        let cfg = top.appending(path: "cfg")
        setenv("CLAUDE_CONFIG_DIR", cfg.path, 1)
        check(Installer.directorSkillFile.path == cfg.appending(path: "skills/director/SKILL.md").path
              && Installer.directorAliasFile.path == cfg.appending(path: "skills/duo-director/SKILL.md").path, "CLAUDE_CONFIG_DIR moves both skill files with it")
        let root = top.appending(path: "iroot")
        Installer.testRoot = root
        check(Installer.refusal == nil && Installer.directorSkillFile.path.hasPrefix(root.path), "DUO_INSTALL_ROOT lifts the refusal and the files land under it, not in CLAUDE_CONFIG_DIR")
    }
}
