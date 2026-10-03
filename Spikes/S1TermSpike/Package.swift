// swift-tools-version: 6.2
// Spike S1 (docs/plan/build-plan.md): SwiftTerm hosting the real `claude` TUI. Throwaway.
import PackageDescription

let package = Package(
    name: "S1TermSpike",
    platforms: [.macOS(.v26)],
    dependencies: [
        // SwiftTerm main (2.0 line), pinned: bracketed paste landed after v1.20.0 (stack research).
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", revision: "6a955b066d906ee78fbb158db93b4a48061fc948"),
    ],
    targets: [
        .executableTarget(name: "S1TermSpike", dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")]),
    ]
)
