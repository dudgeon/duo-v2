// swift-tools-version: 6.2
// Spike S7 (build plan): WKWebView local-only by default with an allow list (DL-3); inspector.
import PackageDescription
let package = Package(
    name: "S7WebView",
    platforms: [.macOS(.v26)],
    targets: [.executableTarget(name: "S7WebView")]
)
