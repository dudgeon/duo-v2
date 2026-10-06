import AppKit
import DuoControl
import Observation
import SwiftUI

/// A question Duo asks on its own sheet (slice 3, S3-3 and S3-7; DL-101), never a system alert,
/// so a scripted run can't block on one (F-54). One at a time: the rest wait in the queue.
public struct DuoQuestion: Identifiable {
    public struct Item {
        public var what: String
        public var path: String
        /// With no `what`: the path alone in `text`, this at its right in `text2` ("edited 2d ago").
        public var detail: String? = nil
    }
    /// A name to type, filled in with a suggestion (B of the .docx boards, DL-123). A class, so
    /// the choices read what was typed when they run.
    public final class Field {
        public let label: String
        public var text: String
        public init(label: String, text: String) { self.label = label; self.text = text }
    }
    public struct Choice {
        public var label: String
        public var isDefault = false
        /// Escape picks it.
        public var isCancel = false
        public var action: @MainActor () -> Void
    }
    public let id = UUID()
    public var title: String
    /// Paragraphs; `text` in backticks is set in mono.
    public var paragraphs: [String] = []
    /// What it changes, each with its path, in a box (launch questions, merges, deletes).
    public var items: [Item] = []
    public var field: Field? = nil
    public var note: String? = nil
    public var choices: [Choice]
}

/// Brings Duo forward, unless this instance is isolated (C-28, F-113): a scripted instance with
/// its own support folder never takes the keyboard from the user's work, so a stray Return can't
/// answer its questions. Its windows still show, behind whatever has focus.
@MainActor public enum DuoFocus {
    public static func take() {
        guard !SupportFolder.isIsolated else { return }
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// The queue of Duo's own questions. Static so the launch questions (install, legacy Duo,
/// .gitignore), which run outside the model, can ask too.
@MainActor @Observable public final class SheetCenter {
    public static let shared = SheetCenter()
    public private(set) var queue: [DuoQuestion] = []
    public var current: DuoQuestion? { queue.first }

    public func ask(_ q: DuoQuestion) {
        queue.append(q)
        DuoFocus.take()
    }

    /// Takes the current question off the queue, then runs the choice (which may ask another).
    public func answer(_ choice: DuoQuestion.Choice) {
        if !queue.isEmpty { queue.removeFirst() }
        choice.action()
    }

    public func cancelCurrent() {
        guard let q = current, let c = q.choices.first(where: \.isCancel) else { return }
        answer(c)
    }
}

/// A question as a sheet (S3-3, S3-7): 460 wide on `ground`, open at the top, a title, its
/// paragraphs, a `pane` box listing what it changes with their paths, a `text2` note, the buttons.
struct QuestionSheet: View {
    let q: DuoQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: DuoSpace.gapCardToCard) {
            Text(q.title).duoText(.bodyEmphasis).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(q.paragraphs.enumerated()), id: \.offset) { _, p in
                Text(Self.rich(p)).duoText(.body).fixedSize(horizontal: false, vertical: true)
            }
            if !q.items.isEmpty {
                VStack(alignment: .leading, spacing: DuoSpace.gapGlyphToLabel) {
                    ForEach(Array(q.items.enumerated()), id: \.offset) { _, i in
                        if i.what.isEmpty {
                            HStack(spacing: DuoSpace.gapCardToCard) {
                                Text(i.path).duoText(.mono, lineHeight: DuoTextStyle.body.spec.lineHeight)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 0)
                                if let d = i.detail { Text(d).duoText(.body).foregroundStyle(DuoColor.text2).fixedSize() }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(i.what).duoText(.body).fixedSize(horizontal: false, vertical: true)
                                if !i.path.isEmpty {
                                    Text(i.path).duoText(.mono, lineHeight: DuoTextStyle.body.spec.lineHeight).foregroundStyle(DuoColor.text2)
                                        .lineLimit(1).truncationMode(.middle)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, DuoSpace.cardPadding.leading)
                .padding(.vertical, DuoSpace.gapRowItems)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).fill(DuoColor.pane))
                .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
            }
            if let f = q.field {
                SheetRow(f.label, center: true) {
                    SheetField(text: f.text, focus: true,
                               submit: { if let c = q.choices.first(where: \.isDefault) { SheetCenter.shared.answer(c) } },
                               cancel: { SheetCenter.shared.cancelCurrent() },
                               changed: { f.text = $0 })
                }
            }
            if let n = q.note {
                Text(Self.rich(n)).duoText(.body).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: DuoSpace.gapButtonToButton) {
                Spacer(minLength: 0)
                ForEach(Array(q.choices.enumerated()), id: \.offset) { _, c in
                    if c.isDefault {
                        Button(action: { SheetCenter.shared.answer(c) }) { Text(c.label) }   // not an action: the user's answer to Duo's question
                            .buttonStyle(DefaultSheetButtonStyle()).keyboardShortcut(.defaultAction)
                    } else if c.isCancel {
                        Button(action: { SheetCenter.shared.answer(c) }) { Text(c.label) }   // not an action: the user's answer to Duo's question
                            .buttonStyle(.duo).keyboardShortcut(.cancelAction)
                    } else {
                        Button(action: { SheetCenter.shared.answer(c) }) { Text(c.label) }   // not an action: the user's answer to Duo's question
                            .buttonStyle(.duo)
                    }
                }
            }
            .padding(.top, 6)
        }
        .foregroundStyle(DuoColor.text)
        .padding(DuoMetric.sheetPadding)
        .frame(width: DuoMetric.sheetMoveWidth - 2 * DuoMetric.borderHairline, alignment: .leading)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: DuoMetric.radiusPopover, bottomTrailingRadius: DuoMetric.radiusPopover).fill(DuoColor.ground))
        .padding([.horizontal, .bottom], DuoMetric.borderHairline)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: DuoMetric.radiusPopover, bottomTrailingRadius: DuoMetric.radiusPopover).fill(DuoColor.rule))
        .compositingGroup()
        .duoPopoverShadow()
        .onExitCommand { SheetCenter.shared.cancelCurrent() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(q.title)
    }

    /// `code` in backticks set in mono.
    static func rich(_ s: String) -> AttributedString {
        var out = AttributedString()
        for (i, part) in s.split(separator: "`", omittingEmptySubsequences: false).enumerated() {
            var a = AttributedString(String(part))
            if i % 2 == 1 { a.font = Font(NSFont.monospacedSystemFont(ofSize: DuoTextStyle.mono.spec.size, weight: .regular)) }
            out += a
        }
        return out
    }
}
