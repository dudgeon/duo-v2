import AppKit
import SwiftUI

/// One type style from handoff §4.2. Line heights follow CSS: the extra leading is split evenly
/// above and below the line, so a 13/20 label occupies 20 pt like it does in the targets.
public struct DuoTextSpec: Sendable {
    public let size: CGFloat
    public let lineHeight: CGFloat
    public let weight: Font.Weight
    public let mono: Bool
    public let tracking: CGFloat
    public let uppercase: Bool

    public var font: Font {
        .system(size: size, weight: weight, design: mono ? .monospaced : .default)
    }

    public var nsFont: NSFont {
        mono
            ? .monospacedSystemFont(ofSize: size, weight: weight.nsWeight)
            : .systemFont(ofSize: size, weight: weight.nsWeight)
    }

    /// The height AppKit gives one line of this font with no extra leading.
    public var naturalLineHeight: CGFloat {
        let f = nsFont
        return ceil(f.ascender - f.descender + f.leading)
    }

    public var extraLeading: CGFloat { max(0, lineHeight - naturalLineHeight) }
}

extension Font.Weight {
    var nsWeight: NSFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}

struct DuoTextModifier: ViewModifier {
    let spec: DuoTextSpec
    let weight: Font.Weight?

    func body(content: Content) -> some View {
        content
            .font(.system(size: spec.size, weight: weight ?? spec.weight, design: spec.mono ? .monospaced : .default))
            .tracking(spec.tracking)
            .textCase(spec.uppercase ? .uppercase : nil)
            .lineSpacing(spec.extraLeading)
            .padding(.vertical, spec.extraLeading / 2)
    }
}

extension View {
    /// Applies a handoff type style. `weight` overrides the style's weight (for emphasis).
    public func duoText(_ style: DuoTextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(DuoTextModifier(spec: style.spec, weight: weight))
    }
}
