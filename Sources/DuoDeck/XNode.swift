import Foundation

/// A small editable XML tree for the template work (build, import): qualified names kept, attributes
/// written in sorted order (xmlns first), so the same edits give the same bytes. `Pptx.Node` in
/// DuoSearch is read-only and drops prefixes; this one can be changed and written back.
public final class XNode {
    public var name: String
    public var attrs: [String: String]
    public var children: [XNode] = []
    public var text = ""

    public init(_ name: String, _ attrs: [String: String] = [:], _ children: [XNode] = [], text: String = "") {
        self.name = name; self.attrs = attrs; self.children = children; self.text = text
    }

    /// The name without its prefix.
    public var local: String { name.split(separator: ":").last.map(String.init) ?? name }
    public subscript(_ k: String) -> String? {
        get { attrs[k] }
        set { attrs[k] = newValue }
    }

    /// First child whose local name is `local`.
    public func child(_ local: String) -> XNode? { children.first { $0.local == local } }
    public func kids(_ local: String) -> [XNode] { children.filter { $0.local == local } }
    /// First descendant (depth first) with this local name.
    public func find(_ local: String) -> XNode? {
        for c in children { if c.local == local { return c }; if let d = c.find(local) { return d } }
        return nil
    }
    public func findAll(_ local: String) -> [XNode] {
        children.flatMap { ($0.local == local ? [$0] : []) + $0.findAll(local) }
    }
    public func copy() -> XNode { XNode(name, attrs, children.map { $0.copy() }, text: text) }

    public func removeChildren(_ local: String) { children.removeAll { $0.local == local } }

    // MARK: parse

    private final class Builder: NSObject, XMLParserDelegate {
        var stack: [XNode] = [XNode("#doc")]
        func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            let n = XNode(name, attributes)
            stack.last?.children.append(n)
            stack.append(n)
        }
        func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { _ = stack.popLast() }
        func parser(_ p: XMLParser, foundCharacters s: String) { stack.last?.text += s }
    }

    public static func parse(_ data: Data) -> XNode? {
        let b = Builder(), p = XMLParser(data: data)
        p.delegate = b
        p.shouldProcessNamespaces = false
        p.shouldResolveExternalEntities = false   // a deck is untrusted input
        guard p.parse() else { return nil }
        return b.stack.first?.children.first
    }

    // MARK: write

    static func esc(_ s: String, attr: Bool) -> String {
        var o = s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        if attr { o = o.replacingOccurrences(of: "\"", with: "&quot;") }
        return o
    }

    public func xml() -> String {
        var s = "<\(name)"
        for k in attrs.keys.sorted(by: { a, b in
            let ax = a.hasPrefix("xmlns"), bx = b.hasPrefix("xmlns")
            return ax != bx ? ax : a < b
        }) { s += " \(k)=\"\(Self.esc(attrs[k]!, attr: true))\"" }
        if children.isEmpty && text.isEmpty { return s + "/>" }
        s += ">"
        if children.isEmpty { s += Self.esc(text, attr: false) } else { s += children.map { $0.xml() }.joined() }
        return s + "</\(name)>"
    }

    public func document() -> Data { Data(("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" + xml()).utf8) }
}
