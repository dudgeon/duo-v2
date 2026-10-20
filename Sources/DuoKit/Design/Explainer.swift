import AppKit
import Observation
import SwiftUI

// The Explainer (DL-172, explanatory-tooltips-handoff `02`–`04`): the second tier after a plain
// help tag, for a feature a new user won't guess. A popover Duo draws, with a picture made of Duo's
// own parts. Tasks has the first one. App state is an @Observable class, never view state (DL-30).

/// What the one Explainer at a time holds: whether it is open, where, and the hover clocks.
@MainActor @Observable public final class ExplainerState {
    /// The root view's coordinate space, which trigger and popover frames are measured in.
    static let space = "duoRoot"
    /// A still pointer on the trigger for this long after the help tag (about 1 s) opens it.
    static let dwell: Duration = .milliseconds(2500)
    /// It closes this long after the pointer has left both the trigger and the popover.
    static let leaveGrace: Duration = .milliseconds(300)

    public private(set) var open: ExplainerID?
    public private(set) var anchor: CGRect = .zero
    public private(set) var origin: CGFloat = 0
    public var height: CGFloat = 0
    /// The popover's frame in the window, for ignoring clicks inside it.
    @ObservationIgnored var overCard = false
    @ObservationIgnored var overTrigger = false
    @ObservationIgnored var pinned = false
    /// Where the keyboard was when a keyboard-opened Explainer took focus; Esc gives it back.
    @ObservationIgnored var previousResponder: NSResponder?
    /// Registered trigger frames by key (a plain table: drawing never reads it).
    @ObservationIgnored var frames: [String: CGRect] = [:]
    @ObservationIgnored var dwellTask: Task<Void, Never>?
    @ObservationIgnored var closeTask: Task<Void, Never>?
    @ObservationIgnored var monitors: [Any] = []
    @ObservationIgnored var observers: [NSObjectProtocol] = []
    /// Whether something else is on screen that an Explainer must not cover (a sheet, search, a menu).
    @ObservationIgnored var blocked: () -> Bool = { false }

    public init() {}

    static func dismissedKey(_ id: ExplainerID) -> String { id.rawValue }

    func isDismissed(_ id: ExplainerID) -> Bool { DuoState.load().dismissedExplainers.contains(Self.dismissedKey(id)) }

    /// The pointer moved on a trigger: a move resets the clock; a popover already open stays.
    func moved(_ id: ExplainerID, key: String, origin originKey: String) {
        overTrigger = true
        closeTask?.cancel()
        guard open == nil else { return }
        guard !isDismissed(id) else { return }
        dwellTask?.cancel()
        dwellTask = Task { @MainActor in
            try? await Task.sleep(for: Self.dwell)
            guard !Task.isCancelled, self.overTrigger, !self.blocked() else { return }
            self.show(id, key: key, origin: originKey, pinned: false)
        }
    }

    func left() {
        overTrigger = false
        dwellTask?.cancel()
        scheduleClose()
    }

    func cardHover(_ inside: Bool) {
        overCard = inside
        if inside { closeTask?.cancel() } else { scheduleClose() }
    }

    private func scheduleClose() {
        guard open != nil, !pinned else { return }
        closeTask?.cancel()
        closeTask = Task { @MainActor in
            try? await Task.sleep(for: Self.leaveGrace)
            guard !Task.isCancelled, !self.overTrigger, !self.overCard else { return }
            self.close()
        }
    }

    /// Opens it at a registered trigger. `pinned` (Help › Explain Tasks, VoiceOver's Explain): it stays until Esc, a click or typing.
    @discardableResult
    func show(_ id: ExplainerID, key: String, origin originKey: String, pinned: Bool) -> Bool {
        guard let frame = frames[key] else { return false }
        dwellTask?.cancel(); closeTask?.cancel()
        anchor = frame
        origin = frames[originKey]?.minX ?? frame.minX
        self.pinned = pinned
        previousResponder = pinned ? NSApp.keyWindow?.firstResponder : nil
        height = 0
        withDuoAnimation(.scrimIn) { open = id }
        installMonitors()
        return true
    }

    func close() {
        dwellTask?.cancel(); closeTask?.cancel()
        guard open != nil else { return }
        withDuoAnimation(.scrimOut) { open = nil }
        overCard = false
        if pinned, let r = previousResponder { NSApp.keyWindow?.makeFirstResponder(r) }
        pinned = false; previousResponder = nil
        removeMonitors()
    }

