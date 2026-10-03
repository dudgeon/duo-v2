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

    /// The height AppKit gives one line of this font with no extra leading. Not rounded: the
    /// extra leading must make the line pitch exactly `lineHeight`, as CSS does.
    public var naturalLineHeight: CGFloat {
        let f = nsFont
        return f.ascender - f.descender + f.leading
    }

    public var extraLeading: CGFloat { max(0, lineHeight - naturalLineHeight) }

    /// CoreText's exact line height puts all the extra leading below the glyphs; CSS splits it
    /// above and below. Shifting the text down by half of it, rounded down to the pixel grid,
    /// puts glyphs where the targets draw them (findings F-11: measured 2 pt at 13/20 and mono
    /// 12/19, 1 pt at 11/16).
    public var baselineShift: CGFloat { (extraLeading / 2).rounded(.down) }
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
            .font(spec.mono
                  ? Font(NSFont.monospacedSystemFont(ofSize: spec.size, weight: (weight ?? spec.weight).nsWeight))
                  : .system(size: spec.size, weight: weight ?? spec.weight))
            .tracking(spec.tracking)
            .textCase(spec.uppercase ? .uppercase : nil)
            // Exact line boxes, as CSS line-height draws them (findings F-11). Deriving extra
            // leading from AppKit's font metrics ran about 0.8 pt per line long in SwiftUI.
            .lineHeight(.exact(points: spec.lineHeight))
            .offset(y: spec.baselineShift)
    }
}

extension View {
    /// Applies a handoff type style. `weight` overrides the style's weight (for emphasis).
    public func duoText(_ style: DuoTextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(DuoTextModifier(spec: style.spec, weight: weight))
    }
}
