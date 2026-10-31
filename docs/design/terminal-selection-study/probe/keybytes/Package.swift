// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "KeyBytes",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "/Users/geoff/repos/duo-v2/.build/checkouts/SwiftTerm")],
    targets: [.executableTarget(name: "KeyBytes", dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")],
                                swiftSettings: [.swiftLanguageMode(.v5)])]
)
