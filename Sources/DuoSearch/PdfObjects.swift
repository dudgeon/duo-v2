import Compression
import Foundation

// A small PDF object layer (DL-335, docs/research/pdf-viewing.md §5): enough to find a document's pages and annotations and to
// append an incremental update. Foundation and Compression only. It reads the header, `startxref`, classic xref tables and xref
// streams (following /Prev, and a hybrid file's /XRefStm), objects stored directly or inside object streams, and Flate streams
// with the PNG predictors. Anything it cannot read exactly is refused (`PdfFailure`): it never guesses at a damaged file.

struct PdfFailure: Error, CustomStringConvertible { let description: String; init(_ d: String) { description = d } }

/// A PDF object. Numbers keep their text so a re-serialised dictionary is faithful.
indirect enum PdfObj {
    case null
    case bool(Bool)
    case int(Int)
    case real(String)
    case name(String)
    case string([UInt8])
    case array([PdfObj])
    case dict([String: PdfObj], order: [String])
    case ref(Int, Int)
    case stream([String: PdfObj], order: [String], Data)

    var dict: [String: PdfObj]? {
        switch self { case .dict(let d, _), .stream(let d, _, _): return d; default: return nil }
    }
    var array: [PdfObj]? { if case .array(let a) = self { return a }; return nil }
    var intValue: Int? {
        switch self { case .int(let i): return i; case .real(let s): return Double(s).map { Int($0) }; default: return nil }
    }
    var number: Double? {
        switch self { case .int(let i): return Double(i); case .real(let s): return Double(s); default: return nil }
    }
    var nameValue: String? { if case .name(let n) = self { return n }; return nil }
    var refNumber: Int? { if case .ref(let n, _) = self { return n }; return nil }
    var bytes: [UInt8]? { if case .string(let b) = self { return b }; return nil }
    /// A text string (PDFDocEncoding, UTF-16 or UTF-8 with a BOM).
    var text: String? { bytes.map(PdfText.decode) }

    // MARK: Serialising

    func write(into out: inout [UInt8]) {
        func s(_ t: String) { out.append(contentsOf: Array(t.utf8)) }
        switch self {
        case .null: s("null")
        case .bool(let b): s(b ? "true" : "false")
        case .int(let i): s(String(i))
        case .real(let r): s(r)
        case .name(let n): s("/"); out.append(contentsOf: PdfObj.encodeName(n))
        case .string(let b): PdfObj.writeString(b, into: &out)
        case .array(let a):
            s("[")
            for (i, e) in a.enumerated() { if i > 0 { s(" ") }; e.write(into: &out) }
            s("]")
        case .dict(let d, let order):
            s("<<")
            let keys = order.filter { d[$0] != nil } + d.keys.filter { !order.contains($0) }.sorted()
            for k in keys { s(" /"); out.append(contentsOf: PdfObj.encodeName(k)); s(" "); d[k]!.write(into: &out) }
            s(" >>")
        case .ref(let n, let g): s("\(n) \(g) R")
        case .stream: break   // streams are written by the caller, with their own /Length
        }
    }
    func serialized() -> [UInt8] { var o: [UInt8] = []; write(into: &o); return o }

    static func encodeName(_ n: String) -> [UInt8] {
        var o: [UInt8] = []
        for b in n.utf8 {
            if b <= 32 || b >= 127 || b == 35 || PdfLexer.delimiters.contains(b) { o.append(contentsOf: Array(String(format: "#%02X", b).utf8)) } else { o.append(b) }
        }
        return o
    }
    static func writeString(_ b: [UInt8], into out: inout [UInt8]) {
        out.append(40)
        for c in b {
            switch c {
            case 40, 41, 92: out.append(92); out.append(c)
            case 10: out.append(contentsOf: [92, 110])
            case 13: out.append(contentsOf: [92, 114])
            case 9: out.append(contentsOf: [92, 116])
            default: out.append(c)
            }
        }
        out.append(41)
    }
    static func dict(_ pairs: [(String, PdfObj)]) -> PdfObj {
        var d: [String: PdfObj] = [:]
        for (k, v) in pairs { d[k] = v }
        return .dict(d, order: pairs.map(\.0))
    }
    /// A text string value: PDFDocEncoding when it fits (ASCII), else UTF-16BE with a byte order mark, as a hex string.
    static func text(_ s: String) -> PdfObj {
        if s.unicodeScalars.allSatisfy({ $0.value < 128 }) { return .string(Array(s.utf8)) }
        return .string([0xFE, 0xFF] + s.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] })
    }
}

