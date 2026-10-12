import AVFoundation
import Foundation
import Speech

// MARK: - SpeechAnalyzer family (SpeechTranscriber, DictationTranscriber)

final class AppleAnalyzerEngine: Engine {
    enum Kind { case speech, dictation }
    let kind: Kind
    let terms: [String]
    let locale = Locale(identifier: "en-US")
    var supportsStream: Bool { true }

    init(kind: Kind, terms: [String]) {
        self.kind = kind
        self.terms = terms
    }

    typealias Collector = (StreamState, UInt64) -> Task<Void, Error>

    func make(stream: Bool) -> (any SpeechModule, Collector) {
        switch kind {
        case .speech:
            let t = SpeechTranscriber(locale: locale, preset: stream ? .progressiveTranscription : .transcription)
            return (
                t,
                { st, t0 in
                    Task {
                        for try await r in t.results { st.note(text: String(r.text.characters), isFinal: r.isFinal, t0: t0) }
                    }
                }
            )
        case .dictation:
            let t = DictationTranscriber(
                locale: locale, contentHints: [], transcriptionOptions: [.punctuation],
                reportingOptions: stream ? [.volatileResults] : [], attributeOptions: [])
            return (
                t,
                { st, t0 in
                    Task {
                        for try await r in t.results { st.note(text: String(r.text.characters), isFinal: r.isFinal, t0: t0) }
                    }
                }
            )
        }
    }

    func load() async throws {
        // Read-only status. Never requestAuthorization.
        logErr("SFSpeechRecognizer.authorizationStatus() = \(SFSpeechRecognizer.authorizationStatus().rawValue) (0 notDetermined, 1 denied, 2 restricted, 3 authorized)")
        let (mod, _) = make(stream: false)
        let status = await AssetInventory.status(forModules: [mod])
        logErr("AssetInventory.status(\(kind)) = \(status)")
        if status != .installed {
            if status == .unsupported { throw BenchError("en-US unsupported for \(kind)") }
            if let req = try await AssetInventory.assetInstallationRequest(supporting: [mod]) {
                logErr("installing assets (system download, no UI)...")
                let t0 = nowNs()
                try await req.downloadAndInstall()
                logErr("assets installed in \(Int(msSince(t0))) ms")
            }
            logErr("AssetInventory.status after = \(await AssetInventory.status(forModules: [mod]))")
        }
    }

    func run(_ samples: [Float], stream: Bool, chunkMs: Int) async throws -> ClipResult {
        let (mod, collect) = make(stream: stream)
        let analyzer = SpeechAnalyzer(modules: [mod])
        let fmt = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [mod]) ?? fmt16k
        let full = try convert(makeBuffer16k(samples[...]), to: fmt)

        let tStart = nowNs()
        if !terms.isEmpty {
            let ctx = AnalysisContext()
            ctx.contextualStrings[.general] = terms
            try await analyzer.setContext(ctx)
        }
        let state = StreamState()
        let (inSeq, cont) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.start(inputSequence: inSeq)
        let t0 = stream ? nowNs() : tStart
        let collector = collect(state, t0)

        var tEnd = t0
        if stream {
            let hop = Int(fmt.sampleRate) * chunkMs / 1000
            let total = Int(full.frameLength)
            var pos = 0
            var i = 1
            while pos < total {
                let n = min(hop, total - pos)
                await sleepUntil(t0, ms: Double(i * chunkMs))  // a chunk exists only once it has been spoken
                cont.yield(AnalyzerInput(buffer: sliceMono(full, start: pos, count: n)))
                pos += n
                i += 1
            }
            tEnd = nowNs()
        } else {
            cont.yield(AnalyzerInput(buffer: full))
        }
        cont.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        try await collector.value
        let hyp = squash(state.text)
        if stream {
            return ClipResult(
                hyp: hyp, procMs: msSince(t0), firstPartialMs: state.firstPartialMs, finalMs: msSince(tEnd),
                partials: state.partials)
        }
        let p = msSince(tStart)
        return ClipResult(hyp: hyp, procMs: p, finalMs: p, partials: state.partials)
    }

    func batch(_ samples: [Float]) async throws -> ClipResult { try await run(samples, stream: false, chunkMs: 0) }
    func stream(_ samples: [Float], chunkMs: Int) async throws -> ClipResult {
        try await run(samples, stream: true, chunkMs: chunkMs)
    }
}