    /// Don't show again: closes it, and hover shows only the help tag from now on.
    func dismissForGood(_ id: ExplainerID) {
        DuoState.update { if !$0.dismissedExplainers.contains(Self.dismissedKey(id)) { $0.dismissedExplainers.append(Self.dismissedKey(id)) } }
        close()
        SettingsInfo.shared.revision += 1
    }

    /// Settings › General › Show dismissed explanations again.
    func resetDismissed() {
        DuoState.update { $0.dismissedExplainers = [] }
        SettingsInfo.shared.revision += 1
    }

    // MARK: Dismissal (WCAG 1.4.13): Esc, any click, typing, scrolling, the window losing focus

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, self.open != nil else { return event }
            switch event.type {
            case .keyDown:
                // Return, Space and Tab belong to the focused Don't show again (a keyboard-opened Explainer).
                if self.pinned, [36, 49, 76, 48].contains(event.keyCode) { return event }
                self.close()
                return event.keyCode == 53 ? nil : event   // Esc is ours; typing goes on
            case .leftMouseDown, .rightMouseDown:
                if !self.overCard { self.close() }   // a click on the popover's own button does its action first
            default:
                self.close()
            }
            return event
        } as Any)
        for name in [NSApplication.didResignActiveNotification, NSWindow.didResignKeyNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            })
        }
    }

    private func removeMonitors() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
    }
}

/// Which feature an Explainer is for. Tasks only for now (DL-172 (4)).
public enum ExplainerID: String, Sendable { case tasks }

/// What an Explainer is made of: the feature's noun, a line, a picture, two or three points.
struct ExplainerContent {
    struct Point { let lead: String; let rest: String }
    let title: String
    let line: String
    let points: [Point]
    /// The user guide page; nil until it exists, and then no Learn more is shown (Q-177).
    let learnMore: URL?

    /// What VoiceOver reads for Explain: the title, the line and the points.
    var spoken: String { ([title + ".", line] + points.map { "\($0.lead) \($0.rest)" }).joined(separator: " ") }

    static let tasks = ExplainerContent(
        title: "Tasks", line: "Track the work in this project.",
        points: [.init(lead: "A to-do.", rest: "Check it off when it’s done."),
                 .init(lead: "Detail and context,", rest: "if you want them. Claude reads them."),
                 .init(lead: "Files and Claude Code sessions,", rest: "attached, so the work stays together.")],
        learnMore: nil)
}

// MARK: - Trigger

extension View {
    /// Makes this view an Explainer's trigger: a still pointer for the dwell opens it. `key` names this
    /// trigger's frame; `origin` the frame whose leading edge (the pane's) the popover lines up with.
    func explainerTrigger(_ id: ExplainerID, key: String, origin: String? = nil) -> some View {
        modifier(ExplainerTrigger(id: id, key: key, origin: origin ?? key))
    }

    /// Marks a view whose frame places the popover without being a trigger (the pane's edge).
    func explainerFrame(_ key: String) -> some View { modifier(ExplainerFrame(key: key)) }
}

struct ExplainerFrame: ViewModifier {
    @Environment(AppModel.self) private var model
    let key: String
    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ExplainerState.space)) } action: { model.explainer.frames[key] = $0 }
            .onDisappear { model.explainer.frames[key] = nil }
    }
}

struct ExplainerTrigger: ViewModifier {
    @Environment(AppModel.self) private var model
    let id: ExplainerID
    let key: String
    let origin: String

    func body(content: Content) -> some View {
        content
            .modifier(ExplainerFrame(key: key))
            .onContinuousHover { phase in
                switch phase {
                case .active: model.explainer.moved(id, key: key, origin: origin)
                case .ended: model.explainer.left()
                }
            }
            // The help tag's sentence is the hint; Explain reads the Explainer's words (and opens it).
            .accessibilityAction(named: "Explain") { model.explain(id, key: key, origin: origin) }
    }
}

// MARK: - The popover