enum PdfText {
    static func decode(_ b: [UInt8]) -> String {
        if b.count >= 2, b[0] == 0xFE, b[1] == 0xFF { return utf16(b.dropFirst(2), big: true) }
        if b.count >= 2, b[0] == 0xFF, b[1] == 0xFE { return utf16(b.dropFirst(2), big: false) }
        if b.count >= 3, b[0] == 0xEF, b[1] == 0xBB, b[2] == 0xBF { return String(decoding: b.dropFirst(3), as: UTF8.self) }
        var out = String.UnicodeScalarView()
        for c in b { out.append(Unicode.Scalar(docEncoding(c))!) }
        return String(out)
    }
    static func utf16<S: Sequence>(_ b: S, big: Bool) -> String where S.Element == UInt8 {
        let a = Array(b); var units: [UInt16] = []
        var i = 0
        while i + 1 < a.count { units.append(big ? UInt16(a[i]) << 8 | UInt16(a[i + 1]) : UInt16(a[i + 1]) << 8 | UInt16(a[i])); i += 2 }
        return String(decoding: units, as: UTF16.self)
    }
    static let high: [UInt8: UInt32] = [
        0x18: 0x2D8, 0x19: 0x2C7, 0x1A: 0x2C6, 0x1B: 0x2D9, 0x1C: 0x2DD, 0x1D: 0x2DB, 0x1E: 0x2DA, 0x1F: 0x2DC,
        0x80: 0x2022, 0x81: 0x2020, 0x82: 0x2021, 0x83: 0x2026, 0x84: 0x2014, 0x85: 0x2013, 0x86: 0x192, 0x87: 0x2044,
        0x88: 0x2039, 0x89: 0x203A, 0x8A: 0x2212, 0x8B: 0x2030, 0x8C: 0x201E, 0x8D: 0x201C, 0x8E: 0x201D, 0x8F: 0x2018,
        0x90: 0x2019, 0x91: 0x201A, 0x92: 0x2122, 0x93: 0xFB01, 0x94: 0xFB02, 0x95: 0x141, 0x96: 0x152, 0x97: 0x160,
        0x98: 0x178, 0x99: 0x17D, 0x9A: 0x131, 0x9B: 0x142, 0x9C: 0x153, 0x9D: 0x161, 0x9E: 0x17E, 0xA0: 0x20AC,
    ]
    static func docEncoding(_ c: UInt8) -> UInt32 { high[c] ?? UInt32(c) }
}

// MARK: Lexer

struct PdfLexer {
    static let delimiters: Set<UInt8> = [40, 41, 60, 62, 91, 93, 123, 125, 47, 37]
    static let space: Set<UInt8> = [0, 9, 10, 12, 13, 32]

    let b: [UInt8]
    var pos: Int
    init(_ bytes: [UInt8], at: Int = 0) { b = bytes; pos = at }

    var atEnd: Bool { pos >= b.count }

    mutating func skipSpace() {
        while pos < b.count {
            if PdfLexer.space.contains(b[pos]) { pos += 1 }
            else if b[pos] == 37 { while pos < b.count, b[pos] != 10, b[pos] != 13 { pos += 1 } }
            else { break }
        }
    }
    func isRegular(_ c: UInt8) -> Bool { !PdfLexer.space.contains(c) && !PdfLexer.delimiters.contains(c) }

    /// A run of regular characters (a keyword or a number).
    mutating func word() -> String {
        skipSpace()
        let start = pos
        while pos < b.count, isRegular(b[pos]) { pos += 1 }
        return String(decoding: b[start..<pos], as: UTF8.self)
    }
    mutating func peekWord() -> String { let p = pos; defer { pos = p }; return word() }
    mutating func int() throws -> Int {
        let w = word()
        guard let i = Int(w) else { throw PdfFailure("expected a number at byte \(pos), found '\(w.prefix(12))'") }
        return i
    }

