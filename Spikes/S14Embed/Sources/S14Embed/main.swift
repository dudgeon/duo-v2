import CoreML
import Foundation

// S14 (pass/fail, written first):
// 1. `compile` turns the .mlpackage into .mlmodelc at runtime (MLModel.compileModel), no Xcode.
// 2. `tokens` matches Hugging Face tokenizers on the POC fixtures and golden queries (checked by tokcheck.py).
// 3. `query` embeds a query with the precompiled model; the vector matches Python Core ML / ONNX.
// 4. Under Claude Code's sandbox (Seatbelt; scripts/check-sandbox-embed.sh) `query` works with no
//    writes outside the allowed folders and no network, for each compute-unit setting.
// S15: `bench` measures documents per second for 300-token chunks, batch 32, per compute unit.

let args = CommandLine.arguments
func die(_ m: String) -> Never { FileHandle.standardError.write(Data((m + "\n").utf8)); exit(1) }
let units: [String: MLComputeUnits] = ["cpu": .cpuOnly, "gpu": .cpuAndGPU, "ane": .cpuAndNeuralEngine, "all": .all]
let prefix = "Represent this sentence for searching relevant passages: "

func load(_ path: String, _ cu: String) throws -> MLModel {
    let c = MLModelConfiguration()
    c.computeUnits = units[cu] ?? .all
    return try MLModel(contentsOf: URL(fileURLWithPath: path), configuration: c)
}

func embed(_ model: MLModel, _ batch: [[Int32]]) throws -> [[Float]] {
    let n = batch.count, len = batch.map(\.count).max()!
    let ids = try MLMultiArray(shape: [NSNumber(value: n), NSNumber(value: len)], dataType: .int32)
    let mask = try MLMultiArray(shape: [NSNumber(value: n), NSNumber(value: len)], dataType: .int32)
    for (i, row) in batch.enumerated() {
        for j in 0..<len {
            ids[[NSNumber(value: i), NSNumber(value: j)]] = NSNumber(value: j < row.count ? row[j] : 0)
            mask[[NSNumber(value: i), NSNumber(value: j)]] = NSNumber(value: j < row.count ? 1 : 0)
        }
    }
    let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["input_ids": ids, "attention_mask": mask]))
    let e = out.featureValue(for: "embedding")!.multiArrayValue!
    return (0..<n).map { i in (0..<384).map { j in e[[NSNumber(value: i), NSNumber(value: j)]].floatValue } }
}

switch args.dropFirst().first {
case "compile":
    guard args.count == 4 else { die("compile <in.mlpackage> <out-dir>") }
    let t0 = Date()
    let tmp = try await MLModel.compileModel(at: URL(fileURLWithPath: args[2]))
    let dest = URL(fileURLWithPath: args[3]).appending(path: tmp.lastPathComponent)
    try? FileManager.default.removeItem(at: dest)
    try FileManager.default.createDirectory(at: URL(fileURLWithPath: args[3]), withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: tmp, to: dest)
    print("compiled to \(dest.path) in \(Int(Date().timeIntervalSince(t0) * 1000)) ms (temp was \(tmp.deletingLastPathComponent().path))")
case "tokens":
    let wp = try WordPiece(vocabFile: URL(fileURLWithPath: args[2]))
    // stdin: JSON array of strings → stdout: JSON array of id arrays
    let texts = try JSONDecoder().decode([String].self, from: FileHandle.standardInput.readDataToEndOfFile())
    print(String(decoding: try JSONEncoder().encode(texts.map { wp.encode($0) }), as: UTF8.self))
case "query":
    guard args.count >= 6 else { die("query <model.mlmodelc> <vocab.txt> <cpu|gpu|ane|all> <text>") }
    let t0 = Date()
    let wp = try WordPiece(vocabFile: URL(fileURLWithPath: args[3]))
    let model = try load(args[2], args[4])
    let t1 = Date()
    let v = try embed(model, [wp.encode(prefix + args[5...].joined(separator: " "))])[0]
    let t2 = Date()
    print(String(format: "load %.0f ms, embed %.0f ms", t1.timeIntervalSince(t0) * 1000, t2.timeIntervalSince(t1) * 1000))
    print(v.prefix(4).map { String(format: "%.5f", $0) }.joined(separator: " "))
    print(String(decoding: try JSONEncoder().encode(v), as: UTF8.self))
case "bench":
    guard args.count == 6 else { die("bench <model.mlmodelc> <vocab.txt> <cu> <seconds>") }
    let wp = try WordPiece(vocabFile: URL(fileURLWithPath: args[3]))
    let model = try load(args[2], args[4])
    let words = "the quarterly retention readout covers churn cohorts pricing experiments onboarding funnels and the refunds api".split(separator: " ")
    let text = (0..<300).map { words[$0 % words.count] }.joined(separator: " ")
    // Enumerated-shape models take exactly 32 × (128|256|512): pad 300 tokens to 512 there.
    let fixed = ProcessInfo.processInfo.environment["PAD_TO"].flatMap(Int.init)
    let chunk = Array(wp.encode(text).prefix(300)) + Array(repeating: Int32(0), count: max(0, (fixed ?? 0) - 300))
    let batch = Array(repeating: chunk, count: 32)
    _ = try embed(model, batch)  // warm up (the first call compiles for the device)
    let limit = Double(args[5]) ?? 10; let t0 = Date(); var docs = 0
    while Date().timeIntervalSince(t0) < limit { _ = try embed(model, batch); docs += 32 }
    print(String(format: "%@: %.1f chunks/s (300 tokens, batch 32)", args[4], Double(docs) / Date().timeIntervalSince(t0)))
default:
    die("compile | tokens | query | bench")
}
