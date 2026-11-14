import DuoControl
import Foundation

/// `duo2 voice … --doc` (DL-266, DL-71): voice input into the Markdown document showing in the editor. The scripted twin of
/// the formatting bar's mic and of ⇧⌘D with the document focused; `voice file <audio> --doc` is for tests.
extension AppModel {
    /// The verb is about the document: `--doc`, or a plain `voice start|stop|status` while a document has the keyboard.
    func voiceVerbWantsDocument(_ id: ActionID, _ inv: Invocation) -> Bool {
        if inv.has("doc") { return true }
        if case .document? = voice.target, voice.state.isActive, id == .voiceStop || id == .voiceStatus { return true }
        let idWord = id == .voiceFile ? (inv.positional.count > 1 ? inv.positional[1] : nil) : inv.positional.first
        return idWord == nil && webFocus == .editor && showingMarkdownDocument
    }

    func documentVoiceVerb(_ id: ActionID, _ inv: Invocation, _ done: @escaping @MainActor (Reply) -> Void) {
        guard showingMarkdownDocument, let e = editorIfLoaded, let url = e.url else { return done(.fail("no Markdown document is showing in the editor")) }
        let target = VoiceTarget.document(url.path), name = url.lastPathComponent
        switch id {
        case .voiceStatus:
            let mine = voice.target == target
            done(.ok((mine || voice.state.isActive ? VoiceCopy.line(voice.state) : voice.microphoneLine) + " Document: \(name)" + (e.canDictate ? "." : " (read-only)."),
                     ["state": String(describing: voice.state), "document": voice.target?.key ?? url.path]))
        case .voiceStop:
            guard voice.state.isActive else { return done(.ok("Voice input wasn't on.")) }
            voice.finishWhenDone { state in done(.ok("Stopped. \(self.voice.transcript.settledText.isEmpty ? "Nothing was heard." : "Said: \(self.voice.transcript.settledText)")", ["state": String(describing: state)])) }
        case .voiceStart:
            guard e.canDictate else { return done(.fail("\(name) is read-only")) }
            core.voiceWindow = self
            voice.start(target)
            switch voice.state {
            case .unavailable, .denied, .restricted, .failed: done(.fail(VoiceCopy.line(voice.state)))
            default: done(.ok("Voice input is on for \(name)." + (voice.state == .asking ? " Duo is asking the user first." : "")))
            }
        case .voiceFile:
            guard e.canDictate else { return done(.fail("\(name) is read-only")) }
            guard let path = inv.positional.first else { return done(.fail("usage: \(id.action.usage)")) }
            let file = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: file.path) else { return done(.fail("no audio file at \(file.path) (give an absolute path)")) }
            guard !voice.state.isActive else { return done(.fail("voice input is already on; stop it first")) }
            core.voiceWindow = self
            voice.start(target, source: .file(file)) { state in
                switch state {
                case .idle where self.voice.notice != nil: done(.fail("\(self.voice.notice?.text ?? "") (\(name))"))
                case .idle: done(.ok("Said into \(name): \(self.voice.transcript.settledText.isEmpty ? "(nothing recognised)" : self.voice.transcript.settledText).",
                                     ["said": self.voice.transcript.settledText]))
                default: done(.fail(VoiceCopy.line(state)))
                }
            }
        default: done(.fail("not a voice verb"))
        }
    }
}
