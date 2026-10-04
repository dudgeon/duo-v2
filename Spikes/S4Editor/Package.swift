// swift-tools-version: 6.2
// Spikes S4/S5 (build plan): CM6 live preview in a WKWebView; byte-faithful round trip; latency;
// RSS; external-edit merge. Loads the vendored bundle from ../../Vendor/codemirror/dist.
import PackageDescription
let package = Package(
    name: "S4Editor",
    platforms: [.macOS(.v26)],
    targets: [.executableTarget(name: "S4Editor")]
)
