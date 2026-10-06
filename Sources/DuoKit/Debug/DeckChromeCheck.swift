import AppKit
import SwiftUI

/// The deck's two bars laid out at a width, for checks (F-121, Q-68): the width they need there,
/// and optionally a picture. The right pane can be as narrow as `paneMinRight`.
@MainActor public enum DeckChromeCheck {
    public static func layout(_ model: AppModel, width: CGFloat, png: URL? = nil) -> CGSize {
        guard let viewer = model.deckViewerIfLoaded, let url = viewer.url else { return .zero }
        let view = VStack(spacing: 0) {
            DeckBar(viewer: viewer, path: url.lastPathComponent, file: url)
            DuoColor.ground.frame(height: 24)
            DeckPickerBar(viewer: viewer)
        }
        .background(DuoColor.pane)
        .environment(model)
        let host = NSHostingController(rootView: view)
        let need = host.sizeThatFits(in: CGSize(width: width, height: 2000))
        if let png {
            host.view.frame = NSRect(x: 0, y: 0, width: width, height: need.height)
            host.view.layoutSubtreeIfNeeded()
            if let rep = host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds) {
                host.view.cacheDisplay(in: host.view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: png)
            }
        }
        return need
    }
}
