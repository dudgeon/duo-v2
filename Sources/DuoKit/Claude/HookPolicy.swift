import DuoControl
import Foundation

/// The Claude Code setting that keeps Duo's per-session hooks from running, if one does (F-749). Duo passes its hooks in a
/// `--settings` file; `disableAllHooks` anywhere silences them (F-311), and a managed `allowManagedHooksOnly` runs only
/// the organization's. A managed Mac (Geoff's work Mac) sets these where the user can't, so every place Claude Code reads
/// managed settings from is read here (2.1.325's binary): the managed file and its `managed-settings.d/` drop-ins, the
/// MDM profiles (per user, then the device's), and the server-delivered `remote-settings.json`; then the user's and the
/// project's files. A policy helper command's output can't be read; `sources` says which managed sources exist, so a
/// report from a managed Mac shows them even when none names a hook setting.
public enum HookPolicy {
    public struct Source: Sendable { public let label: String; public let managed: Bool; let read: @Sendable () -> [String: Any]? }

    public static let managedDir = "/Library/Application Support/ClaudeCode"

    public static func sources(cwd: String?, managedDir: String = managedDir, preferences: String = "/Library/Managed Preferences",
                               claudeDir: URL = ClaudeStorage.root, user: String = NSUserName()) -> [Source] {
        @Sendable func json(_ p: String) -> [String: Any]? {
            (try? Data(contentsOf: URL(fileURLWithPath: p))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
        @Sendable func plist(_ p: String) -> [String: Any]? {
            (try? Data(contentsOf: URL(fileURLWithPath: p))).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        }
        var out: [Source] = [.init(label: "managed-settings.json", managed: true, read: { json(managedDir + "/managed-settings.json") })]
        let dropIns = ((try? FileManager.default.contentsOfDirectory(atPath: managedDir + "/managed-settings.d")) ?? []).filter { $0.hasSuffix(".json") }.sorted()
        out += dropIns.map { f in .init(label: "managed-settings.d/\(f)", managed: true, read: { json(managedDir + "/managed-settings.d/" + f) }) }
        out += [.init(label: "MDM profile (\(user))", managed: true, read: { plist("\(preferences)/\(user)/com.anthropic.claudecode.plist") }),
                .init(label: "MDM profile (device)", managed: true, read: { plist("\(preferences)/com.anthropic.claudecode.plist") }),
                .init(label: "remote-settings.json (from the organization)", managed: true, read: { json(claudeDir.appending(path: "remote-settings.json").path) }),
                .init(label: "~/.claude/settings.json", managed: false, read: { json(claudeDir.appending(path: "settings.json").path) })]
        if let d = cwd {
            out += [.init(label: ".claude/settings.json", managed: false, read: { json(d + "/.claude/settings.json") }),
                    .init(label: ".claude/settings.local.json", managed: false, read: { json(d + "/.claude/settings.local.json") })]
        }
        return out
    }

    /// The setting that turns Duo's hooks off, and where; nil when none of the readable sources does.
    public static func blocker(cwd: String?, managedDir: String = managedDir, preferences: String = "/Library/Managed Preferences",
                               claudeDir: URL = ClaudeStorage.root, user: String = NSUserName()) -> String? {
        let all = sources(cwd: cwd, managedDir: managedDir, preferences: preferences, claudeDir: claudeDir, user: user)
        for s in all where s.managed {
            if s.read()?["allowManagedHooksOnly"] as? Bool == true { return "allowManagedHooksOnly, in \(s.label)" }
        }
        for s in all where s.read()?["disableAllHooks"] as? Bool == true { return "disableAllHooks, in \(s.label)" }
        return nil
    }

    /// The managed sources this Mac has, for the report: none, or their labels.
    public static func managedPresent(managedDir: String = managedDir, preferences: String = "/Library/Managed Preferences",
                                      claudeDir: URL = ClaudeStorage.root, user: String = NSUserName()) -> [String] {
        sources(cwd: nil, managedDir: managedDir, preferences: preferences, claudeDir: claudeDir, user: user).filter { $0.managed && $0.read() != nil }.map(\.label)
    }
}
