@preconcurrency import CoreML
import FluidAudio
import Foundation

let realHome = String(cString: getpwuid(getuid())!.pointee.pw_dir)
let cacheRoot = URL(fileURLWithPath: realHome).appendingPathComponent("Library/Caches/duo-voice-input", isDirectory: true)
let modelsRoot = cacheRoot.appendingPathComponent("models", isDirectory: true)

/// FluidAudio CustomVocabulary: CTC 110M keyword spotting + transcript rescoring. VocabularyBoostingSession would
/// look for the CTC tokenizer in ~/Library/Application Support at this pin (no override), so this re-creates its
/// rescore() with the public pieces and our own model folder.
struct CtcBoost {
    let vocab: CustomVocabularyContext
    let spotter: CtcKeywordSpotter
    let rescorer: VocabularyRescorer
    let cfg: ContextBiasingConstants.VocabSizeConfig

    init(terms: [String]) async throws {
        let variant = CtcModelVariant.ctc110m
        let dir = modelsRoot.appendingPathComponent("fluid", isDirectory: true)
            .appendingPathComponent(variant.repo.folderName, isDirectory: true)
        try await CtcModels.download(to: dir, variant: variant)
        let models = try await CtcModels.load(from: dir, variant: variant)
        let tok = try await CtcTokenizer.load(from: dir)
        let vterms = terms.compactMap { t -> CustomVocabularyTerm? in
            let ids = tok.encode(t)
            return ids.isEmpty ? nil : CustomVocabularyTerm(text: t, ctcTokenIds: ids)
        }
        vocab = CustomVocabularyContext(terms: vterms)
        spotter = CtcKeywordSpotter(models: models, blankId: models.vocabulary.count)
        cfg = ContextBiasingConstants.rescorerConfig(forVocabSize: vterms.count)
        rescorer = try await VocabularyRescorer.create(
            spotter: spotter, vocabulary: vocab, config: .default, ctcModelDirectory: dir)
    }

    func apply(text: String, timings: [TokenTiming], samples: [Float]) async -> String {
        guard !timings.isEmpty, !samples.isEmpty,
            let spot = try? await spotter.spotKeywordsWithLogProbs(
                audioSamples: samples, customVocabulary: vocab, minScore: nil),
            !spot.logProbs.isEmpty
        else { return text }
        let out = rescorer.ctcTokenRescore(
            transcript: text, tokenTimings: timings, logProbs: spot.logProbs, frameDuration: spot.frameDuration,
            cbw: cfg.cbw, marginSeconds: 0.5, minSimilarity: max(cfg.minSimilarity, vocab.minSimilarity))
        return out.wasModified ? out.text : text
    }
}

// MARK: - Parakeet TDT (v2, v3, Redux): batch

final class FluidTdtEngine: Engine {
    enum Which { case v2, v3, redux }
    let which: Which
    let terms: [String]
    var manager: AsrManager!
    var boost: CtcBoost?

    init(which: Which, terms: [String]) {
        self.which = which
        self.terms = terms
    }

    func load() async throws {
        let models: AsrModels
        switch which {
        case .v2:
            models = try await AsrModels.downloadAndLoad(
                to: modelsRoot.appendingPathComponent("parakeet-v2", isDirectory: true), version: .v2)
        case .v3:
            models = try await AsrModels.downloadAndLoad(
                to: modelsRoot.appendingPathComponent("parakeet-v3", isDirectory: true), version: .v3)
        case .redux:
            ModelHub.offlineMode = true
            models = try AsrModels.loadLocal(
                from: URL(fileURLWithPath: "/Users/geoff/repos/mini-meeting-minutes/Models/parakeet-redux"),
                version: .redux, encoderComputeUnits: .cpuAndGPU)
        }
        manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        if !terms.isEmpty {
            boost = try await CtcBoost(terms: terms)
            logErr("CustomVocabulary: \(boost!.vocab.terms.count) terms, CTC 110M keyword spotting + rescoring")
        }
    }

    func batch(_ samples: [Float]) async throws -> ClipResult {
        let t0 = nowNs()
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let r = try await manager.transcribe(samples, decoderState: &state)
        var text = r.text
        if let boost { text = await boost.apply(text: text, timings: r.tokenTimings ?? [], samples: samples) }
        let p = msSince(t0)
        return ClipResult(hyp: squash(text), procMs: p, finalMs: p)
    }
}

// MARK: - Parakeet Unified 0.6B (one checkpoint: batch + streaming)

final class FluidUnifiedEngine: Engine {
    let terms: [String]
    let streaming: Bool
    var boost: CtcBoost?
    var batchMgr: UnifiedAsrManager!
    var streamMgr: StreamingUnifiedAsrManager!
    var supportsStream: Bool { streaming }

    let ucfg: UnifiedConfig

