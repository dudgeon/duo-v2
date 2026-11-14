import AppKit
import CoreGraphics
import Foundation
import PDFKit

// What a Claude session gets from a PDF (DL-334, docs/research/pdf-viewing.md §4): `duo2 doc read <file.pdf>` returns PDFKit's text
// (the same text the viewer shows, so page numbers match) with a `--- page N ---` line before each page, then the pages worth
// looking at as images, with why; `duo2 pdf render <file> <page>` draws one. Binary files are otherwise refused by `doc read`.
public enum PdfRead {
    public struct Look: Equatable, Sendable {
        public var page: Int; public var reason: String
        public init(page: Int, reason: String) { self.page = page; self.reason = reason }
    }

    public struct Result: Sendable {
        public var text: String
        public var pages: Int
        public var look: [Look]
    }

    /// Fewer than this many non-space characters is a page without a text layer.
    static let minimumCharacters = 20
    /// A page with at least this many path-paint operators and less text than `figureText` is mostly a figure.
    static let figurePaints = 6
    static let figureText = 400

    public static func read(_ url: URL) throws -> Result {
        guard let doc = PDFDocument(url: url) else { throw PdfReadFailure("can't open \(url.lastPathComponent) as a PDF") }
        if doc.isLocked { throw PdfReadFailure("\(url.lastPathComponent) is locked with a password") }
        let cg = CGPDFDocument(url as CFURL)
        var out = "", look: [Look] = []
        for i in 0..<doc.pageCount {
            let text = (doc.page(at: i)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            out += "--- page \(i + 1) ---\n" + text + "\n"
            let chars = text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
            if chars < minimumCharacters { look.append(Look(page: i + 1, reason: "no text layer")); continue }
            if let cg, let page = cg.page(at: i + 1) {
                let c = drawing(page)
                if c.images > 0 || (c.paints >= figurePaints && text.count < figureText) { look.append(Look(page: i + 1, reason: "mostly a figure")) }
            }
        }
        if !look.isEmpty {
            out += "\nPages to look at as images (the text above leaves out what they show):\n"
            for l in look { out += "- page \(l.page): \(l.reason)\n" }
        }
        out += "\nRender one with `duo2 pdf render \(shellName(url)) <page>` and read the PNG.\n"
        return Result(text: out, pages: doc.pageCount, look: look)
    }

    static func shellName(_ url: URL) -> String { url.lastPathComponent.contains(" ") ? "\"\(url.lastPathComponent)\"" : url.lastPathComponent }

    // MARK: What a page draws

    final class Counter {
        var images = 0, paints = 0, depth = 0
        var table: CGPDFOperatorTableRef?
    }

    /// The images and path paints in a page's content (forms are followed to a depth of four).
    static func drawing(_ page: CGPDFPage) -> (images: Int, paints: Int) {
        let c = Counter()
        let table = CGPDFOperatorTableCreate()!
        c.table = table
        let paint: CGPDFOperatorCallback = { _, info in Unmanaged<Counter>.fromOpaque(info!).takeUnretainedValue().paints += 1 }
        for op in ["f", "F", "f*", "S", "s", "B", "B*", "b", "b*"] { CGPDFOperatorTableSetCallback(table, op, paint) }
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            let c = Unmanaged<Counter>.fromOpaque(info!).takeUnretainedValue()
            var name: UnsafePointer<Int8>?
            guard CGPDFScannerPopName(scanner, &name), let name else { return }
            let cs = CGPDFScannerGetContentStream(scanner)
            guard let obj = CGPDFContentStreamGetResource(cs, "XObject", name) else { return }
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(obj, .stream, &stream), let stream, let dict = CGPDFStreamGetDictionary(stream) else { return }
            var sub: UnsafePointer<Int8>?
            guard CGPDFDictionaryGetName(dict, "Subtype", &sub), let sub else { return }
            if String(cString: sub) == "Image" { c.images += 1 }
            else if String(cString: sub) == "Form", c.depth < 4 {
                var res: CGPDFDictionaryRef?
                guard CGPDFDictionaryGetDictionary(dict, "Resources", &res), let res else { return }   // a form without its own resources isn't followed
                let inner = CGPDFContentStreamCreateWithStream(stream, res, cs)
                let s = CGPDFScannerCreate(inner, c.table, info)
                c.depth += 1
                CGPDFScannerScan(s)
                c.depth -= 1
                CGPDFScannerRelease(s)
                CGPDFContentStreamRelease(inner)
            }
        }
        let cs = CGPDFContentStreamCreateWithPage(page)
        let scanner = CGPDFScannerCreate(cs, table, Unmanaged.passUnretained(c).toOpaque())
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(cs)
        CGPDFOperatorTableRelease(table)
        return (c.images, c.paints)
    }

    // MARK: Render

    /// PNG data of one page (1-based) `width` px wide, drawn by PDFKit with its annotations.
    public static func render(_ url: URL, page n: Int, width: Int = 1000) throws -> Data {
        guard let doc = PDFDocument(url: url) else { throw PdfReadFailure("can't open \(url.lastPathComponent) as a PDF") }
        if doc.isLocked { throw PdfReadFailure("\(url.lastPathComponent) is locked with a password") }
        guard n >= 1, n <= doc.pageCount, let page = doc.page(at: n - 1) else {
            throw PdfReadFailure("\(url.lastPathComponent) has \(doc.pageCount) page\(doc.pageCount == 1 ? "" : "s"): there is no page \(n)")
        }
        var box = page.bounds(for: .cropBox)
        if page.rotation % 180 != 0 { box = CGRect(x: 0, y: 0, width: box.height, height: box.width) }
        guard box.width > 0, box.height > 0 else { throw PdfReadFailure("page \(n) has no size") }
        let size = CGSize(width: CGFloat(width), height: (CGFloat(width) * box.height / box.width).rounded())
        let image = page.thumbnail(of: size, for: .cropBox)
        // Redrawn into a bitmap of exactly the pixels asked for (a thumbnail takes the screen's scale).
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let gc = NSGraphicsContext(bitmapImageRep: rep) else { throw PdfReadFailure("couldn't draw page \(n)") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { throw PdfReadFailure("couldn't draw page \(n)") }
        return png
    }
}

public struct PdfReadFailure: Error, CustomStringConvertible { public let description: String; public init(_ d: String) { description = d } }
