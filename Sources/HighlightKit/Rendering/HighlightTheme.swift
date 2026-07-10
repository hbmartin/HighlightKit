public import Foundation
#if canImport(UIKit)
public import UIKit
/// The platform color type (`UIColor` / `NSColor`).
public typealias HighlightColor = UIColor
/// The platform font type (`UIFont` / `NSFont`).
public typealias HighlightFont = UIFont
#elseif canImport(AppKit)
public import AppKit
public typealias HighlightColor = NSColor
public typealias HighlightFont = NSFont
#endif

/// Text styling for one scope.
public struct ScopeStyle: Sendable {
    public var color: HighlightColor?
    public var bold: Bool
    public var italic: Bool

    public init(color: HighlightColor? = nil, bold: Bool = false, italic: Bool = false) {
        self.color = color
        self.bold = bold
        self.italic = italic
    }
}

/// Maps token scopes to text attributes.
///
/// Lookup walks dot-separated scopes from most to least specific
/// (`title.function.invoke` → `title.function` → `title`), then falls
/// back through the token's outer scopes — mirroring how highlight.js
/// themes cascade in CSS.
public struct HighlightTheme: Sendable {
    /// Describes the code font without holding a (non-`Sendable`)
    /// platform font object; resolved when rendering.
    public struct FontSpec: Sendable {
        /// PostScript font name; `nil` uses the system monospaced font.
        public var name: String?
        public var size: CGFloat

        public init(name: String? = nil, size: CGFloat = 13) {
            self.name = name
            self.size = size
        }

        /// The platform font this spec describes.
        public func resolved() -> HighlightFont {
            if let name, let font = HighlightFont(name: name, size: size) {
                return font
            }
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }

    /// Base color for plain text.
    public var foregroundColor: HighlightColor
    /// Suggested background color for the rendered code.
    public var backgroundColor: HighlightColor
    /// Font applied to the whole string.
    public var font: FontSpec
    /// Scope → style. Dot-path scopes (`.titleFunction`) fall back
    /// structurally; string literals work for custom scopes.
    public var styles: [HighlightScope: ScopeStyle]

    public init(
        foregroundColor: HighlightColor,
        backgroundColor: HighlightColor,
        font: FontSpec = FontSpec(),
        styles: [HighlightScope: ScopeStyle]
    ) {
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.font = font
        self.styles = styles
    }

    /// Resolves the style for a token, trying the innermost scope's dot
    /// path first, then each outer scope.
    public func style(for token: HighlightToken) -> ScopeStyle? {
        for scope in token.scopes.reversed() {
            if let style = style(forScope: scope) {
                return style
            }
        }
        return nil
    }

    /// Resolves a single scope through its dot-path fallbacks.
    public func style(forScope scope: HighlightScope) -> ScopeStyle? {
        var name = Substring(scope.rawValue)
        while true {
            if let style = styles[HighlightScope(String(name))] {
                return style
            }
            guard let dot = name.lastIndex(of: ".") else { return nil }
            name = name[..<dot]
        }
    }

    /// Resolves a raw scope name (as carried by ``HighlightToken``).
    public func style(forScope scope: String) -> ScopeStyle? {
        style(forScope: HighlightScope(scope))
    }
}

extension HighlightResult {
    /// Renders the highlighted code as an attributed string.
    ///
    /// - Parameters:
    ///   - code: the exact code string that produced this result.
    ///   - theme: colors and font to apply.
    public func attributedString(for code: String, theme: HighlightTheme) -> NSAttributedString {
        let baseFont = theme.font.resolved()
        let text = NSMutableAttributedString(
            string: code,
            attributes: [
                .font: baseFont,
                .foregroundColor: theme.foregroundColor,
            ]
        )
        let fullLength = (code as NSString).length

        var boldItalicCache: [String: HighlightFont] = [:]
        for token in tokens {
            guard let style = theme.style(for: token) else { continue }
            guard token.range.location + token.range.length <= fullLength else { continue }

            var attributes: [NSAttributedString.Key: Any] = [:]
            if let color = style.color {
                attributes[.foregroundColor] = color
            }
            if style.bold || style.italic {
                let key = "\(style.bold ? "b" : "")\(style.italic ? "i" : "")"
                let font = boldItalicCache[key] ?? baseFont.withTraits(bold: style.bold, italic: style.italic)
                boldItalicCache[key] = font
                attributes[.font] = font
            }
            if !attributes.isEmpty {
                text.addAttributes(attributes, range: token.range)
            }
        }
        return text
    }
}

extension HighlightFont {
    /// Returns a variant of this font with the requested traits, falling
    /// back to the original font when the variant does not exist.
    func withTraits(bold: Bool, italic: Bool) -> HighlightFont {
        #if canImport(UIKit)
        var traits = fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return HighlightFont(descriptor: descriptor, size: pointSize)
        #elseif canImport(AppKit)
        var traits = fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        let descriptor = fontDescriptor.withSymbolicTraits(traits)
        return HighlightFont(descriptor: descriptor, size: pointSize) ?? self
        #endif
    }
}
