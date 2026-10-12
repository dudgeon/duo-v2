import Foundation
import WhisperKit

final class WhisperKitEngine: Engine {
    let modelName: String
    let terms: [String]
    var pipe: WhisperKit!
    var promptTokens: [Int]? = nil

    init(modelName: String, terms: [String]) {
        self.modelName = modelName
        self.terms = terms
    }

    func load() async throws {
        let base = modelsRoot.appendingPathComponent("whisperkit", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let cfg = WhisperKitConfig(model: modelName, downloadBase: base, verbose: false, prewarm: true, load: true, download: true)
        pipe = try await WhisperKit(cfg)
        if !terms.isEmpty, let tok = pipe.tokenizer {
            // Whisper's `prompt`: previous-context text the decoder conditions on.
            let text = " " + terms.joined(separator: ", ") + "."
            promptTokens = tok.encode(text: text).filter { $0 < tok.specialTokens.specialTokenBegin }
            logErr("promptTokens: \(promptTokens!.count) tokens for \(terms.count) terms")
        }
    }

    func batch(_ samples: [Float]) async throws -> ClipResult {
        let opts = DecodingOptions(
            task: .transcribe, language: "en", temperature: 0, skipSpecialTokens: true, withoutTimestamps: true,
            promptTokens: promptTokens)
        let t0 = nowNs()
        let r = try await pipe.transcribe(audioArray: samples, decodeOptions: opts)
        let text = r.map { $0.text }.joined(separator: " ")
        let p = msSince(t0)
        return ClipResult(hyp: squash(text), procMs: p, finalMs: p)
    }
}