    mutating func object() throws -> PdfObj {
        skipSpace()
        guard pos < b.count else { throw PdfFailure("the file ends inside an object") }
        let c = b[pos]
        switch c {
        case 60:   // <
            if pos + 1 < b.count, b[pos + 1] == 60 { pos += 2; return try dictBody() }
            return try hexString()
        case 40: return try literalString()
        case 47: pos += 1; return .name(name())
        case 91:
            pos += 1
            var items: [PdfObj] = []
            while true {
                skipSpace()
                guard pos < b.count else { throw PdfFailure("an array never closes") }
                if b[pos] == 93 { pos += 1; return .array(items) }
                items.append(try object())
            }
        default: break
        }
        let start = pos
        let w = word()
        if w.isEmpty { pos = start + 1; throw PdfFailure("unexpected '\(String(decoding: [c], as: UTF8.self))' at byte \(start)") }
        switch w {
        case "true": return .bool(true)
        case "false": return .bool(false)
        case "null": return .null
        default: break
        }
        if let i = Int(w) {
            if i >= 0 {   // maybe `n g R`
                let save = pos
                var probe = self
                let g = probe.word()
                if let gen = Int(g), gen >= 0 {
                    probe.skipSpace()
                    if probe.pos < b.count, b[probe.pos] == 82, probe.pos + 1 >= b.count || !isRegular(b[probe.pos + 1]) {
                        pos = probe.pos + 1
                        return .ref(i, gen)
                    }
                }
                pos = save
            }
            return .int(i)
        }
        if Double(w) != nil || w.allSatisfy({ "+-.0123456789".contains($0) }) {
            guard Double(w) != nil else { throw PdfFailure("bad number '\(w)'") }
            return .real(w)
        }
        throw PdfFailure("unexpected '\(w.prefix(12))' at byte \(start)")
    }

    mutating func name() -> String {
        var out: [UInt8] = []
        while pos < b.count, isRegular(b[pos]) {
            if b[pos] == 35, pos + 2 < b.count, let h = UInt8(String(decoding: b[pos + 1...pos + 2], as: UTF8.self), radix: 16) { out.append(h); pos += 3 }
            else { out.append(b[pos]); pos += 1 }
        }
        return String(decoding: out, as: UTF8.self)
    }

    mutating func dictBody() throws -> PdfObj {
        var d: [String: PdfObj] = [:], order: [String] = []
        while true {
            skipSpace()
            guard pos < b.count else { throw PdfFailure("a dictionary never closes") }
            if b[pos] == 62 {
                guard pos + 1 < b.count, b[pos + 1] == 62 else { throw PdfFailure("stray '>' at byte \(pos)") }
                pos += 2
                return .dict(d, order: order)
            }
            guard b[pos] == 47 else { throw PdfFailure("a dictionary key isn't a name at byte \(pos)") }
            pos += 1
            let k = name()
            let v = try object()
            if d[k] == nil { order.append(k) }
            d[k] = v
        }
    }

    mutating func hexString() throws -> PdfObj {
        pos += 1
        var out: [UInt8] = [], hi: Int?
        while pos < b.count, b[pos] != 62 {
            let c = b[pos]; pos += 1
            guard let v = Int(String(decoding: [c], as: UTF8.self), radix: 16) else { if PdfLexer.space.contains(c) { continue }; throw PdfFailure("bad hex string") }
            if let h = hi { out.append(UInt8(h << 4 | v)); hi = nil } else { hi = v }
        }
        guard pos < b.count else { throw PdfFailure("a hex string never closes") }
        pos += 1
        if let h = hi { out.append(UInt8(h << 4)) }
        return .string(out)
    }

    mutating func literalString() throws -> PdfObj {
        pos += 1
        var out: [UInt8] = [], depth = 1
        while pos < b.count {
            let c = b[pos]; pos += 1
            switch c {
            case 40: depth += 1; out.append(c)
            case 41:
                depth -= 1
                if depth == 0 { return .string(out) }
                out.append(c)
            case 92:
                guard pos < b.count else { break }
                let e = b[pos]; pos += 1
                switch e {
                case 110: out.append(10)
                case 114: out.append(13)
                case 116: out.append(9)
                case 98: out.append(8)
                case 102: out.append(12)
                case 13: if pos < b.count, b[pos] == 10 { pos += 1 }
                case 10: break
                case 48...55:
                    var v = Int(e - 48), n = 1
                    while n < 3, pos < b.count, (48...55).contains(b[pos]) { v = v * 8 + Int(b[pos] - 48); pos += 1; n += 1 }
                    out.append(UInt8(v & 0xFF))
                default: out.append(e)
                }
            case 13:   // a bare CR or CRLF inside a string is one LF
                if pos < b.count, b[pos] == 10 { pos += 1 }
                out.append(10)
            default: out.append(c)
            }
        }
        throw PdfFailure("a string never closes")
    }
}

