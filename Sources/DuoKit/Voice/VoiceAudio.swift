@preconcurrency import AVFoundation
import Foundation

// Audio sources for voice input (DL-260): the microphone through AVAudioEngine and a file, both as a
// stream of PCM buffers the recognizer consumes. Audio is never written to disk.

/// AVAudioPCMBuffer isn't Sendable; each buffer is handed on once and never touched again.
struct VoiceBuffer: @unchecked Sendable { let buffer: AVAudioPCMBuffer }

public enum VoiceAudioSource: Sendable, Equatable {
    case microphone
    case file(URL)
}

enum VoiceAudioError: Error, Equatable {
    case noMicrophone
    case unreadable(String)
}

/// The microphone: taps the input node, reports a smoothed level, ends its stream when the device goes away.
final class MicCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var observer: NSObjectProtocol?
    let stream: AsyncStream<VoiceBuffer>
    private let continuation: AsyncStream<VoiceBuffer>.Continuation
    private let level: @Sendable (Float) -> Void
    private let lost: @Sendable () -> Void

    init(level: @escaping @Sendable (Float) -> Void, lost: @escaping @Sendable () -> Void) {
        (stream, continuation) = AsyncStream<VoiceBuffer>.makeStream(bufferingPolicy: .unbounded)
        self.level = level
        self.lost = lost
    }

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw VoiceAudioError.noMicrophone }
        let level = self.level, continuation = self.continuation
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            if let ch = buffer.floatChannelData?[0] {
                var sum: Float = 0
                let n = Int(buffer.frameLength)
                for i in 0..<n { sum += ch[i] * ch[i] }
                level(n > 0 ? min(1, (sum / Float(n)).squareRoot() * 6) : 0)
            }
            continuation.yield(VoiceBuffer(buffer: buffer))
        }
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.lost()
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        if let o = observer { NotificationCenter.default.removeObserver(o); observer = nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation.finish()
    }
}

/// A file read in order, as fast as the recognizer takes it.
enum FileFeed {
    static func stream(_ url: URL) throws -> AsyncStream<VoiceBuffer> {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch { throw VoiceAudioError.unreadable(url.lastPathComponent) }
        let (stream, continuation) = AsyncStream<VoiceBuffer>.makeStream(bufferingPolicy: .unbounded)
        let format = file.processingFormat
        // Read here, off the caller's actor, then close the stream: the file is short or the recognizer waits.
        Task.detached {
            while file.framePosition < file.length {
                guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { break }
                do { try file.read(into: buf, frameCount: 4096) } catch { break }
                if buf.frameLength == 0 { break }
                continuation.yield(VoiceBuffer(buffer: buf))
            }
            // Half a second of silence, so the last word is followed by a pause the recognizer can end on.
            if let tail = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate / 2)) {
                tail.frameLength = tail.frameCapacity
                continuation.yield(VoiceBuffer(buffer: tail))
            }
            continuation.finish()
        }
        return stream
    }
}

/// Converts buffers to the format the recognizer wants.
final class VoiceConverter: @unchecked Sendable {
    private var converter: AVAudioConverter?
    private let target: AVAudioFormat
    init(to target: AVAudioFormat) { self.target = target }

    func convert(_ b: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if b.format == target { return b }
        if converter == nil || converter?.inputFormat != b.format { converter = AVAudioConverter(from: b.format, to: target) }
        guard let converter else { return nil }
        let cap = AVAudioFrameCount(Double(b.frameLength) * target.sampleRate / b.format.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else { return nil }
        nonisolated(unsafe) var fed = false
        nonisolated(unsafe) let input = b
        var err: NSError?
        let status = converter.convert(to: out, error: &err) { _, statusOut in
            if fed { statusOut.pointee = .noDataNow; return nil }
            fed = true; statusOut.pointee = .haveData; return input
        }
        return status == .error || out.frameLength == 0 ? nil : out
    }
}
