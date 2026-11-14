import CoreGraphics
import Foundation

/// The rows of text a page's content stream shows, with where each character sits: for the files whose layout PDFKit gets wrong
/// (a wrapped line split over two rows, a 1 pt font under a scaled text matrix: what macOS prints). A row is one show operator
/// (`Tj`, `TJ`, `'`, `"`); its characters are the string's bytes read as Latin-1, so only simple fonts with a /Widths array are
/// understood: a row in any other font is left out, and the caller keeps PDFKit's boxes when the text isn't found here.
enum PdfTextRows {
    struct Row {
        var text: [Character]
        /// Page space: the left of the first character and the baseline.
        var x0: CGFloat
        var baseline: CGFloat
        /// The font size on the page.
        var size: CGFloat
        /// Each character's advance on the page.
        var advance: [CGFloat]

        /// The x range of characters `a...b`.
        func span(_ a: Int, _ b: Int) -> (CGFloat, CGFloat) {
            let lo = x0 + advance[0..<a].reduce(0, +)
            return (lo, lo + advance[a...b].reduce(0, +))
        }
    }

    final class State {
        var rows: [Row] = []
        var ctm = CGAffineTransform.identity, stack: [CGAffineTransform] = []
        var tm = CGAffineTransform.identity, tlm = CGAffineTransform.identity
        var size: CGFloat = 0, tc: CGFloat = 0, tw: CGFloat = 0, th: CGFloat = 1, leading: CGFloat = 0
        /// Widths by character code, nil when the current font isn't one we can measure.
        var widths: [CGFloat]?
        var fonts: [String: [CGFloat]?] = [:]
    }

    static func rows(_ page: CGPDFPage) -> [Row] {
        let st = State()
        let table = CGPDFOperatorTableCreate()!
        CGPDFOperatorTableSetCallback(table, "q") { _, i in let s = state(i); s.stack.append(s.ctm) }
        CGPDFOperatorTableSetCallback(table, "Q") { _, i in let s = state(i); if let c = s.stack.popLast() { s.ctm = c } }
        CGPDFOperatorTableSetCallback(table, "cm") { sc, i in
            guard let m = nums(sc, 6) else { return }
            let s = state(i); s.ctm = CGAffineTransform(a: m[0], b: m[1], c: m[2], d: m[3], tx: m[4], ty: m[5]).concatenating(s.ctm)
        }
        CGPDFOperatorTableSetCallback(table, "BT") { _, i in let s = state(i); s.tm = .identity; s.tlm = .identity }
        CGPDFOperatorTableSetCallback(table, "Tc") { sc, i in if let v = num(sc) { state(i).tc = v } }
        CGPDFOperatorTableSetCallback(table, "Tw") { sc, i in if let v = num(sc) { state(i).tw = v } }
        CGPDFOperatorTableSetCallback(table, "Tz") { sc, i in if let v = num(sc) { state(i).th = v / 100 } }
        CGPDFOperatorTableSetCallback(table, "TL") { sc, i in if let v = num(sc) { state(i).leading = v } }
        CGPDFOperatorTableSetCallback(table, "Tf") { sc, i in
            guard let size = num(sc) else { return }
            var name: UnsafePointer<Int8>?
            guard CGPDFScannerPopName(sc, &name), let name else { return }
            let s = state(i)
            s.size = size
            let key = String(cString: name)
            if let known = s.fonts[key] { s.widths = known; return }
            var w: [CGFloat]?
            if let obj = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(sc), "Font", name) {
                var dict: CGPDFDictionaryRef?
                if CGPDFObjectGetValue(obj, .dictionary, &dict), let dict { w = PdfTextRows.fontWidths(dict) }
            }
            s.fonts[key] = w
            s.widths = w
        }
        CGPDFOperatorTableSetCallback(table, "Td") { sc, i in if let m = nums(sc, 2) { move(state(i), m[0], m[1]) } }
        CGPDFOperatorTableSetCallback(table, "TD") { sc, i in if let m = nums(sc, 2) { let s = state(i); s.leading = -m[1]; move(s, m[0], m[1]) } }
        CGPDFOperatorTableSetCallback(table, "T*") { _, i in let s = state(i); move(s, 0, -s.leading) }
        CGPDFOperatorTableSetCallback(table, "Tm") { sc, i in
            guard let m = nums(sc, 6) else { return }
            let s = state(i); s.tm = CGAffineTransform(a: m[0], b: m[1], c: m[2], d: m[3], tx: m[4], ty: m[5]); s.tlm = s.tm
        }
        CGPDFOperatorTableSetCallback(table, "Tj") { sc, i in if let b = string(sc) { show(state(i), [(b, 0)]) } }
        CGPDFOperatorTableSetCallback(table, "'") { sc, i in
            let s = state(i); move(s, 0, -s.leading); if let b = string(sc) { show(s, [(b, 0)]) }
        }
        CGPDFOperatorTableSetCallback(table, "\"") { sc, i in
            let s = state(i)
            guard let b = string(sc), let ac = num(sc), let aw = num(sc) else { return }
            s.tw = aw; s.tc = ac; move(s, 0, -s.leading); show(s, [(b, 0)])
        }
        CGPDFOperatorTableSetCallback(table, "TJ") { sc, i in
            var arr: CGPDFArrayRef?
            guard CGPDFScannerPopArray(sc, &arr), let arr else { return }
            var parts: [(bytes: [UInt8], shift: CGFloat)] = []
            for k in 0..<CGPDFArrayGetCount(arr) {
                var str: CGPDFStringRef?
                var v: CGPDFReal = 0
                if CGPDFArrayGetString(arr, k, &str), let str, let p = CGPDFStringGetBytePtr(str) {
                    parts.append((Array(UnsafeBufferPointer(start: p, count: CGPDFStringGetLength(str))), 0))
                } else if CGPDFArrayGetNumber(arr, k, &v) {
                    if parts.isEmpty { parts.append(([], CGFloat(v))) } else { parts[parts.count - 1].shift += CGFloat(v) }
                }
            }
            show(state(i), parts)
        }
        let cs = CGPDFContentStreamCreateWithPage(page)
        let scanner = CGPDFScannerCreate(cs, table, Unmanaged.passUnretained(st).toOpaque())
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(cs)
        CGPDFOperatorTableRelease(table)
        return st.rows
    }

    /// A simple font's widths by character code, or nil (a composite font, or no /Widths).
    static func fontWidths(_ font: CGPDFDictionaryRef) -> [CGFloat]? {
        var sub: UnsafePointer<Int8>?
        guard CGPDFDictionaryGetName(font, "Subtype", &sub), let sub, ["Type1", "TrueType", "MMType1"].contains(String(cString: sub)) else { return nil }
        var arr: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(font, "Widths", &arr), let arr else { return nil }
        var first: CGPDFInteger = 0
        _ = CGPDFDictionaryGetInteger(font, "FirstChar", &first)
        var missing: CGPDFReal = 0
        var desc: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(font, "FontDescriptor", &desc), let desc { _ = CGPDFDictionaryGetNumber(desc, "MissingWidth", &missing) }
        var out = [CGFloat](repeating: CGFloat(missing), count: 256)
        for k in 0..<CGPDFArrayGetCount(arr) {
            var v: CGPDFReal = 0
            let code = Int(first) + k
            if CGPDFArrayGetNumber(arr, k, &v), code >= 0, code < 256 { out[code] = CGFloat(v) }
        }
        return out
    }
}