// MARK: Filters

enum PdfFilters {
    /// Raw deflate (Compression's COMPRESSION_ZLIB is raw), after the 2-byte zlib header.
    static func inflate(_ data: Data) throws -> Data {
        guard data.count > 2 else { throw PdfFailure("a Flate stream is empty") }
        let src = [UInt8](data.dropFirst(2))
        var out = Data()
        let dstSize = 64 * 1024
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: dstSize)
        defer { dst.deallocate() }
        let sp = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { sp.deallocate() }
        guard compression_stream_init(sp, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { throw PdfFailure("can't start inflating") }
        defer { compression_stream_destroy(sp) }
        return try src.withUnsafeBufferPointer { sbuf in
            sp.pointee.src_ptr = sbuf.baseAddress ?? UnsafePointer(dst)
            sp.pointee.src_size = sbuf.count
            sp.pointee.dst_ptr = dst
            sp.pointee.dst_size = dstSize
            while true {
                let before = sp.pointee.src_size
                let status = compression_stream_process(sp, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = dstSize - sp.pointee.dst_size
                out.append(dst, count: produced)
                sp.pointee.dst_ptr = dst
                sp.pointee.dst_size = dstSize
                if status == COMPRESSION_STATUS_END { return out }
                if status == COMPRESSION_STATUS_ERROR { throw PdfFailure("a Flate stream is damaged") }
                if produced == 0 && sp.pointee.src_size == 0 { return out }   // truncated stream: what came out
                if produced == 0 && sp.pointee.src_size == before { throw PdfFailure("damaged compressed stream") }   // no input used, nothing made: it would loop
            }
        }
    }

    /// PNG predictors (10 to 15): each row starts with its filter byte.
    static func unpredict(_ d: Data, columns: Int, colors: Int, bpc: Int) throws -> Data {
        let bpp = max(1, colors * bpc / 8)
        let row = (columns * colors * bpc + 7) / 8
        guard row > 0 else { throw PdfFailure("bad predictor columns") }
        let a = [UInt8](d)
        var out = [UInt8](); out.reserveCapacity(a.count)
        var prev = [UInt8](repeating: 0, count: row)
        var i = 0
        while i + 1 + row <= a.count {
            let f = a[i]; var cur = Array(a[(i + 1)..<(i + 1 + row)]); i += 1 + row
            for x in 0..<row {
                let left = x >= bpp ? Int(cur[x - bpp]) : 0, up = Int(prev[x]), ul = x >= bpp ? Int(prev[x - bpp]) : 0
                switch f {
                case 0: break
                case 1: cur[x] = UInt8((Int(cur[x]) + left) & 0xFF)
                case 2: cur[x] = UInt8((Int(cur[x]) + up) & 0xFF)
                case 3: cur[x] = UInt8((Int(cur[x]) + (left + up) / 2) & 0xFF)
                case 4:
                    let p = left + up - ul, pa = abs(p - left), pb = abs(p - up), pc = abs(p - ul)
                    let pr = (pa <= pb && pa <= pc) ? left : (pb <= pc ? up : ul)
                    cur[x] = UInt8((Int(cur[x]) + pr) & 0xFF)
                default: throw PdfFailure("unknown PNG predictor row type \(f)")
                }
            }
            out.append(contentsOf: cur); prev = cur
        }
        return Data(out)
    }
}

// MARK: The file

/// How an object is found.
enum PdfEntry { case free, offset(Int, gen: Int), inStream(Int, index: Int) }

final class PdfFile {
    let bytes: [UInt8]
    /// Object numbers to entries, newest section first.
    private(set) var entries: [Int: PdfEntry] = [:]
    /// The newest trailer (or xref stream dictionary), and the others down the chain.
    private(set) var trailers: [[String: PdfObj]] = []
    private(set) var newestStartxref = 0
    private(set) var newestIsStream = false
    /// Where `%PDF-` starts. Cross-reference offsets count from there (as Acrobat and the CoreGraphics reader take them), so a file with
    /// junk in front keeps working: every offset read is shifted by this, and every one written is shifted back.
    private(set) var headerOffset = 0
    private var cache: [Int: PdfObj] = [:]
    private var objStms: [Int: (objects: [Int: PdfObj], order: [Int])] = [:]

