// swift-tools-version: 5.9
// Vendored core of swift-markdown-engine (Apache-2.0), commit 1c2e76c1 (2026-07-10), for spike S6.
// Only the dependency-free `MarkdownEngine` target; the code-block and LaTeX bridges are left out.
import PackageDescription
let package = Package(
    name: "MarkdownEngine",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MarkdownEngine", targets: ["MarkdownEngine"])],
    targets: [.target(name: "MarkdownEngine", exclude: ["MarkdownEngine.docc"])]
)
