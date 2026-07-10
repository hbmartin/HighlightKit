import Foundation
import Testing
@testable import HighlightKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@Suite("Dynamic themes")
struct DynamicThemeTests {
    @Test func adaptiveColorResolvesPerAppearance() {
        let light = HighlightColor(rgb: 0x111111)
        let dark = HighlightColor(rgb: 0xEEEEEE)
        let adaptive = HighlightColor.adaptive(light: light, dark: dark)

        #if os(watchOS)
        #expect(adaptive == dark)
        #elseif canImport(UIKit)
        let lightTrait = UITraitCollection(userInterfaceStyle: .light)
        let darkTrait = UITraitCollection(userInterfaceStyle: .dark)
        #expect(adaptive.resolvedColor(with: lightTrait) == light.resolvedColor(with: lightTrait))
        #expect(adaptive.resolvedColor(with: darkTrait) == dark.resolvedColor(with: darkTrait))
        #elseif canImport(AppKit)
        var resolved: NSColor?
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            resolved = NSColor(cgColor: adaptive.cgColor)
        }
        var resolvedDark: NSColor?
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            resolvedDark = NSColor(cgColor: adaptive.cgColor)
        }
        #expect(resolved != nil)
        #expect(resolvedDark != nil)
        #expect(resolved != resolvedDark)
        #endif
    }

    @Test func adaptiveThemeMergesScopes() {
        let light = HighlightTheme(
            foregroundColor: .black,
            backgroundColor: .white,
            styles: [
                "keyword": ScopeStyle(color: HighlightColor(rgb: 0xAA0000), bold: true),
                "only-light": ScopeStyle(color: HighlightColor(rgb: 0x001100)),
            ]
        )
        let dark = HighlightTheme(
            foregroundColor: .white,
            backgroundColor: .black,
            styles: [
                "keyword": ScopeStyle(color: HighlightColor(rgb: 0xFF8888)),
                "only-dark": ScopeStyle(color: HighlightColor(rgb: 0x88FF88), italic: true),
            ]
        )
        let merged = HighlightTheme.adaptive(light: light, dark: dark)
        #expect(merged.styles["keyword"] != nil)
        #expect(merged.styles["keyword"]?.bold == true)
        #expect(merged.styles["only-light"]?.color != nil)
        #expect(merged.styles["only-dark"]?.italic == true)
        #expect(Set(merged.styles.keys) == ["keyword", "only-light", "only-dark"])
    }

    @Test func builtInAdaptiveGithubThemeRenders() {
        let code = "let x = 42 // answer"
        let result = Highlighter.shared.highlight(code, as: "swift")
        for theme in [HighlightTheme.github, .githubLight, .githubDark] {
            let attributed = result.attributedString(for: code, theme: theme)
            #expect(attributed.length == (code as NSString).length)
            var range = NSRange()
            #expect(attributed.attribute(.foregroundColor, at: 0, effectiveRange: &range) != nil)
        }
    }

    @Test func builtInAdaptiveThemeStillResolvesBothAppearances() {
        #if os(watchOS)
        #expect(HighlightTheme.github.foregroundColor == HighlightTheme.githubDark.foregroundColor)
        #elseif canImport(UIKit)
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        #expect(
            HighlightTheme.github.foregroundColor.resolvedColor(with: light)
                == HighlightTheme.githubLight.foregroundColor.resolvedColor(with: light)
        )
        #expect(
            HighlightTheme.github.foregroundColor.resolvedColor(with: dark)
                == HighlightTheme.githubDark.foregroundColor.resolvedColor(with: dark)
        )
        #elseif canImport(AppKit)
        func resolved(_ color: NSColor, as name: NSAppearance.Name) -> NSColor? {
            var result: NSColor?
            NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
                result = NSColor(cgColor: color.cgColor)?.usingColorSpace(.deviceRGB)
            }
            return result
        }
        #expect(
            resolved(HighlightTheme.github.foregroundColor, as: .aqua)
                == resolved(HighlightTheme.githubLight.foregroundColor, as: .aqua)
        )
        #expect(
            resolved(HighlightTheme.github.foregroundColor, as: .darkAqua)
                == resolved(HighlightTheme.githubDark.foregroundColor, as: .darkAqua)
        )
        #endif
    }
}
