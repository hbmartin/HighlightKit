import Foundation

/// Opaque parser state that lets a later highlight call resume where a
/// previous one stopped — for incremental, line-by-line highlighting in
/// editors. Obtained from ``HighlightResult/continuation``.
///
/// It captures the **complete** resumable state: the mode stack, embedded
/// sub-language continuations, callback data (e.g. a heredoc's opening
/// token), and keyword-relevance counts. So a construct whose *state*
/// spans lines — an open block comment, a heredoc body, an embedded
/// language — resumes correctly on the next line.
///
/// `Continuation` is `Equatable`: two values are equal when they describe
/// the same downstream tokenization state. An incremental editor uses this
/// to stop cascading work — after re-highlighting a changed line, if the resulting
/// continuation equals the previously stored end-state of that line, the
/// following lines are unaffected and need not be re-highlighted:
///
/// ```swift
/// let result = highlighter.highlight(line, as: lang, continuation: prev)
/// if result.continuation == storedEndState[lineIndex] { return }  // converged
/// storedEndState[lineIndex] = result.continuation
/// ```
///
/// - Important: Highlighting a line **in isolation** cannot see the
///   surrounding text, so regex context that crosses a line boundary is
///   lost — `^`/`$`/`\b`/lookaround at a line's edge, and multi-line
///   lookahead such as a `(…) =>` arrow function whose `=>` is on a later
///   line. For such constructs a line-by-line pass can differ from
///   highlighting the whole text at once. This is intrinsic to
///   line-isolation and is shared by every line-mode highlighter; the
///   continuation carries all it *can*. When exactness matters (Phrase's
///   code blocks), highlight the whole block string in one call — that is
///   always token-for-token exact and, at this engine's throughput, fast
///   enough for typical blocks.
public struct Continuation: Equatable, Sendable {
    // Full resumable parser state (mode stack + per-run state a resumed
    // line needs to reproduce the whole-buffer tokenization).
    let state: ResumeState

    /// Equality compares every state component that can change downstream
    /// tokenization: the owning compiled-language generation, mode stack,
    /// callback data (for example a heredoc delimiter), keyword relevance
    /// counters, and recursively nested sub-language continuations.
    public static func == (lhs: Continuation, rhs: Continuation) -> Bool {
        statesAreStructurallyEqual(lhs.state, rhs.state)
    }

    private static func statesAreStructurallyEqual(_ lhs: ResumeState, _ rhs: ResumeState) -> Bool {
        if lhs === rhs { return true }
        guard lhs.owner === rhs.owner,
              framesAreEqual(lhs, rhs),
              lhs.keywordHits == rhs.keywordHits,
              lhs.subContinuations.count == rhs.subContinuations.count
        else { return false }

        for (name, leftState) in lhs.subContinuations {
            guard let rightState = rhs.subContinuations[name],
                  statesAreStructurallyEqual(leftState, rightState)
            else { return false }
        }
        return true
    }

    private static func framesAreEqual(_ lhs: ResumeState, _ rhs: ResumeState) -> Bool {
        var a: ModeFrame? = lhs.topFrame
        var b: ModeFrame? = rhs.topFrame
        while let fa = a, let fb = b {
            // Compiled modes are shared singletons within a language, so
            // identity comparison is exact and O(stack depth).
            if fa.mode !== fb.mode { return false }
            let leftData = lhs.responseData[ObjectIdentifier(fa)] ?? [:]
            let rightData = rhs.responseData[ObjectIdentifier(fb)] ?? [:]
            if leftData != rightData { return false }

            a = fa.parent
            b = fb.parent
        }
        return a == nil && b == nil
    }
}

/// Complete resumable state of a highlight pass — everything a following
/// line needs to continue exactly as whole-buffer highlighting would.
/// A reference type so it threads through the engine and the
/// ``Continuation`` without copying.
final class ResumeState: Sendable {
    /// Owning grammar generation. Besides keeping the immutable compiled
    /// graph alive, identity prevents a continuation from being resumed
    /// with another language, another Highlighter, or a re-registered
    /// grammar that happens to have the same name.
    let owner: CompiledLanguage
    /// Top of the mode stack (parent-linked, immutable).
    let topFrame: ModeFrame
    /// Continuation state for explicit single-name sub-languages. The
    /// engine keeps highlight.js's per-language behavior within one pass,
    /// then discards entries whose host mode is no longer active before it
    /// exposes a continuation to the next incremental chunk.
    let subContinuations: [String: ResumeState]
    /// Immutable callback-data snapshots keyed by mode-frame identity —
    /// carries e.g. nested `endSameAsBegin` delimiters independently.
    let responseData: [ObjectIdentifier: [String: String]]
    /// Per-run keyword hit counts (indexed by the owner generation's
    /// dense per-word counter ids), so relevance saturation is continuous
    /// across a line-by-line pass.
    let keywordHits: [UInt8]

