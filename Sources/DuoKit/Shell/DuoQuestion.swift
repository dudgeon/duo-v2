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
        /// With a `what` and no `path`: the name in body type, this at the right in `text2` (DL-192).
        /// With a `what` and a `path`: the clash row of `standins2-handoff/q50-clash` (DL-132 c): `what` in mono,
        /// `path` under it in `text2` ("from ~/Downloads"), this at the right in `text2`.
        public var detail: String? = nil
        /// A caption over a mono value, as the trust question's box draws them (trust-notice-handoff `02`): `what` in `text2`,
        /// `path` under it in mono and `text`, wrapping rather than cutting.
        public var captioned = false
        /// With a `what` and a `path`: the path under it in body type and `text2`, not mono (the voice sheet's box).
        public var sub = false
    }
    /// A name to type, filled in with a suggestion (B of the .docx boards, DL-123). A class, so
    /// the choices read what was typed when they run.
    public final class Field {
        public let label: String
        public var text: String
        public init(label: String, text: String) { self.label = label; self.text = text }
    }
    /// A choice from a short list, as a popup (`Move it to [In progress ▾]`, task-board board 12).
    /// A class, so the choices read what was picked when they run.
    public final class Pick {
        public let label: String
        public let options: [(value: String, title: String)]
        public var selected: String
        public init(label: String, options: [(value: String, title: String)], selected: String) {
            self.label = label; self.options = options; self.selected = selected
        }
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
    /// The items' box scrolls past this height (Delete n Sessions…, DL-247: about five sessions).
    public var itemsMaxHeight: CGFloat? = nil
    public var field: Field? = nil
    public var pick: Pick? = nil
    public var note: String? = nil
    /// The note in `control` type (12/16), as the memory question draws it (park-handoff); others use body.
    public var noteIsSmall = false
    /// Lines under the first paragraph in a `WHAT’S NEW` box, up to 160 high, then it scrolls
    /// (the update question, DL-132 b).
    public var notes: [String] = []
    /// A report in mono in a `pane` box, up to 260 high, then it scrolls and can be selected (the chat-fallback Debug sheet, DL-234).
    public var report: String? = nil
    /// The cancel button sits apart at the left, as macOS sheets put the one that dismisses
    /// (the update question's Later, DL-132 b).
    public var leadingCancel = false
    public var choices: [Choice]
}

/// Brings Duo forward, unless this instance is isolated (C-28, F-113): a scripted instance with
/// its own support folder never takes the keyboard from the user's work, so a stray Return can't
/// answer its questions. Its windows still show, behind whatever has focus.
@MainActor public enum DuoFocus {
    public static func take() {
        guard !SupportFolder.isIsolated, !TestBackground.isOn else { return }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// A background test launch (F-227): an accessory app (no Dock icon, no menu bar) that never
    /// activates, with every window it shows transparent and click-through. Windows are still
    /// ordered in and drawn, so captures (drawn from the views, F-120), terminals, web views and
    /// the first responder work as on screen. Called before the app finishes launching.
    /// A test build is an accessory from its Info.plist (`LSUIElement`, scripts/bundle.sh); one that
    /// isn't a background launch (opened from Finder, or `DUO_TEST_FOREGROUND=1`) becomes a regular app.
    public static func startBackground() {
        let app = NSApplication.shared   // NSApp is still nil while the App initialises
        guard TestBackground.isOn else {
            if Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true { app.setActivationPolicy(.regular) }
            return
        }
        app.setActivationPolicy(.accessory)
        FileHandle.standardError.write(Data("Duo: background test launch (F-227): no Dock icon, windows drawn but not shown; \(TestBackground.foregroundVariable)=1 shows them\n".utf8))
        // Popovers, sheets and the Settings window are windows too: hide each as it appears.
        NotificationCenter.default.addObserver(forName: NSApplication.didUpdateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NSApp.windows.forEach(hide) }
        }
    }

