import Foundation

/// The commands a split routes by its active side (`routing-verbs`).
public enum SplitCommand: String, CaseIterable, Sendable {
    case closeTab, save, find, sendSelection, dictation, formattingBar
}

/// What a command does, given the active side. One table, so a DuoCheck covers every command × side
/// (legacy rule 1: the active side is model state, never inferred from DOM focus).
public enum SplitRoute: Equatable, Sendable {
    /// ⌘W on the preview: the preview closes, the source stays as an ordinary tab.
    case closePreview
    /// ⌘W on the source: the whole split closes (the preview has no file of its own).
    case closeSplit
    /// ⌘S: the one buffer, whichever side.
    case saveDocument
    /// ⌘F: the active side's own find.
    case findInSide(SplitRole)
    /// ⌘D: the source's selection; on the preview, its picked item (a deck's shape with its slot).
    case sendSelection(SplitRole)
    /// ⇧⌘D: dictation goes into the source, whichever side is active.
    case dictateIntoSource
    /// The DL-266 bar shows over the source only, while it has the keyboard.
    case formattingBarOverSource
    /// A document pair (slice 2): ⌘W closes that side's document and leaves the other an ordinary tab.
    case closeSideDocument(SplitRole)
    /// A document pair: the bar and dictation go to the active side.
    case formattingBarOverActive
    case none
}

public enum SplitRouting {
    /// `docPair` is true for slice 2's two documents: any side is a document, so the active side gets everything.
    public static func route(_ command: SplitCommand, active: SplitRole, docPair: Bool = false) -> SplitRoute {
        switch command {
        case .closeTab: docPair ? .closeSideDocument(active) : active == .preview ? .closePreview : .closeSplit
        case .save: .saveDocument
        case .find: .findInSide(active)
        case .sendSelection: .sendSelection(active)
        case .dictation: docPair ? .formattingBarOverActive : .dictateIntoSource
        case .formattingBar: docPair ? .formattingBarOverActive : active == .source ? .formattingBarOverSource : .none
        }
    }
}
