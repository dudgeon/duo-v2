import Foundation

/// BERT uncased WordPiece, matching Hugging Face `tokenizers` for bge-small: BertNormalizer
/// (clean text, CJK spacing, lowercase, strip accents), BertPreTokenizer (whitespace and
/// punctuation), WordPiece with `##`, 100-character words, [CLS] … [SEP].
struct WordPiece {
    let vocab: [String: Int32]
    let unk: Int32, cls: Int32, sep: Int32

    init(vocabFile: URL) throws {
        var v: [String: Int32] = [:]
        for (i, line) in try String(contentsOf: vocabFile, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if !line.isEmpty { v[String(line)] = Int32(i) }
        }
        vocab = v
        unk = v["[UNK]"]!; cls = v["[CLS]"]!; sep = v["[SEP]"]!
    }

    static func isPunct(_ s: Unicode.Scalar) -> Bool {
        let c = s.value
        if (33...47).contains(c) || (58...64).contains(c) || (91...96).contains(c) || (123...126).contains(c) { return true }
        switch s.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation: return true
        default: return false
        }
    }

    static func isCJK(_ s: Unicode.Scalar) -> Bool {
        let c = s.value
        return (0x4E00...0x9FFF).contains(c) || (0x3400...0x4DBF).contains(c) || (0x20000...0x2A6DF).contains(c)
            || (0x2A700...0x2B73F).contains(c) || (0x2B740...0x2B81F).contains(c) || (0x2B820...0x2CEAF).contains(c)
            || (0xF900...0xFAFF).contains(c) || (0x2F800...0x2FA1F).contains(c)
    }

    static func isWhitespace(_ s: Unicode.Scalar) -> Bool {
        s == " " || s == "\t" || s == "\n" || s == "\r" || s.properties.generalCategory == .spaceSeparator
    }

    static func isControl(_ s: Unicode.Scalar) -> Bool {
        if s == "\t" || s == "\n" || s == "\r" { return false }
        switch s.properties.generalCategory {
        case .control, .format, .surrogate, .privateUse, .unassigned: return true
        default: return false
        }
    }

    func normalize(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for s in text.unicodeScalars {
            if s.value == 0 || s.value == 0xFFFD || Self.isControl(s) { continue }
            if Self.isWhitespace(s) { out.append(" "); continue }
            if Self.isCJK(s) { out.append(" "); out.append(s); out.append(" "); continue }
            out.append(s)
        }
        // lowercase, then strip accents (NFD, drop combining marks), as BertNormalizer does.
        let lowered = String(out).lowercased()
        let nfd = lowered.decomposedStringWithCanonicalMapping
        return String(String.UnicodeScalarView(nfd.unicodeScalars.filter { $0.properties.generalCategory != .nonspacingMark }))
    }

    func words(_ text: String) -> [String] {
        var words: [String] = []
        var cur = String.UnicodeScalarView()
        func flush() { if !cur.isEmpty { words.append(String(cur)); cur = String.UnicodeScalarView() } }
        for s in normalize(text).unicodeScalars {
            if Self.isWhitespace(s) { flush() }
            else if Self.isPunct(s) { flush(); words.append(String(s)) }
            else { cur.append(s) }
        }
        flush()
        return words
    }

    func pieces(_ word: String) -> [Int32] {
        let chars = Array(word.unicodeScalars)
        if chars.count > 100 { return [unk] }
        var out: [Int32] = []
        var start = 0
        while start < chars.count {
            var end = chars.count
            var found: Int32?
            while start < end {
                var sub = String(String.UnicodeScalarView(chars[start..<end]))
                if start > 0 { sub = "##" + sub }
                if let id = vocab[sub] { found = id; break }
                end -= 1
            }
            guard let id = found else { return [unk] }
            out.append(id)
            start = end
        }
        return out
    }

    /// [CLS] tokens [SEP], truncated to `maxLength` like the POC's tokenizer.
    func encode(_ text: String, maxLength: Int = 512) -> [Int32] {
        var ids = words(text).flatMap(pieces)
        if ids.count > maxLength - 2 { ids = Array(ids.prefix(maxLength - 2)) }
        return [cls] + ids + [sep]
    }
}
