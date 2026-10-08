import AppKit
import DuoControl
import QuickLookUI
import SwiftUI

// Pictures in chat (chat-paste-handoff `picture`, `sent`, `edges`, `replay`; DL-161): a row of
// thumbnails above your text in the composer, up to three (or a grid) at the top of your bubble,
// Quick Look on a click, and the line that says why a pasted picture didn't go in.

/// Views wrapped on to a new line at the width offered, each at its own size.
struct ChatFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    private func place(_ s: Subviews, width: CGFloat) -> (points: [CGPoint], size: CGSize) {
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, w: CGFloat = 0, out: [CGPoint] = []
        for v in s {
            let sz = v.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width { x = 0; y += row + lineSpacing; row = 0 }
            out.append(CGPoint(x: x, y: y))
            x += sz.width + spacing; row = max(row, sz.height); w = max(w, x - spacing)
        }
        return (out, CGSize(width: w, height: y + row))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews s: Subviews, cache: inout ()) -> CGSize { place(s, width: proposal.width ?? .infinity).size }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews s: Subviews, cache: inout ()) {
        for (v, p) in zip(s, place(s, width: bounds.width).points) { v.place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), anchor: .topLeading, proposal: .unspecified) }
    }
}

/// Decoded pictures, kept: a bubble's data is decoded once, not on every draw.
@MainActor enum ChatPictureCache {
    private static let cache = NSCache<NSString, NSImage>()
    static func image(_ p: ChatImage) -> NSImage? {
        let key = p.id.uuidString as NSString
        if let i = cache.object(forKey: key) { return i }
        guard let i = NSImage(data: p.data) else { return nil }
        cache.setObject(i, forKey: key)
        return i
    }
}

/// Quick Look for a picture: a copy in Duo's own support folder (never the project, nowhere Claude reads).
@MainActor final class ChatQuickLook: NSObject, @preconcurrency QLPreviewPanelDataSource {
    static let shared = ChatQuickLook()
    private var url: URL?

    static var folder: URL { DuoPaths.support.appending(path: "chat-images") }

    func show(_ data: Data, ext: String = "png", name: String = UUID().uuidString) {
        let dir = Self.folder
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "\(name).\(ext)")
        guard (try? data.write(to: file)) != nil else { return }
        url = file
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func show(_ image: NSImage, token: String) {
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        show(png, name: "picture-" + token.filter(\.isNumber) + "-" + String(Int(Date().timeIntervalSince1970)))
    }

    func show(_ p: ChatImage) { show(p.data, ext: p.mediaType.hasSuffix("jpeg") ? "jpg" : p.mediaType.hasSuffix("gif") ? "gif" : p.mediaType.hasSuffix("webp") ? "webp" : "png", name: p.id.uuidString) }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! { url as NSURL? }
}

/// A picture cropped to fill its box, the centre kept (Q-148c), on a `rule` edge.
struct ChatThumb: View {
    let image: NSImage?
    let width: CGFloat, height: CGFloat
    var body: some View {
        ZStack {
            DuoColor.pane
            if let image { Image(nsImage: image).resizable().scaledToFill().frame(width: width, height: height) }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: DuoMetric.radiusChatThumb))
        .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusChatThumb).strokeBorder(DuoColor.rule, lineWidth: DuoMetric.borderHairline))
    }
}

/// The composer's row of pictures, with the dashed tile while Claude Code takes one.
struct ChatPictureRow: View {
    let chat: ChatSession
    private let side = DuoSpace.chatPasteThumb