    /// Makes a window invisible in a background launch; nothing otherwise.
    public static func hide(_ window: NSWindow) {
        guard TestBackground.isOn, window.alphaValue != 0 else { return }
        window.alphaValue = 0
        window.ignoresMouseEvents = true
    }
}

/// The queue of Duo's own questions. Static so the launch questions (install, legacy Duo,
/// .gitignore), which run outside the model, can ask too.
@MainActor @Observable public final class SheetCenter {
    public static let shared = SheetCenter()
    public private(set) var queue: [DuoQuestion] = []
    /// Bumped when a question's popup changes.
    public var pickRevision = 0
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

/// The update question's notes (DL-132 b, standins2-handoff q47-writable): `WHAT’S NEW` over the
/// release's lines in a `pane` box like the items', up to 160 high, then it scrolls (DL-249).
struct NotesBox: View {
    let lines: [String]
    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 4) {
                Text("WHAT’S NEW").duoText(.sectionLabel).foregroundStyle(DuoColor.text2)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                    Text(Self.attributed(l)).duoText(.body).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, DuoSpace.cardPadding.leading)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 160)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
        .accessibilityLabel("What’s new: " + lines.map(UpdateCheck.plainNote).joined(separator: " "))
    }

    /// A line with its Markdown links drawn as links, as chat draws a web link (text colour, solid
    /// underline); a click opens the address in the default browser.
    static func attributed(_ line: String) -> AttributedString {
        var out = AttributedString()
        var at = line.startIndex
        for l in UpdateCheck.noteLinks(line) {
            out += AttributedString(String(line[at..<l.range.lowerBound]))
            var a = AttributedString(l.text)
            a.link = l.url
            a.foregroundColor = DuoColor.text
            a.underlineStyle = Text.LineStyle(pattern: .solid, color: DuoColor.controlEdge)
            out += a
            at = l.range.upperBound
        }
        return out + AttributedString(String(line[at...]))
    }
}

/// A report in mono, scrollable, selectable (the chat-fallback Debug sheet, DL-234).
struct ReportBox: View {
    let text: String
    var body: some View {
        ScrollView(.vertical) {
            Text(text)
                .font(Font(NSFont.monospacedSystemFont(ofSize: DuoTextStyle.mono.spec.size, weight: .regular)))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DuoSpace.cardPadding.leading)
                .padding(.vertical, 10)
        }
        .frame(height: 260)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusCard).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
        .accessibilityLabel("Report")
    }
}