    init(
        owner: CompiledLanguage,
        topFrame: ModeFrame,
        subContinuations: [String: ResumeState],
        responseData: [ObjectIdentifier: [String: String]],
        keywordHits: [UInt8]
    ) {
        self.owner = owner
        self.topFrame = topFrame
        self.subContinuations = subContinuations
        self.responseData = responseData
        self.keywordHits = keywordHits
    }

    /// A fresh state rooted at `language` (start of a document).
    static func initial(_ language: CompiledLanguage) -> ResumeState {
        ResumeState(
            owner: language,
            topFrame: ModeFrame(mode: language.root, parent: nil),
            subContinuations: [:],
            responseData: [:],
            keywordHits: Array(
                repeating: 0, count: language.keywordHitCounterCount
            )
        )
    }
}

/// The outcome of highlighting one piece of code.
public struct HighlightResult: Sendable {
    /// The language the code was highlighted as (`nil` for plain text).
    public let language: String?

    /// How confident the grammar is that the code is really this
    /// language; used to rank candidates during auto-detection.
    public let relevance: Double

    /// `true` when parsing was aborted because the code contained
    /// something illegal for the language (only when illegals are
    /// honored); `tokens` is empty in that case.
    public let illegal: Bool

    /// Scoped runs, ordered by location, non-overlapping. Text not
    /// covered by any token is plain.
    public let tokens: [HighlightToken]

    /// UTF-16 length of the source that produced this result.
    public let sourceLength: Int

    /// Number of syntax tokens omitted by the caller's token budget.
    public let omittedTokenCount: Int

    /// Whether token output was truncated while relevance and continuation
    /// were still computed for the complete source.
    public var isTruncated: Bool { omittedTokenCount > 0 }

    /// Parser state for continuing this highlight on subsequent text.
    public let continuation: Continuation?

    /// Second-best language found during auto-detection.
    public let secondBest: (language: String, relevance: Double)?

    init(
        language: String?,
        relevance: Double,
        illegal: Bool,
        tokens: [HighlightToken],
        sourceLength: Int = 0,
        omittedTokenCount: Int = 0,
        continuation: Continuation? = nil,
        secondBest: (language: String, relevance: Double)? = nil
    ) {
        self.language = language
        self.relevance = relevance
        self.illegal = illegal
        self.tokens = tokens
        self.sourceLength = sourceLength
        self.omittedTokenCount = omittedTokenCount
        self.continuation = continuation
        self.secondBest = secondBest
    }

    /// A no-highlighting result (plain text).
    static func plain(language: String? = nil, sourceLength: Int = 0) -> HighlightResult {
        HighlightResult(
            language: language,
            relevance: 0,
            illegal: false,
            tokens: [],
            sourceLength: sourceLength
        )
    }

    func normalizedSourceLength(_ sourceLength: Int) -> HighlightResult {
        HighlightResult(
            language: language,
            relevance: relevance,
            illegal: illegal,
            tokens: tokens,
            sourceLength: sourceLength,
            omittedTokenCount: omittedTokenCount,
            continuation: continuation,
            secondBest: secondBest
        )
    }

    func applying(_ budget: HighlightBudget?) -> HighlightResult {
        guard let budget, tokens.count > budget.maximumTokens else { return self }
        return HighlightResult(
            language: language,
            relevance: relevance,
            illegal: illegal,
            tokens: Array(tokens.prefix(budget.maximumTokens)),
            sourceLength: sourceLength,
            omittedTokenCount: tokens.count - budget.maximumTokens,
            continuation: continuation,
            secondBest: secondBest
        )
    }
}

/// A single frame of the runtime mode stack. Frames are immutable and
/// form a parent-linked chain, so a chain tail can be stored and resumed
/// safely (see ``Continuation``).
final class ModeFrame: Sendable {
    let mode: CompiledMode
    let parent: ModeFrame?

    init(mode: CompiledMode, parent: ModeFrame?) {
        self.mode = mode
        self.parent = parent
    }
}
