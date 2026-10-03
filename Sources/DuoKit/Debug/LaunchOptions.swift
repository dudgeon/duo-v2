import Foundation

/// Command-line flags for fixture mode and the comparison loop (handoff §0.2, §15 slice 1).
///
///   Duo --state overview                       open in a target state
///   Duo --state overview --capture out.png     ...capture the content below the toolbar, then quit
///   Duo --capture-window out.png               capture the whole window with screencapture(1)
///   Duo --fixture path/to/fixture.json         use another fixture file
///   Duo --left collapsed                       start with the left pane collapsed
///   Duo --terminals demo                       real claude terminals in scratch folders (.build/demo)
///   Duo --gallery on                           the component gallery instead of the window
///   Duo --then open:checkout-redesign,peek     run actions after launch, before capturing
///                                              (open:<project>, open:<project>/<session>,
///                                              peek, down, up, jump, home, zoom-out, focus-tile)
///
/// Every flag takes a value. AppKit reads arguments as `-key value` pairs; a valueless flag
/// swallows the next one, and a path left over is treated as a file to open, which stops the
/// window from appearing (findings F-8).
public struct LaunchOptions: Sendable {
    public var fixturePath: String?
    public var state: TargetState?
    public var capturePath: String?
    public var captureWindowPath: String?
    public var collapseLeft = false
    public var thenActions: [String] = []
    public var gallery = false
    /// `--terminals demo[:<root>]`: real claude sessions in scratch folders.
    public var terminals: String?

    public var capturing: Bool { capturePath != nil || captureWindowPath != nil }

    public init(arguments: [String] = CommandLine.arguments) {
        var it = arguments.dropFirst().makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--fixture": fixturePath = it.next()
            case "--state":
                let name = it.next() ?? ""
                guard let s = TargetState(rawValue: name) else {
                    FileHandle.standardError.write(Data("Unknown state '\(name)'. Known: \(TargetState.allCases.map(\.rawValue).joined(separator: ", "))\n".utf8))
                    exit(64)
                }
                state = s
            case "--capture": capturePath = it.next()
            case "--capture-window": captureWindowPath = it.next()
            case "--left": collapseLeft = it.next() == "collapsed"
            case "--terminals": terminals = it.next()
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
