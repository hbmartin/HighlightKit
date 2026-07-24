public import Foundation
import Synchronization

/// Maps a UTF-16 source range to an equal-length range in caller-owned text.
public struct HighlightRangeMapping: Hashable, Sendable {
    public let sourceRange: NSRange
    public let destinationRange: NSRange

    public init(sourceRange: NSRange, destinationRange: NSRange) {
        self.sourceRange = sourceRange
        self.destinationRange = destinationRange
    }
}

public struct HighlightRenderOptions: Hashable, Sendable {
    public var appliesForegroundColors: Bool
    public var appliesFontTraits: Bool
    public var maximumRenderedRuns: Int?

    public init(
        appliesForegroundColors: Bool = true,
        appliesFontTraits: Bool = true,
        maximumRenderedRuns: Int? = nil
    ) {
        if let maximumRenderedRuns {
            precondition(maximumRenderedRuns >= 0, "maximumRenderedRuns must not be negative")
        }
        self.appliesForegroundColors = appliesForegroundColors
        self.appliesFontTraits = appliesFontTraits
        self.maximumRenderedRuns = maximumRenderedRuns
    }
}

public struct HighlightRenderSummary: Hashable, Sendable {
    public let appliedRuns: Int
    public let omittedRuns: Int
    public var isTruncated: Bool { omittedRuns > 0 }

    public init(appliedRuns: Int, omittedRuns: Int) {
        self.appliedRuns = appliedRuns
        self.omittedRuns = omittedRuns
    }
}

public enum HighlightRenderingError: Error, Equatable, Sendable {
    case invalidRangeMapping(HighlightRangeMapping)
}

/// A reusable theme renderer that overlays syntax attributes onto existing
/// attributed text without replacing caller-owned attributes.
public final class HighlightRenderer: @unchecked Sendable {
    private struct ResolvedStyle {
        let id: Int
        let color: HighlightColor?
        let bold: Bool
        let italic: Bool
    }

    private enum CachedStyle {
        case missing
        case value(ResolvedStyle)
    }

    private struct FontKey: Hashable {
        let font: ObjectIdentifier
        let bold: Bool
        let italic: Bool
    }

    private final class FontBox: @unchecked Sendable {
        let value: HighlightFont

        init(_ value: HighlightFont) {
            self.value = value
        }
    }

    private struct State {
        var styles: [String: CachedStyle] = [:]
        var distinctStyles: [ResolvedStyle] = []
        var fonts: [FontKey: FontBox] = [:]
    }

    private struct Candidate {
        var range: NSRange
        let style: ResolvedStyle
    }

    private struct Mutation {
        let range: NSRange
        let attributes: [NSAttributedString.Key: Any]
    }

    public let theme: HighlightTheme
    public let regularFont: HighlightFont
    public let boldFont: HighlightFont
    public let italicFont: HighlightFont
    public let boldItalicFont: HighlightFont

    private let state = Mutex(State())

    public init(theme: HighlightTheme) {
        self.theme = theme
        let regular = theme.font.resolved()
        self.regularFont = regular
        self.boldFont = regular.withTraits(bold: true, italic: false)
        self.italicFont = regular.withTraits(bold: false, italic: true)
        self.boldItalicFont = regular.withTraits(bold: true, italic: true)
    }

    /// Applies syntax attributes to existing storage and returns exact run
    /// accounting after token/range/font intersections.
    ///
    /// When `mappings` is omitted, the overlay covers the shared prefix of
    /// the result's source length and `text`; a mismatched pairing renders
    /// a clipped overlay instead of failing. Explicit mappings are always
    /// validated and throw on any inconsistency.
    @discardableResult
    public func apply(
        _ result: HighlightResult,
        to text: NSMutableAttributedString,
        mappings requestedMappings: [HighlightRangeMapping]? = nil,
        options: HighlightRenderOptions = HighlightRenderOptions()
    ) throws -> HighlightRenderSummary {
        try apply(
            result,
            to: text,
            mappings: requestedMappings,
            options: options,
            cancellationProbe: nil
        )
    }

