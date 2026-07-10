import Foundation

extension HighlightColor {
    /// `0xRRGGBB` convenience.
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension HighlightTheme {
    /// GitHub's light code theme (port of highlight.js `github.css`).
    public static let githubLight: HighlightTheme = {
        HighlightTheme(
            foregroundColor: HighlightColor(rgb: 0x24292E),
            backgroundColor: HighlightColor(rgb: 0xFFFFFF),
            styles: [
                .keyword: ScopeStyle(color: HighlightColor(rgb: 0xD73A49)),
                .doctag: ScopeStyle(color: HighlightColor(rgb: 0xD73A49)),
                .templateTag: ScopeStyle(color: HighlightColor(rgb: 0xD73A49)),
                .templateVariable: ScopeStyle(color: HighlightColor(rgb: 0xD73A49)),
                .type: ScopeStyle(color: HighlightColor(rgb: 0xD73A49)),
                .variableLanguage: ScopeStyle(color: HighlightColor(rgb: 0xD73A49)),

                .title: ScopeStyle(color: HighlightColor(rgb: 0x6F42C1)),
                .titleClass: ScopeStyle(color: HighlightColor(rgb: 0x6F42C1)),
                .titleClassInherited: ScopeStyle(color: HighlightColor(rgb: 0x6F42C1)),
                .titleFunction: ScopeStyle(color: HighlightColor(rgb: 0x6F42C1)),

                .attr: ScopeStyle(color: HighlightColor(rgb: 0x005CC5)),
                .attribute: ScopeStyle(color: HighlightColor(rgb: 0x005CC5)),
                .literal: ScopeStyle(color: HighlightColor(rgb: 0x005CC5)),
                .meta: ScopeStyle(color: HighlightColor(rgb: 0x005CC5)),
                .number: ScopeStyle(color: HighlightColor(rgb: 0x005CC5)),
                .operator: ScopeStyle(color: HighlightColor(rgb: 0x005CC5)),
                .selectorAttr: ScopeStyle(color: HighlightColor(rgb: 0x005CC5)),
                .selectorClass: ScopeStyle(color: HighlightColor(rgb: 0x005CC5)),
                .selectorId: ScopeStyle(color: HighlightColor(rgb: 0x005CC5)),
                .variable: ScopeStyle(color: HighlightColor(rgb: 0xE36209)),
                .variableConstant: ScopeStyle(color: HighlightColor(rgb: 0x005CC5)),

                .regexp: ScopeStyle(color: HighlightColor(rgb: 0x032F62)),
                .string: ScopeStyle(color: HighlightColor(rgb: 0x032F62)),
                .metaString: ScopeStyle(color: HighlightColor(rgb: 0x032F62)),
                .charEscape: ScopeStyle(color: HighlightColor(rgb: 0x22863A)),

                .builtIn: ScopeStyle(color: HighlightColor(rgb: 0xE36209)),
                .symbol: ScopeStyle(color: HighlightColor(rgb: 0xE36209)),

                .comment: ScopeStyle(color: HighlightColor(rgb: 0x6A737D)),
                .code: ScopeStyle(color: HighlightColor(rgb: 0x6A737D)),
                .formula: ScopeStyle(color: HighlightColor(rgb: 0x6A737D)),

                .name: ScopeStyle(color: HighlightColor(rgb: 0x22863A)),
                .quote: ScopeStyle(color: HighlightColor(rgb: 0x22863A)),
                .selectorPseudo: ScopeStyle(color: HighlightColor(rgb: 0x22863A)),
                .selectorTag: ScopeStyle(color: HighlightColor(rgb: 0x22863A)),
                .tag: ScopeStyle(color: HighlightColor(rgb: 0x22863A)),

                .subst: ScopeStyle(color: HighlightColor(rgb: 0x24292E)),
                .section: ScopeStyle(color: HighlightColor(rgb: 0x005CC5), bold: true),
                .bullet: ScopeStyle(color: HighlightColor(rgb: 0x735C0F)),

                .emphasis: ScopeStyle(color: HighlightColor(rgb: 0x24292E), italic: true),
                .strong: ScopeStyle(color: HighlightColor(rgb: 0x24292E), bold: true),

                .addition: ScopeStyle(color: HighlightColor(rgb: 0x22863A)),
                .deletion: ScopeStyle(color: HighlightColor(rgb: 0xB31D28)),

                .link: ScopeStyle(color: HighlightColor(rgb: 0x032F62)),
                .punctuation: ScopeStyle(color: HighlightColor(rgb: 0x24292E)),
                .property: ScopeStyle(color: HighlightColor(rgb: 0x005CC5)),
                .params: ScopeStyle(color: HighlightColor(rgb: 0x24292E)),
            ]
        )
    }()

    /// GitHub's dark code theme (port of highlight.js `github-dark.css`).
    public static let githubDark: HighlightTheme = {
        HighlightTheme(
            foregroundColor: HighlightColor(rgb: 0xC9D1D9),
            backgroundColor: HighlightColor(rgb: 0x0D1117),
            styles: [
                .keyword: ScopeStyle(color: HighlightColor(rgb: 0xFF7B72)),
                .doctag: ScopeStyle(color: HighlightColor(rgb: 0xFF7B72)),
                .templateTag: ScopeStyle(color: HighlightColor(rgb: 0xFF7B72)),
                .templateVariable: ScopeStyle(color: HighlightColor(rgb: 0xFF7B72)),
                .type: ScopeStyle(color: HighlightColor(rgb: 0xFF7B72)),
                .variableLanguage: ScopeStyle(color: HighlightColor(rgb: 0xFF7B72)),

                .title: ScopeStyle(color: HighlightColor(rgb: 0xD2A8FF)),
                .titleClass: ScopeStyle(color: HighlightColor(rgb: 0xD2A8FF)),
                .titleClassInherited: ScopeStyle(color: HighlightColor(rgb: 0xD2A8FF)),
                .titleFunction: ScopeStyle(color: HighlightColor(rgb: 0xD2A8FF)),

                .attr: ScopeStyle(color: HighlightColor(rgb: 0x79C0FF)),
                .attribute: ScopeStyle(color: HighlightColor(rgb: 0x79C0FF)),
                .literal: ScopeStyle(color: HighlightColor(rgb: 0x79C0FF)),
                .meta: ScopeStyle(color: HighlightColor(rgb: 0x79C0FF)),
                .number: ScopeStyle(color: HighlightColor(rgb: 0x79C0FF)),
                .operator: ScopeStyle(color: HighlightColor(rgb: 0x79C0FF)),
                .selectorAttr: ScopeStyle(color: HighlightColor(rgb: 0x79C0FF)),
                .selectorClass: ScopeStyle(color: HighlightColor(rgb: 0x79C0FF)),
                .selectorId: ScopeStyle(color: HighlightColor(rgb: 0x79C0FF)),
                .variable: ScopeStyle(color: HighlightColor(rgb: 0xFFA657)),
                .variableConstant: ScopeStyle(color: HighlightColor(rgb: 0x79C0FF)),

                .regexp: ScopeStyle(color: HighlightColor(rgb: 0xA5D6FF)),
                .string: ScopeStyle(color: HighlightColor(rgb: 0xA5D6FF)),
                .metaString: ScopeStyle(color: HighlightColor(rgb: 0xA5D6FF)),
                .charEscape: ScopeStyle(color: HighlightColor(rgb: 0x7EE787)),

                .builtIn: ScopeStyle(color: HighlightColor(rgb: 0xFFA657)),
                .symbol: ScopeStyle(color: HighlightColor(rgb: 0xFFA657)),

                .comment: ScopeStyle(color: HighlightColor(rgb: 0x8B949E)),
                .code: ScopeStyle(color: HighlightColor(rgb: 0x8B949E)),
                .formula: ScopeStyle(color: HighlightColor(rgb: 0x8B949E)),

                .name: ScopeStyle(color: HighlightColor(rgb: 0x7EE787)),
                .quote: ScopeStyle(color: HighlightColor(rgb: 0x7EE787)),
                .selectorPseudo: ScopeStyle(color: HighlightColor(rgb: 0x7EE787)),
                .selectorTag: ScopeStyle(color: HighlightColor(rgb: 0x7EE787)),
                .tag: ScopeStyle(color: HighlightColor(rgb: 0x7EE787)),

                .subst: ScopeStyle(color: HighlightColor(rgb: 0xC9D1D9)),
                .section: ScopeStyle(color: HighlightColor(rgb: 0x1F6FEB), bold: true),
                .bullet: ScopeStyle(color: HighlightColor(rgb: 0xF2CC60)),

                .emphasis: ScopeStyle(color: HighlightColor(rgb: 0xC9D1D9), italic: true),
                .strong: ScopeStyle(color: HighlightColor(rgb: 0xC9D1D9), bold: true),

                .addition: ScopeStyle(color: HighlightColor(rgb: 0xAFF5B4)),
                .deletion: ScopeStyle(color: HighlightColor(rgb: 0xFFDCD7)),

                .link: ScopeStyle(color: HighlightColor(rgb: 0xA5D6FF)),
                .punctuation: ScopeStyle(color: HighlightColor(rgb: 0xC9D1D9)),
                .property: ScopeStyle(color: HighlightColor(rgb: 0x79C0FF)),
                .params: ScopeStyle(color: HighlightColor(rgb: 0xC9D1D9)),
            ]
        )
    }()

    /// An Xcode "Default (Light)"-style theme.
    public static let xcodeLight: HighlightTheme = {
        HighlightTheme(
            foregroundColor: HighlightColor(rgb: 0x000000),
            backgroundColor: HighlightColor(rgb: 0xFFFFFF),
            styles: [
                .keyword: ScopeStyle(color: HighlightColor(rgb: 0x9B2393), bold: true),
                .templateTag: ScopeStyle(color: HighlightColor(rgb: 0x9B2393), bold: true),
                .templateVariable: ScopeStyle(color: HighlightColor(rgb: 0x9B2393), bold: true),
                .variableLanguage: ScopeStyle(color: HighlightColor(rgb: 0x9B2393), bold: true),

                .string: ScopeStyle(color: HighlightColor(rgb: 0xC41A16)),
                .regexp: ScopeStyle(color: HighlightColor(rgb: 0xC41A16)),
                .metaString: ScopeStyle(color: HighlightColor(rgb: 0xC41A16)),
                .charEscape: ScopeStyle(color: HighlightColor(rgb: 0xC41A16)),

                .number: ScopeStyle(color: HighlightColor(rgb: 0x1C00CF)),
                .literal: ScopeStyle(color: HighlightColor(rgb: 0x1C00CF)),
                .symbol: ScopeStyle(color: HighlightColor(rgb: 0x1C00CF)),

                .comment: ScopeStyle(color: HighlightColor(rgb: 0x536579)),
                .code: ScopeStyle(color: HighlightColor(rgb: 0x536579)),
                .formula: ScopeStyle(color: HighlightColor(rgb: 0x536579)),
                .quote: ScopeStyle(color: HighlightColor(rgb: 0x536579)),
                .doctag: ScopeStyle(color: HighlightColor(rgb: 0x506375), bold: true),

                .type: ScopeStyle(color: HighlightColor(rgb: 0x3900A0)),
                .titleClass: ScopeStyle(color: HighlightColor(rgb: 0x3900A0)),
                .titleClassInherited: ScopeStyle(color: HighlightColor(rgb: 0x3900A0)),

                .title: ScopeStyle(color: HighlightColor(rgb: 0x326D74)),
                .titleFunction: ScopeStyle(color: HighlightColor(rgb: 0x326D74)),
                .builtIn: ScopeStyle(color: HighlightColor(rgb: 0x6C36A9)),

                .meta: ScopeStyle(color: HighlightColor(rgb: 0x643820)),
                .attr: ScopeStyle(color: HighlightColor(rgb: 0x947100)),
                .attribute: ScopeStyle(color: HighlightColor(rgb: 0x947100)),
                .property: ScopeStyle(color: HighlightColor(rgb: 0x947100)),

                .variable: ScopeStyle(color: HighlightColor(rgb: 0x0F68A0)),
                .variableConstant: ScopeStyle(color: HighlightColor(rgb: 0x0F68A0)),

                .name: ScopeStyle(color: HighlightColor(rgb: 0x326D74)),
                .tag: ScopeStyle(color: HighlightColor(rgb: 0x326D74)),
                .selectorTag: ScopeStyle(color: HighlightColor(rgb: 0x326D74)),
                .selectorAttr: ScopeStyle(color: HighlightColor(rgb: 0x947100)),
                .selectorClass: ScopeStyle(color: HighlightColor(rgb: 0x3900A0)),
                .selectorId: ScopeStyle(color: HighlightColor(rgb: 0x3900A0)),
                .selectorPseudo: ScopeStyle(color: HighlightColor(rgb: 0x326D74)),

                .subst: ScopeStyle(color: HighlightColor(rgb: 0x000000)),
                .operator: ScopeStyle(color: HighlightColor(rgb: 0x000000)),
                .punctuation: ScopeStyle(color: HighlightColor(rgb: 0x000000)),
                .params: ScopeStyle(color: HighlightColor(rgb: 0x000000)),

                .section: ScopeStyle(color: HighlightColor(rgb: 0x1C00CF), bold: true),
                .bullet: ScopeStyle(color: HighlightColor(rgb: 0x643820)),
                .emphasis: ScopeStyle(color: HighlightColor(rgb: 0x000000), italic: true),
                .strong: ScopeStyle(color: HighlightColor(rgb: 0x000000), bold: true),
                .link: ScopeStyle(color: HighlightColor(rgb: 0x0F68A0)),

                .addition: ScopeStyle(color: HighlightColor(rgb: 0x22863A)),
                .deletion: ScopeStyle(color: HighlightColor(rgb: 0xB31D28)),
            ]
        )
    }()

    /// An Xcode "Default (Dark)"-style theme.
    public static let xcodeDark: HighlightTheme = {
        HighlightTheme(
            foregroundColor: HighlightColor(rgb: 0xFFFFFF),
            backgroundColor: HighlightColor(rgb: 0x292A30),
            styles: [
                .keyword: ScopeStyle(color: HighlightColor(rgb: 0xFC5FA3), bold: true),
                .templateTag: ScopeStyle(color: HighlightColor(rgb: 0xFC5FA3), bold: true),
                .templateVariable: ScopeStyle(color: HighlightColor(rgb: 0xFC5FA3), bold: true),
                .variableLanguage: ScopeStyle(color: HighlightColor(rgb: 0xFC5FA3), bold: true),

                .string: ScopeStyle(color: HighlightColor(rgb: 0xFC6A5D)),
                .regexp: ScopeStyle(color: HighlightColor(rgb: 0xFC6A5D)),
                .metaString: ScopeStyle(color: HighlightColor(rgb: 0xFC6A5D)),
                .charEscape: ScopeStyle(color: HighlightColor(rgb: 0xFC6A5D)),

                .number: ScopeStyle(color: HighlightColor(rgb: 0xD0BF69)),
                .literal: ScopeStyle(color: HighlightColor(rgb: 0xD0BF69)),
                .symbol: ScopeStyle(color: HighlightColor(rgb: 0xD0BF69)),

                .comment: ScopeStyle(color: HighlightColor(rgb: 0x6C7986)),
                .code: ScopeStyle(color: HighlightColor(rgb: 0x6C7986)),
                .formula: ScopeStyle(color: HighlightColor(rgb: 0x6C7986)),
                .quote: ScopeStyle(color: HighlightColor(rgb: 0x6C7986)),
                .doctag: ScopeStyle(color: HighlightColor(rgb: 0x92A9BD), bold: true),

                .type: ScopeStyle(color: HighlightColor(rgb: 0xD0A8FF)),
                .titleClass: ScopeStyle(color: HighlightColor(rgb: 0x9EF1DD)),
                .titleClassInherited: ScopeStyle(color: HighlightColor(rgb: 0xD0A8FF)),

                .title: ScopeStyle(color: HighlightColor(rgb: 0x67B7A4)),
                .titleFunction: ScopeStyle(color: HighlightColor(rgb: 0x67B7A4)),
                .builtIn: ScopeStyle(color: HighlightColor(rgb: 0xA167E6)),

                .meta: ScopeStyle(color: HighlightColor(rgb: 0xFD8F3F)),
                .attr: ScopeStyle(color: HighlightColor(rgb: 0xBF8555)),
                .attribute: ScopeStyle(color: HighlightColor(rgb: 0xBF8555)),
                .property: ScopeStyle(color: HighlightColor(rgb: 0xBF8555)),

                .variable: ScopeStyle(color: HighlightColor(rgb: 0x6BDFFF)),
                .variableConstant: ScopeStyle(color: HighlightColor(rgb: 0x6BDFFF)),

                .name: ScopeStyle(color: HighlightColor(rgb: 0x67B7A4)),
                .tag: ScopeStyle(color: HighlightColor(rgb: 0x67B7A4)),
                .selectorTag: ScopeStyle(color: HighlightColor(rgb: 0x67B7A4)),
                .selectorAttr: ScopeStyle(color: HighlightColor(rgb: 0xBF8555)),
                .selectorClass: ScopeStyle(color: HighlightColor(rgb: 0xD0A8FF)),
                .selectorId: ScopeStyle(color: HighlightColor(rgb: 0xD0A8FF)),
                .selectorPseudo: ScopeStyle(color: HighlightColor(rgb: 0x67B7A4)),

                .subst: ScopeStyle(color: HighlightColor(rgb: 0xFFFFFF)),
                .operator: ScopeStyle(color: HighlightColor(rgb: 0xFFFFFF)),
                .punctuation: ScopeStyle(color: HighlightColor(rgb: 0xFFFFFF)),
                .params: ScopeStyle(color: HighlightColor(rgb: 0xFFFFFF)),

                .section: ScopeStyle(color: HighlightColor(rgb: 0xD0BF69), bold: true),
                .bullet: ScopeStyle(color: HighlightColor(rgb: 0xFD8F3F)),
                .emphasis: ScopeStyle(color: HighlightColor(rgb: 0xFFFFFF), italic: true),
                .strong: ScopeStyle(color: HighlightColor(rgb: 0xFFFFFF), bold: true),
                .link: ScopeStyle(color: HighlightColor(rgb: 0x6BDFFF)),

                .addition: ScopeStyle(color: HighlightColor(rgb: 0xAFF5B4)),
                .deletion: ScopeStyle(color: HighlightColor(rgb: 0xFFDCD7)),
            ]
        )
    }()

    /// All built-in themes by name. Adaptive entries (`"github"`,
    /// `"xcode"`) follow the system appearance at render time.
    public static let builtInThemes: [String: HighlightTheme] = {
        [
            "github": .github,
            "github-light": .githubLight,
            "github-dark": .githubDark,
            "xcode": .xcode,
            "xcode-light": .xcodeLight,
            "xcode-dark": .xcodeDark,
        ]
    }()

    /// Names of all built-in themes, sorted.
    public static let builtInThemeNames: [String] = builtInThemes.keys.sorted()

    /// Looks up a built-in theme by name (case-insensitive), e.g.
    /// `"github"`, `"xcode-dark"`.
    public static func named(_ name: String) -> HighlightTheme? {
        builtInThemes[name.lowercased()]
    }
}
