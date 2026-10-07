import AppKit
import Foundation

/// Files dropped on the file tree (DL-117): from Finder, or from another folder of the tree, they
/// move into the folder under the pointer (the project root from its empty area). The same move
/// as `duo2 file move`, undoable with Edit › Undo.
extension AppModel {
    /// The folder a drop on `path` lands in: a folder row is itself, a file row its folder, nil the root.
    public func dropFolder(_ path: String?) -> URL? { targetFolder(for: path) }

    /// Whether the drop would copy (another volume, as Finder does; Q-51) rather than move.
    public func dropCopies(_ urls: [URL], onto path: String?) -> Bool {
        guard let dir = dropFolder(path) else { return false }
        return urls.contains { !FileDrop.sameVolume($0, dir) }
    }

    /// Takes a drop of files onto the tree. A taken name asks first (Replace, Keep Both, Cancel);
    /// a folder can't go into itself. Returns whether anything will happen.
    @discardableResult
    public func dropFiles(_ urls: [URL], onto path: String?) -> Bool {
        guard terminalsMode == .live, let dir = dropFolder(path) else { return false }
        return moveFiles(urls, into: dir)
    }

    /// Moves files into a folder of the project: a drop, or Move To… (the same rules and undo).
    @discardableResult
    func moveFiles(_ urls: [URL], into dir: URL) -> Bool {
        let (plans, refused) = FileDrop.plan(urls.filter(\.isFileURL), into: dir)
        let note = refused.isEmpty ? nil : refused.joined(separator: "; ") + "."
        DuoLog.write("drop on \(relative(dir) ?? "project root"): \(plans.count) item(s), refused \(refused.count)")
        guard !plans.isEmpty else {
            if let note { info(note) }
            return false
        }
        let clashes = plans.filter(\.clashes)
        if clashes.isEmpty {
            carryOut(plans, clash: nil, note: note)
        } else {
            askClash(clashes, in: dir) { [weak self] answer in
                guard let self else { return }
                guard let answer else { return }
                self.carryOut(plans, clash: answer, note: note)
            }
        }
        return true
    }

    /// The clash question, as `standins2-handoff/q50-clash` draws it (DL-132 c): a count in the
    /// title when several clash, and each row says where the dropped one came from and when the
    /// one there was edited. Keep Both is the default, as the answer that loses nothing.
    func askClash(_ clashes: [FileDrop.Plan], in dir: URL, then: @escaping @MainActor (FileDrop.Clash?) -> Void) {
        let place = relative(dir) ?? currentProject?.name ?? dir.lastPathComponent
        let title = clashes.count == 1 ? "“\(clashes[0].dest.lastPathComponent)” already exists in \(place)."
                                       : "\(clashes.count) items already exist in \(place)."
        let q = DuoQuestion(
            title: title,
            paragraphs: ["Replace puts \(clashes.count == 1 ? "the one" : "the ones") there in the Trash. Keep Both gives \(clashes.count == 1 ? "the dropped one a new name" : "the dropped ones new names"), like Finder."],
            items: clashes.map { c in
                let edited = (try? c.dest.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    .map { d -> String in let a = Self.ago(d); return a == "now" ? "the one there: edited just now" : "the one there: edited \(a) ago" }
                return .init(what: c.dest.lastPathComponent, path: "from " + Self.short(c.source.deletingLastPathComponent().path), detail: edited ?? "")
            },
            choices: [
                .init(label: "Cancel", isCancel: true) { then(nil) },
                .init(label: "Replace") { then(.replace) },
                .init(label: "Keep Both", isDefault: true) { then(.keepBoth) },
            ])
        if ProcessInfo.processInfo.environment["DUO_AUTOCONFIRM"] != nil {   // scripted checks answer with `answer:<label>`
            FileHandle.standardError.write(Data("question: \(title) [\(q.choices.map(\.label).joined(separator: " | "))]\n".utf8))
        }
        // After the drag has finished, as for the map's drops (F-51).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { MainActor.assumeIsolated { SheetCenter.shared.ask(q) } }
    }

    /// Moves (or copies) every planned item, then keeps tabs on the moved ones and offers undo.
    func carryOut(_ plans: [FileDrop.Plan], clash: FileDrop.Clash?, note: String?) {
        var done: [FileDrop.Done] = [], failed: [String] = []
        // Leaving the project (Move To… a folder outside it): its tabs close first, saved where they are.
        for p in plans where relative(p.dest) == nil { if let r = relative(p.source) { closeDocumentsUnder(r) } }
        for p in plans {
            do { done.append(try FileDrop.perform(p, clash: clash)) } catch { failed.append(error.localizedDescription) }
        }
        for d in done {
            FileHandle.standardError.write(Data("drop: \(d.mode.rawValue) \(d.source.path) -> \(d.dest.path)\(d.replaced != nil ? " (replaced)" : "")\n".utf8))
        }
        followTabs(done, back: false)
        if !done.isEmpty {
            let copies = done.allSatisfy { $0.mode == .copy }
            registerUndo(copies ? "Copy" : "Move") { model in
                let left = FileDrop.undo(done)
                model.followTabs(done, back: true)
                if !left.isEmpty { model.info("Undo couldn't put everything back: " + left.joined(separator: "; ") + ".") }
            }
        }
        let problems = (note.map { [$0] } ?? []) + failed
        if !problems.isEmpty { info(problems.joined(separator: " ")) }
    }

    /// Open tabs follow items moved inside the project (and back, on undo).
    func followTabs(_ done: [FileDrop.Done], back: Bool) {
        var changed = false
        for d in done where d.mode == .move {
            let (from, to) = back ? (d.dest, d.source) : (d.source, d.dest)
            guard let old = relative(from) else { continue }
            if let new = relative(to) { moved(old, to: new, url: to) }
            changed = true
        }
        if !changed { afterChange {} }
    }
}
