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
    /// Dark answers by appearance; light and Classic (DL-252) answer by `DuoScheme.classicActive`, which `AppearanceSetting.apply()`
    /// flips along with a nudge of the appearance, so every observer that copies a resolved colour out resolves it again.
    static func duoDynamic(light: UInt32, dark: UInt32, classic: UInt32, name: String, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> NSColor {
        let l = duoFixed(light).withAlphaComponent(lightAlpha), d = duoFixed(dark).withAlphaComponent(darkAlpha)
        let c = duoFixed(classic).withAlphaComponent(lightAlpha)
        return NSColor(name: NSColor.Name("duo.\(name)")) { appearance in
            DuoScheme.resolved(appearance) == .dark ? d : DuoScheme.classicActive ? c : l
        }
    }

    /// A shadow colour by appearance, as 0-255 channels and an opacity (the shadow tokens are rgba).
    static func duoDynamicRGBA(light: (Int, Int, Int, CGFloat), dark: (Int, Int, Int, CGFloat), name: String) -> NSColor {
        func make(_ c: (Int, Int, Int, CGFloat)) -> NSColor {
            NSColor(srgbRed: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: c.3)
        }
        let l = make(light), d = make(dark)
        return NSColor(name: NSColor.Name("duo.\(name)")) { appearance in
            DuoScheme.resolved(appearance) == .dark ? d : l
        }
    }
}
