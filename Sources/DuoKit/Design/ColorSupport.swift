import AppKit

extension NSColor {
    /// An sRGB colour from a 0xRRGGBB literal.
    static func duoFixed(_ rgb: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    /// A colour that follows the view's appearance. Views never use raw hex (handoff §4).
    static func duoDynamic(light: UInt32, dark: UInt32, name: String) -> NSColor {
        let l = duoFixed(light), d = duoFixed(dark)
        return NSColor(name: NSColor.Name("duo.\(name)")) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? d : l
        }
    }
}