    var trailer: [String: PdfObj] { trailers[0] }
    var size: Int { max(trailers.compactMap { $0["Size"]?.intValue }.first ?? 0, (entries.keys.max() ?? 0) + 1) }

    init(_ data: Data) throws {
        bytes = [UInt8](data)
        guard bytes.count > 20, let h = Self.find(Array("%PDF-".utf8), in: bytes, from: 0, to: min(bytes.count, 1024)) else {
            throw PdfFailure("not a PDF file (no %PDF- header)")
        }
        headerOffset = h
        do { try readXrefChain() }
        catch where h > 0 {
            // Offsets that count from byte 0 instead (a writer that ignored the junk in front): read them that way.
            entries = [:]; trailers = []; headerOffset = 0
            do { try readXrefChain() } catch { throw PdfFailure("the cross-reference data can't be read, with or without the \(h) bytes in front of %PDF-") }
        }
        guard trailer["Root"]?.refNumber != nil else { throw PdfFailure("the trailer has no /Root: this file's cross-reference data can't be read") }
    }

    static func find(_ needle: [UInt8], in hay: [UInt8], from: Int, to: Int) -> Int? {
        guard !needle.isEmpty, to - from >= needle.count else { return nil }
        var i = from
        while i <= to - needle.count {
            if hay[i] == needle[0], hay[i..<(i + needle.count)].elementsEqual(needle) { return i }
            i += 1
        }
        return nil
    }
    static func findLast(_ needle: [UInt8], in hay: [UInt8], from: Int) -> Int? {
        var i = hay.count - needle.count
        while i >= from {
            if hay[i] == needle[0], hay[i..<(i + needle.count)].elementsEqual(needle) { return i }
            i -= 1
        }
        return nil
    }

    // MARK: Cross-reference data

    private func readXrefChain() throws {
        let tailStart = max(0, bytes.count - 1 << 20)
        guard let k = Self.findLast(Array("startxref".utf8), in: bytes, from: tailStart) else { throw PdfFailure("no startxref near the end of the file") }
        var lx = PdfLexer(bytes, at: k + 9)
        guard let first = try? lx.int() else { throw PdfFailure("startxref has no offset") }
        newestStartxref = first
        var offset: Int? = first
        var seen = Set<Int>(), firstSection = true
        while let off = offset {
            guard !seen.contains(off) else { throw PdfFailure("the cross-reference chain loops") }
            seen.insert(off)
            guard off > 0, off + headerOffset < bytes.count else { throw PdfFailure("a cross-reference offset (\(off)) is outside the file") }
            var lex = PdfLexer(bytes, at: off + headerOffset)
            lex.skipSpace()
            let tr: [String: PdfObj]
            if bytes[lex.pos...].starts(with: Array("xref".utf8)) {
                lex.pos += 4
                tr = try readTable(&lex)
                if firstSection { newestIsStream = false }
                if let xs = tr["XRefStm"]?.intValue {   // a hybrid file: the stream's entries rank below the table's
                    guard xs > 0, xs + headerOffset < bytes.count else { throw PdfFailure("bad /XRefStm") }
                    _ = try readStream(at: xs + headerOffset)
                }
            } else {
                tr = try readStream(at: off + headerOffset)
                if firstSection { newestIsStream = true }
            }
            trailers.append(tr)
            firstSection = false
            offset = tr["Prev"]?.intValue
        }
    }

    private func put(_ n: Int, _ e: PdfEntry) { if entries[n] == nil { entries[n] = e } }

    private func readTable(_ lex: inout PdfLexer) throws -> [String: PdfObj] {
        while true {
            lex.skipSpace()
            if lex.peekWord() == "trailer" { _ = lex.word(); break }
            let start = try lex.int(), count = try lex.int()
            guard count >= 0, count < 10_000_000 else { throw PdfFailure("bad cross-reference subsection") }
            for i in 0..<count {
                let o = try lex.int(), g = try lex.int()
                let t = lex.word()
                switch t {
                case "n": put(start + i, .offset(o + headerOffset, gen: g))
                case "f": put(start + i, .free)
                default: throw PdfFailure("a cross-reference entry is damaged (byte \(lex.pos))")
                }
            }
        }
        guard case .dict(let d, _) = try lex.object() else { throw PdfFailure("the trailer isn't a dictionary") }
        return d
    }

