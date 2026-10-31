import AppKit
import Foundation

/// Which document editor (C-135): one per side of a split tab (DL-278). The slot is stable, so a swap
/// moves where an editor draws, never which document it holds (no page reload on Swap Sides).
/// Multi-window (DL-141) gives each window its own `EditorSet`; a ref names an editor within one.
public struct EditorRef: Hashable, Sendable, CustomStringConvertible {
    public enum Slot: String, Sendable, CaseIterable { case main, second }
    public var slot: Slot
    public init(_ slot: Slot) { self.slot = slot }
    public static let main = EditorRef(.main)
    public static let second = EditorRef(.second)
    public var description: String { slot.rawValue }
}

/// Where each open file lives (multi-window's "every live view has one home", F-167): one editor at a
/// time holds a file's buffer, watcher and unsaved text. Shared by every `EditorSet`, so a later
/// second window keeps the rule without a sync layer.
@MainActor
public final class DocumentHomes {
    private var homes: [String: (set: ObjectIdentifier, ref: EditorRef)] = [:]
    public init() {}

    /// /tmp and /var resolve to /private only while the path exists: compare without it (as `moveHeld` does).
    static func key(_ url: URL) -> String { EditorController.plainPath(url.standardizedFileURL.resolvingSymlinksInPath().path) }

    func home(of url: URL) -> (set: ObjectIdentifier, ref: EditorRef)? { homes[Self.key(url)] }
    func set(_ url: URL, _ set: ObjectIdentifier, _ ref: EditorRef) { homes[Self.key(url)] = (set, ref) }
    /// A file or folder was renamed or moved: its homes follow (a path under `old` becomes one under `new`).
    func move(from old: String, to new: String) {
        let o = Self.key(URL(fileURLWithPath: old)), n = Self.key(URL(fileURLWithPath: new))
        for (k, h) in homes where k == o || k.hasPrefix(o + "/") {
            homes[k] = nil
            homes[n + k.dropFirst(o.count)] = h
        }
    }

    func clear(_ url: URL, ifHeldBy set: ObjectIdentifier, _ ref: EditorRef) {
        let k = Self.key(url)
        if let h = homes[k], h.set == set, h.ref == ref { homes[k] = nil }
    }
}

/// The document editors of one window (C-135): made on first use, one per slot. `active` is the slot
/// the menus, ⌘S, Format, voice and `duo2 doc …` with no path act on; the editor that last took the
/// keyboard, or the side a split made active.
@MainActor
public final class EditorSet {
    public let homes: DocumentHomes
    /// Makes and wires an editor for a slot (the model's `wireEditor`).
    let make: (EditorRef) -> EditorController
    private var made: [EditorRef.Slot: EditorController] = [:]
    /// Called when `active` changes (the model bumps `editorRevision` so bars and menus re-read).
    var onActiveChange: (() -> Void)?

    public var active: EditorRef = .main {
        didSet { if oldValue != active { onActiveChange?() } }
    }

    init(homes: DocumentHomes, make: @escaping (EditorRef) -> EditorController) {
        self.homes = homes
        self.make = make
    }

    public func editor(_ ref: EditorRef) -> EditorController {
        if let e = made[ref.slot] { return e }
        let e = make(ref)
        e.homeSet = self
        made[ref.slot] = e
        return e
    }

    /// The editor in `ref` if it was ever made (status checks mustn't make one: a WebContent process each).
    public func ifLoaded(_ ref: EditorRef) -> EditorController? { made[ref.slot] }

    /// Every editor made so far, main first.
    public var loaded: [(ref: EditorRef, editor: EditorController)] {
        EditorRef.Slot.allCases.compactMap { s in made[s].map { (EditorRef(s), $0) } }
    }

    public func ref(of editor: EditorController) -> EditorRef? {
        made.first { $0.value === editor }.map { EditorRef($0.key) }
    }

    /// The editor whose document on screen is `url`.
    public func showing(_ url: URL) -> EditorController? {
        let k = DocumentHomes.key(url)
        return loaded.first { $0.editor.url.map(DocumentHomes.key) == k }?.editor
    }

    /// Opens `file` in `ref`, after any other editor whose page holds it has saved and let go (DL-278:
    /// one document per file, never two buffers that take each other's saves as outside changes).
    /// False when the file stays where it is: its holder keeps unsaved text from a conflict or a
    /// removal (DL-77), which only that page has, so the caller shows the holder instead.
    @discardableResult
    public func open(_ file: URL, in ref: EditorRef) -> Bool {
        let target = editor(ref)
        let me = ObjectIdentifier(self)
        // The editor showing it is its home, whatever the registry says (a rename it followed on disk).
        if let shown = showing(file), let r = self.ref(of: shown), r != ref { homes.set(file, me, r) }
        if let h = homes.home(of: file), !(h.set == me && h.ref == ref), h.set == me, let holder = ifLoaded(h.ref) {
            guard holder.canRelease(file) else { return false }
            homes.set(file, me, ref)
            holder.release(file) { target.openHere(file) }
            return true
        }
        // A home in another window's set (DL-141, later) releases through that set.
        homes.set(file, me, ref)
        target.openHere(file)
        return true
    }

    /// `ref` stops holding `file` (its tab closed or the file left).
    func forgetHome(_ file: URL, in ref: EditorRef) { homes.clear(file, ifHeldBy: ObjectIdentifier(self), ref) }
}

extension EditorController {
    /// Whether `file` can move to another editor: not while this page holds unsaved text for it that a
    /// conflict or a removal kept (DL-77), which would be lost.
    func canRelease(_ file: URL) -> Bool {
        if let u = url, DocumentHomes.key(u) == DocumentHomes.key(file) { return !(dirty && (conflict || removedOnDisk)) }
        return !keptInConflict(file)
    }

    /// Saves `file` if it is the document on screen, then lets it go: the page drops its state for it
    /// (undo, caret, a stale buffer) and the watchers stop, so another editor opens it fresh from disk.
    func release(_ file: URL, then: @escaping @MainActor () -> Void) {
        guard let u = url, DocumentHomes.key(u) == DocumentHomes.key(file) else { forget(file); then(); return }
        saveNow(force: true) { [weak self] in
            self?.closeFile()
            then()
        }
    }
}
