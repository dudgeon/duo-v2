import SwiftUI

// `/model` and `/effort` as cards (chat-slash-handoff `model-card`, `effort-card`; DL-143): docked in
// the composer's place like a review card, but bordered in `text`: you asked for it, and Claude isn't
// waiting on you. Every word in it is read off the TUI's screen; every key goes to the TUI after
// re-reading that the same picker is up. Nothing is chosen until ⏎, s or a button.

extension ChatPicker {
    /// The card's first word: what the screen is about.
    var subject: String {
        switch kind {
        case .model: "MODEL"
        case .effort: "EFFORT"
        case .confirm: title.lowercased().contains("effort") ? "EFFORT" : "MODEL"
        }
    }
}

struct ChatPickerCard: View {
    let chat: ChatSession
    let picker: ChatPicker

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(picker.subject).duoText(.sectionLabel).foregroundStyle(DuoColor.text)
                Text(picker.kind == .confirm ? "· " + picker.title.uppercased() : "· /" + picker.kind.rawValue.uppercased()).duoText(.sectionLabel).foregroundStyle(DuoColor.text2)
                Spacer(minLength: 8)
                if picker.kind != .effort {
                    Text(picker.kind == .confirm ? "Claude Code’s own question, answered with its keys" : "Claude Code’s own picker, answered with its keys")
                        .duoText(.control).foregroundStyle(DuoColor.text2).lineLimit(1)
                }
            }
            switch picker.kind {
            case .model: model
            case .effort: effort
            case .confirm: confirm
            }
        }
        // The board's 14/16 padding sits inside a 1.5 border that CSS draws outside it.
        .padding(EdgeInsets(top: 15.5, leading: 17.5, bottom: 15.5, trailing: 17.5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusReviewCard).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusReviewCard).strokeBorder(DuoColor.text, lineWidth: 1.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(picker.kind == .confirm ? picker.title : picker.kind == .model ? "Choose a model" : "Choose an effort level")
    }

    /// Switch model? / Change effort level? (DL-168): Claude Code's own words, its answers keyed by their numbers, none chosen.
    @ViewBuilder var confirm: some View {
        Text(picker.heading).duoText(.bodyEmphasis).foregroundStyle(DuoColor.text).fixedSize(horizontal: false, vertical: true)
        if !picker.description.isEmpty {
            Text(picker.description).duoText(.body).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true)
        }
        VStack(spacing: 5) {
            ForEach(picker.rows, id: \.n) { r in
                HStack(alignment: .top, spacing: 10) {
                    ChatKeyCap(n: r.n).padding(.top, 1)
                    Text(r.name).duoText(.body).foregroundStyle(DuoColor.text).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(EdgeInsets(top: 6, leading: 11, bottom: 6, trailing: 11))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody).fill(DuoColor.pane))
                .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody).strokeBorder(DuoColor.controlEdge, lineWidth: DuoMetric.borderHairline))
                .contentShape(Rectangle())
                .onActivate { Task { await chat.confirmAnswer(r.n) } }  // action: session chat
                .accessibilityLabel("\(r.n). \(r.name)")
            }
        }
        HStack(spacing: 6) {
            ChatKeyedButton(title: "Cancel", key: "esc") { Task { await chat.pickerFinish(.cancel) } }  // action: session chat
        }
    }

    @ViewBuilder var model: some View {
        if !picker.description.isEmpty {
            Text(picker.description).duoText(.body).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true)
        }
        VStack(spacing: 5) {
            ForEach(picker.rows, id: \.n) { r in
                HStack(alignment: .top, spacing: 10) {
                    ChatKeyCap(n: r.n).padding(.top, 1)
                    Text(r.name + (r.selected ? " ✔" : "")).duoText(.bodyEmphasis).foregroundStyle(DuoColor.text)
                        .frame(width: 150, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    Text(r.note).duoText(.body).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(EdgeInsets(top: 6, leading: 11, bottom: 6, trailing: 11))   // 5/10 inside a 1 pt border
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody).fill(r.cursor ? DuoColor.selected : DuoColor.pane))
                .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusChatStepBody)
                    .strokeBorder(r.cursor ? DuoColor.text : DuoColor.controlEdge, lineWidth: r.cursor ? 1.5 : DuoMetric.borderHairline))
                .contentShape(Rectangle())
                .onActivate { Task { await chat.pickerMove(to: r.n) } }  // action: session chat
                .accessibilityLabel("\(r.n). \(r.name)\(r.selected ? ", in use" : ""). \(r.note)")
                .accessibilityAddTraits(r.cursor ? .isSelected : [])
            }
        }
        ForEach(picker.footnotes, id: \.self) { Text($0).duoText(.control).foregroundStyle(DuoColor.text2) }
        HStack(spacing: 6) {
            ChatKeyedButton(title: "Set as Default", key: "⏎") { Task { await chat.pickerFinish(.confirm) } }  // action: session chat
            ChatKeyedButton(title: "This Session Only", key: "s") { Task { await chat.pickerFinish(.sessionOnly) } }  // action: session chat
            ChatKeyedButton(title: "Cancel", key: "esc") { Task { await chat.pickerFinish(.cancel) } }  // action: session chat
        }
    }

    @ViewBuilder var effort: some View {
        if let ends = picker.ends {
            HStack {
                Text(ends.0)
                Spacer()
                Text(ends.1)
            }
            .duoText(.control).foregroundStyle(DuoColor.text2)
        }
        HStack(spacing: 0) {
            ForEach(Array(picker.levels.enumerated()), id: \.offset) { i, l in
                if i > 0 { DuoColor.rule.frame(width: DuoMetric.borderHairline) }
                Text(l).duoText(.control, weight: i == picker.level ? .semibold : nil).foregroundStyle(DuoColor.text)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(i == picker.level ? DuoColor.selected : DuoColor.pane)
                    .contentShape(Rectangle())
                    .onActivate { Task { await chat.pickerLevel(to: i) } }  // action: session chat
                    .accessibilityLabel(l)
                    .accessibilityAddTraits(i == picker.level ? .isSelected : [])
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: DuoMetric.radiusControl))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).strokeBorder(DuoColor.controlEdge, lineWidth: DuoMetric.borderHairline))
        HStack(spacing: 6) {
            ChatKeyedButton(title: "Confirm", key: "⏎") { Task { await chat.pickerFinish(.confirm) } }  // action: session chat
            if picker.sessionOnly { ChatKeyedButton(title: "This Session Only", key: "s") { Task { await chat.pickerFinish(.sessionOnly) } } }  // action: session chat
            ChatKeyedButton(title: "Cancel", key: "esc") { Task { await chat.pickerFinish(.cancel) } }  // action: session chat
            Spacer(minLength: 8)
            Text("←/→ to adjust").duoText(.control).foregroundStyle(DuoColor.text2)
        }
    }
}
