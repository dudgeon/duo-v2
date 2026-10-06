// swift-tools-version: 6.2
import PackageDescription

// Sparkle (in-app updates) is vendored as a framework (Vendor/Sparkle/README.md) and linked by the
// app alone: DuoChecks and duo2 don't load it.
let sparkle = Context.packageDirectory + "/Vendor/Sparkle"

let package = Package(
    name: "Duo",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Duo", targets: ["Duo"]),
        .executable(name: "duo2", targets: ["duo2"]),
        .library(name: "DuoKit", targets: ["DuoKit"]),
    ],
    dependencies: [
        // SwiftTerm main (2.0 line), pinned. Spikes S1/S2 passed on this commit (findings F-17, F-18).
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", revision: "6a955b066d906ee78fbb158db93b4a48061fc948"),
    ],
    targets: [
        // The app ↔ CLI protocol: Foundation only, so `duo2` stays small and sandbox-friendly.
        .target(name: "DuoControl"),
        // Cross-project search (SRCH, Phase M): index, Core ML embedder, hybrid ranking. Foundation,
        // SQLite, Core ML and Accelerate only, so the read-only CLI can use it in Claude's sandbox.
        .target(name: "DuoSearch", dependencies: ["DuoControl"], linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "DuoKit", dependencies: ["DuoControl", "DuoSearch", .product(name: "SwiftTerm", package: "SwiftTerm")]),
        .executableTarget(name: "duo2", dependencies: ["DuoControl", "DuoSearch"]),
        .executableTarget(name: "Duo", dependencies: ["DuoKit"],
                          swiftSettings: [.unsafeFlags(["-F", sparkle])],
                          linkerSettings: [.unsafeFlags(["-F", sparkle, "-framework", "Sparkle",
                                                         "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        // Checks run as an executable (`swift run DuoChecks`): the Command Line Tools ship neither
        // XCTest nor the Swift Testing macro plugin. Move these to a test target once Xcode is installed.
        .executableTarget(name: "DuoChecks", dependencies: ["DuoKit", "DuoControl", "DuoSearch", .product(name: "SwiftTerm", package: "SwiftTerm")]),
    ]
)
