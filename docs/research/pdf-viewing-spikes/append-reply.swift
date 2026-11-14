// Spike (research/pdf-viewing, F-644): PDFKit can't write /IRT (an object reference) and only
// saves by rewriting the whole file. This appends a reply thread as an ISO 32000 incremental
// update instead: new objects + a rewritten /Annots array + an xref section with /Prev.
// The original bytes stay an exact prefix, so a signature over them would still cover them.
// Usage: swift append-reply.swift <in.pdf> <out.pdf> <annotsObj> <parentAnnotObj>
// Scope: a spike. It handles a classic xref table and a page whose /Annots is an indirect
// array; a real writer also needs xref streams, inline /Annots and object streams.
import Foundation

let a = CommandLine.arguments
let inURL = URL(fileURLWithPath: a[1]), outURL = URL(fileURLWithPath: a[2])
let annotsObj = Int(a[3])!, parent = Int(a[4])!
var data = try Data(contentsOf: inURL)
let text = String(decoding: data, as: UTF8.self)

func match(_ pattern: String, in s: String) -> [String] {
    let re = try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    guard let m = re.matches(in: s, range: NSRange(s.startIndex..., in: s)).last else { return [] }
    return (1..<m.numberOfRanges).map { String(s[Range(m.range(at: $0), in: s)!]) }
}
let prev = Int(match(#"startxref\s+(\d+)\s+%%EOF\s*$"#, in: text)[0])!
let trailer = match(#"trailer\s*<<(.*?)>>\s*startxref"#, in: text)[0]
let size = Int(match(#"/Size\s+(\d+)"#, in: trailer)[0])!
let root = match(#"/Root\s+(\d+ \d+ R)"#, in: trailer)[0]
let oldAnnots = match("\\n\(annotsObj) 0 obj\\s*\\[(.*?)\\]\\s*endobj", in: text)[0]

func pdfDate(_ d: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "yyyyMMddHHmmss"; f.timeZone = TimeZone(identifier: "UTC")
    return "D:\(f.string(from: d))Z"
}
let now = pdfDate(Date())
let reply = size, state = size + 1
// Hidden (F 32) state reply, as Acrobat writes it; the reply is a normal Text annotation.
let objs: [(Int, String)] = [
    (reply, "<< /Type /Annot /Subtype /Text /Rect [ 520 690 540 710 ] /F 4 /T (Claude) /Contents (Reply written by an incremental update.) /NM (duo-c-0102) /IRT \(parent) 0 R /RT /R /M (\(now)) /CreationDate (\(now)) /Name /Comment >>"),
    (state, "<< /Type /Annot /Subtype /Text /Rect [ 520 690 540 710 ] /F 32 /T (Geoff) /Contents (Accepted set by Geoff) /NM (duo-c-0103) /IRT \(parent) 0 R /StateModel (Review) /State (Accepted) /M (\(now)) /CreationDate (\(now)) >>"),
    (annotsObj, "[ \(oldAnnots.trimmingCharacters(in: .whitespacesAndNewlines)) \(reply) 0 R \(state) 0 R ]"),
]
var tail = Data("\n".utf8)
var offsets: [(Int, Int)] = []
for (num, body) in objs {
    offsets.append((num, data.count + tail.count))
    tail += Data("\(num) 0 obj\n\(body)\nendobj\n".utf8)
}
let xrefAt = data.count + tail.count
var xref = "xref\n0 1\n0000000000 65535 f \n"
for (num, off) in offsets.sorted(by: { $0.0 < $1.0 }) { xref += "\(num) 1\n" + String(format: "%010d 00000 n \n", off) }
xref += "trailer\n<< /Size \(size + 2) /Root \(root) /Prev \(prev) >>\nstartxref\n\(xrefAt)\n%%EOF\n"
tail += Data(xref.utf8)
let original = data
data += tail
try data.write(to: outURL)
print("appended \(tail.count) B; original is byte prefix: \(data.starts(with: original))")
