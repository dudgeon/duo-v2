import DuoControl
import DuoKit
import Foundation

// F-200: Claude Code files a session under its folder's realpath (/private/tmp, not /tmp; LR-24),
// and Foundation's resolvingSymlinksInPath() strips /private, so a folder move under /tmp or /var
// left its sessions behind. F-201: an empty DUO_AUTOCONFIRM (or any Duo variable) counts as unset.

@MainActor func pathChecks() throws {
    print("pasted pictures (LR-39, legacy ENH-108)")
    let d = Date(timeIntervalSince1970: 1_800_000_000)
    check(ImagePaste.fileExtension(mime: "image/png") == "png" && ImagePaste.fileExtension(mime: "image/jpeg") == "jpg" && ImagePaste.fileExtension(mime: "image/webp") == "webp" && ImagePaste.fileExtension(mime: "image/gif") == "gif", "png, jpeg, gif and webp are saved")
    check(ImagePaste.fileExtension(mime: "image/heic") == nil && ImagePaste.fileExtension(mime: "text/plain") == nil, "other types are left alone")
    let n1 = ImagePaste.fileName(docStem: "My Note", date: d, ext: "png") { _ in false }
    check(n1.hasPrefix("My-Note-") && n1.hasSuffix(".png") && !n1.contains(" ") && !n1.contains("/"), "name is <stem>-<date>.<ext> with no spaces")
    let n2 = ImagePaste.fileName(docStem: "My Note", date: d, ext: "png") { $0 == n1 }
    check(n2 == n1.replacingOccurrences(of: ".png", with: "-2.png"), "a taken name gets -2, never overwritten")
    check(ImagePaste.link(fileName: n1) == "![](\(n1))" && !ImagePaste.link(fileName: "a b.png").contains(" ") && !ImagePaste.link(fileName: n1).contains("/"), "link is relative and encoded")
    check(ImagePaste.link(fileName: "Plan: v2 (draft).png") == "![](Plan%3A%20v2%20%28draft%29.png)", "a colon or bracket in the name can't break the link")

    print("real paths (LR-24, F-200)")
    let fm = FileManager.default
    check(URL.realPath("/tmp") == "/private/tmp" && URL.realPath("/private/tmp") == "/private/tmp", "/tmp is /private/tmp, as Claude spells it")
    check(URL(fileURLWithPath: "/private/tmp").realPath == "/private/tmp", "a /private path keeps /private (Foundation's resolvingSymlinksInPath drops it)")
    check(URL.realPath("/tmp/duo-no-such-\(getpid())/a/b") == "/private/tmp/duo-no-such-\(getpid())/a/b", "a path that isn't there yet resolves its deepest existing folder")
    check(URL.realPath("/") == "/" && URL.realPath("/tmp/") == "/private/tmp", "the root and a trailing slash")

    // BUG-098 (F-262): Move to Trash on a file already gone from disk is not an error.
    let gone = URL(fileURLWithPath: "/tmp/duo-trash-\(UUID().uuidString.prefix(8)).md")
    check((try? FileActions.trashIfPresent(gone)) == false, "trashing a file that is already gone is a quiet no-op, not a throw")
    let there = URL(fileURLWithPath: "/tmp/duo-trash-\(UUID().uuidString.prefix(8)).md")
    try? Data("x".utf8).write(to: there)
    check((try? FileActions.trashIfPresent(there)) == true && !fm.fileExists(atPath: there.path), "a file that is there still goes to the Trash")

    // A folder reached through /tmp and through a symlink of the user's own: a move maps its
    // sessions in Claude's spelling whichever way the folder was named, and undo brings them back.
    let root = URL(fileURLWithPath: "/tmp/duo-paths-\(UUID().uuidString.prefix(8))")
    let real = root.realPath   // /private/tmp/…
    let claude = root.appending(path: "claude")
    let link = root.appending(path: "link").path
    try fm.createDirectory(atPath: real + "/work/elsewhere/side/sub", withIntermediateDirectories: true)
    try fm.createDirectory(atPath: real + "/work/home", withIntermediateDirectories: true)
    try fm.createSymbolicLink(atPath: link, withDestinationPath: real + "/work")
    func session(_ id: String, cwd: String) throws -> URL {
        let d = claude.appending(path: "projects/" + ClaudeStorage.encode(cwd)); try fm.createDirectory(at: d, withIntermediateDirectories: true)
        let u = d.appending(path: "\(id).jsonl")
        try (#"{"type":"user","cwd":"\#(cwd)","uuid":"u-\#(id)","sessionId":"\#(id)","message":{"content":"hi"}}"# + "\n").write(to: u, atomically: true, encoding: .utf8)
        return u
    }
    let side = real + "/work/elsewhere/side"
    let s1 = try session("p1", cwd: side), original = try Data(contentsOf: s1)
    _ = try session("p2", cwd: side + "/sub")
    let m = Migrator(claudeDir: claude, journalDir: root.appending(path: "migrations"))
    let bucket = { (p: String) in claude.appending(path: "projects/" + ClaudeStorage.encode(p)) }
    for (how, from, to) in [("/tmp", root.path + "/work/elsewhere/side", root.path + "/work/home/side"),
                            ("a symlink of the user's", link + "/elsewhere/side", link + "/home/side")] {
        let plan = try m.planFolderMove(from, to: to)
        let dest = real + "/work/home/side"
        check(plan.steps.filter { $0.op == .appendRelocated }.count == 2, "moving a folder named through \(how) takes its 2 sessions")
        let done = try m.apply(plan)
        let moved = bucket(dest).appending(path: "p1.jsonl")
        check(done.state == .committed && fm.fileExists(atPath: moved.path) && fm.fileExists(atPath: bucket(dest + "/sub").appending(path: "p2.jsonl").path)
              && ((try? String(contentsOf: moved, encoding: .utf8)) ?? "").contains(#""relocatedCwd":"\#(dest)""#),
              "its sessions go to the buckets Claude reads for the new real path (\(how))")
        try m.undo(done)
        check(fm.fileExists(atPath: side + "/sub") && (try? Data(contentsOf: s1)) == original && !fm.fileExists(atPath: moved.path),
              "and undo puts the folder and its sessions back (\(how))")
    }
    let relocated = try m.apply(try m.planRelocate("p1", to: root.path + "/work/home"))
    check(fm.fileExists(atPath: bucket(real + "/work/home").appending(path: "p1.jsonl").path), "relocating to a /tmp folder files it under /private/tmp")
    try m.undo(relocated)
    // Reconnect after a move outside Duo, named the Foundation way (/tmp) for a session filed under /private/tmp.
    try fm.moveItem(atPath: side, toPath: real + "/work/moved")
    let reconnect = try m.apply(try m.planReconnect(root.path + "/work/elsewhere/side", to: root.path + "/work/moved"))
    check(reconnect.steps.filter { $0.op == .appendRelocated }.count == 2 && fm.fileExists(atPath: bucket(real + "/work/moved").appending(path: "p1.jsonl").path),
          "reconnect finds the sessions of a folder named through /tmp")
    try m.undo(reconnect)
    try? fm.removeItem(atPath: real)

    print("environment flags (F-190, F-201)")
    check(!Env.isSet("DUO_AUTOCONFIRM", ["DUO_AUTOCONFIRM": ""]), "DUO_AUTOCONFIRM= (empty) counts as unset")
    check(Env.isSet("DUO_AUTOCONFIRM", ["DUO_AUTOCONFIRM": "1"]) && !Env.isSet("DUO_AUTOCONFIRM", [:]), "set to 1 is on; absent is off")
    check(Env.value("CLAUDE_CONFIG_DIR", ["CLAUDE_CONFIG_DIR": ""]) == nil, "an empty folder variable is no folder, not the current directory")
    // Every Duo variable read goes through Env, so none can be on while empty.
    var dir = URL(fileURLWithPath: #filePath)
    for _ in 0..<2 { dir.deleteLastPathComponent() }
    var raw: [String] = []
    for case let u as URL in fm.enumerator(at: dir, includingPropertiesForKeys: nil) ?? FileManager.DirectoryEnumerator()
    where u.pathExtension == "swift" && !u.path.contains("/DuoChecks/") && u.lastPathComponent != "Env.swift" {
        let text = (try? String(contentsOf: u, encoding: .utf8)) ?? ""
        for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
        where line.range(of: #"environment\["(DUO_[A-Z_]+|CLAUDE_CONFIG_DIR)"\]\s*(!=|==)\s*nil"#, options: .regularExpression) != nil {
            raw.append("\(u.lastPathComponent):\(i + 1)")
        }
    }
    check(raw.isEmpty, "no Duo flag is tested by presence alone (use Env.isSet)\(raw.isEmpty ? "" : ": " + raw.joined(separator: ", "))")
}
