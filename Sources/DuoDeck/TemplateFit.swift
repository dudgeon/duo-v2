import CoreText
import Foundation

/// The measured fit (Q-379, DL-292): a slot's text set in the template's font and size, against the
/// placeholder's box minus its insets, counting the lines the text takes and the lines the box holds.
/// CoreText does the setting. A font that isn't installed here falls back to a metric-similar system
/// font, and the message says so. PowerPoint's own shrink-on-overflow (`normAutofit`) is not applied:
/// Google Slides and an exported file show the nominal size.
public enum TemplateFit {
    public struct Measure: Equatable, Sendable {
        public var lines: Int
        /// The box's capacity in lines at this size.
        public var holds: Int
        public var size: Double
        /// "Inter isn't installed here; measured in Helvetica Neue" when the template's font fell back.
        public var fontNote: String?
    }

    /// The font that stands in for `name`: itself when installed, else a system font of similar
    /// metrics (a serif, a monospace or a sans, by the name).
    static func font(_ name: String, size: Double) -> (ct: CTFont, note: String?) {
        let want = name.lowercased()
        let f = CTFontCreateWithName(name as CFString, CGFloat(size), nil)
        let fam = (CTFontCopyFamilyName(f) as String).lowercased()
        let full = (CTFontCopyFullName(f) as String).lowercased()
        let ps = (CTFontCopyPostScriptName(f) as String).lowercased()
        if fam == want || full == want || ps == want.replacingOccurrences(of: " ", with: "") {
            return (f, nil)
        }
        let serif = ["serif", "garamond", "georgia", "times", "lora", "merriweather", "playfair", "baskerville", "cambria", "caladea", "tinos", "spectral", "crimson", "cormorant", "bitter", "vollkorn", "palatino"]
        let mono = ["mono", "courier", "consolas", "menlo", "code", "cousine"]
        let stand = mono.contains { want.contains($0) } ? "Menlo" : serif.contains { want.contains($0) } && !want.contains("sans") ? "Georgia" : "Helvetica Neue"
        // Inter sets about 7% wider than Helvetica Neue: lineCount measures it at a size that makes up for it.
        let widen = want.hasPrefix("inter") ? 1.07 : 1.0
        let s = CTFontCreateWithName(stand as CFString, CGFloat(size), nil)
        return (s, "\(name) isn't installed here; measured in \(CTFontCopyFamilyName(s) as String)" + (widen > 1 ? ", widened 7% for \(name)" : ""))
    }

    /// How many lines `text` takes in `width` pt.
    public static func lineCount(_ text: String, font name: String, size: Double, width: Double) -> (lines: Int, note: String?) {
        var (f, note) = font(name, size: size)
        guard width > 1, !text.isEmpty else { return (text.isEmpty ? 0 : 99, note) }
        if note?.contains("widened 7%") == true { f = CTFontCreateCopyWithAttributes(f, CGFloat(size * 1.07), nil, nil) }
        let attrs = [kCTFontAttributeName: f] as CFDictionary
        let astr = CFAttributedStringCreate(nil, text as CFString, attrs)!
        let setter = CTFramesetterCreateWithAttributedString(astr)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 100_000), transform: nil), nil)
        return (CFArrayGetCount(CTFrameGetLines(frame)), note)
    }

    static func lineHeight(font name: String, size: Double, spacing: Double?) -> Double {
        let (f, _) = font(name, size: size)
        let h = Double(CTFontGetAscent(f) + CTFontGetDescent(f) + CTFontGetLeading(f))
        return h * (spacing ?? 1.0)
    }

    /// The text of `n` characters made of "Sample text" repeated (what the specimen and the limit
    /// check both use), cut to exactly `n`.
    public static func sample(_ n: Int, kind: String = "text") -> String {
        guard n > 0 else { return "" }
        let unit = kind == "number" ? "1234567890" : "Sample text "
        var s = ""
        while s.count < n { s += unit }
        return String(s.prefix(n)).trimmingCharacters(in: .whitespaces)
    }

    /// Lines `text` takes in the placeholder and the lines the box holds. nil when the placeholder
    /// has no box or no font size (nothing to measure against).
    public static func measure(text: [String], in ph: TemplateInventory.Placeholder, bulleted: Bool) -> Measure? {
        guard let box = ph.box, let size = ph.fontSize, let face = ph.font else { return nil }
        let width = box.w - ph.insets[0] - ph.insets[2] - (bulleted ? max(ph.indent, 14.4) : ph.indent)
        let height = box.h - ph.insets[1] - ph.insets[3]
        var total = 0
        var note: String?
        for para in text {
            let r = lineCount(para, font: face, size: size, width: width)
            total += max(r.lines, 1); note = r.note
        }
        let lh = lineHeight(font: face, size: size, spacing: ph.lineSpacing)
        let gaps = Double(max(text.count - 1, 0)) * (ph.spaceBefore ?? 0)
        let holds = Int(max(0, ((height - gaps) / lh + 0.02).rounded(.down)))
        return Measure(lines: total, holds: max(holds, 1), size: size, fontNote: note)
    }

    /// `does not fit: 2 lines at 18 pt; the box holds 1`, plus the font note.
    public static func overflow(_ m: Measure) -> String? {
        guard m.lines > m.holds else { return nil }
        return "does not fit: \(m.lines) line\(m.lines == 1 ? "" : "s") at \(sizeText(m.size)) pt; the box holds \(m.holds)" + (m.fontNote.map { " (\($0))" } ?? "")
    }

    static func sizeText(_ s: Double) -> String { s == s.rounded() ? String(Int(s)) : String(format: "%.1f", s) }

    /// The most characters (or points of that many characters) a placeholder holds, by the same
    /// measure; nil when there is nothing to measure against.
    public static func largestFit(kind: String, in ph: TemplateInventory.Placeholder, bulleted: Bool, paragraphs: Int = 1, upTo cap: Int = 400) -> Int? {
        func ok(_ k: Int) -> Bool? {
            measure(text: Array(repeating: sample(k, kind: kind), count: paragraphs), in: ph, bulleted: bulleted).map { $0.lines <= $0.holds }
        }
        guard ok(1) == true else { return ok(1) == nil ? nil : 0 }
        var lo = 1, hi = cap
        while lo < hi { let mid = (lo + hi + 1) / 2; if ok(mid) == true { lo = mid } else { hi = mid - 1 } }
        return lo
    }

    /// For a limit in the definition: nil when `max` characters fit, else the message with the
    /// largest count that does.
    public static func limitTooHigh(max n: Int, kind: String, in ph: TemplateInventory.Placeholder, bulleted: Bool, paragraphs: Int = 1) -> String? {
        func fits(_ k: Int) -> Measure? {
            guard let m = measure(text: Array(repeating: sample(k, kind: kind), count: paragraphs), in: ph, bulleted: bulleted) else { return nil }
            return m
        }
        guard let m = fits(n), m.lines > m.holds else { return nil }
        var lo = 1, hi = n   // fits(lo) is assumed; find the largest k with lines <= holds
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if let mm = fits(mid), mm.lines <= mm.holds { lo = mid } else { hi = mid - 1 }
        }
        let subject = paragraphs > 1 ? "\(paragraphs) points of \(n) characters" : "\(n) characters"
        return "limit too high: \(subject) at \(sizeText(m.size)) pt take \(m.lines) line\(m.lines == 1 ? "" : "s"); the box holds \(m.holds); largest that fits: \(lo)" + (m.fontNote.map { " (\($0))" } ?? "")
    }
}