    private func readStream(at off: Int) throws -> [String: PdfObj] {
        let (num, obj) = try indirect(at: off, expect: nil)
        _ = num
        guard case .stream(let d, _, let raw) = obj, d["Type"]?.nameValue == "XRef" else { throw PdfFailure("the cross-reference data at byte \(off) can't be read") }
        let data = try decode(d, raw)
        guard let w = d["W"]?.array?.compactMap(\.intValue), w.count == 3, w.allSatisfy({ $0 >= 0 && $0 <= 8 }) else { throw PdfFailure("a cross-reference stream has no usable /W") }
        let size = d["Size"]?.intValue ?? 0
        let index = d["Index"]?.array?.compactMap(\.intValue) ?? [0, size]
        guard index.count % 2 == 0 else { throw PdfFailure("bad /Index in a cross-reference stream") }
        let rec = w.reduce(0, +)
        guard rec > 0 else { throw PdfFailure("empty /W") }
        let a = [UInt8](data)
        var p = 0
        func field(_ n: Int) -> Int { var v = 0; for _ in 0..<n { v = v << 8 | Int(a[p]); p += 1 }; return v }
        for s in stride(from: 0, to: index.count, by: 2) {
            for i in 0..<index[s + 1] {
                guard p + rec <= a.count else { throw PdfFailure("a cross-reference stream is short") }
                let t = w[0] == 0 ? 1 : field(w[0])
                let f2 = field(w[1]), f3 = field(w[2])
                switch t {
                case 0: put(index[s] + i, .free)
                case 1: put(index[s] + i, .offset(f2 + headerOffset, gen: f3))
                case 2: put(index[s] + i, .inStream(f2, index: f3))
                default: break
                }
            }
        }
        return d
    }

    // MARK: Objects

    /// Parses `n g obj … endobj` at `off`.
    func indirect(at off: Int, expect: Int?) throws -> (Int, PdfObj) {
        guard off >= 0, off < bytes.count else { throw PdfFailure("an object offset (\(off)) is outside the file") }
        var lex = PdfLexer(bytes, at: off)
        guard let n = try? lex.int(), (try? lex.int()) != nil, lex.word() == "obj" else { throw PdfFailure("no object at byte \(off): the cross-reference data doesn't match the file") }
        if let e = expect, e != n { throw PdfFailure("object \(e) isn't at byte \(off) (found \(n)): the cross-reference data doesn't match the file") }
        let value = try lex.object()
        guard case .dict(let d, let order) = value else { return (n, value) }
        let save = lex.pos
        if lex.peekWord() == "stream" {
            _ = lex.word()
            if lex.pos < bytes.count, bytes[lex.pos] == 13 { lex.pos += 1 }
            if lex.pos < bytes.count, bytes[lex.pos] == 10 { lex.pos += 1 }
            let start = lex.pos
            var length: Int?
            if let l = d["Length"] {
                if let i = l.intValue { length = i }
                else if let r = l.refNumber, r != n, let v = try? object(r)?.intValue { length = v }
            }
            var end: Int
            if let l = length, l >= 0, start + l <= bytes.count {
                var chk = PdfLexer(bytes, at: start + l)
                if chk.peekWord() == "endstream" { end = start + l } else { length = nil; end = start }
            } else { length = nil; end = start }
            if length == nil {
                guard let e = Self.find(Array("endstream".utf8), in: bytes, from: start, to: bytes.count) else { throw PdfFailure("a stream never ends (object \(n))") }
                end = e
                if end > start, bytes[end - 1] == 10 { end -= 1 }
                if end > start, bytes[end - 1] == 13 { end -= 1 }
            }
            return (n, .stream(d, order: order, Data(bytes[start..<end])))
        }
        lex.pos = save
        return (n, value)
    }

    func object(_ n: Int) throws -> PdfObj? {
        if let c = cache[n] { return c }
        guard let e = entries[n] else { return nil }
        let v: PdfObj
        switch e {
        case .free: return nil
        case .offset(let off, _):
            v = try indirect(at: off, expect: n).1
        case .inStream(let stm, _):
            v = try objStm(stm).objects[n] ?? .null
        }
        cache[n] = v
        return v
    }

