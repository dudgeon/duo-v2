import DuoControl
import DuoKit
import Foundation

/// DL-339 (Q-510, Q-514, ENH-344, ENH-345): a new install opens project sessions in chat and an existing
/// one doesn't change; the app says Window Color and `window colour` still works; the Files fold and the
/// open folders are remembered; Help links to the guide and films.
@MainActor func teachingLayerChecks() {
    print("teaching layer (DL-339)")
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appending(path: "duo-teach-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: dir) }
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

    // Q-510: a support folder with neither chat.json nor state.json is a new install.
    let chatURL = dir.appending(path: "chat.json")
    let fresh = ChatPrefs.load(chatURL)
    check(fresh.mode(for: "new") == .chat, "a new install's project sessions open in chat")
    check(fm.fileExists(atPath: chatURL.path) && ChatPrefs.load(chatURL).mode(for: "new") == .chat, "and that is saved, so it stays the choice")
    check(fresh.mode(for: "new", home: true) == .chat, "Home still opens in chat")

    // An existing user (state.json present, no chat.json) keeps the terminal.
    let old = dir.appending(path: "old")
    try? fm.createDirectory(at: old, withIntermediateDirectories: true)
    try? Data("{}".utf8).write(to: old.appending(path: "state.json"))
    let existing = ChatPrefs.load(old.appending(path: "chat.json"))
    check(existing.mode(for: "new") == .terminal && !fm.fileExists(atPath: old.appending(path: "chat.json").path), "an existing install's project sessions stay in the terminal, and nothing is written")
    var chose = ChatPrefs(); chose.set(.terminal, for: "a"); chose.save(old.appending(path: "chat.json"))
    check(ChatPrefs.load(old.appending(path: "chat.json")).mode(for: "new") == .terminal, "a saved choice is read as it was")
    var fixed = fresh; fixed.fixedDefault = .terminal
    check(fixed.mode(for: "new") == .terminal, "New sessions open in: Terminal overrides")

    // Q-514: the verb is American; the old spelling resolves to it.
    check(DuoAction.resolve(["window", "color", "blue"])?.0.id.rawValue == "window color", "duo2 window color")
    let alias = DuoAction.resolve(["window", "colour", "blue"])
    check(alias?.0.id.rawValue == "window color" && alias?.rest == ["blue"], "duo2 window colour still works")

    // ENH-344: the fold and the open folders are remembered.
    let state = dir.appending(path: "s.json")
    try? DuoState.write(state) { $0.filesFolded = ["p"]; $0.expandedFolders = ["p": ["docs", "docs/a"]] }
    let back = DuoState.load(state)
    check(back.filesFolded == ["p"] && back.expandedFolders["p"] == ["docs", "docs/a"], "the Files fold and open folders round-trip in Duo's state")
    check(DuoState.load(dir.appending(path: "none.json")).filesFolded.isEmpty, "an old state file has none")

    // ENH-345: Help's links, and the guide pages the explainers open.
    check(DuoLinks.guide.absoluteString.hasSuffix("/docs/guide/README.md") && DuoLinks.guidePage("director").absoluteString.hasSuffix("/docs/guide/director.md"), "the guide and its pages")
    check(DuoLinks.introFilm.lastPathComponent == "duo-intro.mp4" && DuoLinks.directorFilm.lastPathComponent == "duo-director.mp4", "the two films")
    let guide = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "docs/guide")
    for page in ["tasks", "sessions", "director", "home"] { check(fm.fileExists(atPath: guide.appending(path: page + ".md").path), "guide page \(page).md exists (an explainer's Learn more)") }
    for page in ["projects", "home", "where-a-session-belongs"] {
        let text = (try? String(contentsOf: guide.appending(path: page + ".md"), encoding: .utf8)) ?? ""
        check(text.range(of: #"(?<![_A-Za-z])PROJECT\.md"#, options: .regularExpression) == nil, "\(page).md says _PROJECT.md")
    }
}
