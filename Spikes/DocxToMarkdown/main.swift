import Foundation
// Spike driver: docx2md <in-dir> <out-dir> [--reject] [--comments-as-footnotes]
let a = CommandLine.arguments
let (src, dst) = (URL(fileURLWithPath: a[1]), URL(fileURLWithPath: a[2]))
try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
for f in try FileManager.default.contentsOfDirectory(atPath: src.path).sorted() where f.hasSuffix(".docx") {
    let name = (f as NSString).deletingPathExtension
    var o = Docx.Options(imagesFolder: "\(name)-images")
    if a.contains("--reject") { o.trackedChanges = .reject }
    if a.contains("--comments-as-footnotes") { o.comments = .footnotes }
    let r = try Docx.convert(src.appending(path: f), options: o)
    try r.markdown.write(to: dst.appending(path: "\(name).md"), atomically: true, encoding: .utf8)
    if !r.images.isEmpty {
        let dir = dst.appending(path: "\(name)-images")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in r.images { try i.data.write(to: dir.appending(path: i.name)) }
    }
    try (r.report.lines(o).joined(separator: "\n") + "\n").write(to: dst.appending(path: "\(name).summary"), atomically: true, encoding: .utf8)
}
