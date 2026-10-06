import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Dragging files in and out of the file tree (DL-117). A row drags its file (onto a terminal it
// types the path; onto another folder of the tree it moves there). Files dropped from Finder or
// the tree move into the folder under the pointer: a folder row is itself, a file row its folder,
// the tree's empty area the project root.

/// A row's file as a drag: the file URL (what Finder and terminals take), on Geoff's drag card (F-51).
struct DragsFile: ViewModifier {
    @Environment(AppModel.self) private var model
    let path: String
    let name: String

    func body(content: Content) -> some View {
        if model.terminalsMode == .live, let url = model.fileURL(path) {
            content.onDrag({ NSItemProvider(object: url as NSURL) }, preview: { DragCard(title: name, detail: (path as NSString).deletingLastPathComponent) })  // action: file move
        } else {
            content
        }
    }
}

/// Takes files dropped on the tree. `target` is the folder they land in ("" for the root).
struct TakesFileDrops: ViewModifier {
    @Environment(AppModel.self) private var model
    let target: String

    func body(content: Content) -> some View {
        if model.terminalsMode == .live {
            content.onDrop(of: [.fileURL], delegate: TreeDropDelegate(model: model, target: target))  // action: file move
        } else {
            content
        }
    }
}

@MainActor
struct TreeDropDelegate: DropDelegate {
    let model: AppModel
    let target: String

    /// The dragged files, read from the drag pasteboard (available while the drag is over us).
    private var urls: [URL] {
        (NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    private var path: String? { target.isEmpty ? nil : target }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }

    func dropEntered(info: DropInfo) { model.treeDropTarget = target }

    func dropExited(info: DropInfo) { if model.treeDropTarget == target { model.treeDropTarget = nil } }

    /// The pointer's badge says what will happen: a move, or a copy from another volume (Finder's +).
    func dropUpdated(info: DropInfo) -> DropProposal? {
        model.treeDropTarget = target
        let items = urls
        guard !items.isEmpty, let dir = model.dropFolder(path) else { return DropProposal(operation: .forbidden) }
        if items.allSatisfy({ FileDrop.refusal($0, into: dir) != nil }) { return DropProposal(operation: .forbidden) }
        return DropProposal(operation: model.dropCopies(items, onto: path) ? .copy : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        model.treeDropTarget = nil
        return model.dropFiles(urls, onto: path)
    }
}

/// The drop highlight on a folder row, and on the tree for the root (stand-in, Q-50): the
/// selection fill with a dashed `controlEdge` border, the tokens' "drop target" dash.
struct DropHighlight: View {
    var radius: CGFloat = DuoMetric.radiusSelection

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(DuoColor.selected)
            .overlay(RoundedRectangle(cornerRadius: radius)
                .strokeBorder(DuoColor.controlEdge, style: StrokeStyle(lineWidth: DuoMetric.borderHairline, dash: DuoShadow.dashPattern)))
            .allowsHitTesting(false)
    }
}