    /// tier = (chunkFrames, rightFrames), 80 ms each; default 13/13 = 2.08 s theoretical latency.
    init(terms: [String], streaming: Bool, tier: (Int, Int) = (13, 13)) {
        self.terms = terms
        self.streaming = streaming
        self.ucfg = UnifiedConfig(leftFrames: 70, chunkFrames: tier.0, rightFrames: tier.1)
    }

    func load() async throws {
        let base = modelsRoot.appendingPathComponent("fluid", isDirectory: true)
                if streaming {
            streamMgr = StreamingUnifiedAsrManager(config: ucfg)
            try await streamMgr.loadModels(to: base)
            if !terms.isEmpty { throw BenchError("--context unsupported for fluid-parakeet-stream: StreamingUnifiedAsrManager.configureVocabularyBoosting needs the CTC tokenizer in ~/Library/Application Support (outside the allowed folders)") }
        } else {
            batchMgr = UnifiedAsrManager()
            try await batchMgr.loadModels(to: base)
            if !terms.isEmpty { boost = try await CtcBoost(terms: terms) }
        }
    }

    func batch(_ samples: [Float]) async throws -> ClipResult {
        let t0 = nowNs()
        let text: String
        if streaming {
            try await streamMgr.reset()
            try await streamMgr.appendAudio(makeBuffer16k(samples[...]))
            try await streamMgr.processBufferedAudio()
            text = try await streamMgr.finish()
        } else {
            if let boost {
                let r = try await batchMgr.transcribeWithTimings(samples)
                text = await boost.apply(text: r.text, timings: r.tokenTimings, samples: samples)
            } else {
                text = try await batchMgr.transcribe(samples)
            }
        }
        let p = msSince(t0)
        return ClipResult(hyp: squash(text), procMs: p, finalMs: p)
    }

    func stream(_ samples: [Float], chunkMs: Int) async throws -> ClipResult {
        try await streamMgr.reset()
        let t0 = nowNs()
        var first: Double? = nil
        var partials = 0
        var last = ""
        let hop = 16 * chunkMs
        var pos = 0
        var i = 1
        while pos < samples.count {
            let n = min(hop, samples.count - pos)
            await sleepUntil(t0, ms: Double(i * chunkMs))
            try await streamMgr.appendAudio(makeBuffer16k(samples[pos..<(pos + n)]))
            try await streamMgr.processBufferedAudio()
            let p = await streamMgr.getPartialTranscript().trimmingCharacters(in: .whitespacesAndNewlines)
            if !p.isEmpty && p != last {
                partials += 1
                last = p
                if first == nil { first = msSince(t0) }
            }
            pos += n
            i += 1
        }
        let tEnd = nowNs()
        let text = try await streamMgr.finish()
        return ClipResult(
            hyp: squash(text), procMs: msSince(t0), firstPartialMs: first, finalMs: msSince(tEnd), partials: partials)
    }
}

// MARK: - Nemotron streaming 0.6B (560 ms chunks)

final class FluidNemotronEngine: Engine {
    var mgr: StreamingNemotronAsrManager!
    var supportsStream: Bool { true }

    func load() async throws {
        mgr = StreamingNemotronAsrManager(requestedChunkSize: .ms560)
        try await mgr.loadModels(to: modelsRoot.appendingPathComponent("fluid", isDirectory: true))
    }

    func batch(_ samples: [Float]) async throws -> ClipResult {
        await mgr.reset()
        let t0 = nowNs()
        try await mgr.appendAudio(makeBuffer16k(samples[...]))
        try await mgr.processBufferedAudio()
        let text = try await mgr.finish()
        let p = msSince(t0)
        return ClipResult(hyp: squash(text), procMs: p, finalMs: p)
    }

    func stream(_ samples: [Float], chunkMs: Int) async throws -> ClipResult {
        await mgr.reset()
        let t0 = nowNs()
        var first: Double? = nil
        var partials = 0
        var last = ""
        let hop = 16 * chunkMs
        var pos = 0
        var i = 1
        while pos < samples.count {
            let n = min(hop, samples.count - pos)
            await sleepUntil(t0, ms: Double(i * chunkMs))
            try await mgr.appendAudio(makeBuffer16k(samples[pos..<(pos + n)]))
            try await mgr.processBufferedAudio()
            let p = await mgr.getPartialTranscript().trimmingCharacters(in: .whitespacesAndNewlines)
            if !p.isEmpty && p != last {
                partials += 1
                last = p
                if first == nil { first = msSince(t0) }
            }
            pos += n
            i += 1
        }
        let tEnd = nowNs()
        let text = try await mgr.finish()
        return ClipResult(
            hyp: squash(text), procMs: msSince(t0), firstPartialMs: first, finalMs: msSince(tEnd), partials: partials)
    }
}
