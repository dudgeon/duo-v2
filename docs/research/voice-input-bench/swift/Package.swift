// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "asrbench",
    platforms: [.macOS(.v26)],
    dependencies: [
        // FluidAudio v0.18.3 (2026-11-07).
        .package(url: "https://github.com/FluidInference/FluidAudio.git",
                 exact: "0.18.3", traits: []),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.1"),
    ],
    targets: [
        .executableTarget(
            name: "asrbench",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
