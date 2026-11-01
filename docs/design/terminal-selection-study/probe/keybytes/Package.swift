// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "KeyBytes",
    platforms: [.macOS(.v26)],
    // The repo's own SwiftTerm checkout, after a `swift build` at the root.
    dependencies: [.package(path: "../../../../../.build/checkouts/SwiftTerm")],
    targets: [.executableTarget(name: "KeyBytes", dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")],
                                swiftSettings: [.swiftLanguageMode(.v5)])]
)
