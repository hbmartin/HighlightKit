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
        continuation: Continuation? = nil,
        cache: HighlightCache? = nil,
        cacheKey: HighlightCacheKey? = nil
    ) async throws -> HighlightResult {
        guard let cache, let cacheKey else {
            if let cache { await cache.recordBypass() }
            return try await highlightUncached(
                code,
                selection: selection,
                options: options,
                budget: budget,
                continuation: continuation
            )
        }

        try Task.checkCancellation()
        let canonicalSelection: LanguageSelection
        let selectionIdentity: String
        switch selection {
        case .plain:
            canonicalSelection = .plain
            selectionIdentity = "plain"
        case .named(let requested):
            guard let canonical = registry.canonicalName(for: requested) else {
                // An unknown name is unknown for the whole registry
                // revision, so the negative entry ignores source length and
                // continuation identity — one entry per name, not one per
                // request shape.
                let key = makeCacheRequestKey(
                    caller: cacheKey,
                    selection: "unknown:\(requested.lowercased())",
                    options: options,
                    sourceLength: 0,
                    continuation: nil
                )
                _ = await cache.recordUnknownLanguage(requested, for: key)
                throw HighlightError.unknownLanguage(requested)
            }
            canonicalSelection = .named(canonical)
            selectionIdentity = "named:\(canonical)"
        case .automatic:
            let subset = options.automaticSubset.map { names in
                names.compactMap(registry.canonicalName(for:))
            }
            canonicalSelection = .automatic
            selectionIdentity = "automatic:\(subset?.joined(separator: ",") ?? "*")"
        }

        let sourceLength = code.utf16.count
        let requestKey = makeCacheRequestKey(
            caller: cacheKey,
            selection: selectionIdentity,
            options: options,
            sourceLength: sourceLength,
            continuation: continuation
        )
        let result = try await cache.value(
            for: requestKey,
            allowsInsertion: budget == nil
        ) { [self] in
            try await highlightUncached(
                code,
                selection: canonicalSelection,
                options: options,
                budget: nil,
                continuation: continuation
            )
        }
        try Task.checkCancellation()
        return result.applying(budget)
    }

    private func highlightUncached(
        _ code: String,
        selection: LanguageSelection,
        options: HighlightOptions,
        budget: HighlightBudget?,
        continuation: Continuation?
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

    private func makeCacheRequestKey(
        caller: HighlightCacheKey,
        selection: String,
        options: HighlightOptions,
        sourceLength: Int,
        continuation: Continuation?
    ) -> HighlightCacheRequestKey {
        HighlightCacheRequestKey(
            caller: caller,
            registry: ObjectIdentifier(registry),
            registryRevision: registry.revision,
            selection: selection,
            ignoreIllegals: options.ignoreIllegals,
            sourceLength: sourceLength,
            continuation: continuation.map { ObjectIdentifier($0.state) }
        )
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
        let result = try await highlight(
            code,
            selection: selection,
            options: options,
            budget: budget
        )
        try Task.checkCancellation()
        let renderer = HighlightRenderer(theme: theme)
        let text = NSMutableAttributedString(
            string: code,
            attributes: [
                .font: renderer.regularFont,
                .foregroundColor: theme.foregroundColor,
            ]
        )
        _ = try renderer.apply(
            result,
            to: text,
            mappings: nil,
            options: HighlightRenderOptions(),
            cancellationProbe: { Task.isCancelled }
        )
        try Task.checkCancellation()
        return text
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
