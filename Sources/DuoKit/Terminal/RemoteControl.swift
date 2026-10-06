import Foundation

/// Remote Control for sessions Duo starts (DL-128, F-127): `claude --remote-control <name>` makes
/// the session reachable from the Claude app. Gated on the installed CLI listing the flag in its
/// `--help`, asked once per binary and bounded like `claude --version` (C-34); a claude without
/// it starts the session without Remote Control.
public enum RemoteControl {
    nonisolated(unsafe) private static var cache: [String: Bool] = [:]
    private static let lock = NSLock()

    /// Whether this claude takes `--remote-control`. Unknown (failed, hung) counts as no.
    public static func supported(_ claude: String) -> Bool {
        lock.lock()
        if let hit = cache[claude] { lock.unlock(); return hit }
        lock.unlock()
        let yes = ClaudeVersion.output(claude, ["--help"])?.contains("--remote-control") ?? false
        lock.lock(); cache[claude] = yes; lock.unlock()
        return yes
    }

    /// Asks in the background at launch, so a session start finds the answer cached.
    public static func warm(_ claude: String) {
        DispatchQueue.global(qos: .utility).async { _ = supported(claude) }
    }

    public static func forget() { lock.lock(); cache = [:]; lock.unlock() }

    /// The arguments for a session that wants Remote Control under `name`; none when it doesn't, or
    /// when this claude can't.
    public static func args(_ name: String?, claude: String) -> [String] {
        guard let name, supported(claude) else { return [] }
        return ["--remote-control", name]
    }

    /// The name a session gets when none is given: its project and a short id ("duo-v2 3f2a9c1e").
    public static func defaultName(project: String, sessionID: String) -> String {
        "\(project) \(sessionID.prefix(8))"
    }
}
