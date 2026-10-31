@preconcurrency import AVFoundation
import CoreAudio
import DuoObjC
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
    /// The engine refused (an exception or error from AVAudioEngine); the text says what it was.
    case micFailed(String)
}

/// Whether the Mac has a microphone to listen to: a default input device with at least one input channel.
/// Read from CoreAudio before AVAudioEngine is touched, since AVAudioEngine raises (and takes the app down)
/// when there's none (F-447; a Mac mini with no microphone plugged in).
public enum VoiceDevice {
    /// The default input device and its input channel count, or nil when there's no device.
    public static func defaultInput() -> (id: AudioObjectID, channels: Int)? {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var bytes: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &bytes) == noErr, bytes > 0 else { return (id, 0) }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(bytes), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &streams, 0, nil, &bytes, raw) == noErr else { return (id, 0) }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return (id, list.reduce(0) { $0 + Int($1.mNumberChannels) })
    }

    /// The rule: a device with input channels. Separate from the lookup so DuoChecks can test it.
    public static func usable(_ input: (id: AudioObjectID, channels: Int)?) -> Bool {
        guard let input else { return false }
        return input.id != kAudioObjectUnknown && input.channels > 0
    }

    public static var hasMicrophone: Bool { usable(defaultInput()) }
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

    /// Every AVAudioEngine call that can raise runs inside DuoCatchException: an exception becomes an error,
    /// never a crash, whatever the device does (F-447).
    func start() throws {
        guard VoiceDevice.hasMicrophone else { throw VoiceAudioError.noMicrophone }
        let level = self.level, continuation = self.continuation
        var format: AVAudioFormat?
        var caught: NSError?
        let ok = DuoCatchException({
            let input = self.engine.inputNode
            let f = input.outputFormat(forBus: 0)
            guard f.sampleRate > 0, f.channelCount > 0 else { return }
            format = f
            input.installTap(onBus: 0, bufferSize: 4096, format: f) { buffer, _ in
                if let ch = buffer.floatChannelData?[0] {
                    var sum: Float = 0
                    let n = Int(buffer.frameLength)
                    for i in 0..<n { sum += ch[i] * ch[i] }
                    level(n > 0 ? min(1, (sum / Float(n)).squareRoot() * 6) : 0)
                }
                continuation.yield(VoiceBuffer(buffer: buffer))
            }
            self.tapped = true
            self.engine.prepare()
        }, &caught)
        guard ok else { stop(); throw VoiceAudioError.micFailed(caught?.localizedDescription ?? "unknown") }
        guard format != nil else { stop(); throw VoiceAudioError.noMicrophone }
        // A device that comes or goes (AirPods, an iPhone's Continuity mic, a USB mic) changes the engine's
        // configuration: the dictation stops with "the microphone went away" and keeps its words.
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.lost()
        }
        var startError: Error?
        let started = DuoCatchException({
            do { try self.engine.start() } catch { startError = error }
        }, &caught)
        guard started, startError == nil else {
            stop()
            throw VoiceAudioError.micFailed(startError.map { "\($0)" } ?? caught?.localizedDescription ?? "unknown")
        }
    }

    private var tapped = false

    func stop() {
        if let o = observer { NotificationCenter.default.removeObserver(o); observer = nil }
        _ = DuoCatchException({
            if self.tapped { self.engine.inputNode.removeTap(onBus: 0); self.tapped = false }
            self.engine.stop()
        }, nil)
        continuation.finish()
    }
}

/// A file read in order, as fast as the recognizer takes it; or, `realtime`, at the pace it was spoken, as a
/// microphone delivers it (live checks that act mid-dictation: switching modes, pressing Return or Esc).
enum FileFeed {
    static func stream(_ url: URL, realtime: Bool = false) throws -> (stream: AsyncStream<VoiceBuffer>, stop: @Sendable () -> Void) {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch { throw VoiceAudioError.unreadable(url.lastPathComponent) }
        let (stream, continuation) = AsyncStream<VoiceBuffer>.makeStream(bufferingPolicy: .unbounded)
        let format = file.processingFormat
        // Read here, off the caller's actor, then close the stream: the file is short or the recognizer waits.
        let reader = Task.detached {
            while file.framePosition < file.length, !Task.isCancelled {
                guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { break }
                do { try file.read(into: buf, frameCount: 4096) } catch { break }
                if buf.frameLength == 0 { break }
                continuation.yield(VoiceBuffer(buffer: buf))
                if realtime { try? await Task.sleep(nanoseconds: UInt64(Double(buf.frameLength) / format.sampleRate * 1_000_000_000)) }
            }
            if Task.isCancelled { return continuation.finish() }
            // Half a second of silence, so the last word is followed by a pause the recognizer can end on.
            if let tail = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate / 2)) {
                tail.frameLength = tail.frameCapacity
                continuation.yield(VoiceBuffer(buffer: tail))
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in reader.cancel() }
        return (stream, { reader.cancel(); continuation.finish() })
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
