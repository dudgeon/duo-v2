import CoreML
import DuoControl
import Foundation

/// The search model (SRCH L6, L16; spikes S13–S15, F-35): `bge-small-en-v1.5` at the POC's pinned
/// revision, converted to Core ML fp16, CLS pooling and L2 normalisation inside the model.
/// The app compiles it once into Duo's Application Support folder; the CLI loads that read-only.
public struct ModelIdentity: Codable, Sendable, Equatable {
    public var name = "bge-small-en-v1.5"
    public var revision = "5c38ec7c405ec4b44b94cc5a9bb96e735b38267a"
    public var numerics = "coreml-fp16-cls-l2"
    public var dimensions = 384
    public var queryPrefix = "Represent this sentence for searching relevant passages: "
    public static let current = ModelIdentity()
    /// Part of the index's identity (FR-7.3.8): an index built with another model is never queried.
    public var key: String { "\(name)@\(revision.prefix(12))/\(numerics)" }
}

public enum SearchPaths {
    /// `DUO_SEARCH_ROOT` moves everything (tests, scratch indexes).
    public static var root: URL {
        if let r = ProcessInfo.processInfo.environment["DUO_SEARCH_ROOT"] { return URL(fileURLWithPath: r) }
        return SupportFolder.duo.appending(path: "search")
    }
    public static var index: URL { root.appending(path: "index.sqlite") }
    public static var compiledModel: URL { root.appending(path: "model/bge-small-fp16.mlmodelc") }
    public static var vocab: URL { root.appending(path: "model/vocab.txt") }
}

public final class Embedder: @unchecked Sendable {
    public enum Use: Sendable { case query, indexing }
    public let identity = ModelIdentity.current
    public let tokenizer: WordPiece
    private let model: MLModel
    public static let maxTokens = 512

    /// Queries run on the CPU: no accelerator caches, nothing written, exact numerics inside
    /// Claude's sandbox (F-35). Indexing runs on the GPU. Never `.all` (MPS cache writes, F-35).
    public init(modelAt url: URL = SearchPaths.compiledModel, vocab: URL = SearchPaths.vocab, use: Use) throws {
        tokenizer = try WordPiece(vocabFile: vocab)
        let config = MLModelConfiguration()
        config.computeUnits = use == .query ? .cpuOnly : .cpuAndGPU
        model = try MLModel(contentsOf: url, configuration: config)
    }

    /// Compiles the shipped `.mlpackage` into Duo's folder (app only: it writes to the temp
    /// folder, which the sandboxed CLI can't). Returns the compiled model's location.
    public static func install(package: URL, vocab: URL) async throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: SearchPaths.compiledModel.deletingLastPathComponent(), withIntermediateDirectories: true)
        let compiled = try await MLModel.compileModel(at: package)
        try? fm.removeItem(at: SearchPaths.compiledModel)
        try fm.moveItem(at: compiled, to: SearchPaths.compiledModel)
        try? fm.removeItem(at: SearchPaths.vocab)
        try fm.copyItem(at: vocab, to: SearchPaths.vocab)
        return SearchPaths.compiledModel
    }

    public func embedQuery(_ text: String) throws -> [Float] {
        try embed([tokenizer.encode(identity.queryPrefix + text, maxLength: Self.maxTokens)])[0]
    }

    public func embedDocuments(_ texts: [String]) throws -> [[Float]] {
        let ids = texts.map { tokenizer.encode($0, maxLength: Self.maxTokens) }
        // Similar lengths together, so each batch pads little (as the POC does).
        let order = ids.indices.sorted { ids[$0].count > ids[$1].count }
        var out = [[Float]](repeating: [], count: texts.count)
        for start in stride(from: 0, to: order.count, by: 32) {
            let slice = Array(order[start..<min(start + 32, order.count)])
            for (i, v) in zip(slice, try embed(slice.map { ids[$0] })) { out[i] = v }
        }
        return out
    }

    private func embed(_ batch: [[Int32]]) throws -> [[Float]] {
        let n = batch.count, len = batch.map(\.count).max() ?? 1
        let shape = [NSNumber(value: n), NSNumber(value: len)]
        let ids = try MLMultiArray(shape: shape, dataType: .int32)
        let mask = try MLMultiArray(shape: shape, dataType: .int32)
        let idp = ids.dataPointer.bindMemory(to: Int32.self, capacity: n * len)
        let mp = mask.dataPointer.bindMemory(to: Int32.self, capacity: n * len)
        for (i, row) in batch.enumerated() {
            for j in 0..<len {
                idp[i * len + j] = j < row.count ? row[j] : 0
                mp[i * len + j] = j < row.count ? 1 : 0
            }
        }
        let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["input_ids": ids, "attention_mask": mask]))
        guard let e = out.featureValue(for: "embedding")?.multiArrayValue else { throw SearchError("model gave no embedding") }
        let d = identity.dimensions
        // The output may be fp32 with strides; read through the shaped API for safety.
        return (0..<n).map { i in (0..<d).map { j in e[[NSNumber(value: i), NSNumber(value: j)]].floatValue } }
    }
}

public struct SearchError: Error, CustomStringConvertible {
    public var description: String
    public init(_ d: String) { description = d }
}