    func apply(
        _ result: HighlightResult,
        to text: NSMutableAttributedString,
        mappings requestedMappings: [HighlightRangeMapping]?,
        options: HighlightRenderOptions,
        cancellationProbe: (@Sendable () -> Bool)?
    ) throws -> HighlightRenderSummary {
        if cancellationProbe?() == true { throw CancellationError() }
        let sourceLength = result.sourceLength == 0 ? text.length : result.sourceLength
        let mappings: [HighlightRangeMapping]
        if let requestedMappings {
            for mapping in requestedMappings {
                guard mapping.sourceRange.location >= 0,
                      mapping.destinationRange.location >= 0,
                      mapping.sourceRange.length == mapping.destinationRange.length,
                      NSMaxRange(mapping.sourceRange) <= sourceLength,
                      NSMaxRange(mapping.destinationRange) <= text.length
                else { throw HighlightRenderingError.invalidRangeMapping(mapping) }
            }
            mappings = requestedMappings
        } else {
            // A result paired with text of a different length (a stale cache
            // entry, the wrong string) must degrade to a clipped overlay:
            // the non-throwing public conveniences build on this path.
            let overlap = min(sourceLength, text.length)
            mappings = [HighlightRangeMapping(
                sourceRange: NSRange(location: 0, length: overlap),
                destinationRange: NSRange(location: 0, length: overlap)
            )]
        }
        guard options.appliesForegroundColors || options.appliesFontTraits else {
            return HighlightRenderSummary(appliedRuns: 0, omittedRuns: 0)
        }

        var candidates: [Candidate] = []
        candidates.reserveCapacity(result.tokens.count)
        for (tokenIndex, token) in result.tokens.enumerated() {
            if tokenIndex & 63 == 0, cancellationProbe?() == true { throw CancellationError() }
            guard let style = resolvedStyle(for: token) else { continue }
            let hasColor = options.appliesForegroundColors && style.color != nil
            let hasTraits = options.appliesFontTraits && (style.bold || style.italic)
            guard hasColor || hasTraits else { continue }
            for mapping in mappings {
                let intersection = NSIntersectionRange(token.range, mapping.sourceRange)
                guard intersection.length > 0 else { continue }
                let destination = NSRange(
                    location: mapping.destinationRange.location
                        + intersection.location - mapping.sourceRange.location,
                    length: intersection.length
                )
                if let last = candidates.last,
                   last.style.id == style.id,
                   NSMaxRange(last.range) == destination.location {
                    candidates[candidates.count - 1].range.length += destination.length
                } else {
                    candidates.append(Candidate(range: destination, style: style))
                }
            }
        }
        candidates.sort { $0.range.location < $1.range.location }

        var mutations: [Mutation] = []
        for candidate in candidates {
            if cancellationProbe?() == true { throw CancellationError() }
            var colorAttributes: [NSAttributedString.Key: Any] = [:]
            if options.appliesForegroundColors, let color = candidate.style.color {
                colorAttributes[.foregroundColor] = color
            }
            guard options.appliesFontTraits,
                  candidate.style.bold || candidate.style.italic
            else {
                if !colorAttributes.isEmpty {
                    mutations.append(Mutation(range: candidate.range, attributes: colorAttributes))
                }
                continue
            }

            text.enumerateAttribute(.font, in: candidate.range) { value, range, _ in
                let base = (value as? HighlightFont) ?? regularFont
                var attributes = colorAttributes
                attributes[.font] = resolvedFont(
                    from: base,
                    bold: candidate.style.bold,
                    italic: candidate.style.italic
                )
                mutations.append(Mutation(range: range, attributes: attributes))
            }
        }

        let limit = min(options.maximumRenderedRuns ?? mutations.count, mutations.count)
        for (index, mutation) in mutations.prefix(limit).enumerated() {
            if index & 63 == 0, cancellationProbe?() == true { throw CancellationError() }
            text.addAttributes(mutation.attributes, range: mutation.range)
        }
        return HighlightRenderSummary(
            appliedRuns: limit,
            omittedRuns: mutations.count - limit
        )
    }

    public func attributedString(
        for code: String,
        result: HighlightResult,
        options: HighlightRenderOptions = HighlightRenderOptions()
    ) -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: code,
            attributes: [
                .font: regularFont,
                .foregroundColor: theme.foregroundColor,
            ]
        )
        _ = try? apply(result, to: text, options: options)
        return text
    }

    private func resolvedStyle(for token: HighlightToken) -> ResolvedStyle? {
        let key = token.scopes.joined(separator: "\u{1F}")
        return state.withLock { state in
            if let cached = state.styles[key] {
                switch cached {
                case .missing: return nil
                case .value(let style): return style
                }
            }
            guard let style = theme.style(for: token) else {
                state.styles[key] = .missing
                return nil
            }
            if let existing = state.distinctStyles.first(where: {
                $0.bold == style.bold && $0.italic == style.italic
                    && colorsEqual($0.color, style.color)
            }) {
                state.styles[key] = .value(existing)
                return existing
            }
            let resolved = ResolvedStyle(
                id: state.distinctStyles.count,
                color: style.color,
                bold: style.bold,
                italic: style.italic
            )
            state.distinctStyles.append(resolved)
            state.styles[key] = .value(resolved)
            return resolved
        }
    }

    private func resolvedFont(from font: HighlightFont, bold: Bool, italic: Bool) -> HighlightFont {
        if font === regularFont {
            switch (bold, italic) {
            case (true, true): return boldItalicFont
            case (true, false): return boldFont
            case (false, true): return italicFont
            case (false, false): return regularFont
            }
        }
        let key = FontKey(font: ObjectIdentifier(font), bold: bold, italic: italic)
        let box = state.withLock { state in
            if let cached = state.fonts[key] { return cached }
            let resolved = font.withTraits(bold: bold, italic: italic)
            let box = FontBox(resolved)
            state.fonts[key] = box
            return box
        }
        return box.value
    }

    private func colorsEqual(_ lhs: HighlightColor?, _ rhs: HighlightColor?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (lhs?, rhs?): lhs.isEqual(rhs)
        default: false
        }
    }
}
