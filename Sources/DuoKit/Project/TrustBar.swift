import SwiftUI

/// The "Trust this folder" notice (DL-229, trust-notice-handoff). Under a terminal it is a console bar drawn as
/// `ConsoleEndedBar` is (40 high, a `consoleRule` above, padding 16, console buttons); in chat it sits over the composer
/// in `NoticeBar`'s look (`ground`, a `rule` above, padding 10 20, sheet buttons). The bar changes in place as the
/// notice moves from the offer to "now trusts" or the failure.
struct TrustBar: View {
    @Environment(AppModel.self) private var model
    let key: String
    var inChat = false

    static func message(_ n: TrustNotice) -> String {
        switch n.phase {
        case .offer: "Claude Code doesn’t trust \(n.folder) yet, so /fork couldn’t start."
        case .runClaude: "Claude Code doesn’t trust \(n.folder). Run claude there once and answer its trust question."
        case .trusted: n.forkLine == nil ? "Claude Code now trusts \(n.folder). Run /fork again." : "Claude Code now trusts \(n.folder)."
        case .failed(let why): "Couldn’t change Claude Code’s settings: \(why)."
        }
    }

    var body: some View {
        if let n = model.trustNotice(key) {
            if inChat { chatBar(n) } else { consoleBar(n) }
        }
    }

    private func consoleBar(_ n: TrustNotice) -> some View {
        VStack(spacing: 0) {
            ConsoleRule()
            HStack(spacing: 10) {
                Text(Self.message(n)).duoText(.body).foregroundStyle(DuoColor.consoleText).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 8)
                HStack(spacing: 6) { buttons(n, console: true) }.fixedSize()
            }
            .padding(.horizontal, DuoMetric.consoleBarPadding)
            .frame(height: DuoMetric.consoleBarHeight - DuoMetric.borderHairline)
        }
        .background(DuoColor.console)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.announce(n))
    }

    private func chatBar(_ n: TrustNotice) -> some View {
        HStack(alignment: .center, spacing: DuoSpace.gapButtonToButton) {
            Text(Self.message(n)).duoText(.body).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            HStack(spacing: DuoSpace.gapButtonToButton) { buttons(n, console: false) }.fixedSize()
        }
        .padding(.vertical, DuoMetric.noticePaddingY)
        .padding(.horizontal, DuoMetric.noticePaddingX)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DuoColor.ground)
        .overlay(alignment: .top) { DuoColor.rule.frame(height: DuoMetric.borderHairline) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.announce(n))
    }

    /// What VoiceOver says: once when the bar appears, and again when it changes.
    static func announce(_ n: TrustNotice) -> String {
        switch n.phase {
        case .offer: "/fork couldn’t start: Claude Code doesn’t trust \(n.folder) yet"
        default: message(n)
        }
    }

    @ViewBuilder private func buttons(_ n: TrustNotice, console: Bool) -> some View {
        switch n.phase {
        case .offer:
            barButton("Not Now", console: console, isDefault: false) { model.dismissTrustNotice(key) }
            barButton("Trust This Folder…", console: console, isDefault: true) { model.askToTrust(key) }
        case .runClaude:
            barButton("OK", console: console, isDefault: true) { model.closeTrustNotice(key) }
        case .trusted:
            barButton("OK", console: console, isDefault: n.forkLine == nil) { model.closeTrustNotice(key) }
            if n.forkLine != nil {
                let can = model.canForkAgain(key)
                barButton("Fork Again", console: console, isDefault: true) { model.forkAgain(key) }
                    .disabled(!can).help(can ? "" : "Finish what you’re typing first")
            }
        case .failed:
            barButton("Not Now", console: console, isDefault: false) { model.dismissTrustNotice(key) }
            barButton("Try Again", console: console, isDefault: true) { model.askToTrust(key) }
        }
    }

    @ViewBuilder private func barButton(_ title: String, console: Bool, isDefault: Bool, _ action: @escaping () -> Void) -> some View {
        if console {
            let b = Button(title, action: action)
            if isDefault { b.buttonStyle(ConsoleButtonStyle(bold: true)).keyboardShortcut(.defaultAction) }
            else { b.buttonStyle(ConsoleButtonStyle()) }
        } else {
            let b = Button(action: action) { Text(title) }
            if isDefault { b.buttonStyle(DefaultSheetButtonStyle()) } else { b.buttonStyle(.duo) }
        }
    }
}
