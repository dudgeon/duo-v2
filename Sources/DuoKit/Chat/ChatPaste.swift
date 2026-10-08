import AppKit
import Foundation
import UniformTypeIdentifiers

// ⌘V in the composer. Text pastes as before; a file copied in Finder becomes a file chip (as a drop
// does); an image goes through Claude Code's own image paste: Ctrl+V makes the TUI read the Mac's
// pasteboard and put `[Image #N]` in its prompt, and the composer shows a chip for that token. Duo
// writes no image file. On send the tokens travel inside the text (external editor), or stay in the
// TUI's prompt while the text is pasted after them (paste mode: images first, then the text, since
// a token can't be typed back where it was; the finding is logged by the session that owns records).

public enum ChatPaste {
    public static let tokenPattern = try! NSRegularExpression(pattern: #"\[Image #\d+\]"#)

    /// The `[Image #N]` tokens in a text, in order.
    public static func tokens(in s: String) -> [String] {
        let ns = s as NSString
        return tokenPattern.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    /// The token a Ctrl+V added: in the prompt now and not before.
    public static func newToken(before: String, after: String) -> String? {
        let had = Set(tokens(in: before))
        return tokens(in: after).first { !had.contains($0) }
    }

    // MARK: What the pasteboard holds

    public enum Route { case text, chip(URL), image(NSImage?) }

    static func fileURLs(_ pb: NSPasteboard) -> [URL] {
        (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    static func isImageFile(_ u: URL) -> Bool { UTType(filenameExtension: u.pathExtension)?.conforms(to: .image) == true }

    static func holdsImage(_ pb: NSPasteboard) -> Bool {
        pb.availableType(from: [.png, .tiff]) != nil || pb.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    /// Whether Edit › Paste is on: text, an image or a file.
    public static func canPaste(_ pb: NSPasteboard) -> Bool {
        pb.string(forType: .string) != nil || !fileURLs(pb).isEmpty || holdsImage(pb)
    }

    /// What ⌘V does, in the order it does it: files first (a Finder copy has a name as text too),
    /// then text, then an image that came with no text. Only the first image file takes Ctrl+V:
    /// Claude Code reads the pasteboard itself, so a second press would take the same one.
    public static func routes(_ pb: NSPasteboard) -> [Route] {
        let files = fileURLs(pb)
        if !files.isEmpty {
            var out: [Route] = [], image: NSImage?, took = false
            for u in files {
                if !took, isImageFile(u) { took = true; image = NSImage(contentsOf: u) } else { out.append(.chip(u)) }
            }
            return took ? out + [.image(image)] : out
        }
        if pb.string(forType: .string) != nil { return [.text] }
        if holdsImage(pb) { return [.image((pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.first)] }
        return []
    }

    // MARK: Sending with tokens

    public struct SendPlan: Equatable {
        /// Attached tokens whose chips were removed: deleted from the TUI's prompt.
        public var remove: [String]
        /// Attached tokens still in the composer: left in the prompt.
        public var keep: [String]
        /// The text to paste after them: the composer's, with every attached token taken out.
        public var paste: String
        public init(remove: [String], keep: [String], paste: String) { self.remove = remove; self.keep = keep; self.paste = paste }
    }

    public static func sendPlan(attached: [String], composer: String) -> SendPlan {
        let here = Set(tokens(in: composer))
        var text = composer
        for t in attached { text = text.replacingOccurrences(of: t + " ", with: "").replacingOccurrences(of: t, with: "") }
        return SendPlan(remove: attached.filter { !here.contains($0) }, keep: attached.filter { here.contains($0) },
                        paste: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The TUI's prompt holds nothing but tokens this composer attached.
    public static func promptHoldsOnly(_ prompt: String, _ attached: [String]) -> Bool {
        let set = Set(attached)
        guard tokens(in: prompt).allSatisfy(set.contains) else { return false }
        var rest = prompt
        for t in tokens(in: prompt) { rest = rest.replacingOccurrences(of: t, with: "") }
        return rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The prompt as the TUI moves through it: a token is one unit, any other character one each.
    /// The TUI puts a space after a token, which the screen trims: a prompt ending in one has it.
    public static func units(_ prompt: String) -> [String] {
        let ns = prompt as NSString
        var out: [String] = [], at = 0
        for m in tokenPattern.matches(in: prompt, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: at, length: m.range.location - at)).map(String.init)
            out.append(ns.substring(with: m.range)); at = m.range.upperBound
        }
        out += ns.substring(from: at).map(String.init)
        if let last = out.last, tokenPattern.firstMatch(in: last, range: NSRange(location: 0, length: (last as NSString).length)) != nil { out.append(" ") }
        return out
    }

    /// The keys that delete one token from a prompt with the caret at `cursor` (in units): move to
    /// just after it, Backspace. Leaves the caret where the token was.
    public static func deleteStep(units: [String], cursor: Int, token: String) -> (keys: [ChatKey], units: [String], cursor: Int)? {
        guard let i = units.firstIndex(of: token) else { return nil }
        let move = cursor - (i + 1)
        var rest = units
        rest.remove(at: i)
        return ((move > 0 ? Array(repeating: ChatKey.left, count: move) : Array(repeating: .right, count: -move)) + [.backspace], rest, i)
    }
}

extension ChatSession {
    /// Whether Ctrl+V is still Claude Code's image paste (`chat:imagePaste`).
    static var ctrlVIsImagePaste: Bool {
        let file = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/keybindings.json")
        guard let data = try? Data(contentsOf: file), let text = String(data: data, encoding: .utf8), text.contains("chat:imagePaste") else { return true }
        return text.range(of: #""ctrl\+v"\s*:\s*"chat:imagePaste""#, options: .regularExpression) != nil
    }

    /// An image on the clipboard goes into Claude's prompt as Claude Code's own `[Image #N]` (Ctrl+V);
    /// on success the token is the last of `ui.attachedTokens`, its picture in `ui.images`.
    public func attachClipboardImage(_ image: NSImage?) async -> ChatAnswerResult {
        guard !sending else { return .refused("Claude’s prompt is busy") }
        if terminal == nil, fixtureScreenText != nil {   // a fixture chat has no TUI: the next number
            note(token: "[Image #\(ui.attachedTokens.count + 1)]", image)
            return .done
        }
        guard terminal != nil else { return .refused("the terminal isn't running") }
        let s = reread()
        guard s.kind == .idle || s.kind == .busy else {
            fallBack(.handedOver("Claude is asking something in the terminal; paste the image there."))
            return .refused("the terminal is showing a dialog")
        }
        guard Self.ctrlVIsImagePaste else { return .refused("Ctrl+V isn’t Claude Code’s image paste in your keybindings") }
        sending = true
        defer { sending = false }
        let before = s.input ?? ""
        terminal?.sendKeys(ChatKey.ctrlV.bytes)
        for _ in 0..<30 {
            await pause(100_000_000)
            if let token = ChatPaste.newToken(before: before, after: reread().input ?? "") {
                note(token: token, image)
                // What Ctrl+G will show now holds the token; the composer opens no raw copy of it.
                if usesExternalEditor { sending = false; ui.composerBasis = await peekPrompt() }
                return .done
            }
        }
        return .refused("Claude Code didn’t take the image")
    }

    private func note(token: String, _ image: NSImage?) {
        ui.images[token] = image ?? NSImage(size: NSSize(width: 1, height: 1))
        ui.attachedTokens.append(token)
    }

    /// Paste mode, before the text goes in: deletes from Claude's prompt the tokens whose chips are
    /// gone, then puts the caret at the end. Re-reads the screen after each; nil when it reads as
    /// expected, else why not. Not exercised against a real TUI (the work Mac's 2.1.219 is the one that pastes).
    func removeImageTokens(_ remove: [String], from prompt: String) async -> String? {
        var units = ChatPaste.units(prompt), cursor = units.count
        for t in remove {
            guard let step = ChatPaste.deleteStep(units: units, cursor: cursor, token: t) else { return "Claude’s prompt doesn’t hold \(t)" }
            for k in step.keys { _ = await press(k) }
            units = step.units; cursor = step.cursor
            let shown = reread().input ?? ""
            guard ChatPaste.tokens(in: shown) == units.filter({ ChatPaste.tokens(in: $0).count == 1 }) else { return "Claude’s prompt didn’t read as expected after removing \(t)" }
        }
        for _ in cursor..<units.count { _ = await press(.right) }
        return nil
    }

    /// Everything about attached images is forgotten (sent, or the chat is cleared).
    func forgetImages() { ui.images = [:]; ui.attachedTokens = [] }
}

/// For DuoChecks: the composer's text as it would be sent, for a text with image chips.
@MainActor public enum ComposerProbe {
    /// Sets `text` (tokens turn to chips for the images given), then adds a chip at the caret; returns what would be sent.
    public static func sent(setting text: String, images: [String: NSImage], adding token: String) -> String {
        let chat = ChatSession(key: "probe", mode: .chat)
        chat.ui.images = images
        let v = ComposerTextView()
        v.coordinator = ChatComposerField.Coordinator(chat: chat)
        v.setPlain(text)
        v.insertImageChip(token, NSImage(size: NSSize(width: 4, height: 4)))
        return v.plainText
    }
}
