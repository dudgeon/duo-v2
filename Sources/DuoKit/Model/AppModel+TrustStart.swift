import Foundation
import DuoControl

// F-444: Claude Code's folder trust question at the start of a session in a folder it hasn't trusted
// ("Accessing workspace: … Yes, I trust this folder"). Chat mode never falls back to the terminal for it
// (DL-258): Duo asks with its trust sheet (DL-229's surface; the words for this case are Q-338's stand-in)
// and gives Claude Code your answer on its own screen. Claude Code then records the trust itself, as when
// you answer in the terminal, so Duo writes nothing to its file here, and nothing is trusted unless you say so.

extension AppModel {
    /// The sheet for Claude Code's start-of-session question about `folder` (the session's real folder).
    /// `answer` runs with true for Trust Folder, false for Don't Trust.
    public static func trustStartQuestion(folder: String, home: String = ClaudeTrust.realPath(NSHomeDirectory()),
                                          config: URL = ClaudeTrust.configFile(),
                                          answer: @escaping @MainActor (Bool) -> Void) -> DuoQuestion {
        let name = (folder as NSString).lastPathComponent
        let configShown = (config.path as NSString).abbreviatingWithTildeInPath
        // Claude keys trust at the repository's top folder, and never keeps it for the home folder.
        let keyFolder = ClaudeTrust.repositoryTop(of: folder) ?? folder
        let keyName = (keyFolder as NSString).lastPathComponent
        var q = DuoQuestion(title: "Trust “\(name)” for Claude Code?", choices: [])
        q.paragraphs = [
            "Claude Code asks before it works in a folder for the first time, and this session is waiting for your answer.",
            folder == home
                ? "If you trust it, Duo gives Claude Code your answer, “Yes, I trust this folder”. Claude Code trusts your home folder one session at a time, so it asks again in the next one."
                : "If you trust it, Duo gives Claude Code your answer, “Yes, I trust this folder”, and Claude Code records it in its file:",
        ]
        q.items = [.init(what: "Folder", path: folder, captioned: true)]
        if folder != home {
            q.items.append(.init(what: "In \(configShown)", path: "projects › …/\(keyName) › hasTrustDialogAccepted: true", captioned: true))
        }
        q.note = "Only this folder. Claude Code will then use its settings, hooks and tools here without asking. If you don’t trust it, Claude Code exits and this session ends; nothing changes."
        q.choices = [
            .init(label: "Don’t Trust", isCancel: true) { answer(false) },
            .init(label: "Trust Folder", isDefault: true) { answer(true) },
        ]
        return q
    }

    /// Chat read the trust question on `chat`'s screen: ask, if it names the session's own folder. False leaves it
    /// to the terminal (another folder's question is not this session's to answer). `done` gets "trusted <path>",
    /// "not trusted <path>", or why the answer didn't go.
    @discardableResult
    public func askTrustAtStart(_ chat: ChatSession, folder: String, path: String, source: String = "you", done: ((String) -> Void)? = nil) -> Bool {
        let real = ClaudeTrust.realPath(folder)
        guard ChatScreenReader.samePath(path, real) else { return false }
        SheetCenter.shared.ask(Self.trustStartQuestion(folder: real) { trust in
            Task { @MainActor in
                let r = await chat.answerTrust(trust, path: real)
                if r.ok {
                    DuoLog.write("\(trust ? "trusted" : "didn’t trust") \(real) for Claude Code at a session's start (asked by \(source))")
                    done?((trust ? "trusted " : "not trusted ") + real)
                } else {
                    done?("the answer didn’t go: \(r.why ?? "the screen changed")")
                }
            }
        })
        return true
    }
}
