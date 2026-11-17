import DuoControl
import Foundation

/// The Claude Code setting that keeps Duo's per-session hooks from running, if one does (F-749). Duo passes its hooks in a
/// `--settings` file; `disableAllHooks` anywhere silences them (F-311), and a managed `allowManagedHooksOnly`
/// runs only the organization's. Read from the managed file, the user's settings and the project's two files.
public enum HookPolicy {
    public static func blocker(cwd: String?, managed: String = ClientCaps.managedSettings, claudeDir: URL = ClaudeStorage.root) -> String? {
        func json(_ u: URL) -> [String: Any]? { (try? Data(contentsOf: u)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
        let managedJSON = json(URL(fileURLWithPath: managed))
        if managedJSON?["allowManagedHooksOnly"] as? Bool == true { return "allowManagedHooksOnly, in managed settings" }
        var files: [(String, URL)] = [("managed settings", URL(fileURLWithPath: managed)), ("~/.claude/settings.json", claudeDir.appending(path: "settings.json"))]
        if let d = cwd {
            files += [(".claude/settings.json", URL(fileURLWithPath: d).appending(path: ".claude/settings.json")),
                      (".claude/settings.local.json", URL(fileURLWithPath: d).appending(path: ".claude/settings.local.json"))]
        }
        for (name, url) in files where json(url)?["disableAllHooks"] as? Bool == true { return "disableAllHooks, in \(name)" }
        return nil
    }
}
