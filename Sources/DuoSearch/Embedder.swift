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
        if let r = Env.value("DUO_SEARCH_ROOT") { return URL(fileURLWithPath: r) }
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
    /// Indexing runs every batch at one of a few fixed shapes, each on a model of its own that never sees another shape
    /// (C-161, F-586, F-593, F-594). A loaded Core ML model on the GPU keeps memory each time its input shape changes
    /// between predictions: two shapes alternating with the same content grew 1.7 MB a call, and a busy indexer
    /// switching among shapes held 51 GB after three days; one shape held steady through 300 calls of varied text.
    /// A batch takes the cheapest shape that fits (2 × 128 at 4.5 ms a call, 32 × 512 at 81 ms), so small files stay
    /// cheap. Padded positions are masked, so the vectors are the same.
    public static let batchRows = 32
    public static let shapes: [(rows: Int, length: Int)] = [(2, 128), (2, 512), (8, 512), (32, 512)]
    public var fixedShapes: Bool
    private let url: URL
    private let config: MLModelConfiguration
    private var shapeModels: [Int: MLModel] = [:]
    private let lock = NSLock()   // one batch at a time per Embedder; shape models made under it

    /// Queries run on the CPU: no accelerator caches, nothing written, exact numerics inside
    /// Claude's sandbox (F-35). Indexing runs on the GPU. Never `.all` (MPS cache writes, F-35).
    public init(modelAt url: URL = SearchPaths.compiledModel, vocab: URL = SearchPaths.vocab, use: Use) throws {
        tokenizer = try WordPiece(vocabFile: vocab)
        let config = MLModelConfiguration()
        config.computeUnits = use == .query ? .cpuOnly : .cpuAndGPU
        model = try MLModel(contentsOf: url, configuration: config)
        self.url = url
        self.config = config
        fixedShapes = use == .indexing
        if fixedShapes, let big = Self.shapes.last { shapeModels[Self.key(big.rows, big.length)] = model }
    }

    /// How many models this embedder has loaded (one per shape it has run, for DuoChecks).
    public var modelCount: Int { lock.withLock { max(shapeModels.count, 1) } }

    static func key(_ rows: Int, _ length: Int) -> Int { rows << 16 | length }

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
        for start in stride(from: 0, to: order.count, by: Self.batchRows) {
            let slice = Array(order[start..<min(start + Self.batchRows, order.count)])
            for (i, v) in zip(slice, try embed(slice.map { ids[$0] })) { out[i] = v }
        }
        return out
    }

    /// The (rows, length) a batch is run at: its own with `fixedShapes` off, else the cheapest fixed shape that fits.
    static func shape(rows: Int, longest: Int, fixed: Bool) -> (rows: Int, length: Int) {
        guard fixed else { return (rows, max(longest, 1)) }
        return shapes.first { $0.rows >= rows && $0.length >= longest } ?? (max(rows, batchRows), max(longest, maxTokens))
    }

    private func embed(_ texts: [[Int32]]) throws -> [[Float]] {
        guard let first = texts.first else { return [] }
        let (n, len) = Self.shape(rows: texts.count, longest: texts.map(\.count).max() ?? 1, fixed: fixedShapes)
        // Extra rows repeat the first text (a row with no unmasked token isn't a valid input); their vectors are dropped.
        let batch = texts + Array(repeating: first, count: n - texts.count)
        lock.lock(); defer { lock.unlock() }
        let runner: MLModel
        if fixedShapes {
            if let m = shapeModels[Self.key(n, len)] { runner = m } else {
                runner = try MLModel(contentsOf: url, configuration: config)
                shapeModels[Self.key(n, len)] = runner
            }
        } else { runner = model }
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
        let out = try runner.prediction(from: MLDictionaryFeatureProvider(dictionary: ["input_ids": ids, "attention_mask": mask]))
        guard let e = out.featureValue(for: "embedding")?.multiArrayValue else { throw SearchError("model gave no embedding") }
        let d = identity.dimensions
        // The output may be fp32 with strides; read through the shaped API for safety.
        return (0..<texts.count).map { i in (0..<d).map { j in e[[NSNumber(value: i), NSNumber(value: j)]].floatValue } }
    }
}

