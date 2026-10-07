import Foundation

/// Duo's hang log (DL-139, F-163): each time Duo's main thread stalls for 250 ms or more, one line
/// in `Duo/logs/hangs.jsonl` saying when, for how long, what was on screen and, for a long stall,
/// where the main thread was. It stays on this Mac, in Duo's own folder (an isolated instance
/// writes to its own), capped at 512 KB: past that the older half goes. `duo2 hangs` reads it.
public enum HangLog {
    public static var file: URL { SupportFolder.duo.appending(path: "logs/hangs.jsonl") }
    public static let cap = 512 * 1024
    /// A stall this long is logged.
    public static let threshold: TimeInterval = 0.25

    public struct Record: Codable, Sendable, Equatable {
        /// When the stall began.
        public var at: Date
        public var ms: Int
        /// What was on screen as it ended: `chat · checkout-redesign · 135 items, 1,943 steps`.
        public var screen: String
        /// Duo's version and build, so a stack is read against the binary that made it.
        public var version: String
        /// For stalls of half a second or more: the main thread, sampled every 50 ms while it was
        /// stuck. Each frame is `image@0xoffset` (read with `atos`), innermost first.
        public var samples: [[String]]?
        /// The app's executable and where it was loaded, to read the samples' Duo frames.
        public var binary: String?

        public init(at: Date, ms: Int, screen: String, version: String, samples: [[String]]? = nil, binary: String? = nil) {
            self.at = at; self.ms = ms; self.screen = screen; self.version = version; self.samples = samples; self.binary = binary
        }
    }

    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    /// One line at the end; past the cap, only the newer half of the file is kept.
    public static func append(_ r: Record, to url: URL = file) {
        guard let line = try? encoder.encode(r) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = (try? Data(contentsOf: url)) ?? Data()
        data.append(line); data.append(0x0A)
        if data.count > cap {
            let half = data.count - cap / 2
            let cut = data[half...].firstIndex(of: 0x0A).map { $0 + 1 } ?? data.endIndex
            data = Data(data[cut...])
        }
        try? data.write(to: url, options: .atomic)
    }

    public static func read(from url: URL = file) -> [Record] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(Record.self, from: Data($0)) }
    }

    public static func clear(_ url: URL = file) { try? FileManager.default.removeItem(at: url) }

    /// The stalls since `since`, newest last, as `duo2 hangs` prints them.
    public static func report(_ records: [Record], stacks: Bool, symbolicate: ([String], String?) -> [String] = { f, _ in f }) -> String {
        guard !records.isEmpty else { return "No stalls of \(Int(threshold * 1000)) ms or more logged." }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var out: [String] = []
        let long = records.filter { $0.ms >= 2000 }.count
        out.append("\(records.count) stall\(records.count == 1 ? "" : "s"), \(long) of 2 s or more (a beach ball); longest \(records.map(\.ms).max() ?? 0) ms.")
        for r in records {
            out.append("\(f.string(from: r.at))  \(String(r.ms).leftPad(6)) ms  \(r.screen)")
            if stacks, let s = r.samples, !s.isEmpty {
                // Where the main thread was most often: its innermost frames in Duo, counted over the samples.
                var counts: [String: Int] = [:], depth: [String: Int] = [:]
                for sample in s {
                    var seen = Set<String>()
                    for (i, frame) in symbolicate(sample, r.binary).prefix(64).enumerated() where frame.contains("(Duo)") && seen.insert(frame).inserted {
                        counts[frame, default: 0] += 1
                        depth[frame, default: 0] += i
                    }
                }
                // The innermost frame of the first sample, often in AppKit or SwiftUI: what Duo was waiting on.
                if let top = s.first?.first { out.append("      in: " + (symbolicate([top], r.binary).first ?? top)) }
                // Most often first, then innermost first: the top line is where it was stuck.
                let avg = { (f: String) in Double(depth[f] ?? 0) / Double(max(1, counts[f] ?? 1)) }
                for (frame, n) in counts.sorted(by: { $0.value != $1.value ? $0.value > $1.value : avg($0.key) < avg($1.key) }).prefix(8) {
                    out.append("      \(n)/\(s.count)  \(frame)")
                }
                if counts.isEmpty, let first = s.first { out += symbolicate(first, r.binary).prefix(12).map { "      " + $0 } }
            }
        }
        return out.joined(separator: "\n")
    }
}

private extension String {
    func leftPad(_ n: Int) -> String { count >= n ? self : String(repeating: " ", count: n - count) + self }
}
