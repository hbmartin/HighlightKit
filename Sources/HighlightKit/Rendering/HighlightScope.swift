/// A token's semantic role — `.keyword`, `.titleFunction`, … — matching
/// highlight.js scope names.
///
/// Typed like `Notification.Name`: a transparent wrapper over the scope
/// string, so the standard scopes get autocomplete and typo safety while
/// remaining an *open* set — grammars (including ones you register) can
/// introduce scopes no enum could represent, and dot-path scopes like
/// `"title.function.invoke"` resolve through structural fallback rather
/// than a flat case list. Performance is identical to raw strings by
/// construction (same hashing, same storage); the render path is
/// dominated by `NSAttributedString` itself, not key lookup.
public struct HighlightScope: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

// The standard highlight.js scopes
// (https://highlightjs.readthedocs.io/en/latest/css-classes-reference.html).
extension HighlightScope {
    // Language syntax
    public static let keyword: Self = "keyword"
    public static let builtIn: Self = "built_in"
    public static let type: Self = "type"
    public static let literal: Self = "literal"
    public static let number: Self = "number"
    public static let `operator`: Self = "operator"
    public static let punctuation: Self = "punctuation"
    public static let property: Self = "property"
    public static let regexp: Self = "regexp"
    public static let string: Self = "string"
    public static let charEscape: Self = "char.escape"
    public static let subst: Self = "subst"
    public static let symbol: Self = "symbol"
    public static let variable: Self = "variable"
    public static let variableLanguage: Self = "variable.language"
    public static let variableConstant: Self = "variable.constant"
    public static let title: Self = "title"
    public static let titleClass: Self = "title.class"
    public static let titleClassInherited: Self = "title.class.inherited"
    public static let titleFunction: Self = "title.function"
    public static let titleFunctionInvoke: Self = "title.function.invoke"
    public static let params: Self = "params"
    public static let comment: Self = "comment"
    public static let doctag: Self = "doctag"
    public static let meta: Self = "meta"
    public static let metaPrompt: Self = "meta.prompt"
    public static let metaString: Self = "meta.string"

    // Markup
    public static let section: Self = "section"
    public static let tag: Self = "tag"
    public static let name: Self = "name"
    public static let attr: Self = "attr"
    public static let attribute: Self = "attribute"
    public static let bullet: Self = "bullet"
    public static let code: Self = "code"
    public static let emphasis: Self = "emphasis"
    public static let strong: Self = "strong"
    public static let formula: Self = "formula"
    public static let link: Self = "link"
    public static let quote: Self = "quote"

    // CSS
    public static let selectorTag: Self = "selector-tag"
    public static let selectorId: Self = "selector-id"
    public static let selectorClass: Self = "selector-class"
    public static let selectorAttr: Self = "selector-attr"
    public static let selectorPseudo: Self = "selector-pseudo"

    // Templates and diffs
    public static let templateTag: Self = "template-tag"
    public static let templateVariable: Self = "template-variable"
    public static let addition: Self = "addition"
    public static let deletion: Self = "deletion"
}
