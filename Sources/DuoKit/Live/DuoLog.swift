import Foundation

/// A small diagnostic log at `App Support/Duo/logs/duo.log` (last 1 MB kept), for events a
/// person reports but stderr doesn't reach (Duo opened from Finder or `open`).
public enum DuoLog {
    static var file: URL { DuoPaths.support.appending(path: "logs/duo.log") }

    public static func write(_ line: String) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let data = Data("\(f.string(from: Date())) \(line)\n".utf8)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: file) {
            defer { try? h.close() }
            if (try? h.seekToEnd()) ?? 0 > 1 << 20 { try? h.truncate(atOffset: 0) }
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: file)
        }
    }
}
