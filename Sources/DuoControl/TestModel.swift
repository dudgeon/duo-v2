import Foundation

/// The model a test instance's Claude sessions run on (DL-153): Haiku 5.5, so a test that starts a
/// real Claude spends little whatever it forgot to ask for. A test instance is an isolated one
/// (`SupportFolder.isIsolated`, F-113) or a test build (`SupportFolder.testBundleID`, DL-151);
/// `DUO_MODEL` picks another model for it. The user's own Duo gets nothing: its sessions start on
/// the model Claude Code chooses, as before.
public enum TestModel {
    /// Haiku 5.5's full name in Claude Code's model catalog (2.1.293, F-207). Not the `haiku` alias:
    /// that means the newest Haiku, which moves, and older CLIs read it as 4.5.
    public static let haiku = "claude-haiku-5-5"
    public static let variable = "DUO_MODEL"

    /// The model for a session this instance starts, or nil to leave Claude Code's own choice.
    public static func model(environment: [String: String], isolated: Bool, bundleID: String?) -> String? {
        guard isolated || bundleID == SupportFolder.testBundleID else { return nil }
        if let asked = environment[variable], !asked.isEmpty { return asked }
        return haiku
    }

    /// `--model <m>` for this process's sessions, or nothing in the user's own Duo. A flag rather than
    /// `ANTHROPIC_MODEL`, so it wins over one the launching shell left set, and shows in ps.
    public static func args(environment: [String: String] = ProcessInfo.processInfo.environment,
                            isolated: Bool = SupportFolder.isIsolated,
                            bundleID: String? = Bundle.main.bundleIdentifier) -> [String] {
        model(environment: environment, isolated: isolated, bundleID: bundleID).map { ["--model", $0] } ?? []
    }
}
