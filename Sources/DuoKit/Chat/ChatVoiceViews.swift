import AppKit
import SwiftUI

// Voice input in chat (voice-input-handoff `composer`, DL-261): the mic inside the field at its trailing end, and the
// hint row's lines while it listens. Listening is shown in ink (`text`), never the needs-you accent and never red.

/// The 30 pt circle in the field, bottom-aligned. At rest `text2` on nothing; under the pointer `selected`; listening
/// `text` with a `pane` glyph; dashed `rule` while the speech model downloads or when a profile blocks it.
struct ChatMicButton: View {
    @Environment(AppModel.self) private var model
    let chat: ChatSession

    var body: some View {
        let voice = model.voice
        let mine = voice.target == .chat(chat.key)
        let state = mine ? voice.state : .idle
        let listening = state == .listening
        let dashed: Bool = { if case .preparing = state { return true }; return state == .restricted }()
        // With no microphone (NoMic.dc.html): 1, slashed and dimmed, explained; 2, gone until there is one; 3, as ever.
        let none = !voice.microphoneAvailable && !state.isActive
        let slashed = none && VoiceNoMicStyle.current == .slashed
        let hover = chat.ui.hoverChip == "mic" && !listening && !slashed
        Group {
        if none && VoiceNoMicStyle.current == .hidden {
            Color.clear.frame(width: 0, height: 0)
        } else {
        ZStack {
            Circle().fill(listening ? DuoColor.text : hover ? DuoColor.selected : Color.clear)
            if dashed {
                Circle().strokeBorder(DuoColor.rule, style: StrokeStyle(lineWidth: DuoMetric.borderHairline, dash: DuoShadow.dashPattern))
            }
            if listening {
                // DL-272: the terminal's level bars in chat too, in place of the mic, `pane` on the `text` circle.
                VoiceBars(levels: voice.levels, color: DuoColor.pane)
            } else {
                Image(systemName: slashed ? "mic.slash" : "mic")
                    .font(.system(size: DuoSymbolSize.toolbarIcon, weight: .regular))
                    .foregroundStyle(slashed ? DuoColor.controlEdge : hover ? DuoColor.text : DuoColor.text2)
            }
        }
        .frame(width: ChatMicButton.diameter, height: ChatMicButton.diameter)
        .contentShape(Circle())
        .onHover { inside in
            if inside { chat.ui.hoverChip = "mic" } else if chat.ui.hoverChip == "mic" { chat.ui.hoverChip = nil }
        }
        .onActivate { model.toggleVoice(.chat(chat.key)) }  // action: voice start
        .help(slashed ? VoiceNoMicStyle.tooltip : VoiceCopy.tooltip)
        .accessibilityLabel(slashed ? VoiceNoMicStyle.tooltip : listening ? "Stop voice input" : "Voice input")
        .accessibilityIdentifier("voice.mic")
        }
        }
        .transition(.opacity)
        .animation(MotionSettings.shared.reduce ? nil : .easeOut(duration: 0.15), value: voice.microphoneAvailable)
    }

    static let diameter: CGFloat = 30
    /// What the field gives up at its right: the mic, 8 each side, less the text's own 14 inset; nothing while option 2 hides it.
    static let reserved: CGFloat = 32
    @MainActor static func reserved(for voice: VoiceInput) -> CGFloat {
        !voice.microphoneAvailable && VoiceNoMicStyle.current == .hidden ? 0 : reserved
    }
}

/// The hint row while voice input is on: the level meter and its keys, the model download, or a line saying why not.
struct ChatVoiceLine: View {
    let voice: VoiceInput

    /// Whether voice input has taken the hint row.
    static func shows(_ state: VoiceState) -> Bool {
        switch state {
        case .idle, .asking, .restricted: false
        default: true
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            switch voice.state {
            case .listening:
                // DL-272: the mic's bars say it's listening; the hint row keeps only the keys.
                if voice.holding {
                    Text("Let go of ⇧⌘D to finish").duoText(.chatMeta).foregroundStyle(DuoColor.text2)
                } else {
                    Text(voice.target.map { if case .chat = $0 { "⇧⌘D or the mic finishes · esc discards" } else { "⇧⌘D finishes" } } ?? "")
                        .duoText(.chatMeta).foregroundStyle(DuoColor.text2)
                }
            case .finishing:
                Ring()
                Text("Finishing…").duoText(.chatMeta).foregroundStyle(DuoColor.text2)
            case .preparing(let p):
                Ring()
                Text(VoiceCopy.line(.preparing(progress: p))).duoText(.chatMeta).foregroundStyle(DuoColor.text)
                Text("· once per Mac").duoText(.chatMeta).foregroundStyle(DuoColor.text2)
            case .denied:
                Text(VoiceCopy.denied).duoText(.chatMeta).foregroundStyle(DuoColor.text)
                Text("Open Privacy Settings").duoText(.chatMeta).foregroundStyle(DuoColor.text2)
                    .padding(.horizontal, 8)
                    .overlay(Capsule().strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
                    .contentShape(Capsule())
                    .onActivate { VoicePrivacy.openMicrophoneSettings() }  // not an action: opens System Settings for a person at the screen
                    .accessibilityLabel("Open Privacy Settings")
            case .unavailable(let w), .failed(let w):
                Text(w).duoText(.chatMeta).foregroundStyle(DuoColor.text)
                if let a = VoiceCopy.aside(for: voice.state) { Text(a).duoText(.chatMeta).foregroundStyle(DuoColor.text2) }
            default:
                EmptyView()
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// The terminal mic's three level bars (DL-271), for chat's mic while it listens (DL-272): 2 wide, 2 apart, centred,
/// each 2 pt (quiet, a dot) to 12 pt (loud), from `VoiceInput.barHeights`.
struct VoiceBars: View {
    let levels: [Double]
    let color: Color
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(VoiceInput.barHeights(levels, still: MotionSettings.shared.reduce).enumerated()), id: \.offset) { _, h in
                RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2, height: 2 + 10 * h)
            }
        }
        .frame(height: 12)
    }
}

/// The working ring, still.
struct Ring: View {
    var body: some View {
        Circle().strokeBorder(DuoColor.text, lineWidth: 1.5).frame(width: 10, height: 10)
    }
}

/// A boxed one-line notice, as a tooltip is drawn (the restricted line under the field; the terminal's question notice).
struct VoiceNoticeBox: View {
    let text: String
    var body: some View {
        Text(text).duoText(.chatMeta).foregroundStyle(DuoColor.text)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: DuoMetric.radiusPlaceholderBar).fill(DuoColor.pane))
            .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusPlaceholderBar).strokeBorder(DuoColor.controlEdge, lineWidth: DuoMetric.borderHairline))
    }
}

enum VoicePrivacy {
    static func openMicrophoneSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") { NSWorkspace.shared.open(u) }
    }
}
