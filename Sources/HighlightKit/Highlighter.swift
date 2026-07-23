public import Foundation

/// Syntax highlighter with a highlight.js-compatible parsing engine.
public final class Highlighter: Sendable {
    /// A process-wide instance with every bundled language registered.
    /// No result cache is installed implicitly.
    public static let shared = Highlighter()

    let registry: LanguageRegistry

    public init(languages: [LanguageDescriptor] = LanguageCatalog.all) {
        self.registry = LanguageRegistry(languages: languages)
    }

    public func register(_ language: LanguageDescriptor) {
        registry.register([language])
    }

    public var languageNames: [String] { registry.languageNames }

    /// Registered languages and their repository-oriented metadata.
    public var languages: [LanguageInfo] { registry.languageInfos }

    public func language(named name: String) -> LanguageInfo? {
        guard let canonical = registry.canonicalName(for: name) else { return nil }
        return languages.first { $0.name == canonical }
    }

    public func hasLanguage(named name: String) -> Bool {
        registry.hasLanguage(named: name)
    }

    /// Highlights synchronously. Unknown named languages and invalid
    /// grammars are reported instead of becoming plain text.
    public func highlight(
        _ code: String,
        selection: LanguageSelection,
        options: HighlightOptions = HighlightOptions(),
        budget: HighlightBudget? = nil,
        continuation: Continuation? = nil
    ) throws -> HighlightResult {
        let sourceLength = code.utf16.count
        let result: HighlightResult
        switch selection {
        case .plain:
            result = .plain(sourceLength: sourceLength)
        case .named(let language):
            result = try registry.highlight(
                code,
                languageName: language,
                ignoreIllegals: options.ignoreIllegals,
                continuation: continuation
            )
        case .automatic:
            result = registry.highlightAuto(code, subset: options.automaticSubset)
        }
        return result.normalizedSourceLength(sourceLength).applying(budget)
    }

    /// Cancellable named or automatic highlighting. Cancellation is always
    /// surfaced as `CancellationError`; partial candidates are never returned.
    public func highlight(
        _ code: String,
        selection: LanguageSelection,
        options: HighlightOptions = HighlightOptions(),
        budget: HighlightBudget? = nil,
        continuation: Continuation? = nil
    ) async throws -> HighlightResult {
        try Task.checkCancellation()
        let sourceLength = code.utf16.count
        let result: HighlightResult
        switch selection {
        case .plain:
            result = .plain(sourceLength: sourceLength)
        case .named(let language):
            result = try registry.highlight(
                code,
                languageName: language,
                ignoreIllegals: options.ignoreIllegals,
                continuation: continuation,
                cancellationProbe: { Task.isCancelled }
            )
        case .automatic:
            result = await registry.highlightAuto(code, subset: options.automaticSubset)
        }
        try Task.checkCancellation()
        return result.normalizedSourceLength(sourceLength).applying(budget)
    }

    public func attributedString(
        for code: String,
        selection: LanguageSelection,
        options: HighlightOptions = HighlightOptions(),
        budget: HighlightBudget? = nil,
        theme: HighlightTheme = .github
    ) throws -> NSAttributedString {
        try highlight(
            code,
            selection: selection,
            options: options,
            budget: budget
        ).attributedString(for: code, theme: theme)
    }

    public func attributedString(
        for code: String,
        selection: LanguageSelection,
        options: HighlightOptions = HighlightOptions(),
        budget: HighlightBudget? = nil,
        theme: HighlightTheme = .github
    ) async throws -> NSAttributedString {
        try await highlight(
            code,
            selection: selection,
            options: options,
            budget: budget
        ).attributedString(for: code, theme: theme)
    }
}

// Test-only compatibility for the pre-0.3 spelling. It is internal, so the
// source-breaking public surface contains no nullable or silent-fallback API.
extension Highlighter {
    func highlight(
        _ code: String,
        as languageName: String,
        ignoreIllegals: Bool = true,
        continuation: Continuation? = nil
    ) -> HighlightResult {
        (try? highlight(
            code,
            selection: .named(languageName),
            options: HighlightOptions(ignoreIllegals: ignoreIllegals),
            continuation: continuation
        )) ?? .plain(sourceLength: code.utf16.count)
    }

    func highlightAuto(_ code: String, subset: [String]? = nil) -> HighlightResult {
        (try? highlight(
            code,
            selection: .automatic,
            options: HighlightOptions(automaticSubset: subset)
        )) ?? .plain(sourceLength: code.utf16.count)
    }

    func highlightAuto(_ code: String, subset: [String]? = nil) async -> HighlightResult {
        (try? await highlight(
            code,
            selection: .automatic,
            options: HighlightOptions(automaticSubset: subset)
        )) ?? .plain(sourceLength: code.utf16.count)
    }

    func attributedString(
        for code: String,
        language: String? = nil,
        theme: HighlightTheme = .github
    ) -> NSAttributedString {
        let selection: LanguageSelection = language.map(LanguageSelection.named) ?? .automatic
        return (try? attributedString(for: code, selection: selection, theme: theme))
            ?? NSAttributedString(string: code)
    }
}