/// An indexing embedder that loads when a pass first has something to embed and goes after it has sat
/// idle: the Core ML model, its buffers and the tokenizer's tables are tens of MB the app needn't
/// hold between bursts of editing (C-79).
public final class EmbedderSource: @unchecked Sendable {
    private let lock = NSLock()
    private let make: () throws -> Embedder
    private var current: Embedder?
    private var used = Date.distantPast
    /// How many times the model was loaded (for DuoChecks).
    public private(set) var loads = 0
    /// How much the process's footprint may grow while one model is loaded before it's let go and loaded afresh
    /// (F-593, F-594). Core ML's GPU memory for a loaded model grows with every prediction, and only releasing the model
    /// returns it. Counting calls (F-593's `maxUses`) reloaded hundreds of times in a bulk pass of small batches; a
    /// budget on the growth itself reloads only when memory has actually piled up. nil: never.
    public var memoryBudget: UInt64?
    private var baseline: UInt64 = 0

    /// This process's physical footprint (what Activity Monitor's Memory and footprint(1) report, GPU memory included).
    public static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? info.phys_footprint : 0
    }

    public init(load: @escaping () throws -> Embedder) { make = load }

    /// Loads the tokenizer by itself (the vocabulary file), so chunking a file that needs no new vectors doesn't load the
    /// Core ML model (F-599: an idle pass that re-read one changed transcript loaded the model just to tokenize it).
    public var tokenizerLoad: (() throws -> WordPiece)?
    private var tokenizerKept: WordPiece?
    public func tokenizer() throws -> WordPiece {
        lock.lock()
        if let c = current { lock.unlock(); return c.tokenizer }
        if let t = tokenizerKept { lock.unlock(); return t }
        let load = tokenizerLoad
        lock.unlock()
        guard let load else { return try get().tokenizer }
        let t = try load()
        lock.lock(); tokenizerKept = t; lock.unlock()
        return t
    }
    /// A fixed embedder, never released.
    public init(_ fixed: Embedder) { current = fixed; make = { fixed } }

    public var isLoaded: Bool { lock.lock(); defer { lock.unlock() }; return current != nil }

    public func get() throws -> Embedder {
        lock.lock(); defer { lock.unlock() }
        used = Date()
        if current != nil, let budget = memoryBudget, Self.footprint() > baseline + budget { current = nil }
        if let current { return current }
        let e = try make()
        current = e; loads += 1
        baseline = Self.footprint()
        return e
    }

    /// Lets the model go when it hasn't been used for `seconds`. True if it went.
    @discardableResult public func releaseIfIdle(after seconds: TimeInterval, now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard current != nil, now.timeIntervalSince(used) >= seconds else { return false }
        // A fixed embedder (made by `init(_:)`) comes straight back from `make`, so this only drops the reference.
        current = nil
        return true
    }
}

/// The one query embedder (C-79, task 7): loaded on the first semantic query, shared by every
/// query after it (search's field, the List's filter), and dropped by `release()` when search
/// has been quiet. Typing 30 characters loads the Core ML model once, not 30 times.
public enum QueryEmbedder {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: Embedder?
    /// How many times the model was loaded (DuoChecks reads it).
    nonisolated(unsafe) public private(set) static var loads = 0
    nonisolated(unsafe) private static var used = Date.distantPast

    public static func shared() throws -> Embedder {
        lock.lock(); defer { lock.unlock() }
        used = Date()
        if let cached { return cached }
        let e = try Embedder(use: .query)
        cached = e
        loads += 1
        return e
    }

    /// Drops the model once no query has used it for `seconds` (the app's idle release, C-79). True if it went.
    @discardableResult public static func releaseIfIdle(after seconds: TimeInterval, now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard cached != nil, now.timeIntervalSince(used) >= seconds else { return false }
        cached = nil
        return true
    }

    /// Drops the model's memory; the next query loads it again.
    public static func release() {
        lock.lock(); defer { lock.unlock() }
        cached = nil
    }
}

public struct SearchError: Error, CustomStringConvertible {
    public var description: String
    public init(_ d: String) { description = d }
}
