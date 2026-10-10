import Foundation

/// Command-line flags for fixture mode and the comparison loop (handoff §0.2, §15 slice 1).
///
///   Duo --state overview                       open in a target state
///   Duo --state overview --capture out.png     ...capture the content below the toolbar, then quit
///   Duo --capture-window out.png               capture the whole window (drawn; screencapture(1) only with DUO_SCREENCAPTURE=1)
///   Duo --capture-scale 4 ...                  capture at 4 pixels per point, drawn at that size (default 2; or DUO_CAPTURE_SCALE)
///   Duo --fixture path/to/fixture.json         use another fixture file
///   Duo --left collapsed                       start with the left pane collapsed
///   Duo --window 1280x800                      fixture mode at another window size (DB-25; default 1440x900)
///   Duo                                        every Claude session, live; Home from Duo's state (DL-82)
///   Duo --workspace ~/work                     the same, with ~/work as Home's folder for this run
///   Duo --terminals demo                       real claude terminals in scratch folders (.build/demo)
///   Duo --gallery on                           the component gallery instead of the window
///   Duo --then open:checkout-redesign,peek     run actions after launch, before capturing
///                                              (open:<project>, open:<project>/<session>,
///                                              peek, down, up, jump, home, zoom-out, focus-tile)
///
/// Every flag takes a value. AppKit reads arguments as `-key value` pairs; a valueless flag
/// swallows the next one, and a path left over is treated as a file to open, which stops the
/// window from appearing (findings F-8).
///
/// Every flag makes a scripted run, which never uses the user's support folder: a new flag goes
/// in `SupportFolder.scriptedFlags` too (C-21, F-89; DuoChecks checks).
public struct LaunchOptions: Sendable {
    public var fixturePath: String?
    public var state: TargetState?
    /// A search-handoff target (`search-overview`, …), applied on top of `state`.
    public var searchState: String?
    public var capturePath: String?
    public var captureWindowPath: String?
    /// `--capture-scale N` (1–8, decimals ok) or `DUO_CAPTURE_SCALE`: the capture's pixels per point,
    /// drawn at that scale (not upsampled). The flag wins; 2 is the default.
    public var captureScale: Double = LaunchOptions.captureScale(arguments: CommandLine.arguments)
    public var collapseLeft = false
    /// `--window <w>x<h>`: the whole window's size for a fixture run (the design size otherwise).
    public var windowSize: CGSize?
    public var thenActions: [String] = []
    public var gallery = false
    /// `--terminals demo[:<root>]`: real claude sessions in scratch folders.
    public var terminals: String?
    /// `--workspace <root>`: real projects and sessions under root (Phase E).
    public var workspace: String?

    public var capturing: Bool { capturePath != nil || captureWindowPath != nil }
    /// The design fixture is for target states, captures and the gallery; a plain launch is live (DL-82).
    public var usesFixture: Bool { state != nil || searchState != nil || fixturePath != nil || gallery || capturing || thenActions.isEmpty == false }

    /// The capture scale from `--capture-scale`, else `DUO_CAPTURE_SCALE`, else 2; values outside 1–8 are ignored.
    public static func captureScale(arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment) -> Double {
        func valid(_ s: String?) -> Double? { s.flatMap(Double.init).flatMap { $0 >= 1 && $0 <= 8 ? $0 : nil } }
        if let i = arguments.firstIndex(of: "--capture-scale"), i + 1 < arguments.count, let v = valid(arguments[i + 1]) { return v }
        return valid(environment["DUO_CAPTURE_SCALE"]) ?? 2
    }

    public init(arguments: [String] = CommandLine.arguments) {
        var it = arguments.dropFirst().makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--fixture": fixturePath = it.next()
            case "--state":
                let name = it.next() ?? ""
                if SearchTargets.screens.contains(name) || SurfaceTargets.screens.contains(name) || ChatTargets.screens.contains(name) || NarrowTargets.screens.contains(name) || HomeListTargets.screens.contains(name) { state = .overview; searchState = name; continue }
                guard let s = TargetState(rawValue: name) else {
                    FileHandle.standardError.write(Data("Unknown state '\(name)'. Known: \(TargetState.allCases.map(\.rawValue).joined(separator: ", "))\n".utf8))
                    exit(64)
                }
                state = s
            case "--capture": capturePath = it.next()
            case "--capture-window": captureWindowPath = it.next()
            case "--capture-scale": _ = it.next()   // read by `captureScale(arguments:)`
            case "--left": collapseLeft = it.next() == "collapsed"
            case "--window":
                let wh = (it.next() ?? "").split(separator: "x").compactMap { Double($0) }
                if wh.count == 2 { windowSize = CGSize(width: wh[0], height: wh[1]) }
            case "--terminals": terminals = it.next()
            case "--workspace": workspace = it.next()
            case "--gallery": gallery = it.next() == "on"
            case "--then": thenActions = (it.next() ?? "").split(separator: ",").map(String.init)
            default: break  // AppKit passes its own flags (-NSDocumentRevisionsDebugMode etc.)
            }
        }
    }

    /// The fixture to load: `--fixture`, else the copy bundled in the app, else the one in the repo.
    public func resolveFixture() throws -> Fixture {
        if let fixturePath {
            return try Fixture.load(from: URL(fileURLWithPath: fixturePath))
        }
        if let bundled = Bundle.main.url(forResource: "fixture", withExtension: "json") {
            return try Fixture.load(from: bundled)
        }
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let candidate = dir.appending(path: "docs/design/build-handoff/fixture.json")
            if FileManager.default.fileExists(atPath: candidate.path) { return try Fixture.load(from: candidate) }
            dir.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "No fixture.json found. Pass --fixture <path>."])
    }
}
