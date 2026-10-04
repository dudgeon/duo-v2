import SwiftUI

/// "Send to Claude" and "Send to ▸" (DL-69), for any context menu. `payload` builds the text for
/// a receiving session (file paths depend on its folder); nil means there's nothing to send.
struct SendMenu: View {
    @Environment(AppModel.self) private var model
    let payload: @MainActor (String?) -> String?

    var body: some View {
        switch model.sendTarget {
        case .success(let t):
            Button("Send to Claude") { if let p = payload(t.key) { model.send(p, to: t.key) } }
        case .failure(let why):
            Button("Send to Claude: \(why.reason)") {}.disabled(true)
        }
        let visible = (try? model.sendTarget.get())?.key
        Menu("Send To") {
            ForEach(model.sendTargets.filter { $0.key != visible }) { t in
                Button(t.project.isEmpty ? t.title : "\(t.title) — \(t.project)") { if let p = payload(t.key) { model.send(p, to: t.key) } }
            }
            if model.sendTargets.contains(where: { $0.key != visible }) { Divider() }
            Button("New Session") { if let p = payload(nil) { model.sendToNewSession(p) } }
        }
    }
}
