// swift-tools-version: 6.2
// Spike S6 (build plan): the native hedge. swift-markdown-engine (vendored) against S4's criteria.
import PackageDescription
let package = Package(
    name: "S6Native",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "../../Vendor/swift-markdown-engine")],
    targets: [.executableTarget(name: "S6Native", dependencies: [.product(name: "MarkdownEngine", package: "swift-markdown-engine")],
                                swiftSettings: [.swiftLanguageMode(.v5)])]
)
