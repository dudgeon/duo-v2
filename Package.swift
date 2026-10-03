// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Duo",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Duo", targets: ["Duo"]),
        .library(name: "DuoKit", targets: ["DuoKit"]),
    ],
    dependencies: [
        // SwiftTerm main (2.0 line), pinned. Spikes S1/S2 passed on this commit (findings F-17, F-18).
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", revision: "6a955b066d906ee78fbb158db93b4a48061fc948"),
    ],
    targets: [
        .target(name: "DuoKit", dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")]),
        .executableTarget(name: "Duo", dependencies: ["DuoKit"]),
        // Checks run as an executable (`swift run DuoChecks`): the Command Line Tools ship neither
        // XCTest nor the Swift Testing macro plugin. Move these to a test target once Xcode is installed.
        .executableTarget(name: "DuoChecks", dependencies: ["DuoKit"]),
    ]
)