// MARK: - SFSpeechRecognizer, on-device only

final class SFSpeechEngine: Engine {
    let terms: [String]
    var recognizer: SFSpeechRecognizer!
    var supportsStream: Bool { true }
    init(terms: [String]) { self.terms = terms }

    static func authError() -> String? {
        let s = SFSpeechRecognizer.authorizationStatus()
        if s == .authorized { return nil }
        return "SFSpeechRecognizer.authorizationStatus() = \(s.rawValue) (0 notDetermined, 1 denied, 2 restricted); not authorized and asking would show a prompt, so no recognition was attempted"
    }

    func load() async throws {
        guard let r = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else { throw BenchError("no recognizer for en-US") }
        logErr("supportsOnDeviceRecognition = \(r.supportsOnDeviceRecognition), isAvailable = \(r.isAvailable)")
        guard r.supportsOnDeviceRecognition else { throw BenchError("on-device recognition unsupported") }
        recognizer = r
    }

    func run(_ samples: [Float], stream: Bool, chunkMs: Int) async throws -> ClipResult {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        if !terms.isEmpty { req.contextualStrings = terms }
        let state = StreamState()
        let tStart = nowNs()
        let t0Box = Box(tStart)
        let done = DoneBox()
        let task = recognizer.recognitionTask(with: req) { result, error in
            if let result {
                state.note(text: result.bestTranscription.formattedString, isFinal: false, t0: t0Box.value)
                if result.isFinal { done.finish(result.bestTranscription.formattedString, nil) }
            }
            if let error { done.finish(nil, error) }
        }
        var tEnd = tStart
        if stream {
            let t0 = nowNs()
            t0Box.value = t0
            let hop = 16 * chunkMs
            var pos = 0
            var i = 1
            while pos < samples.count {
                let n = min(hop, samples.count - pos)
                await sleepUntil(t0, ms: Double(i * chunkMs))
                req.append(makeBuffer16k(samples[pos..<(pos + n)]))
                pos += n
                i += 1
            }
            tEnd = nowNs()
        } else {
            req.append(makeBuffer16k(samples[...]))
        }
        req.endAudio()
        let (text, err) = await done.wait()
        task.cancel()
        if text == nil, let err { throw err }
        let hyp = squash(text ?? "")
        if stream {
            return ClipResult(
                hyp: hyp, procMs: msSince(t0Box.value), firstPartialMs: state.firstPartialMs, finalMs: msSince(tEnd),
                partials: state.partials)
        }
        let p = msSince(tStart)
        return ClipResult(hyp: hyp, procMs: p, finalMs: p, partials: state.partials)
    }

    func batch(_ samples: [Float]) async throws -> ClipResult { try await run(samples, stream: false, chunkMs: 0) }
    func stream(_ samples: [Float], chunkMs: Int) async throws -> ClipResult {
        try await run(samples, stream: true, chunkMs: chunkMs)
    }
}

final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ v: T) { value = v }
}

final class DoneBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: (String?, Error?)? = nil
    private var cont: CheckedContinuation<(String?, Error?), Never>? = nil
    func finish(_ t: String?, _ e: Error?) {
        lock.lock()
        if result != nil {
            lock.unlock()
            return
        }
        result = (t, e)
        let c = cont
        cont = nil
        lock.unlock()
        c?.resume(returning: (t, e))
    }
    func wait() async -> (String?, Error?) {
        await withCheckedContinuation { c in
            lock.lock()
            if let r = result {
                lock.unlock()
                c.resume(returning: r)
            } else {
                cont = c
                lock.unlock()
            }
        }
    }
}
