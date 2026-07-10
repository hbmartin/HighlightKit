import Foundation
import Testing
@testable import HighlightKit

@Suite("Themes and rendering")
struct ThemeTests {
    @Test func scopeFallbackWalksDotPath() {
        let theme = HighlightTheme(
            foregroundColor: .black,
            backgroundColor: .white,
            styles: ["title": ScopeStyle(color: .red)]
        )
        #expect(theme.style(forScope: "title.function.invoke")?.color == .red)
        #expect(theme.style(forScope: "title")?.color == .red)
        #expect(theme.style(forScope: "keyword") == nil)
    }

    @Test func exactScopeWinsOverPrefix() {
        let theme = HighlightTheme(
            foregroundColor: .black,
            backgroundColor: .white,
            styles: [
                "title": ScopeStyle(color: .red),
                "title.function": ScopeStyle(color: .blue),
            ]
        )
        #expect(theme.style(forScope: "title.function")?.color == .blue)
        #expect(theme.style(forScope: "title.class")?.color == .red)
    }

    @Test func tokenStyleFallsBackThroughOuterScopes() {
        let theme = HighlightTheme(
            foregroundColor: .black,
            backgroundColor: .white,
            styles: ["string": ScopeStyle(color: .green)]
        )
        // innermost scope unknown, outer "string" applies
        let token = HighlightToken(range: NSRange(location: 0, length: 1), scopes: ["string", "unknown-scope"])
        #expect(theme.style(for: token)?.color == .green)
    }

    @Test func attributedStringAppliesColorsAndFonts() {
        let code = #"{"a": true}"#
        let result = Highlighter.shared.highlight(code, as: "json")
        let attributed = result.attributedString(for: code, theme: .githubLight)
        #expect(attributed.length == (code as NSString).length)

        // base attributes exist everywhere
        var effective = NSRange()
        let baseColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: &effective)
        #expect(baseColor != nil)
        let font = attributed.attribute(.font, at: 0, effectiveRange: &effective)
        #expect(font != nil)

        // the attr token got its themed color
        if let attrToken = result.tokens.first(where: { $0.scope == "attr" }) {
            let color = attributed.attribute(.foregroundColor, at: attrToken.range.location, effectiveRange: &effective) as? HighlightColor
            #expect(color == HighlightTheme.githubLight.styles["attr"]?.color)
        } else {
            Issue.record("no attr token")
        }
    }

    @Test func boldAndItalicTraitsApply() {
        let theme = HighlightTheme(
            foregroundColor: .black,
            backgroundColor: .white,
            styles: ["strong": ScopeStyle(bold: true), "emphasis": ScopeStyle(italic: true)]
        )
        let custom = LanguageDescriptor(name: "mini") {
            LanguageDefinition(name: "mini", root: Mode(contains: [
                Mode(scope: "strong", begin: #"\*\*[^*]+\*\*"#),
                Mode(scope: "emphasis", begin: "_[^_]+_"),
            ]))
        }
        let highlighter = Highlighter(languages: [custom])
        let code = "**bold** and _italic_"
        let result = highlighter.highlight(code, as: "mini")
        let attributed = result.attributedString(for: code, theme: theme)

        var range = NSRange()
        let boldFont = attributed.attribute(.font, at: 0, effectiveRange: &range) as? HighlightFont
        #expect(boldFont != nil)
        #if canImport(UIKit)
        #expect(boldFont?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        #else
        #expect(boldFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #endif
    }

    @Test func builtInThemesResolveFonts() {
        #expect(HighlightTheme.githubLight.font.resolved().pointSize == 13)
        let named = HighlightTheme.FontSpec(name: "Menlo", size: 15)
        #expect(named.resolved().pointSize == 15)
        let missing = HighlightTheme.FontSpec(name: "NoSuchFontFamily", size: 11)
        #expect(missing.resolved().pointSize == 11) // falls back to system mono
    }

    @Test func themeRegistryLooksUpByName() {
        #expect(HighlightTheme.builtInThemeNames == [
            "github", "github-dark", "github-light",
            "xcode", "xcode-dark", "xcode-light",
        ])
        #expect(HighlightTheme.named("XCode-Dark") != nil) // case-insensitive
        #expect(HighlightTheme.named("no-such-theme") == nil)
        // every named theme styles a keyword
        for name in HighlightTheme.builtInThemeNames {
            let theme = HighlightTheme.named(name)
            #expect(theme?.style(forScope: "keyword")?.color != nil, Comment(rawValue: name))
        }
    }

    @Test func builtInThemeCopiesRemainIndependent() {
        var theme = HighlightTheme.githubLight
        theme.font.size = 99
        theme.styles["test-only"] = ScopeStyle(bold: true)

        #expect(HighlightTheme.githubLight.font.size == 13)
        #expect(HighlightTheme.githubLight.styles["test-only"] == nil)

        var registry = HighlightTheme.builtInThemes
        registry.removeValue(forKey: "github-light")
        #expect(HighlightTheme.named("github-light") != nil)
    }

    @Test func builtInThemesSupportConcurrentReads() async {
        await withTaskGroup(of: Bool.self) { group in
            for index in 0..<64 {
                group.addTask {
                    let theme: HighlightTheme = switch index % 6 {
                    case 0: .github
                    case 1: .githubLight
                    case 2: .githubDark
                    case 3: .xcode
                    case 4: .xcodeLight
                    default: .xcodeDark
                    }
                    return theme.styles[.keyword] != nil
                        && HighlightTheme.builtInThemeNames.count == 6
                }
            }
            for await valid in group {
                #expect(valid)
            }
        }
    }

    @Test func oneCallAttributedStringConvenience() {
        let code = "let x = 1"
        // explicit language
        let explicit = Highlighter.shared.attributedString(for: code, language: "swift", theme: .xcodeLight)
        #expect(explicit.string == code)
        var range = NSRange()
        let color = explicit.attribute(.foregroundColor, at: 0, effectiveRange: &range) as? HighlightColor
        #expect(color != nil) // `let` is a styled keyword
        // automatic detection
        let auto = Highlighter.shared.attributedString(for: "SELECT id FROM users;")
        #expect(auto.string == "SELECT id FROM users;")
    }
}