/// Drawn over the window, above everything but the sheets.
struct ExplainerOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let state = model.explainer
        ZStack(alignment: .topLeading) {
            if let id = state.open {
                let content = ExplainerContent.tasks
                GeometryReader { root in
                    placed(state: state, root: root.size) {
                        ExplainerCard(content: content, picture: { TaskExplainerPicture() },
                                      onDismissForGood: { state.dismissForGood(id) }, takesFocus: state.pinned)
                    }
                }
                .transition(.opacity)
            }
        }
        .allowsHitTesting(state.open != nil)
        // Never while a sheet or search is open.
        .onAppear { state.blocked = { [unowned model] in SheetCenter.shared.current != nil || model.search.isOpen } }
    }

    /// Above the trigger with its left edge on the pane's 16 inset; below when there's no room above.
    private func placed<C: View>(state: ExplainerState, root: CGSize, @ViewBuilder _ card: () -> C) -> some View {
        let w = DuoMetric.explainerWidth, arrow = DuoMetric.explainerArrow
        let h = state.height
        let above = state.anchor.minY - arrow - h >= 4
        let x = min(max(state.origin + DuoSpace.panePadding, 4), max(root.width - w - 4, 4))
        let y = above ? state.anchor.minY - arrow - h : state.anchor.maxY + arrow
        let arrowX = min(max(state.anchor.midX - x, 16), w - 16)
        return VStack(spacing: 0) {
            if !above { ExplainerArrow(pointsDown: false).frame(width: w, alignment: .leading).offset(x: arrowX - arrow / 2) }
            card()
                .frame(width: w)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { state.height = $0 }
            if above { ExplainerArrow(pointsDown: true).frame(width: w, alignment: .leading).offset(x: arrowX - arrow / 2) }
        }
        .frame(width: w)
        .opacity(h > 0 ? 1 : 0)   // not drawn until measured, so it never jumps
        .offset(x: x, y: above ? y : y - arrow)
        .onHover { state.cardHover($0) }
    }
}

/// The 12-wide arrow on the trigger's side, `pane` filled with a `rule` edge.
struct ExplainerArrow: View {
    let pointsDown: Bool
    var body: some View {
        let a = DuoMetric.explainerArrow
        ZStack {
            Path { p in
                if pointsDown { p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: a / 2, y: a / 2)); p.addLine(to: CGPoint(x: a, y: 0)) }
                else { p.move(to: CGPoint(x: 0, y: a / 2)); p.addLine(to: CGPoint(x: a / 2, y: 0)); p.addLine(to: CGPoint(x: a, y: a / 2)) }
            }
            .fill(DuoColor.pane)
            Path { p in
                if pointsDown { p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: a / 2, y: a / 2)); p.addLine(to: CGPoint(x: a, y: 0)) }
                else { p.move(to: CGPoint(x: 0, y: a / 2)); p.addLine(to: CGPoint(x: a / 2, y: 0)); p.addLine(to: CGPoint(x: a, y: a / 2)) }
            }
            .stroke(DuoColor.rule, lineWidth: DuoMetric.borderHairline)
        }
        .frame(width: a, height: a / 2)
        .padding(pointsDown ? .top : .bottom, -DuoMetric.borderHairline)   // sits over the frame's own edge
        .accessibilityHidden(true)
    }
}

/// The popover's frame and parts (`04-component`): title, line, picture, points, footer.
struct ExplainerCard<Picture: View>: View {
    let content: ExplainerContent
    @ViewBuilder let picture: () -> Picture
    let onDismissForGood: () -> Void
    /// Opened from the keyboard: focus goes to Don't show again (Learn more, when shown, would take it first).
    var takesFocus = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(content.title).duoText(.title).foregroundStyle(DuoColor.text)
                    Text(content.line).duoText(.body).foregroundStyle(DuoColor.text)
                }
                .padding(.top, 1)
                picture().accessibilityHidden(true)   // decorative
                VStack(alignment: .leading, spacing: 7.5) {
                    ForEach(Array(content.points.enumerated()), id: \.offset) { i, p in
                        HStack(alignment: .top, spacing: 8) {
                            ExplainerMark(number: i + 1).padding(.top, 0.5)
                            (Text(p.lead + " ").fontWeight(.semibold).foregroundStyle(DuoColor.text)
                                + Text(p.rest).foregroundStyle(DuoColor.text2))
                                .font(.system(size: 12)).lineSpacing(3.5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(EdgeInsets(top: DuoSpace.popoverPadding.top, leading: DuoSpace.popoverPadding.leading, bottom: DuoMetric.explainerBottom, trailing: DuoSpace.popoverPadding.leading))
            DuoColor.rule.frame(height: DuoMetric.borderHairline)
            HStack {
                if let url = content.learnMore {
                    Text("Learn more about \(content.title.lowercased())").duoText(.control).foregroundStyle(DuoColor.text)
                        .onActivate { NSWorkspace.shared.open(url) }  // not an action: opens the user guide page (Q-177)
                }
                Spacer(minLength: 0)
                Text("Don’t show again").duoText(.control).foregroundStyle(DuoColor.text2)
                    .contentShape(Rectangle())
                    .onActivate(onDismissForGood)  // action: settings explainers
                    .accessibilityLabel("Don’t show again")
                    .background(ExplainerFocus(focus: takesFocus && content.learnMore == nil, action: onDismissForGood).allowsHitTesting(false))
            }
            .padding(.horizontal, DuoSpace.popoverPadding.leading).padding(.top, 9.5).padding(.bottom, 13)
        }
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusPopover).fill(DuoColor.pane).duoPopoverShadow())   // the shadow on the frame alone, not on the parts in it
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusPopover).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(content.spoken)
    }
}

