import Foundation

// asrbench --engine <name> --manifest <m.jsonl> --out <results.jsonl> [--mode batch|stream] [--context <terms.txt>]
//          [--chunk-ms 100] [--limit N]

let engineNames = [
    "apple-speechtranscriber", "apple-dictation", "apple-sfspeech",
    "fluid-parakeet-v3", "fluid-parakeet-v2", "fluid-parakeet-redux",
    "fluid-parakeet-unified", "fluid-parakeet-stream", "fluid-parakeet-stream-7-1", "fluid-parakeet-stream-2-2", "fluid-nemotron-stream",
    "whisperkit-turbo", "whisperkit-small-en",
]

var args: [String: String] = [:]
do {
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let a = it.next() {
        guard a.hasPrefix("--"), let v = it.next() else {
            logErr("usage: asrbench --engine <\(engineNames.joined(separator: "|"))> --manifest m.jsonl --out r.jsonl [--mode batch|stream] [--context terms.txt] [--chunk-ms 100] [--limit N]")
            exit(64)
        }
        args[String(a.dropFirst(2))] = v
    }
}
guard let engineName = args["engine"], let manifestPath = args["manifest"], let outPath = args["out"] else {
    logErr("need --engine, --manifest, --out. Engines: \(engineNames.joined(separator: ", "))")
    exit(64)
}
let mode = args["mode"] ?? "batch"
let chunkMs = Int(args["chunk-ms"] ?? "100") ?? 100
let limit = Int(args["limit"] ?? "") ?? Int.max
let terms = try readTerms(args["context"])

// Per-clip results for Geoff's takes may only go under $CLAUDE_JOB_DIR/tmp/private/.
if manifestPath.contains("takes") {
    let priv = (ProcessInfo.processInfo.environment["CLAUDE_JOB_DIR"] ?? "") + "/tmp/private/"
    if !(outPath.hasPrefix(priv) && priv.count > 14) {
        logErr("refusing: results for the takes manifest must be written under $CLAUDE_JOB_DIR/tmp/private/")
        exit(65)
    }
}

let writer = try JsonlWriter(path: outPath)

func engineFor(_ name: String) -> Engine? {
    switch name {
    case "apple-speechtranscriber": return AppleAnalyzerEngine(kind: .speech, terms: terms)
    case "apple-dictation": return AppleAnalyzerEngine(kind: .dictation, terms: terms)
    case "apple-sfspeech": return SFSpeechEngine(terms: terms)
    case "fluid-parakeet-v3": return FluidTdtEngine(which: .v3, terms: terms)
    case "fluid-parakeet-v2": return FluidTdtEngine(which: .v2, terms: terms)
    case "fluid-parakeet-redux": return FluidTdtEngine(which: .redux, terms: terms)
    case "fluid-parakeet-unified": return FluidUnifiedEngine(terms: terms, streaming: false)
    case "fluid-parakeet-stream": return FluidUnifiedEngine(terms: terms, streaming: true)
    case "fluid-parakeet-stream-7-1": return FluidUnifiedEngine(terms: terms, streaming: true, tier: (7, 1))
    case "fluid-parakeet-stream-2-2": return FluidUnifiedEngine(terms: terms, streaming: true, tier: (2, 2))
    case "fluid-nemotron-stream": return FluidNemotronEngine()
    case "whisperkit-turbo": return WhisperKitEngine(modelName: "openai_whisper-large-v3-v20240930_turbo", terms: terms)
    case "whisperkit-small-en": return WhisperKitEngine(modelName: "openai_whisper-small.en", terms: terms)
    default: return nil
    }
}

guard let engine = engineFor(engineName) else {
    logErr("unknown engine \(engineName)")
    exit(64)
}
if mode == "stream" && !engine.supportsStream {
    writer.write(["error": "\(engineName) has no streaming mode", "engine": engineName])
    exit(0)
}
if engineName == "apple-sfspeech", let e = SFSpeechEngine.authError() {
    writer.write(["error": e, "engine": engineName])
    logErr(e)
    exit(0)
}

let clips = Array(try readManifest(manifestPath).prefix(limit))
guard let first = clips.first else {
    logErr("empty manifest")
    exit(66)
}

let tLoad = nowNs()
do {
    try await engine.load()
} catch {
    writer.write(["error": "load failed: \(error)", "engine": engineName])
    logErr("load failed: \(error)")
    exit(0)
}
let loadMs = msSince(tLoad)
logErr("load_ms \(Int(loadMs))")

func run(_ samples: [Float]) async throws -> ClipResult {
    mode == "stream" ? try await engine.stream(samples, chunkMs: chunkMs) : try await engine.batch(samples)
}

// Warm-up on the first clip, not scored.
do {
    let s = try loadSamples16k(first.wav)
    let t = nowNs()
    _ = try await run(s)
    logErr("warm-up \(Int(msSince(t))) ms")
} catch {
    logErr("warm-up failed (continuing): \(error)")
}

var firstLine = true
for clip in clips {
    var rec: [String: Any] = ["id": clip.id, "engine": engineName, "mode": mode]
    if firstLine { rec["load_ms"] = loadMs }
    firstLine = false
    do {
        let samples = try loadSamples16k(clip.wav)
        rec["audio_ms"] = Double(samples.count) / 16.0
        let r = try await run(samples)
        rec["hyp"] = r.hyp
        rec["proc_ms"] = r.procMs
        rec["final_ms"] = r.finalMs ?? r.procMs
        if let f = r.firstPartialMs { rec["first_partial_ms"] = f }
        rec["partials"] = r.partials ?? 0
    } catch {
        rec["error"] = "\(error)"
    }
    writer.write(rec)
}
exit(0)