    var body: some View {
        ChatFlow(spacing: 8, lineSpacing: 8) {
            ForEach(chat.ui.attachedTokens, id: \.self) { token in
                let hovered = chat.ui.hoveredPicture == token
                ChatThumb(image: chat.ui.images[token], width: side, height: side)
                    .overlay(alignment: .topTrailing) {
                        if hovered {
                            ZStack {
                                Circle().fill(DuoColor.pane)
                                Circle().strokeBorder(DuoColor.controlEdge, lineWidth: DuoMetric.borderHairline)
                                Cross().stroke(DuoColor.text, style: StrokeStyle(lineWidth: 1.3, lineCap: .round)).frame(width: 8, height: 8)
                            }
                            .frame(width: 18, height: 18)
                            .contentShape(Circle())
                            .offset(x: 6.5, y: -5.5)   // as drawn: a little inside the corner
                            .onActivate { chat.removePicture(token) }  // not an action: the composer's own editing, like deleting text
                            .accessibilityLabel("Remove picture")
                        }
                    }
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { chat.ui.hoveredPicture = token } else if chat.ui.hoveredPicture == token { chat.ui.hoveredPicture = nil }
                    }
                    .onActivate { if let i = chat.ui.images[token] { ChatQuickLook.shared.show(i, token: token) } }  // not an action: previews a picture in the composer
                    .accessibilityLabel("Picture \(token.filter(\.isNumber)): preview")
            }
            if chat.ui.addingPicture {
                Text("Adding…").duoText(.control).foregroundStyle(DuoColor.text2)
                    .frame(width: side, height: side)
                    .overlay(RoundedRectangle(cornerRadius: DuoMetric.radiusChatThumb)
                        .strokeBorder(DuoColor.controlEdge, style: StrokeStyle(lineWidth: DuoMetric.borderHairline, dash: DuoShadow.dashPattern)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// An 8×8 cross: `M1 1l6 6M7 1l-6 6`.
struct Cross: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width / 8, y: r.minY + r.height / 8)); p.addLine(to: CGPoint(x: r.maxX - r.width / 8, y: r.maxY - r.height / 8))
        p.move(to: CGPoint(x: r.maxX - r.width / 8, y: r.minY + r.height / 8)); p.addLine(to: CGPoint(x: r.minX + r.width / 8, y: r.maxY - r.height / 8))
        return p
    }
}

/// The pictures at the top of your bubble, right-aligned: up to three at 120×90 in a row, four or
/// more in a three-column grid at 100×75 (chat-paste-handoff `sent`, `edges`).
struct ChatSentPictures: View {
    let pictures: [ChatImage]

    var body: some View {
        let grid = pictures.count > 3
        let w = grid ? DuoSpace.chatSentThumbGridWidth : DuoSpace.chatSentThumbWidth, h = grid ? DuoSpace.chatSentThumbGridHeight : DuoSpace.chatSentThumbHeight
        let rows = grid ? stride(from: 0, to: pictures.count, by: 3).map { Array(pictures[$0..<min($0 + 3, pictures.count)]) } : [pictures]
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row) { p in
                        ChatThumb(image: ChatPictureCache.image(p), width: w, height: h)
                            .contentShape(Rectangle())
                            .onActivate { ChatQuickLook.shared.show(p) }  // not an action: previews a picture in your message
                            .accessibilityLabel("Picture you sent: preview")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// Under the field, in the hint row's place until you type or paste again: why a picture didn't go in.
struct ChatPasteNoticeLine: View {
    let chat: ChatSession
    let notice: ChatPasteNotice

    var body: some View {
        let moved = notice == .keysMoved
        HStack(spacing: 0) {
            Text(moved ? "Your Claude Code keys move Ctrl+V, so pictures go in from the terminal. " : "Claude Code didn’t take the picture. ")
                .duoText(.control).foregroundStyle(DuoColor.text2)
            Text(moved ? "Show terminal" : "Paste it in the terminal").duoText(.control).foregroundStyle(DuoColor.text).underline(color: DuoColor.controlEdge)
                .onActivate {  // action: session chat
                    chat.ui.pasteNotice = nil
                    chat.fallBack(.handedOver(moved ? "Pictures go into Claude’s prompt here: your Claude Code keys move Ctrl+V. Chat comes back after."
                                                    : "Paste the picture into Claude’s prompt here; chat comes back after."))
                }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}
