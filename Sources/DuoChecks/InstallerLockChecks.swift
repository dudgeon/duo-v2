import DuoControl
import Foundation

/// BUG-117 (F-339): the install survives a CLAUDE.md that is a link, read-only, locked, unreadable
/// or not UTF-8: it never overwrites what it couldn't read, says what it skipped, and does the rest.
@MainActor func installerLockChecks() throws {
    print("installer: locked, unreadable and linked files (BUG-117)")
    let fm = FileManager.default
    let cli = "/x/Duo.app/Contents/Helpers/duo2"
    let saved = Installer.testRoot
    let top = fm.temporaryDirectory.appending(path: "inl-\(UUID().uuidString.prefix(6))")
    defer {
        Installer.testRoot = saved
        lockTool("/usr/bin/chflags", ["-R", "nouchg", top.path]); lockTool("/bin/chmod", ["-R", "u+rwX", top.path])
        try? fm.removeItem(at: top)
    }

    func fresh(_ name: String, claudeMD body: Data?) throws {
        let root = top.appending(path: name)
        try fm.createDirectory(at: root.appending(path: "claude"), withIntermediateDirectories: true)
        Installer.testRoot = root
        if let body { try body.write(to: Installer.claudeMD) }
        Installer.recordConsent(true, cli: cli)
    }
    func restDone(_ r: Installer.Report) -> Bool {
        r.lines.contains { $0.hasPrefix("Skill: written") } && r.lines.contains { $0.hasPrefix("Director skill: written") }
            && (try? fm.destinationOfSymbolicLink(atPath: Installer.link.path)) == cli
    }
    func said(_ r: Installer.Report) -> Bool { r.lines.contains { $0.hasPrefix("CLAUDE.md block: skipped") } }
    let mine = "My rules\n"

    // A symlink to a dotfiles copy: the link survives and the target gets the block.
    do {
        try fresh("link", claudeMD: nil)
        let dot = Installer.testRoot!.appending(path: "dotfiles/CLAUDE.md")
        try fm.createDirectory(at: dot.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(mine.utf8).write(to: dot)
        try fm.createSymbolicLink(atPath: Installer.claudeMD.path, withDestinationPath: "../dotfiles/CLAUDE.md")
        _ = Installer.install(cli: cli)
        check((try? fm.destinationOfSymbolicLink(atPath: Installer.claudeMD.path)) == "../dotfiles/CLAUDE.md", "a symlinked CLAUDE.md is still a link afterwards")
        let t = (try? String(contentsOf: dot, encoding: .utf8)) ?? ""
        check(t.hasPrefix(mine) && t.contains("<!-- duo2:begin"), "the block went into the file it points at, the user's text kept")
    }

    // Read-only, locked, unreadable, not UTF-8: untouched, said, the rest installed, the block not marked removed.
    let cases: [(String, Data, (URL) -> Void, (URL) -> Void)] = [
        ("readonly", Data(mine.utf8), { lockTool("/bin/chmod", ["444", $0.path]) }, { lockTool("/bin/chmod", ["644", $0.path]) }),
        ("locked", Data(mine.utf8), { lockTool("/usr/bin/chflags", ["uchg", $0.path]) }, { lockTool("/usr/bin/chflags", ["nouchg", $0.path]) }),
        ("unreadable", Data(mine.utf8), { lockTool("/bin/chmod", ["000", $0.path]) }, { lockTool("/bin/chmod", ["644", $0.path]) }),
        ("notutf8", Data([0x4d, 0x79, 0x20, 0x72, 0x75, 0x6c, 0x65, 0x73, 0x20, 0xe9, 0x0a]), { _ in }, { _ in }),
    ]
    for (name, body, lock, unlock) in cases {
        try fresh(name, claudeMD: body)
        lock(Installer.claudeMD)
        let r = Installer.install(cli: cli)
        let doctor = Installer.status(cli: nil)
        unlock(Installer.claudeMD)
        check((try? Data(contentsOf: Installer.claudeMD)) == body, "\(name): CLAUDE.md is exactly as it was")
        check(said(r), "\(name): Duo says it skipped the block, in its report")
        check(restDone(r), "\(name): the skills and the link are still installed")
        check(!Installer.manifest().blockRemovedByUser, "\(name): the block isn't marked as removed by the user")
        check(doctor.contains { $0.hasPrefix("Skipped at the last install") }, "\(name): doctor says what was skipped")
        if name != "notutf8" {
            _ = Installer.install(cli: cli)
            check(((try? String(contentsOf: Installer.claudeMD, encoding: .utf8)) ?? "").contains("<!-- duo2:begin"), "\(name): fixed, the next install adds the block")
        }
    }

    // A file that was fine, then became unreadable, isn't read as "the user removed the block".
    do {
        try fresh("later", claudeMD: Data(mine.utf8))
        _ = Installer.install(cli: cli)
        lockTool("/bin/chmod", ["000", Installer.claudeMD.path])
        _ = Installer.install(cli: cli)
        lockTool("/bin/chmod", ["644", Installer.claudeMD.path])
        check(!Installer.manifest().blockRemovedByUser && Installer.manifest().blockHash != nil, "unreadable after a good install: not marked removed")
    }
}

private func lockTool(_ tool: String, _ args: [String]) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
    p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
    try? p.run(); p.waitUntilExit()
}
