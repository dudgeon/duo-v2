import Foundation
// Spike driver: regenerates out/duo from docs/ with the app's converter.
//   swiftc -O ../../Sources/DuoSearch/Pptx.swift ../../Sources/DuoSearch/Docx.swift main.swift -o /tmp/docx2md
//   /tmp/docx2md docs out/duo [--reject] [--leave-comments-out]
let a = CommandLine.arguments
let (src, dst) = (URL(fileURLWithPath: a[1]), URL(fileURLWithPath: a[2]))
try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
for f in try FileManager.default.contentsOfDirectory(atPath: src.path).sorted() where f.hasSuffix(".docx") {
    let name = (f as NSString).deletingPathExtension
    var o = Docx.Options(imagesFolder: "\(name)-images")
    if a.contains("--reject") { o.trackedChanges = .reject }
    if a.contains("--leave-comments-out") { o.comments = .leaveOut }
    do {
        let r = try Docx.convert(src.appending(path: f), options: o)
        try r.markdown.write(to: dst.appending(path: "\(name).md"), atomically: true, encoding: .utf8)
        if !r.images.isEmpty {
            let dir = dst.appending(path: "\(name)-images")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for i in r.images { try i.data.write(to: dir.appending(path: i.name)) }
        }
        let s = r.report.summary(o)
        try ((s.done + s.gaps.map { "gap: " + $0 }).joined(separator: "\n") + "\n").write(to: dst.appending(path: "\(name).summary"), atomically: true, encoding: .utf8)
    } catch {
        try "failed: \(error)\n".write(to: dst.appending(path: "\(name).summary"), atomically: true, encoding: .utf8)
    }
}
