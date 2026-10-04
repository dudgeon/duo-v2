// swift-tools-version: 6.2
// Spikes S14/S15 (build plan): Core ML query embedding from a plain command-line binary, inside
// Claude Code's sandbox; WordPiece tokenizer parity; throughput.
import PackageDescription
let package = Package(
    name: "S14Embed",
    platforms: [.macOS(.v26)],
    targets: [.executableTarget(name: "S14Embed")]
)
