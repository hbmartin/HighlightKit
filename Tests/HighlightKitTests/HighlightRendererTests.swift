import Foundation
import Testing
@testable import HighlightKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@Suite("Composable highlight renderer")
struct HighlightRendererTests {
    @Test func overlayPreservesCallerAttributes() throws {
        let code = "let value = 42"
        let result = try Highlighter.shared.highlight(code, selection: .named("swift"))
        let text = NSMutableAttributedString(string: code)
        let range = NSRange(location: 0, length: text.length)
        let background = HighlightColor.systemYellow
        let link = URL(string: "https://example.com")!
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        text.addAttributes([
            .backgroundColor: background,
            .link: link,
            .paragraphStyle: paragraph,
        ], range: range)

        let summary = try HighlightRenderer(theme: .githubLight).apply(result, to: text)
        #expect(summary.appliedRuns > 0)
        #expect((text.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? HighlightColor)?.isEqual(background) == true)
        #expect((text.attribute(.link, at: 0, effectiveRange: nil) as? URL) == link)
        #expect((text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.lineSpacing == 3)
    }

    @Test func colorsAndTraitsCanBeEnabledIndependently() throws {
        let code = "let value = 42"
        let result = try Highlighter.shared.highlight(code, selection: .named("swift"))
        let renderer = HighlightRenderer(theme: .githubLight)
        let original = HighlightFont.monospacedSystemFont(ofSize: 17, weight: .regular)
        let colorsOnly = NSMutableAttributedString(string: code, attributes: [.font: original])
        _ = try renderer.apply(
            result,
            to: colorsOnly,
            options: HighlightRenderOptions(appliesForegroundColors: true, appliesFontTraits: false)
        )
        #expect((colorsOnly.attribute(.font, at: 0, effectiveRange: nil) as? HighlightFont) === original)

        let traitsOnly = NSMutableAttributedString(string: code, attributes: [.font: original])
        _ = try renderer.apply(
            result,
            to: traitsOnly,
            options: HighlightRenderOptions(appliesForegroundColors: false, appliesFontTraits: true)
        )
        #expect(traitsOnly.attribute(.foregroundColor, at: 0, effectiveRange: nil) == nil)
    }

    @Test func utf16MappingsRebaseSelectedRanges() throws {
        let code = "let emoji = \"😀\""
        let result = try Highlighter.shared.highlight(code, selection: .named("swift"))
        let destination = NSMutableAttributedString(string: "prefix: " + code)
        let mapping = HighlightRangeMapping(
            sourceRange: NSRange(location: 0, length: code.utf16.count),
            destinationRange: NSRange(location: 8, length: code.utf16.count)
        )
        let summary = try HighlightRenderer(theme: .githubLight).apply(
            result,
            to: destination,
            mappings: [mapping]
        )
        #expect(summary.appliedRuns > 0)
        #expect(destination.attribute(.foregroundColor, at: 0, effectiveRange: nil) == nil)
        #expect(destination.attribute(.foregroundColor, at: 8, effectiveRange: nil) != nil)
    }

    @Test func mismatchedResultAndTextClampToTheSharedPrefix() throws {
        let code = "let x = 1"
        let result = try Highlighter.shared.highlight(code, selection: .named("swift"))
        let renderer = HighlightRenderer(theme: .githubLight)

        let shorter = renderer.attributedString(for: "let", result: result)
        #expect(shorter.length == 3)
        #expect(shorter.attribute(.foregroundColor, at: 0, effectiveRange: nil) != nil)

        let longer = NSMutableAttributedString(string: code + " // trailing")
        let summary = try renderer.apply(result, to: longer)
        #expect(summary.appliedRuns > 0)
    }

    @Test func invalidMappingsThrow() throws {
        let result = try Highlighter.shared.highlight("let x = 1", selection: .named("swift"))
        let text = NSMutableAttributedString(string: "short")
        let mapping = HighlightRangeMapping(
            sourceRange: NSRange(location: 0, length: 3),
            destinationRange: NSRange(location: 4, length: 3)
        )
        #expect(throws: HighlightRenderingError.self) {
            try HighlightRenderer(theme: .githubLight).apply(result, to: text, mappings: [mapping])
        }
    }

    @Test func runBudgetCountsPostFontIntersections() throws {
        let theme = HighlightTheme(
            foregroundColor: .black,
            backgroundColor: .white,
            styles: [
                .keyword: ScopeStyle(color: .red, bold: true),
                .literal: ScopeStyle(color: .red, bold: true),
            ]
        )
        let result = HighlightResult(
            language: "test",
            relevance: 0,
            illegal: false,
            tokens: [
                HighlightToken(range: NSRange(location: 0, length: 2), scopes: ["keyword"]),
                HighlightToken(range: NSRange(location: 2, length: 2), scopes: ["literal"]),
            ],
            sourceLength: 4
        )
        let text = NSMutableAttributedString(string: "abcd")
        text.addAttribute(.font, value: HighlightFont.systemFont(ofSize: 12), range: NSRange(location: 0, length: 2))
        text.addAttribute(.font, value: HighlightFont.systemFont(ofSize: 14), range: NSRange(location: 2, length: 2))
        let summary = try HighlightRenderer(theme: theme).apply(
            result,
            to: text,
            options: HighlightRenderOptions(maximumRenderedRuns: 1)
        )
        #expect(summary.appliedRuns == 1)
        #expect(summary.omittedRuns == 1)
        #expect(summary.isTruncated)
    }
}
