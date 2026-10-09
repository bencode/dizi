import SwiftUI

/// The look from the visual direction (宣纸 light, 墨夜 dark): colours from the asset catalog, type, spacing.
enum Theme {
    static let ground = Color("Ground")
    static let raised = Color("Raised")
    static let ink = Color("Ink")
    static let muted = Color("Muted")
    static let rule = Color("Rule")
    static let accent = Color("AccentColor")
    static let onAccent = Color("OnAccent")
    /// The band behind what has been played.
    static let wash = Color("Wash")
    /// Level dots: the accent in light, gold in dark.
    static let gold = Color("Gold")
    /// Behind a card's first character.
    static let tile = Color("Tile")
    /// An unlit level dot.
    static let dotOff = Color("DotOff")

    /// Score digits, tempo, titles: New York, the system serif.
    static func serif(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// The 4-point spacing scale.
    enum Space {
        static let tiny: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let gutter: CGFloat = 20
        static let wide: CGFloat = 24
        static let wider: CGFloat = 32
    }
}
