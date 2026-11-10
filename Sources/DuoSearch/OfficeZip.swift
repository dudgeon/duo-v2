import Foundation

/// Replaces or adds parts of a zip package and leaves every other entry's bytes exactly as they were (DL-331: Duo writes
/// comments into a Word or PowerPoint file and nothing else). The unchanged entries are copied raw, local header and
/// compressed data together, so they stay byte-identical; the changed and added ones are written stored (no compression),
/// and the central directory and its end record are rebuilt. No zip64, no encryption (the reader's limits).
public enum OfficeZip {
    public struct Failure: Error, CustomStringConvertible { public let description: String }

    struct Record {
        var name: String
        var central: Data       // the central directory record, as read
        var offset: Int         // the local header's offset
        var span: Range<Int> = 0..<0   // the raw local entry: header, data and any data descriptor
    }

    /// CRC-32 (zip's).
    public static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in d { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
    private static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    /// Each entry's raw bytes (local header, data, descriptor) by name: what the checks compare to prove an untouched part stayed untouched.
    public static func rawParts(_ original: Data) throws -> [String: Data] {
        let probe = try patch(original, changes: [:])
        _ = probe
        let d = [UInt8](original)
        func u16(_ i: Int) -> Int { Int(d[i]) | Int(d[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        var eocd = -1
        var i = d.count - 22
        while i >= max(0, d.count - 65_557) { if u32(i) == 0x0605_4B50 { eocd = i; break }; i -= 1 }
        guard eocd >= 0 else { throw Failure(description: "not a zip file") }
        let count = u16(eocd + 10), cdStart = u32(eocd + 16)
        var entries: [(String, Int)] = []
        var p = cdStart
        for _ in 0..<count {
            let n = u16(p + 28), m = u16(p + 30), k = u16(p + 32)
            entries.append((String(decoding: d[(p + 46)..<(p + 46 + n)], as: UTF8.self), u32(p + 42)))
            p += 46 + n + m + k
        }
        let sorted = entries.sorted { $0.1 < $1.1 }
        var out: [String: Data] = [:]
        for (k, e) in sorted.enumerated() { out[e.0] = original.subdata(in: e.1..<(k + 1 < sorted.count ? sorted[k + 1].1 : cdStart)) }
        return out
    }

    /// `original` with `changes` (part name -> new bytes) applied; a part not in the package is added at the end.
    public static func patch(_ original: Data, changes: [String: Data]) throws -> Data {
        let d = [UInt8](original)
        func u16(_ i: Int) -> Int { Int(d[i]) | Int(d[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        var eocd = -1
        var i = d.count - 22
        while i >= max(0, d.count - 65_557) { if u32(i) == 0x0605_4B50 { eocd = i; break }; i -= 1 }
        guard eocd >= 0 else { throw Failure(description: "not a zip file") }
        let count = u16(eocd + 10), cdStart = u32(eocd + 16)
        var records: [Record] = []
        var p = cdStart
        for _ in 0..<count {
            guard p + 46 <= d.count, u32(p) == 0x0201_4B50 else { throw Failure(description: "damaged zip directory") }
            let n = u16(p + 28), m = u16(p + 30), k = u16(p + 32)
            guard p + 46 + n + m + k <= d.count else { throw Failure(description: "damaged zip directory") }
            let name = String(decoding: d[(p + 46)..<(p + 46 + n)], as: UTF8.self)
            records.append(Record(name: name, central: Data(d[p..<(p + 46 + n + m + k)]), offset: u32(p + 42)))
            p += 46 + n + m + k
        }
        // Each entry's raw span runs to the next entry's offset (or the directory), so a data descriptor goes with it.
        let sorted = records.indices.sorted { records[$0].offset < records[$1].offset }
        for (pos, r) in sorted.enumerated() {
            let end = pos + 1 < sorted.count ? records[sorted[pos + 1]].offset : cdStart
            guard records[r].offset < end, end <= d.count else { throw Failure(description: "damaged zip directory") }
            records[r].span = records[r].offset..<end
        }
        var out = Data()
        var newCentral: [Data] = []
        var done = Set<String>()
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16((v >> 16) & 0xFFFF) }
        func put(_ name: String, _ bytes: Data, time: Int, date: Int) -> Data {
            let nm = Array(name.utf8), off = out.count, crc = Int(crc32(bytes))
            out.append(contentsOf: le32(0x0403_4B50) + le16(20) + le16(0x0800) + le16(0) + le16(time) + le16(date) + le32(crc) + le32(bytes.count) + le32(bytes.count) + le16(nm.count) + le16(0))
            out.append(contentsOf: nm); out.append(bytes)
            return Data(le32(0x0201_4B50) + le16(20) + le16(20) + le16(0x0800) + le16(0) + le16(time) + le16(date) + le32(crc) + le32(bytes.count) + le32(bytes.count)
                        + le16(nm.count) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(off) + nm)
        }
        for r in records {
            if let new = changes[r.name] {
                let c = [UInt8](r.central)
                let time = Int(c[12]) | Int(c[13]) << 8, date = Int(c[14]) | Int(c[15]) << 8
                newCentral.append(put(r.name, new, time: time, date: date))
                done.insert(r.name)
            } else {
                let off = out.count
                out.append(original.subdata(in: r.span))
                var c = [UInt8](r.central)
                c.replaceSubrange(42..<46, with: le32(off))
                newCentral.append(Data(c))
            }
        }
        for (name, bytes) in changes.sorted(by: { $0.key < $1.key }) where !done.contains(name) {
            newCentral.append(put(name, bytes, time: 0, date: 0x21))   // 1980-01-01, the zip epoch
        }
        let cdOut = out.count
        for c in newCentral { out.append(c) }
        let size = out.count - cdOut
        out.append(contentsOf: le32(0x0605_4B50) + le16(0) + le16(0) + le16(newCentral.count) + le16(newCentral.count) + le32(size) + le32(cdOut) + le16(0))
        return out
    }
}
