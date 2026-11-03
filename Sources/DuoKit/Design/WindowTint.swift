import AppKit
import SwiftUI

// Window colours (DL-312, DL-313; multi-window-handoff). A window's colour overrides four surfaces in that
// window only: `ground` (the toolbar), `pane` (the sidebar, tab strips, right pane, the All projects panes),
// `chatGround` and `toolOutputFill`. Cards, fields, buttons, the selected row, the console, text, rules,
// the document's page and needs-you never change. A dynamic NSColor can't tell which window it draws in, so
// the colour travels as an environment value each window's RootView sets from its model (F-542). Classic
// turns it off: the model's `windowColour` is nil while Classic is on.

private struct WindowColourKey: EnvironmentKey {
    static let defaultValue: DuoWindowColour.Colour? = nil
}

extension EnvironmentValues {
    /// The window's colour as drawn; nil is None (and Classic).
    public var windowColour: DuoWindowColour.Colour? {
        get { self[WindowColourKey.self] }
        set { self[WindowColourKey.self] = newValue }
    }
}

/// The four surfaces a window colour takes, and the swatch.
public enum WindowRole: Sendable {
    case ground, pane, chatGround, toolOutputFill, swatch
    /// A light tab strip drawn in `ground` today (the console's in chat, Home's): the pale pane tint when the
    /// window has a colour (board 4a′: "tab strips take a pale tint"), plain `ground` when it has none.
    case strip

    func value(_ v: DuoWindowColour.Values) -> UInt32 {
        switch self {
        case .ground: v.ground
        case .pane, .strip: v.pane
        case .chatGround: v.chatGround
        case .toolOutputFill: v.toolOutputFill
        case .swatch: v.swatch
        }
    }

    /// The plain token where the window has no colour.
    var base: NSColor {
        switch self {
        case .ground, .strip: DuoNSColor.ground
        case .pane, .swatch: DuoNSColor.pane
        case .chatGround: DuoNSColor.chatGround
        case .toolOutputFill: DuoNSColor.toolOutputFill
        }
    }
}

/// A surface that takes the window's colour: use `WindowTint.pane` (not `DuoColor.pane`) for a pane's own
/// ground, `WindowTint.ground` for the toolbar, and so on. Anywhere else, the plain token.
public struct WindowTint: ShapeStyle {
    public let role: WindowRole
    public static let ground = WindowTint(role: .ground)
    public static let pane = WindowTint(role: .pane)
    public static let chatGround = WindowTint(role: .chatGround)
    public static let toolOutputFill = WindowTint(role: .toolOutputFill)
    public static let swatch = WindowTint(role: .swatch)
    public static let strip = WindowTint(role: .strip)

    public func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        Color(nsColor: WindowTint.nsColor(role, environment.windowColour)).resolve(in: environment)
    }

    /// The colour for AppKit drawing: a dynamic colour (light, dark) for this window's colour, or the plain token.
    public static func nsColor(_ role: WindowRole, _ colour: DuoWindowColour.Colour?) -> NSColor {
        guard let colour else { return role.base }
        let l = role.value(colour.light), d = role.value(colour.dark)
        return NSColor.duoDynamic(light: l, dark: d, classic: l, name: "window.\(colour.id).\(role)")
    }
}

extension AppModel {
    /// This window's colour for a surface, for AppKit views (`DuoNSColor` can't tell windows apart).
    public func tint(_ role: WindowRole) -> NSColor { WindowTint.nsColor(role, windowColour) }

    /// The swatch's fill: the colour's swatch, or plain `pane` for None.
    public var swatchColor: Color { Color(nsColor: tint(.swatch)) }

    /// On a coloured toolbar, text2 draws as text (DL-313).
    public var toolbarText2: Color { windowColour == nil ? DuoColor.text2 : DuoColor.text }
}
