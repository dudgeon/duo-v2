import CoreAudio
import DuoControl
import Foundation

// Duo knows at rest whether there is a microphone (voice-input-handoff `NoMic.dc.html`): it reads CoreAudio's default input
// device and listens for it changing, so the mics change look by themselves when AirPods, a USB mic or a Continuity mic
// connects, within a second, and when it goes away.

/// Where the device facts come from; replaceable in DuoChecks.
@MainActor public protocol VoiceDeviceSource: AnyObject {
    /// The default input device: its name, and whether it has input channels.
    func current() -> (name: String?, usable: Bool)
    /// `changed` runs (on the main actor) whenever the default input device, the device list or the default device's
    /// input streams change.
    func observe(_ changed: @escaping @MainActor () -> Void)
}

/// CoreAudio's own: a listener on the system object for the default input device and the device list, and one on the
/// default device's stream configuration, moved when the default does.
@MainActor public final class CoreAudioDeviceSource: VoiceDeviceSource {
    private var changed: (@MainActor () -> Void)?
    private var deviceListener: (id: AudioObjectID, block: AudioObjectPropertyListenerBlock)?
    private var systemBlocks: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    public init() {}

    public func current() -> (name: String?, usable: Bool) {
        let d = VoiceDevice.defaultInput()
        return (d.flatMap { Self.name(of: $0.id) }, VoiceDevice.usable(d))
    }

    public func observe(_ changed: @escaping @MainActor () -> Void) {
        self.changed = changed
        guard systemBlocks.isEmpty else { return }
        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
            var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.fire() }
            }
            AudioObjectAddPropertyListenerBlock(system, &addr, DispatchQueue.main, block)
            systemBlocks.append((addr, block))
        }
        watchDefaultDevice()
    }

    private func fire() {
        watchDefaultDevice()
        changed?()
    }

    /// The default device's input stream configuration changes (a device gaining or losing its input).
    private func watchDefaultDevice() {
        let id = VoiceDevice.defaultInput()?.id ?? AudioObjectID(kAudioObjectUnknown)
        if deviceListener?.id == id { return }
        if let old = deviceListener {
            var addr = Self.streams
            AudioObjectRemovePropertyListenerBlock(old.id, &addr, DispatchQueue.main, old.block)
            deviceListener = nil
        }
        guard id != kAudioObjectUnknown else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        var addr = Self.streams
        AudioObjectAddPropertyListenerBlock(id, &addr, DispatchQueue.main, block)
        deviceListener = (id, block)
    }

    private static var streams: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
    }

    /// The device's name (kAudioObjectPropertyName), "AirPods Pro" and the like.
    static func name(of id: AudioObjectID) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var cf: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cf) == noErr, let s = cf?.takeRetainedValue() else { return nil }
        return s as String
    }
}

/// What the mics look like with no microphone (NoMic.dc.html). `DUO_VOICE_NOMIC_STYLE=1|2|3` in an isolated Duo; otherwise 3,
/// today's behaviour, until Geoff chooses.
public enum VoiceNoMicStyle: Sendable {
    /// A slashed mic, dimmed, explained.
    case slashed
    /// Hidden until there is one.
    case hidden
    /// An ordinary mic; a press explains.
    case ordinary

    public static let current: VoiceNoMicStyle = {
        guard SupportFolder.isIsolated else { return .hidden }   // Geoff chose option 2 (DL-264)
        switch ProcessInfo.processInfo.environment["DUO_VOICE_NOMIC_STYLE"] { case "1": return .slashed; case "3": return .ordinary; default: return .hidden }
    }()

    public static let tooltip = "No microphone connected · connect one to dictate"
}
