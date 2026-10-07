import Foundation

/// The one place that decides where Duo keeps its own state (Q-13 default:
/// `~/Library/Application Support/Duo/`). `DUO_SUPPORT_DIR` stands in for Application Support:
/// Duo's folder is `$DUO_SUPPORT_DIR/Duo` (F-74).
///
/// A scripted run (any launch flag in `scriptedFlags`) without `DUO_SUPPORT_DIR` gets a fresh
/// temporary stand-in, `/tmp/duo-XXXXXX`, so it can never rewrite the user's state, archive or
/// socket (C-21, F-89). So does any launch of a test build (`testBundleID`: work trees, bisects,
/// scratch clones; F-198, DL-151), however it was opened. An explicit `DUO_SUPPORT_DIR` always wins;
/// a plain launch of the main build or a release uses the real folder. The path stays short: the
/// control socket's must be under 104 characters.
public enum SupportFolder {
    public static let variable = "DUO_SUPPORT_DIR"

    /// Every flag `LaunchOptions` reads (each takes a value, F-8). Any of them marks a scripted
    /// run: the user's own launches (Finder, Dock, login, Sparkle's relaunch) pass none.
    public static let scriptedFlags: Set<String> = [
        "--workspace", "--state", "--capture", "--capture-window", "--then", "--window",
        "--fixture", "--terminals", "--gallery", "--left",
    ]

    /// What scripts/bundle.sh calls every build but the main checkout's and a release's (F-198).
    public static let testBundleID = "com.dudgeon.duo.test"

    public enum Choice: Equatable, Sendable {
        /// `DUO_SUPPORT_DIR` was set: that folder.
        case given(String)
        /// A scripted run or a test build without it: a fresh temporary folder.
        case temporary
        /// A plain launch: the user's Application Support.
        case real
    }

    /// Whether these arguments (`CommandLine.arguments`, the program first) are a scripted run.
    public static func isScripted(_ arguments: [String]) -> Bool {
        arguments.dropFirst().contains { scriptedFlags.contains($0) }
    }

    public static func choose(arguments: [String], environment: [String: String],
                              bundleID: String? = Bundle.main.bundleIdentifier) -> Choice {
        if let given = environment[variable], !given.isEmpty { return .given(given) }
        return isScripted(arguments) || bundleID == testBundleID ? .temporary : .real
    }

    /// Application Support, or what stands in for it. Read from the process environment each
    /// time (`prepareForLaunch` may have set it).
    public static var applicationSupport: URL {
        if let p = getenv(variable), let given = String(validatingCString: p), !given.isEmpty {
            return URL(fileURLWithPath: given)
        }
        return real
    }

    /// The user's own Application Support, whatever `DUO_SUPPORT_DIR` says.
    public static var real: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] }

    /// Whether an instance with this `DUO_SUPPORT_DIR` is isolated from the user's Duo (C-28,
    /// F-113): its support folder is anything but the real Application Support (a temporary one
    /// from F-89, or an explicit other folder). The one test; it looks at the folder, never the
    /// launch flags, so the user's own Duo started with `--workspace` and the real folder stays theirs.
    /// An isolated instance asks no install or first-run question, never takes focus, and
    /// `Installer` writes nothing outside it unless `DUO_INSTALL_ROOT` is set.
    public static func isIsolated(given: String?, real: URL = real) -> Bool {
        guard let given, !given.isEmpty else { return false }
        let norm = { (u: URL) in u.standardizedFileURL.resolvingSymlinksInPath().path }
        return norm(URL(fileURLWithPath: given)) != norm(real)
    }

    /// This process: read from the environment each time (`prepareForLaunch` may have set it).
    public static var isIsolated: Bool {
        isIsolated(given: getenv(variable).flatMap { String(validatingCString: $0) })
    }

    /// Duo's own folder: state, archive, journals, search index, events, socket and endpoint.
    public static var duo: URL { applicationSupport.appending(path: "Duo") }

    /// Called first thing at the app's launch, before anything reads or writes Duo's folder. A
    /// scripted run without `DUO_SUPPORT_DIR` gets a temporary folder, exported so everything in
    /// this process and every child (terminals, hooks, `duo2`) uses it, and one line on stderr
    /// names it. `scripts/run-live.sh`'s stderr file has the line; point `duo2` at the instance
    /// with `DUO_SUPPORT_DIR=<folder>` (or `DUO_SOCKET`/`DUO_TOKEN` from `<folder>/Duo/endpoint.json`).
    @discardableResult
    public static func prepareForLaunch(arguments: [String] = CommandLine.arguments,
                                        environment: [String: String] = ProcessInfo.processInfo.environment,
                                        bundleID: String? = Bundle.main.bundleIdentifier) -> Choice {
        let choice = choose(arguments: arguments, environment: environment, bundleID: bundleID)
        guard choice == .temporary else { return choice }
        var template = Array("/tmp/duo-XXXXXX".utf8CString)
        let made = template.withUnsafeMutableBufferPointer { mkdtemp($0.baseAddress!) }
        guard made != nil else {
            // Never fall back to the real folder: a scripted run that can't isolate itself stops.
            FileHandle.standardError.write(Data("Duo: a scripted run or test build without \(variable), and no temporary support folder could be made (errno \(errno)); not starting (C-21).\n".utf8))
            exit(73)
        }
        let path = String(decoding: template.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        setenv(variable, path, 1)
        let what = isScripted(arguments) ? "scripted run" : "test build (\(testBundleID), F-198)"
        FileHandle.standardError.write(Data("Duo: \(what) without \(variable); using a temporary support folder, \(path) (C-21, F-89)\n".utf8))
        return choice
    }
}
