// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Duo",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Duo", targets: ["Duo"]),
        .library(name: "DuoKit", targets: ["DuoKit"]),
    ],
    targets: [
        .target(name: "DuoKit"),
        .executableTarget(name: "Duo", dependencies: ["DuoKit"]),
        // Checks run as an executable (`swift run DuoChecks`): the Command Line Tools ship neither
        // XCTest nor the Swift Testing macro plugin. Move these to a test target once Xcode is installed.
        .executableTarget(name: "DuoChecks", dependencies: ["DuoKit"]),
    ]
)
