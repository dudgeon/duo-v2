import Foundation

/// `duo2 deck template specimen <pack>` (lifecycle M3): a deck that uses every template once, each slot
/// filled to its limit with neutral sample text, exported, so the limits can be seen against the real
/// boxes. The sample text is "Sample text" repeated to the limit (`TemplateFit.sample`).
extension Deck {
    /// A small grey PNG (stored, not compressed) at the aspect `w:h`, for image slots in a specimen and
    /// for the picture left where a chart was.
    public static func placeholderPNG(aspect: Double, gray: UInt8 = 0xD8) -> Data {
        let h = 64, w = max(8, min(256, Int((64 * (aspect > 0 ? aspect : 1.5)).rounded())))
        var raw = Data()
        for y in 0..<h {
            raw.append(0)
            for x in 0..<w { raw.append(x == 0 || y == 0 || x == w - 1 || y == h - 1 ? gray &- 0x30 : gray) }
        }
        var adler: (UInt32, UInt32) = (1, 0)
        for b in raw { adler.0 = (adler.0 + UInt32(b)) % 65521; adler.1 = (adler.1 + adler.0) % 65521 }
        var z = Data([0x78, 0x01, 0x01, UInt8(raw.count & 0xFF), UInt8(raw.count >> 8), UInt8(~raw.count & 0xFF), UInt8((~raw.count >> 8) & 0xFF)])
        z.append(raw)
        z.append(contentsOf: [UInt8(adler.1 >> 8), UInt8(adler.1 & 0xFF), UInt8(adler.0 >> 8), UInt8(adler.0 & 0xFF)])
        func be(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
        func chunk(_ type: String, _ body: Data) -> Data {
            var d = Data(be(UInt32(body.count)))
            let td = Data(type.utf8) + body
            d.append(td)
            d.append(contentsOf: be(ZipWriter.crc32(td)))
            return d
        }
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        png.append(chunk("IHDR", Data(be(UInt32(w)) + be(UInt32(h)) + [8, 0, 0, 0, 0])))
        png.append(chunk("IDAT", z))
        png.append(chunk("IEND", Data()))
        return png
    }

    /// The specimen deck's Markdown, and the picture its image slots use (`assets/<imageName>`).
    public static func specimenText(pack: Pack, imageName: String) -> String {
        var out = ["---", "type: deck", "title: \(titleCase(pack.name)) specimen", "template: \(pack.name)"]
        if let f = pack.front["footer"] { out.append("footer: \(f)") }
        out += ["---", ""]
        for (n, t) in pack.templates.enumerated() {
            if n > 0 { out += ["---", ""] }
            out.append("<!-- slide: \(t.name) -->")
            for s in t.slots {
                let head = s.name == "title" ? ["# " + TemplateFit.sample(s.max ?? 30)] : ["", "## \(s.name)"]
                out += head
                switch s.kind {
                case "text", "number": if s.name != "title" { out.append(TemplateFit.sample(s.max ?? 30, kind: s.kind)) }
                case "bullets":
                    for _ in 0..<(s.items ?? 3) { out.append("- " + TemplateFit.sample(s.max ?? 40)) }
                case "image": out.append("![Sample picture](assets/\(imageName))")
                case "table":
                    let cols = s.cols ?? 3
                    out.append("| " + (0..<cols).map { "Header \($0 + 1)" }.joined(separator: " | ") + " |")
                    out.append("|" + String(repeating: " --- |", count: cols))
                    for r in 0..<max((s.rows ?? 4) - 1, 1) { out.append("| " + (0..<cols).map { _ in "Sample \(r + 1)" }.joined(separator: " | ") + " |") }
                default: break
                }
            }
            out += ["", "> [!note]", "> Specimen of the \(t.name) template: each slot is filled to its limit.", ""]
        }
        return out.joined(separator: "\n")
    }

    public struct SpecimenResult: Sendable {
        public var deck: URL
        public var export: Exported
        /// What the measured fit says about the specimen (the same messages `deck check` gives).
        public var fit: [Problem]
    }

    /// Writes the specimen deck (default: beside the pack's definition) and exports it. The export
    /// ignores the measured fit so an overflowing limit shows on the slide; the fit messages come back.
    public static func writeSpecimen(md: URL, out: URL? = nil, now: Date = Date(), timeZone: TimeZone = .current) throws -> SpecimenResult {
        let name = md.deletingPathExtension().lastPathComponent
        let pack = try loadPack(md: md, name: name)
        guard FileManager.default.fileExists(atPath: pack.pptx.path) else { throw Failure(description: "\(pack.pptx.lastPathComponent) isn't built yet: run duo2 deck template build \(name)") }
        let deck = out ?? md.deletingLastPathComponent().appending(path: "\(name)-specimen.md")
        let imageName = "\(name)-specimen.png"
        let assets = deck.deletingLastPathComponent().appending(path: "assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let aspect = pack.templates.flatMap(\.slots).first { $0.kind == "image" }?.aspect ?? 1.5
        try placeholderPNG(aspect: aspect).write(to: assets.appending(path: imageName), options: .atomic)
        try specimenText(pack: pack, imageName: imageName).write(to: deck, atomically: true, encoding: .utf8)
        let dirs = [md.deletingLastPathComponent().deletingLastPathComponent()] + packDirs(near: deck.deletingLastPathComponent())
        let checked = try check(deck: deck, packDirs: dirs)
        let exported = try writeExport(deck: deck, packDirs: dirs, now: now, timeZone: timeZone, measureFit: false)
        return SpecimenResult(deck: deck, export: exported, fit: checked.problems)
    }
}