// Helpers the operator callbacks use (a C callback can capture nothing).
private func state(_ i: UnsafeMutableRawPointer?) -> PdfTextRows.State { Unmanaged<PdfTextRows.State>.fromOpaque(i!).takeUnretainedValue() }
private func num(_ s: CGPDFScannerRef) -> CGFloat? { var v: CGPDFReal = 0; return CGPDFScannerPopNumber(s, &v) ? CGFloat(v) : nil }
private func nums(_ s: CGPDFScannerRef, _ n: Int) -> [CGFloat]? {
    var out = [CGFloat](repeating: 0, count: n)
    for i in stride(from: n - 1, through: 0, by: -1) { guard let v = num(s) else { return nil }; out[i] = v }
    return out
}
private func move(_ s: PdfTextRows.State, _ tx: CGFloat, _ ty: CGFloat) {
    s.tlm = CGAffineTransform(translationX: tx, y: ty).concatenating(s.tlm); s.tm = s.tlm
}
/// Show `bytes` (and the TJ adjustments between them as `(bytes, shift)`), advancing the text matrix.
private func show(_ s: PdfTextRows.State, _ parts: [(bytes: [UInt8], shift: CGFloat)]) {
    let m = s.tm.concatenating(s.ctm)
    guard let widths = s.widths, abs(m.b) < 1e-6, abs(m.c) < 1e-6, m.a > 0, m.d > 0 else {
        // A font we can't measure: move on by nothing; the row is left out.
        return
    }
    var row = PdfTextRows.Row(text: [], x0: m.tx, baseline: m.ty, size: s.size * m.d, advance: [])
    var along: CGFloat = 0
    for p in parts {
        for b in p.bytes {
            let w = Int(b) < widths.count ? widths[Int(b)] : 0
            let adv = (w / 1000 * s.size + s.tc + (b == 32 ? s.tw : 0)) * s.th
            row.text.append(Character(UnicodeScalar(b))); row.advance.append(adv * m.a); along += adv
        }
        if p.shift != 0 {
            let adj = -p.shift / 1000 * s.size * s.th
            along += adj
            if row.advance.isEmpty { row.x0 += adj * m.a } else { row.advance[row.advance.count - 1] += adj * m.a }
        }
    }
    if !row.text.isEmpty { s.rows.append(row) }
    s.tm = CGAffineTransform(translationX: along, y: 0).concatenating(s.tm)
}
private func string(_ sc: CGPDFScannerRef) -> [UInt8]? {
    var str: CGPDFStringRef?
    guard CGPDFScannerPopString(sc, &str), let str, let p = CGPDFStringGetBytePtr(str) else { return nil }
    return Array(UnsafeBufferPointer(start: p, count: CGPDFStringGetLength(str)))
}