/// A question as a sheet (S3-3, S3-7): 460 wide on `ground`, open at the top, a title, its
/// paragraphs, a `pane` box listing what it changes with their paths, a `text2` note, the buttons.
struct QuestionSheet: View {
    let q: DuoQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: DuoSpace.gapCardToCard) {
            Text(q.title).duoText(.bodyEmphasis).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(q.paragraphs.enumerated()), id: \.offset) { n, p in
                Text(Self.rich(p)).duoText(.body).fixedSize(horizontal: false, vertical: true)
                if n == 0 && !q.notes.isEmpty { NotesBox(lines: q.notes) }
            }
            if let r = q.report { ReportBox(text: r) }
            if !q.items.isEmpty {
                // Clash rows (with a detail) sit 6 apart in their own padding, a rule between (q50-clash).
                let rowed = q.items.contains { !$0.what.isEmpty && !$0.path.isEmpty && $0.detail != nil }
                // Name rows (the memory question's tabs, DL-192) are 20-high lines with no gap (park-handoff).
                let named = q.items.contains { !$0.what.isEmpty && $0.path.isEmpty && $0.detail != nil }
                ScrollIfTaller(maxHeight: q.itemsMaxHeight) {
                VStack(alignment: .leading, spacing: rowed || named ? 0 : DuoSpace.gapGlyphToLabel) {
                    ForEach(Array(q.items.enumerated()), id: \.offset) { n, i in
                        if rowed && n > 0 { DuoColor.rule.frame(height: DuoMetric.borderHairline).padding(.horizontal, -DuoSpace.cardPadding.leading) }
                        if i.captioned {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(i.what).duoText(.body).foregroundStyle(DuoColor.text2)
                                Text(i.path).duoText(.mono, lineHeight: DuoTextStyle.body.spec.lineHeight).fixedSize(horizontal: false, vertical: true)
                            }
                        } else if i.what.isEmpty {
                            HStack(spacing: DuoSpace.gapCardToCard) {
                                Text(i.path).duoText(.mono, lineHeight: DuoTextStyle.body.spec.lineHeight)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 0)
                                if let d = i.detail { Text(d).duoText(.body).foregroundStyle(DuoColor.text2).fixedSize() }
                            }
                        } else if i.path.isEmpty, let d = i.detail {
                            // A name and, at the right in `text2`, what goes with it (the memory question's tabs, DL-192).
                            HStack(spacing: DuoSpace.gapCardToCard) {
                                Text(i.what).duoText(.body).lineLimit(1).truncationMode(.tail)
                                Spacer(minLength: 0)
                                Text(d).duoText(.body).foregroundStyle(DuoColor.text2).fixedSize()
                            }
                        } else if let d = i.detail {
                            HStack(alignment: .top, spacing: DuoSpace.gapCardToCard) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(i.what).duoText(.mono, lineHeight: DuoTextStyle.body.spec.lineHeight).lineLimit(1).truncationMode(.middle)
                                    Text(i.path).duoText(.body).foregroundStyle(DuoColor.text2).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer(minLength: 0)
                                Text(d).duoText(.body).foregroundStyle(DuoColor.text2).fixedSize()
                            }
                            .padding(.vertical, 6)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(i.what).duoText(.body).fixedSize(horizontal: false, vertical: true)
                                if !i.path.isEmpty {
                                    if i.sub {
                                        Text(i.path).duoText(.control).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                                    } else {
                                    Text(i.path).duoText(.mono, lineHeight: DuoTextStyle.body.spec.lineHeight).foregroundStyle(DuoColor.text2)
                                        .lineLimit(1).truncationMode(.middle)
                                    }
                                }
                            }
                            .padding(.vertical, i.sub ? 6 : 0)
                        }
                    }
                }
                .padding(.horizontal, DuoSpace.cardPadding.leading)
                .padding(.vertical, rowed ? 0 : named ? DuoSpace.gapGlyphToLabel : DuoSpace.gapRowItems)
                .frame(maxWidth: .infinity, alignment: .leading)
                }
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
            if let p = q.pick { PickRow(pick: p) }
            if let n = q.note {
                Text(Self.rich(n)).duoText(q.noteIsSmall ? .control : .body).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: DuoSpace.gapButtonToButton) {
                if !q.leadingCancel { Spacer(minLength: 0) }
                ForEach(Array(q.choices.enumerated()), id: \.offset) { n, c in
                    if q.leadingCancel && n == 1 { Spacer(minLength: 0) }
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

/// A question's popup: its label, then the options as a pop-up button.
struct PickRow: View {
    let pick: DuoQuestion.Pick

    var body: some View {
        let center = SheetCenter.shared
        let _ = center.pickRevision   // redrawn when the pick changes (the Pick is a class)
        HStack(spacing: 8) {
            Text(pick.label).duoText(.body)
            Picker("", selection: Binding(get: { pick.selected }, set: { pick.selected = $0; center.pickRevision += 1 })) {
                ForEach(pick.options, id: \.value) { o in Text(o.title).tag(o.value) }
            }
            .labelsHidden().pickerStyle(.menu).fixedSize()
            Spacer(minLength: 0)
        }
    }
}

/// Its content as it is, or in a scroll view of `maxHeight` when it's taller (the items' box, DL-247).
struct ScrollIfTaller<Content: View>: View {
    let maxHeight: CGFloat?
    @ViewBuilder let content: () -> Content

    var body: some View {
        if let maxHeight {
            ViewThatFits(in: .vertical) {
                content()
                ScrollView(.vertical) { content() }.frame(height: maxHeight)
            }
            .frame(maxHeight: maxHeight)
        } else {
            content()
        }
    }
}
