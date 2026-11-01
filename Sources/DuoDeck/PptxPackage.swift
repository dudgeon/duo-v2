import DuoSearch
import Foundation

/// A pptx held in memory so parts can be read, changed, added and removed, then written again with
/// the zip writer (fixed times, sorted names: the same package gives the same bytes). Used by the
/// template work: inventory reads it, build and import change it.
public struct PptxPackage {
    public struct Rel: Equatable {
        public var id: String
        public var type: String      // the last path component of the relationship type, e.g. "slideLayout"
        public var target: String    // as written
        public var external: Bool
        public var fullType: String
    }

    public var parts: [String: Data] = [:]

    public init() {}

    public init(_ url: URL) throws {
        let zip = try Pptx.Zip(url)
        for name in zip.entries.keys where !name.hasSuffix("/") {
            if let d = try zip.read(name) { parts[name] = d }
        }
        guard parts["[Content_Types].xml"] != nil else { throw Deck.Failure(description: "\(url.lastPathComponent) is not a PowerPoint file") }
    }

    public func xml(_ name: String) -> XNode? { parts[name].flatMap(XNode.parse) }
    public mutating func set(_ name: String, _ root: XNode) { parts[name] = root.document() }
    public func string(_ name: String) -> String? { parts[name].map { String(decoding: $0, as: UTF8.self) } }

    static func relsPart(of part: String) -> String {
        let dir = (part as NSString).deletingLastPathComponent
        let file = (part as NSString).lastPathComponent
        return (dir.isEmpty ? "" : dir + "/") + "_rels/" + file + ".rels"
    }

    public func rels(of part: String) -> [Rel] {
        guard let r = xml(Self.relsPart(of: part)) else { return [] }
        return r.kids("Relationship").compactMap { n in
            guard let id = n["Id"], let t = n["Type"], let target = n["Target"] else { return nil }
            return Rel(id: id, type: String(t.split(separator: "/").last ?? ""), target: target, external: n["TargetMode"] == "External", fullType: t)
        }
    }

    public mutating func setRels(of part: String, _ rels: [Rel]) {
        let root = XNode("Relationships", ["xmlns": "http://schemas.openxmlformats.org/package/2006/relationships"])
        for r in rels {
            var a = ["Id": r.id, "Type": r.fullType, "Target": r.target]
            if r.external { a["TargetMode"] = "External" }
            root.children.append(XNode("Relationship", a))
        }
        set(Self.relsPart(of: part), root)
    }

    /// The part a relationship of `part` points at.
    public static func resolve(_ target: String, from part: String) -> String {
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        var parts: [Substring] = []
        for p in ((part as NSString).deletingLastPathComponent + "/" + target).split(separator: "/") {
            if p == ".." { _ = parts.popLast() } else if p != "." { parts.append(p) }
        }
        return parts.joined(separator: "/")
    }

    /// The path from `part`'s folder to `target`, as a relationship writes it.
    public static func relative(_ target: String, from part: String) -> String {
        let a = (part as NSString).deletingLastPathComponent.split(separator: "/").map(String.init)
        let b = target.split(separator: "/").map(String.init)
        var i = 0
        while i < a.count, i < b.count - 1, a[i] == b[i] { i += 1 }
        return (Array(repeating: "..", count: a.count - i) + b[i...]).joined(separator: "/")
    }

    public func target(of rel: Rel, from part: String) -> String { Self.resolve(rel.target, from: part) }

    public func related(_ part: String, type: String) -> [String] {
        rels(of: part).filter { $0.type == type && !$0.external }.map { target(of: $0, from: part) }
    }

    /// Drops every part the root relationships don't reach, and the content-type overrides of parts
    /// that are gone.
    public mutating func collectGarbage() {
        var seen = Set<String>(["[Content_Types].xml", "_rels/.rels"])
        var queue = ["_rels/.rels"]
        var parts_: [String] = []
        while let rp = queue.popLast() {
            let owner: String
            if rp == "_rels/.rels" { owner = "" } else {
                let dir = ((rp as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
                owner = (dir.isEmpty ? "" : dir + "/") + String((rp as NSString).lastPathComponent.dropLast(5))
            }
            guard let r = xml(rp) else { continue }
            for rel in r.kids("Relationship") where rel["TargetMode"] != "External" {
                guard let t = rel["Target"] else { continue }
                let p = owner.isEmpty ? Self.resolve("/" + t.trimmingCharacters(in: CharacterSet(charactersIn: "/")), from: "") : Self.resolve(t, from: owner)
                guard parts[p] != nil, seen.insert(p).inserted else { continue }
                parts_.append(p)
                let rr = Self.relsPart(of: p)
                if parts[rr] != nil, seen.insert(rr).inserted { queue.append(rr) }
            }
        }
        for name in parts.keys where !seen.contains(name) { parts[name] = nil }
        if let ct = xml("[Content_Types].xml") {
            ct.children.removeAll { $0.local == "Override" && parts[String(($0["PartName"] ?? "").dropFirst())] == nil }
            set("[Content_Types].xml", ct)
        }
    }

    public mutating func addOverride(_ part: String, _ type: String) {
        guard let ct = xml("[Content_Types].xml") else { return }
        ct.children.removeAll { $0.local == "Override" && $0["PartName"] == "/" + part }
        ct.children.append(XNode("Override", ["PartName": "/" + part, "ContentType": type]))
        set("[Content_Types].xml", ct)
    }

    public mutating func addDefault(_ ext: String, _ type: String) {
        guard let ct = xml("[Content_Types].xml") else { return }
        if ct.kids("Default").contains(where: { $0["Extension"]?.lowercased() == ext.lowercased() }) { return }
        ct.children.insert(XNode("Default", ["Extension": ext, "ContentType": type]), at: 0)
        set("[Content_Types].xml", ct)
    }

    public func contentType(ofExtension ext: String) -> String? {
        xml("[Content_Types].xml")?.kids("Default").first { $0["Extension"]?.lowercased() == ext.lowercased() }?["ContentType"]
    }

    /// Bytes: `[Content_Types].xml` first, then the root rels, then everything else by name.
    public func write() -> Data {
        var out = ZipWriter()
        let first = ["[Content_Types].xml", "_rels/.rels"]
        for n in first { if let d = parts[n] { out.add(n, d) } }
        for n in parts.keys.sorted() where !first.contains(n) { out.add(n, parts[n]!) }
        return out.finish()
    }
}
