import Foundation
#if canImport(UIKit)
public import UIKit
#elseif canImport(AppKit)
public import AppKit
#endif

extension HighlightColor {
    /// A color that resolves against the current appearance — light or
    /// dark — at render time, so a single attributed string follows the
    /// system theme without re-highlighting.
    ///
    /// On watchOS (which has no appearance switching) the dark variant
    /// is used directly.
    public static func adaptive(light: HighlightColor, dark: HighlightColor) -> HighlightColor {
        #if os(watchOS)
        dark
        #elseif canImport(UIKit)
        HighlightColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
        #elseif canImport(AppKit)
        HighlightColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
        #endif
    }
}

extension HighlightTheme {
    /// Combines a light and a dark theme into one whose colors adapt to
    /// the system appearance dynamically (see
    /// `HighlightColor.adaptive(light:dark:)` — DocC cannot link through
    /// the platform-color typealias).
    ///
    /// Non-color style traits (bold/italic) and the font come from the
    /// light theme.
    public static func adaptive(light: HighlightTheme, dark: HighlightTheme) -> HighlightTheme {
        var styles: [HighlightScope: ScopeStyle] = [:]
        let keys = Set(light.styles.keys).union(dark.styles.keys)
        for key in keys {
            let lightStyle = light.styles[key]
            let darkStyle = dark.styles[key]
            let color: HighlightColor? = switch (lightStyle?.color, darkStyle?.color) {
            case (let l?, let d?): .adaptive(light: l, dark: d)
            case (let l?, nil): l
            case (nil, let d?): d
            case (nil, nil): nil
            }
            styles[key] = ScopeStyle(
                color: color,
                bold: lightStyle?.bold ?? darkStyle?.bold ?? false,
                italic: lightStyle?.italic ?? darkStyle?.italic ?? false
            )
        }
        return HighlightTheme(
            foregroundColor: .adaptive(light: light.foregroundColor, dark: dark.foregroundColor),
            backgroundColor: .adaptive(light: light.backgroundColor, dark: dark.backgroundColor),
            font: light.font,
            styles: styles
        )
    }

    /// GitHub theme that follows the system appearance
    /// (``githubLight`` in light mode, ``githubDark`` in dark mode).
    public static let github: HighlightTheme = .adaptive(
        light: .githubLight,
        dark: .githubDark
    )

    /// Xcode-style theme that follows the system appearance
    /// (``xcodeLight`` in light mode, ``xcodeDark`` in dark mode).
    public static let xcode: HighlightTheme = .adaptive(
        light: .xcodeLight,
        dark: .xcodeDark
    )
}
