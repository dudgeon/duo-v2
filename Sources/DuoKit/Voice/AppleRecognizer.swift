@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

// Apple's recognizer, on this Mac (DL-260): SpeechAnalyzer with SpeechTranscriber and progressive results;
// where SpeechTranscriber has no model for the language, SFSpeechRecognizer with on-device recognition.
// Duo has no model of its own and downloads nothing: AssetInventory (macOS) fetches Apple's, and Duo shows its progress.

enum VoiceRecognizerError: Error, Equatable {
    /// No model for this language, from either recognizer.
    case unavailable(language: String)
    /// Speech Recognition is off for Duo (the fallback's own permission).
    case speechDenied
    case speechRestricted
}

final class AppleRecognizer: @unchecked Sendable {
    private enum Engine { case modern(SpeechTranscriber), legacy(SFSpeechRecognizer) }
    private var engine: Engine?
    private var analyzer: SpeechAnalyzer?
    private var legacyTask: SFSpeechRecognitionTask?
    private let locale: Locale

    init(locale: Locale = .current) { self.locale = locale }

    var usesFallback: Bool { if case .legacy? = engine { true } else { false } }

    private var language: String { locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier }

    /// Picks the engine and, for SpeechTranscriber, makes sure its model is installed (reporting progress 0...1).
    func prepare(progress: @escaping @Sendable (Double?) -> Void) async throws {
        if SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            let t = SpeechTranscriber(locale: supported, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
            do {
                let status = await AssetInventory.status(forModules: [t])
                if status < .installed, let request = try await AssetInventory.assetInstallationRequest(supporting: [t]) {
                    let watcher = Task { [p = request.progress] in
                        while !Task.isCancelled {
                            progress(p.totalUnitCount > 0 ? p.fractionCompleted : nil)
                            try? await Task.sleep(nanoseconds: 250_000_000)
                        }
                    }
                    defer { watcher.cancel() }
                    try await request.downloadAndInstall()
                }
                _ = try? await AssetInventory.reserve(locale: supported)
                engine = .modern(t)
                return
            } catch {
                // The model can't be fetched: the fallback, if this Mac has one.
            }
        }
        guard let r = SFSpeechRecognizer(locale: locale), r.supportsOnDeviceRecognition else {
            throw VoiceRecognizerError.unavailable(language: language)
        }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: break
        case .denied: throw VoiceRecognizerError.speechDenied
        case .restricted: throw VoiceRecognizerError.speechRestricted
        default:
            let ok = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
            if !ok { throw VoiceRecognizerError.speechDenied }
        }
        engine = .legacy(r)
    }

    /// Consumes the buffers until they end, reporting each result as it changes; returns once the last is final.
    func run(buffers: AsyncStream<VoiceBuffer>, onResult: @escaping @Sendable (String, Bool) -> Void) async throws {
        switch engine {
        case .modern(let t)?:
            let analyzer = SpeechAnalyzer(modules: [t])
            self.analyzer = analyzer
            let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t])
            try await analyzer.prepareToAnalyze(in: format)
            let (input, cont) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .unbounded)
            try await analyzer.start(inputSequence: input)
            let results = Task {
                for try await r in t.results { onResult(String(r.text.characters), r.isFinal) }
            }
            let converter = format.map(VoiceConverter.init(to:))
            for await vb in buffers {
                guard let out = converter.map({ $0.convert(vb.buffer) }) ?? vb.buffer else { continue }
                cont.yield(AnalyzerInput(buffer: out))
            }
            cont.finish()
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            try await results.value
        case .legacy(let r)?:
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                nonisolated(unsafe) var finished = false
                self.legacyTask = r.recognitionTask(with: request) { result, error in
                    if let result { onResult(result.bestTranscription.formattedString, result.isFinal) }
                    if (result?.isFinal ?? false) || error != nil, !finished { finished = true; done.resume() }
                }
                Task {
                    for await vb in buffers { request.append(vb.buffer) }
                    request.endAudio()
                }
            }
        case nil: break
        }
    }

    /// Ends the analysis now, dropping what's pending (Esc).
    func cancel() async {
        legacyTask?.cancel()
        await analyzer?.cancelAndFinishNow()
    }
}
