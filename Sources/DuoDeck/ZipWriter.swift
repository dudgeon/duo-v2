import Compression
import Foundation

/// Writes a zip (Duo Decks, DL-270). Same entries in the same order give the same bytes: DOS time
/// is fixed at 1980-01-01 00:00, nothing reads the clock, and deflate (Compression's ZLIB, which is
/// raw DEFLATE) is deterministic. No zip64: a deck is far below 4 GB.
struct ZipWriter {
    private var body = Data()
    private var central = Data()
    private var count = 0

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in data { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    private static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        var out = Data(count: data.count + 1024)
        let cap = out.count
        let n = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, cap,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n > 0, n < data.count else { return nil }
        return out.prefix(n)
    }

    private static func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
    private static func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * UInt32($0))) & 0xFF) } }

    mutating func add(_ name: String, _ data: Data) {
        let crc = Self.crc32(data)
        let packed = Self.deflate(data)
        let method = packed == nil ? 0 : 8
        let payload = packed ?? data
        let nameBytes = Array(name.utf8)
        let dosTime = 0, dosDate = (0 << 9) | (1 << 5) | 1   // 1980-01-01 00:00:00
        var local = Data()
        local.append(contentsOf: Self.le32(0x0403_4B50))
        local.append(contentsOf: Self.le16(20) + Self.le16(0x0800) + Self.le16(method) + Self.le16(dosTime) + Self.le16(dosDate))
        local.append(contentsOf: Self.le32(crc) + Self.le32(UInt32(payload.count)) + Self.le32(UInt32(data.count)))
        local.append(contentsOf: Self.le16(nameBytes.count) + Self.le16(0))
        local.append(contentsOf: nameBytes)
        let offset = body.count
        body.append(local)
        body.append(payload)
        var c = Data()
        c.append(contentsOf: Self.le32(0x0201_4B50))
        c.append(contentsOf: Self.le16(20) + Self.le16(20) + Self.le16(0x0800) + Self.le16(method) + Self.le16(dosTime) + Self.le16(dosDate))
        c.append(contentsOf: Self.le32(crc) + Self.le32(UInt32(payload.count)) + Self.le32(UInt32(data.count)))
        c.append(contentsOf: Self.le16(nameBytes.count) + Self.le16(0) + Self.le16(0) + Self.le16(0) + Self.le16(0))
        c.append(contentsOf: Self.le32(0) + Self.le32(UInt32(offset)))
        c.append(contentsOf: nameBytes)
        central.append(c)
        count += 1
    }

    func finish() -> Data {
        var out = body
        let start = out.count
        out.append(central)
        out.append(contentsOf: Self.le32(0x0605_4B50) + Self.le16(0) + Self.le16(0) + Self.le16(count) + Self.le16(count))
        out.append(contentsOf: Self.le32(UInt32(central.count)) + Self.le32(UInt32(start)) + Self.le16(0))
        return out
    }
}
