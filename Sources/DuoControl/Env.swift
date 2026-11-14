import Foundation

/// Duo's environment variables. An empty value counts as unset: `DUO_AUTOCONFIRM=` in a script
/// meant to show a sheet must not answer it (F-190), and an empty folder variable must not mean
/// the current directory (F-201).
public enum Env {
    /// The variable's value, or nil if it's unset or empty.
    public static func value(_ name: String, _ environment: [String: String]) -> String? {
        environment[name].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The process's own variable, read with getenv(3): `ProcessInfo.processInfo.environment` copies the whole environment
    /// into a dictionary on every call, and `ClaudeStorage.root` asked for it thousands of times a refresh (F-598).
    /// getenv sees `setenv` changes the same way.
    public static func value(_ name: String) -> String? {
        getenv(name).map { String(cString: $0) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Whether a flag such as `DUO_AUTOCONFIRM` is on: set to anything but the empty string.
    public static func isSet(_ name: String, _ environment: [String: String]) -> Bool {
        value(name, environment) != nil
    }
    public static func isSet(_ name: String) -> Bool { value(name) != nil }

    /// Scripted runs answer Duo's questions themselves (DUO_AUTOCONFIRM=1).
    public static var autoconfirm: Bool { isSet("DUO_AUTOCONFIRM") }
}