    func gen(_ n: Int) -> Int { if case .offset(_, let g)? = entries[n] { return g }; return 0 }

    /// Follows a reference; a direct value is itself.
    func resolve(_ o: PdfObj?) throws -> PdfObj? {
        var cur = o, hops = 0
        while case .ref(let n, _)? = cur {
            hops += 1; if hops > 16 { throw PdfFailure("a reference chain loops") }
            cur = try object(n)
        }
        return cur
    }
    func dict(_ o: PdfObj?) throws -> [String: PdfObj]? { try resolve(o)?.dict }

    private func objStm(_ n: Int) throws -> (objects: [Int: PdfObj], order: [Int]) {
        if let c = objStms[n] { return c }
        guard case .stream(let d, _, let raw)? = try object(n), d["Type"]?.nameValue == "ObjStm",
              let count = d["N"]?.intValue, let first = d["First"]?.intValue else { throw PdfFailure("object stream \(n) can't be read") }
        let a = [UInt8](try decode(d, raw))
        var lex = PdfLexer(a)
        var pairs: [(Int, Int)] = []
        for _ in 0..<count { pairs.append((try lex.int(), try lex.int())) }
        var objs: [Int: PdfObj] = [:]
        for (num, off) in pairs {
            var l = PdfLexer(a, at: first + off)
            objs[num] = try l.object()
        }
        let r = (objs, pairs.map(\.0))
        objStms[n] = r
        return r
    }

    /// A stream's data with its filters undone (Flate, with PNG predictors, only).
    func decode(_ d: [String: PdfObj], _ raw: Data) throws -> Data {
        var filters: [String] = []
        let f = try resolve(d["Filter"])
        if let n = f?.nameValue { filters = [n] } else if let a = f?.array { filters = a.compactMap { $0.nameValue } }
        var parms: [PdfObj?] = []
        let dp = try resolve(d["DecodeParms"])
        if let a = dp?.array { parms = a } else if dp != nil { parms = [dp] }
        var data = raw
        for (i, name) in filters.enumerated() {
            guard name == "FlateDecode" || name == "Fl" else { throw PdfFailure("a stream uses the \(name) filter, which Duo doesn't read") }
            data = try PdfFilters.inflate(data)
            if i < parms.count, let p = try dict(parms[i]), let pred = p["Predictor"]?.intValue, pred > 1 {
                guard pred >= 10 else { throw PdfFailure("TIFF predictor \(pred) isn't supported") }
                data = try PdfFilters.unpredict(data, columns: p["Columns"]?.intValue ?? 1, colors: p["Colors"]?.intValue ?? 1, bpc: p["BitsPerComponent"]?.intValue ?? 8)
            }
        }
        return data
    }

    // MARK: Pages

    struct Page { var number: Int; var dict: [String: PdfObj] }

    func pages() throws -> [Page] {
        guard let root = try dict(trailer["Root"]), let top = root["Pages"] else { throw PdfFailure("the document has no page tree") }
        var out: [Page] = [], seen = Set<Int>()
        func walk(_ ref: PdfObj) throws {
            guard let n = ref.refNumber, seen.insert(n).inserted, let d = try object(n)?.dict else { return }
            if let kids = try resolve(d["Kids"])?.array, d["Type"]?.nameValue != "Page" {
                for k in kids { try walk(k) }
            } else { out.append(Page(number: n, dict: d)) }
        }
        try walk(top)
        return out
    }

    /// Why the file can't be written to, or nil.
    func writeRefusal() throws -> String? {
        if trailers.contains(where: { $0["Encrypt"] != nil }) { return "it is encrypted: Duo doesn't write comments into an encrypted PDF" }
        if let root = try dict(trailer["Root"]), let perms = try dict(root["Perms"]), let sig = try dict(perms["DocMDP"]),
           let refs = try resolve(sig["Reference"])?.array {
            for r in refs {
                guard let rd = try dict(r), rd["TransformMethod"]?.nameValue == "DocMDP" else { continue }
                let p = try dict(rd["TransformParams"])?["P"]?.intValue ?? 2
                if p < 3 { return "it is certified so that no changes are allowed (DocMDP P \(p)): a comment would invalidate the certification" }
            }
        }
        return nil
    }
}
