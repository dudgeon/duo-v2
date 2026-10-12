import AVFoundation
import Foundation

// MARK: - Clock

@inline(__always) func nowNs() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
func msSince(_ t0: UInt64) -> Double { Double(nowNs() - t0) / 1_000_000 }

func logErr(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

// MARK: - Manifest / output

struct Clip {
    var id: String
    var wav: String
    var ref: String
}

func readManifest(_ path: String) throws -> [Clip] {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    var out: [Clip] = []
    for line in text.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
        guard let obj = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
            let id = obj["id"] as? String, let wav = obj["wav"] as? String
        else { continue }
        out.append(Clip(id: id, wav: wav, ref: obj["ref"] as? String ?? ""))
    }
    return out
}

func readTerms(_ path: String?) throws -> [String] {
    guard let path else { return [] }
    return try String(contentsOfFile: path, encoding: .utf8)
        .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

final class JsonlWriter {
    let handle: FileHandle
    init(path: String) throws {
        FileManager.default.createFile(atPath: path, contents: nil)
        handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    }
    func write(_ obj: [String: Any]) {
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes]) {
            handle.write(d)
            handle.write(Data("\n".utf8))
        }
    }
}

// MARK: - Audio (in memory only; nothing derived is written)

let fmt16k = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

/// Reads any wav and returns 16 kHz mono Float32 samples.
func loadSamples16k(_ path: String) throws -> [Float] {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let inFmt = file.processingFormat
    guard let inBuf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: AVAudioFrameCount(file.length)) else {
        throw BenchError("cannot allocate buffer for \(path)")
    }
    try file.read(into: inBuf)
    let out = try convert(inBuf, to: fmt16k)
    return Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
}

func convert(_ inBuf: AVAudioPCMBuffer, to outFmt: AVAudioFormat) throws -> AVAudioPCMBuffer {
    if inBuf.format == outFmt { return inBuf }
    guard let conv = AVAudioConverter(from: inBuf.format, to: outFmt) else { throw BenchError("no converter") }
    let ratio = outFmt.sampleRate / inBuf.format.sampleRate
    let cap = AVAudioFrameCount(Double(inBuf.frameLength) * ratio) + 4096
    guard let out = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: cap) else { throw BenchError("alloc") }
    var fed = false
    var err: NSError?
    let status = conv.convert(to: out, error: &err) { _, st in
        if fed {
            st.pointee = .endOfStream
            return nil
        }
        fed = true
        st.pointee = .haveData
        return inBuf
    }
    if status == .error { throw err ?? BenchError("convert failed") }
    return out
}

/// 16 kHz mono Float32 samples -> AVAudioPCMBuffer.
func makeBuffer16k(_ samples: ArraySlice<Float>) -> AVAudioPCMBuffer {
    let b = AVAudioPCMBuffer(pcmFormat: fmt16k, frameCapacity: AVAudioFrameCount(max(samples.count, 1)))!
    b.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { p in
        if let base = p.baseAddress { b.floatChannelData![0].update(from: base, count: samples.count) }
    }
    return b
}

/// Copy frames [start, start+n) of a mono non-interleaved buffer.
func sliceMono(_ b: AVAudioPCMBuffer, start: Int, count n: Int) -> AVAudioPCMBuffer {
    let out = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: AVAudioFrameCount(n))!
    out.frameLength = AVAudioFrameCount(n)
    let bpf = Int(b.format.streamDescription.pointee.mBytesPerFrame)
    let src = UnsafeMutableAudioBufferListPointer(b.mutableAudioBufferList)[0].mData!
    let dst = UnsafeMutableAudioBufferListPointer(out.mutableAudioBufferList)[0].mData!
    memcpy(dst, src + start * bpf, n * bpf)
    return out
}

struct BenchError: Error, CustomStringConvertible {
    var description: String
    init(_ d: String) { description = d }
}

// MARK: - Engine protocol

struct ClipResult {
    var hyp: String
    var procMs: Double
    var firstPartialMs: Double? = nil
    var finalMs: Double? = nil
    var partials: Int? = nil
}

protocol Engine {
    /// Loads (and downloads if necessary) the model.
    func load() async throws
    /// One whole clip, audio already in memory. proc_ms == final_ms.
    func batch(_ samples: [Float]) async throws -> ClipResult
    /// Real-time paced stream.
    func stream(_ samples: [Float], chunkMs: Int) async throws -> ClipResult
    var supportsStream: Bool { get }
}

extension Engine {
    var supportsStream: Bool { false }
    func stream(_ samples: [Float], chunkMs: Int) async throws -> ClipResult {
        throw BenchError("stream mode unsupported")
    }
}

func sleepUntil(_ t0: UInt64, ms: Double) async {
    let target = t0 + UInt64(ms * 1_000_000)
    let now = nowNs()
    if target > now { try? await Task.sleep(nanoseconds: target - now) }
}

/// Lock-protected stream state shared with result-collector tasks.
final class StreamState: @unchecked Sendable {
    private let lock = NSLock()
    private var _firstPartial: UInt64? = nil
    private var _partials = 0
    private var _finals: [String] = []
    private var _lastVolatile = ""
    func note(text: String, isFinal: Bool, t0: UInt64) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        if !t.isEmpty {
            if _firstPartial == nil { _firstPartial = nowNs() - t0 }
            _partials += 1
        }
        if isFinal {
            if !t.isEmpty { _finals.append(t) }
            _lastVolatile = ""
        } else {
            _lastVolatile = t
        }
    }
    var firstPartialMs: Double? {
        lock.lock()
        defer { lock.unlock() }
        return _firstPartial.map { Double($0) / 1e6 }
    }
    var partials: Int {
        lock.lock()
        defer { lock.unlock() }
        return _partials
    }
    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return _finals.joined(separator: " ")
    }
}

func squash(_ s: String) -> String {
    s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}
