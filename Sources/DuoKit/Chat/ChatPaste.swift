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
        /// Tokens put in Claude's prompt whose pictures were removed: deleted from it.
        public var remove: [String]
        /// Pictures still in the composer: left in the prompt, first in the message.
        public var keep: [String]
        /// The composer's text, pasted after them.
        public var paste: String
        public init(remove: [String], keep: [String], paste: String) { self.remove = remove; self.keep = keep; self.paste = paste }
        /// The message as Claude gets it: the kept tokens, a space, then the text (F-233).
        public var message: String { (keep + [paste]).filter { !$0.isEmpty }.joined(separator: " ") }
    }

    /// `held`: every token this composer put in Claude's prompt; `kept`: the pictures it still shows.
    public static func sendPlan(held: [String], kept: [String], text: String) -> SendPlan {
        SendPlan(remove: held.filter { !kept.contains($0) }, keep: held.filter(kept.contains), paste: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// A message's text without `[Image #N]` and the space each leaves (the pictures stand for them).
    public static func stripTokens(_ s: String) -> String {
        s.replacingOccurrences(of: #"\[Image #\d+\]\s*"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The TUI's prompt holds nothing but tokens this composer put there.
    public static func promptHoldsOnly(_ prompt: String, _ held: [String]) -> Bool {
        let set = Set(held)
        guard tokens(in: prompt).allSatisfy(set.contains) else { return false }
        var rest = prompt
        for t in tokens(in: prompt) { rest = rest.replacingOccurrences(of: t, with: "") }
        return rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The prompt as the TUI moves through it: a token is one unit, any other character one each.
    public static func units(_ prompt: String) -> [String] {
        let ns = prompt as NSString
        var out: [String] = [], at = 0
        for m in tokenPattern.matches(in: prompt, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: at, length: m.range.location - at)).map(String.init)
            out.append(ns.substring(with: m.range)); at = m.range.upperBound
        }
        return out + ns.substring(from: at).map(String.init)
    }

    /// The keys that delete one token (F-232, measured on 2.1.219 and 2.1.293): Ctrl+A, Right once
    /// per unit up to and including it (counted from the start: 2.1.293 leaves no space after the
    /// last token), Backspace.
    public static func deleteStep(units: [String], token: String) -> (keys: [ChatKey], units: [String])? {
        guard let i = units.firstIndex(of: token) else { return nil }
        var rest = units
        rest.remove(at: i)
        return ([.ctrlA] + Array(repeating: ChatKey.right, count: i + 1) + [.backspace], rest)
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
        ui.pasteNotice = nil
        if terminal == nil, fixtureScreenText != nil {   // a fixture chat has no TUI: the next number
            note(token: "[Image #\(ui.attachedTokens.count + 1)]", image)
            return .done
        }
        guard terminal != nil else { ui.pasteNotice = .notTaken; return .refused("the terminal isn't running") }
        let s = reread()
        guard s.kind == .idle || s.kind == .busy else {
            fallBack(.handedOver("Claude is asking something in the terminal; paste the picture there."))
            return .refused("the terminal is showing a dialog")
        }
        guard Self.ctrlVIsImagePaste else { ui.pasteNotice = .keysMoved; return .refused("Ctrl+V isn’t Claude Code’s image paste in your keybindings") }
        sending = true
        ui.addingPicture = true
        defer { sending = false; ui.addingPicture = false }
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
        ui.pasteNotice = .notTaken
        return .refused("Claude Code didn’t take the picture")
    }

    private func note(token: String, _ image: NSImage?) {
        ui.images[token] = image ?? NSImage(size: NSSize(width: 1, height: 1))
        ui.attachedTokens.append(token)
        ui.heldTokens.append(token)
    }

    /// Paste mode, before the text goes in: deletes from Claude's prompt the tokens whose pictures were
    /// removed (Ctrl+A, Right to it, Backspace; the screen is re-read after each), then Ctrl+E puts the
    /// caret at the end. Nil when it reads as expected, else why not. Keys as measured on the real TUIs (F-232).
    func removeImageTokens(_ remove: [String], from prompt: String) async -> String? {
        var units = ChatPaste.units(prompt)
        for t in remove {
            guard let step = ChatPaste.deleteStep(units: units, token: t) else { return "Claude’s prompt doesn’t hold \(t)" }
            for k in step.keys { _ = await press(k) }
            units = step.units
            guard ChatPaste.tokens(in: reread().input ?? "") == units.filter({ ChatPaste.tokenPattern.firstMatch(in: $0, range: NSRange(location: 0, length: ($0 as NSString).length)) != nil }) else {
                return "Claude’s prompt didn’t read as expected after removing \(t)"
            }
        }
        if !remove.isEmpty { _ = await press(.ctrlE) }
        return nil
    }

    /// The × on a picture: it leaves the composer; its token stays in Claude's prompt until the send deletes it.
    public func removePicture(_ token: String) {
        ui.attachedTokens.removeAll { $0 == token }
        ui.images[token] = nil
        if ui.hoveredPicture == token { ui.hoveredPicture = nil }
    }

    /// Everything about attached images is forgotten (sent, or the chat is cleared).
    func forgetImages() { ui.images = [:]; ui.attachedTokens = []; ui.heldTokens = []; ui.hoveredPicture = nil }
}