/// A numbered mark (16, filled `text`, white 10 semibold; never the accent).
struct ExplainerMark: View {
    let number: Int
    var body: some View {
        Text("\(number)").font(.system(size: 10, weight: .semibold)).foregroundStyle(DuoColor.pane)
            .frame(width: 16, height: 16).background(Circle().fill(DuoColor.text))
    }
}

/// The picture: one annotated task, drawn from Duo's own parts (the task box, a semibold title and
/// `text2` lines, a file chip and a session chip), 268 wide on `ground`, with numbered marks inside
/// the card at its right. Decorative. Sizes are board 02's, measured (title 12, lines 11/17.5).
struct TaskExplainerPicture: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DuoSpace.gapRowItems) {
                TaskBox().scaleEffect(1.25)   // board 02 draws the box at about 11 pt
                Text("Draft the Q4 plan").font(.system(size: 12, weight: .semibold)).foregroundStyle(DuoColor.text).lineLimit(1)
            }.frame(height: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text("Done when staff sign off.").frame(height: 17.5)
                Text("Start from last year’s plan.").frame(height: 17.5)
            }
            .font(.system(size: 11)).foregroundStyle(DuoColor.text2)
            .padding(.top, 2.5).padding(.leading, 18)
            HStack(spacing: 5) {
                chip(mono: true, "outline.md") { BoardGlyph(.page, color: DuoColor.text2).frame(width: 10, height: 10) }
                chip(mono: false, "Q4 outline") { Circle().strokeBorder(DuoColor.text, lineWidth: 1.3).frame(width: 8, height: 8) }
            }
            .padding(.top, 5).padding(.leading, 18)
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 11, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).fill(DuoColor.pane))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusControl).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
        // The marks sit inside the card at its right, level with the title, the first line and the chips.
        .overlay(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                ExplainerMark(number: 1).offset(y: 10.5)
                ExplainerMark(number: 2).offset(y: 31.5)
                ExplainerMark(number: 3).offset(y: 71)
            }.padding(.trailing, 10)
        }
        .padding(EdgeInsets(top: 12, leading: 13, bottom: 11.5, trailing: 13))
        .frame(width: DuoMetric.explainerWidth - 2 * DuoSpace.popoverPadding.leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(DuoColor.ground))
    }

    private func chip<G: View>(mono: Bool, _ text: String, @ViewBuilder glyph: () -> G) -> some View {
        HStack(spacing: 4) {
            glyph()
            Text(text).duoText(mono ? .monoPath : .pill).foregroundStyle(DuoColor.text)
        }
        .padding(.horizontal, 6).frame(height: 17)
        .background(Capsule().fill(DuoColor.pane))
        .overlay(Capsule().strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
    }
}

/// A key view behind Don't show again, so a keyboard-opened Explainer can put focus there (Return or
/// Space does it). SwiftUI's focus state is out (DL-30), so this is the one AppKit piece.
struct ExplainerFocus: NSViewRepresentable {
    let focus: Bool
    let action: () -> Void

    func makeNSView(context: Context) -> ExplainerFocusView { ExplainerFocusView() }

    func updateNSView(_ view: ExplainerFocusView, context: Context) {
        view.action = action
        if focus, !view.tookFocus {
            view.tookFocus = true
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
    }
}

final class ExplainerFocusView: NSView {
    var action: () -> Void = {}
    var tookFocus = false
    override var acceptsFirstResponder: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: -4, dy: -2) }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds.insetBy(dx: -4, dy: -2), xRadius: 4, yRadius: 4).fill() }
    override func becomeFirstResponder() -> Bool { noteFocusRingMaskChanged(); return true }
    override func keyDown(with event: NSEvent) {
        if [36, 49, 76].contains(event.keyCode) { action() } else { super.keyDown(with: event) }
    }
}
