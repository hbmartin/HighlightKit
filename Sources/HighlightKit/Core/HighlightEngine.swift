import Foundation

/// The parsing core: walks the input with the compiled mode tree's
/// matchers and drives a ``TokenEmitter``. Faithful port of the
/// highlight.js `_highlight` loop.
struct HighlightEngine {
    /// Monotonic state predicate used by async auto-detection: once it
    /// returns true it must remain true for the candidate's lifetime.
    /// Production passes `Task.isCancelled`; tests may use transient probes
    /// only to verify that the local component latches an observation.
    typealias CancellationProbe = @Sendable () -> Bool

    /// Resolves language names for sub-language delegation.
    let registry: LanguageRegistry

    /// Languages already active above this engine in a nested
    /// sub-language call. `nil` for the normal top-level hot path.
    let ancestry: LanguageAncestry?

    /// Present only for child tasks of asynchronous auto-detection. Keeping
    /// this optional preserves the synchronous parser's cancellation-agnostic
    /// semantics and lets its main loop stay branch-free.
    let cancellationProbe: CancellationProbe?

    init(
        registry: LanguageRegistry,
        ancestry: LanguageAncestry? = nil,
        cancellationProbe: CancellationProbe? = nil
    ) {
        self.registry = registry
        self.ancestry = ancestry
        self.cancellationProbe = cancellationProbe
    }

    static let maxKeywordHits = 7
    static let cancellationCheckStride = 64

    enum EngineError: Error {
        case illegal(lexeme: String, mode: String?)
        case potentialInfiniteLoop
        case recursiveSubLanguage
    }

    struct InternalResult {
        var relevance: Double
        var tokens: [HighlightToken]
        var resumeState: ResumeState
        var illegal: Bool
    }

    /// Highlights `code` with `language`, throwing on illegal input (when
    /// `ignoreIllegals` is false) so callers can decide how to recover.
    func highlight(
        _ code: NSString,
        language: CompiledLanguage,
        ignoreIllegals: Bool,
        continuation: ResumeState? = nil
    ) throws -> InternalResult {
        if let cancellationProbe, cancellationProbe() {
            throw CancellationError()
        }
        // Validate ownership before consulting the continuation's mode.
        // A foreign/stale continuation starts at this language's root.
        let validatedContinuation: ResumeState? = if let continuation,
                                                     continuation.owner === language {
            continuation
        } else {
            nil
        }
        let initialMode = validatedContinuation?.topFrame.mode ?? language.root

        // A malformed/custom grammar may delegate to itself (directly,
        // through another language, or through auto-detection). Reject the
        // nested call before allocating the UTF-16 working buffer.
        if let ancestry {
            guard ancestry.depth < LanguageAncestry.maximumDepth,
                  !ancestry.wouldNotProgress(
                      language,
                      sourceLength: code.length,
                      initialMode: initialMode
                  )
            else {
                throw EngineError.recursiveSubLanguage
            }
        }

        // Materialize the text as a real CFString-backed NSString once.
        // A lazily bridged Swift string stores UTF-8 and would transcode
        // to UTF-16 on every ICU regex call (turning the parse loop
        // quadratic); copying up front makes every subsequent regex and
        // substring operation O(matched region).
        let contiguous = code.length == 0 ? code : NSString(string: code as String)
        if let cancellationProbe, cancellationProbe() {
            throw CancellationError()
        }
        // Raw UTF-16 buffer for sparse-head candidate scanning.
        var units = [UInt16](repeating: 0, count: contiguous.length)
        units.withUnsafeMutableBufferPointer { buffer in
            if let base = buffer.baseAddress, !buffer.isEmpty {
                contiguous.getCharacters(base, range: NSRange(location: 0, length: contiguous.length))
            }
        }
        // A continuation is meaningful only for the exact immutable
        // compiled-language generation that produced it. Treat a foreign
        // or stale continuation as a fresh document instead of letting its
        // matcher slots index this language's differently sized cache.
        let resume = validatedContinuation ?? ResumeState.initial(language)
        var run = Run(
            engine: self,
            source: contiguous,
            sourceString: contiguous as String,
            language: language,
            ignoreIllegals: ignoreIllegals,
            initialMode: initialMode,
            top: resume.topFrame,
            emitter: TokenEmitter(),
            ruleCache: RuleMatchCache(
                slotCount: language.ruleSlotCount,
                units: units,
                cancellationProbe: cancellationProbe
            )
        )
        run.subContinuations = resume.subContinuations
        run.responseData = resume.responseData
        run.keywordHits = resume.keywordHits
        return try run.execute()
    }

    /// All mutable state of one highlight pass.
    private struct Run {
        let engine: HighlightEngine
        let source: NSString
        /// The same text as `source`, bridged once — reused for every
        /// `NSRegularExpression` call so no per-call conversion happens.
        let sourceString: String
        let language: CompiledLanguage
        let ignoreIllegals: Bool
        /// Mode in which this invocation started. Unlike `top`, this does
        /// not change while the parser walks the current source chunk.
        let initialMode: CompiledMode

        var top: ModeFrame
        let emitter: TokenEmitter
        /// The mode buffer: text awaiting keyword/sub-language processing.
        /// Always a contiguous range of `source` (empty when length == 0).
        var buffer = NSRange(location: 0, length: 0)
        var relevance: Double = 0
        var index = 0
        var iterations = 0
        /// Sticky observation from an interruptible keyword scan. Once any
        /// hot path sees cancellation, a partial candidate cannot escape.
        var wasCancelled = false
        var resumeScanAtSamePosition = false
        var cursor = MatcherCursor()
        /// Forward cache of every rule's next match (see RuleMatchCache).
        let ruleCache: RuleMatchCache

        /// Per-language continuations for explicit sub-languages. This
        /// matches highlight.js within a pass; closed-host entries are
        /// pruned before an incremental continuation is returned.
        var subContinuations: [String: ResumeState] = [:]
        /// Per-run keyword hit counts (relevance saturation).
        var keywordHits: [String: Int] = [:]
        /// Per-run callback data, keyed by mode activation (frame) identity.
        var responseData: [ObjectIdentifier: [String: String]] = [:]
        /// Guards the zero-width begin/end deadlock.
        var lastMatchType: MatchKind?
        var lastMatchIndex = -1

        // MARK: Buffer

        mutating func bufferAppend(_ range: NSRange) {
            guard range.length > 0 else { return }
            if buffer.length == 0 {
                buffer = range
                return
            }
            // Every caller walks the source monotonically. Recovering from
            // a broken range by flushing would hide an engine bug and could
            // silently reorder output; assert the invariant instead.
            assert(buffer.location + buffer.length == range.location)
            buffer.length += range.length
        }

        mutating func clearBuffer() {
            buffer = NSRange(location: buffer.location + buffer.length, length: 0)
        }

        // MARK: Keyword processing

        mutating func processKeywords() {
            guard let keywords = top.mode.keywords, let pattern = top.mode.keywordPatternRe else {
                emitter.addText(length: buffer.length)
                return
            }
            let caseInsensitive = language.caseInsensitive
            if buffer.length >= RuleMatchCache.cancellationProgressMinimumLength,
               let cancellationProbe = engine.cancellationProbe {
                processKeywordsCancellable(
                    keywords: keywords,
                    pattern: pattern,
                    caseInsensitive: caseInsensitive,
                    cancellationProbe: cancellationProbe
                )
                return
            }
            var lastEnd = buffer.location
            // Default (opaque, anchoring) bounds so the buffer behaves
            // like the standalone substring highlight.js scans.
            pattern.enumerateMatches(in: sourceString, options: [], range: buffer) { match, _, _ in
                guard let match else { return }
                let wordRange = match.range
                var word = source.substring(with: wordRange)
                if caseInsensitive { word = word.lowercased() }
                if let data = keywords[word] {
                    // flush text preceding the keyword
                    emitter.addText(length: wordRange.location - lastEnd)

                    if data.relevance != 0 {
                        let hits = keywordHits[word] ?? 0
                        if hits < HighlightEngine.maxKeywordHits {
                            keywordHits[word] = hits + 1
                            relevance += data.relevance
                        }
                    }
                    if data.scope.hasPrefix("_") {
                        // relevance-only keyword; no scope applied
                        emitter.addText(length: wordRange.length)
                    } else {
                        emitter.addKeyword(length: wordRange.length, scope: language.aliasedScope(data.scope))
                    }
                } else {
                    emitter.addText(length: wordRange.location - lastEnd + wordRange.length)
                }
                lastEnd = wordRange.location + wordRange.length
            }
            emitter.addText(length: buffer.location + buffer.length - lastEnd)
        }

        /// Async-only counterpart to ``processKeywords()``. ICU progress
        /// callbacks bound cancellation latency for a very large keyword
        /// buffer with no matches. The ordinary synchronous path above keeps
        /// its original enumeration options and callback body.
        private mutating func processKeywordsCancellable(
            keywords: CompiledKeywords,
            pattern: NSRegularExpression,
            caseInsensitive: Bool,
            cancellationProbe: HighlightEngine.CancellationProbe
        ) {
            var lastEnd = buffer.location
            var callbacksUntilCancellationCheck =
                RuleMatchCache.cancellationProgressCheckStride
            var cancelled = false
            pattern.enumerateMatches(
                in: sourceString,
                options: [.reportProgress],
                range: buffer
            ) { match, _, stop in
                callbacksUntilCancellationCheck -= 1
                if callbacksUntilCancellationCheck == 0 {
                    if cancellationProbe() {
                        cancelled = true
                        stop.pointee = true
                        return
                    }
                    callbacksUntilCancellationCheck =
                        RuleMatchCache.cancellationProgressCheckStride
                }
                guard let match else { return }
                let wordRange = match.range
                var word = source.substring(with: wordRange)
                if caseInsensitive { word = word.lowercased() }
                if let data = keywords[word] {
                    emitter.addText(length: wordRange.location - lastEnd)
                    if data.relevance != 0 {
                        let hits = keywordHits[word] ?? 0
                        if hits < HighlightEngine.maxKeywordHits {
                            keywordHits[word] = hits + 1
                            relevance += data.relevance
                        }
                    }
                    if data.scope.hasPrefix("_") {
                        emitter.addText(length: wordRange.length)
                    } else {
                        emitter.addKeyword(
                            length: wordRange.length,
                            scope: language.aliasedScope(data.scope)
                        )
                    }
                } else {
                    emitter.addText(
                        length: wordRange.location - lastEnd + wordRange.length
                    )
                }
                lastEnd = wordRange.location + wordRange.length
            }
            if !cancelled {
                emitter.addText(length: buffer.location + buffer.length - lastEnd)
            } else {
                wasCancelled = true
            }
        }

        mutating func processSubLanguage() {
            guard buffer.length > 0, let names = top.mode.subLanguage else { return }
            // `substring(with:)` materializes the entire embedded buffer.
            // Do not pay that allocation after the parent task is already
            // cancelled; this path exists only for sub-language modes.
            if engine.cancellationProbe?() == true {
                wasCancelled = true
                return
            }
            let text = source.substring(with: buffer)
            let childAncestry = LanguageAncestry(
                language: language,
                sourceLength: source.length,
                initialMode: initialMode,
                parent: engine.ancestry
            )

            if names.count == 1 {
                let subLanguageName = names[0]
                guard let sub = try? engine.registry.compiledLanguage(named: names[0]) else {
                    if !subContinuations.isEmpty {
                        subContinuations.removeValue(forKey: subLanguageName)
                    }
                    emitter.addText(length: buffer.length)
                    return
                }
                let childEngine = HighlightEngine(
                    registry: engine.registry,
                    ancestry: childAncestry,
                    cancellationProbe: engine.cancellationProbe
                )
                let result: HighlightEngine.InternalResult
                do {
                    result = try childEngine.highlight(
                        text as NSString,
                        language: sub,
                        ignoreIllegals: true,
                        continuation: subContinuations[subLanguageName]
                    )
                } catch is CancellationError {
                    // Do not turn cancellation into an ordinary unknown/
                    // invalid sub-language fallback and keep parsing the
                    // parent for another 64 iterations.
                    wasCancelled = true
                    return
                } catch {
                    if !subContinuations.isEmpty {
                        subContinuations.removeValue(forKey: subLanguageName)
                    }
                    emitter.addText(length: buffer.length)
                    return
                }
                subContinuations[subLanguageName] = result.resumeState
                if top.mode.relevance > 0 {
                    relevance += result.relevance
                }
                emitter.addSublanguage(result.tokens, length: buffer.length)
            } else {
                let result = engine.registry.highlightAuto(
                    text,
                    subset: names.isEmpty ? nil : names,
                    ancestry: childAncestry,
                    cancellationProbe: engine.cancellationProbe
                )
                // Nested auto-detection ranks completed candidates instead
                // of throwing. Its production probe is monotonic, so sample
                // it immediately and latch cancellation in this Run.
                if engine.cancellationProbe?() == true {
                    wasCancelled = true
                    return
                }
                if top.mode.relevance > 0 {
                    relevance += result.relevance
                }
                emitter.addSublanguage(result.tokens, length: buffer.length)
            }
        }

        mutating func processBuffer() {
            if top.mode.subLanguage != nil {
                processSubLanguage()
            } else {
                processKeywords()
            }
            clearBuffer()
        }

        // MARK: Scope emission

        mutating func emitKeyword(range: NSRange, scope: String) {
            emitter.addKeyword(length: range.length, scope: language.aliasedScope(scope))
        }

        mutating func emitMultiClass(_ scope: CompiledScope, match: MultiMatch) {
            guard case .multi(let groups) = scope else { return }
            for (group, scopeName) in groups {
                let range = match.groupRange(group)
                guard range.location != NSNotFound, range.length > 0 else { continue }
                if let scopeName {
                    emitKeyword(range: range, scope: scopeName)
                } else {
                    // unmapped part: run it through keyword processing
                    let saved = buffer
                    buffer = range
                    processKeywords()
                    buffer = saved
                }
            }
        }

        // MARK: Mode transitions

        mutating func response(for frame: ModeFrame) -> Response {
            let key = ObjectIdentifier(frame)
            guard let data = responseData[key] else { return Response() }
            return Response(data: data)
        }

        mutating func persist(_ response: Response, for frame: ModeFrame) {
            let key = ObjectIdentifier(frame)
            if response.data.isEmpty {
                if !responseData.isEmpty {
                    responseData.removeValue(forKey: key)
                }
            } else {
                responseData[key] = response.data
            }
        }

        mutating func startNewMode(_ frame: ModeFrame, match: MultiMatch) {
            let mode = frame.mode
            if let scope = mode.scope {
                emitter.openScope(language.aliasedScope(scope))
            }
            if let beginScope = mode.beginScope {
                switch beginScope {
                case .wrap(let name):
                    emitKeyword(range: buffer, scope: name)
                    clearBuffer()
                case .multi:
                    emitMultiClass(beginScope, match: match)
                    clearBuffer()
                }
            }
            top = frame
        }

        /// Which frame (if any) does this end match actually close?
        mutating func endOfMode(_ frame: ModeFrame, match: MultiMatch, at location: Int) -> ModeFrame? {
            var matched = startsWith(frame.mode.endRe, at: location)

            if matched {
                if let onEnd = frame.mode.onEnd {
                    let resp = response(for: frame)
                    onEnd(match.callbackMatch(in: source), resp)
                    if resp.isMatchIgnored {
                        persist(resp, for: frame)
                        matched = false
                    }
                }
                if matched {
                    var end = frame
                    // The root frame is a permanent parser sentinel: its
                    // compiled mode has no end matcher and must never be
                    // popped. A public custom grammar can nevertheless put
                    // `endsParent` on a direct child, so stop at the
                    // outermost real mode instead of climbing into root.
                    while end.mode.endsParent,
                          let parent = end.parent,
                          parent.parent != nil {
                        end = parent
                    }
                    return end
                }
            }
            // a parent mode might still terminate here
            if frame.mode.endsWithParent, let parent = frame.parent {
                return endOfMode(parent, match: match, at: location)
            }
            return nil
        }

        private mutating func startsWith(
            _ regex: NSRegularExpression?, at location: Int
        ) -> Bool {
            guard let regex, location <= source.length else { return false }
            // Anchored with default (opaque) bounds: identical to testing
            // the regex against the substring starting at `location`.
            let range = NSRange(location: location, length: source.length - location)
            if range.length >= RuleMatchCache.cancellationProgressMinimumLength,
               let cancellationProbe = engine.cancellationProbe {
                if cancellationProbe() {
                    wasCancelled = true
                    return false
                }
                var matched = false
                var cancelled = false
                var callbacksUntilCancellationCheck =
                    RuleMatchCache.cancellationProgressCheckStride
                regex.enumerateMatches(
                    in: sourceString,
                    options: [.anchored, .reportProgress],
                    range: range
                ) { match, _, stop in
                    callbacksUntilCancellationCheck -= 1
                    if callbacksUntilCancellationCheck == 0 {
                        if cancellationProbe() {
                            cancelled = true
                            stop.pointee = true
                            return
                        }
                        callbacksUntilCancellationCheck =
                            RuleMatchCache.cancellationProgressCheckStride
                    }
                    if match != nil {
                        matched = true
                        stop.pointee = true
                    }
                }
                if cancelled { wasCancelled = true }
                return matched
            }
            return regex.firstMatch(in: sourceString, options: [.anchored], range: range) != nil
        }

        /// Advance decision after a vetoed begin match.
        mutating func doIgnore(_ lexeme: NSRange) -> Int {
            if cursor.regexIndex == 0 {
                // No other rules can match here; step one unit forward.
                if lexeme.length > 0 {
                    bufferAppend(NSRange(location: lexeme.location, length: 1))
                }
                return 1
            } else {
                // Other rules may match at this exact spot; rescan there.
                resumeScanAtSamePosition = true
                return 0
            }
        }

        mutating func doBeginMatch(_ match: MultiMatch, newMode: CompiledMode) -> Int {
            let lexeme = match.range
            var callbackResponse: Response?
            if newMode.internalBeforeBegin != nil || newMode.onBegin != nil {
                let resp = Response()
                let view = match.callbackMatch(in: source)
                if let callback = newMode.internalBeforeBegin {
                    callback(view, resp)
                    if resp.isMatchIgnored {
                        return doIgnore(lexeme)
                    }
                }
                if let callback = newMode.onBegin {
                    callback(view, resp)
                    if resp.isMatchIgnored {
                        return doIgnore(lexeme)
                    }
                }
                callbackResponse = resp
            }

            // Allocate the activation only after callbacks accept the
            // match. Veto-heavy grammars otherwise create a dead frame for
            // every rejected candidate.
            let newFrame = ModeFrame(mode: newMode, parent: top)
            if let callbackResponse, !callbackResponse.data.isEmpty {
                persist(callbackResponse, for: newFrame)
            }

            if newMode.skip {
                bufferAppend(lexeme)
            } else {
                if newMode.excludeBegin {
                    bufferAppend(lexeme)
                }
                processBuffer()
                if !newMode.returnBegin && !newMode.excludeBegin {
                    bufferAppend(lexeme)
                }
            }
            startNewMode(newFrame, match: match)
            return newMode.returnBegin ? 0 : lexeme.length
        }

        /// Returns how far to advance, or nil when the end match did not
        /// actually close anything (JS `NO_MATCH`).
        mutating func doEndMatch(_ match: MultiMatch) -> Int? {
            let lexeme = match.range

            guard let endFrame = endOfMode(top, match: match, at: match.index) else {
                return nil
            }

            let origin = top
            if let endScope = origin.mode.endScope, case .wrap(let name) = endScope {
                processBuffer()
                emitKeyword(range: lexeme, scope: name)
            } else if let endScope = origin.mode.endScope, case .multi = endScope {
                processBuffer()
                emitMultiClass(endScope, match: match)
            } else if origin.mode.skip {
                bufferAppend(lexeme)
            } else {
                if !(origin.mode.returnEnd || origin.mode.excludeEnd) {
                    bufferAppend(lexeme)
                }
                processBuffer()
                if origin.mode.excludeEnd {
                    bufferAppend(lexeme)
                }
            }

            var current: ModeFrame? = top
            repeat {
                guard let frame = current else { break }
                if frame.mode.scope != nil {
                    emitter.closeScope()
                }
                if !frame.mode.skip, frame.mode.subLanguage == nil {
                    relevance += frame.mode.relevance
                }
                // Callback data belongs to this mode activation. Once the
                // frame closes it must neither retain memory nor make two
                // otherwise-root continuations compare different.
                let frameKey = ObjectIdentifier(frame)
                if !responseData.isEmpty {
                    responseData.removeValue(forKey: frameKey)
                }
                current = frame.parent
            } while current !== endFrame.parent

            // `endOfMode` never returns the permanent root sentinel, so a
            // closable mode has a parent and the loop finishes at it.
            top = current!
            if let starts = endFrame.mode.starts {
                startNewMode(ModeFrame(mode: starts, parent: top), match: match)
            }
            return origin.mode.returnEnd ? 0 : lexeme.length
        }

        // MARK: Lexeme dispatch

        mutating func processLexeme(textBefore: NSRange, match: MultiMatch?) throws -> Int {
            bufferAppend(textBefore)

            guard let match else {
                processBuffer()
                return 0
            }

            let lexeme = match.range

            // Zero-width begin immediately followed by a zero-width end
            // at the same spot: swallow one character to escape the
            // deadlock (highlight.js issue #2140). At EOF there is no
            // character to swallow — the reference's `slice(i, i+1)` is
            // "" there — so guard the bounds (mirrors the illegal-`$`
            // handler below) and just advance to terminate the loop.
            if case .begin = lastMatchType, case .end = match.rule.kind,
               lastMatchIndex == match.index, lexeme.length == 0 {
                if match.index < source.length {
                    bufferAppend(NSRange(location: match.index, length: 1))
                }
                return 1
            }
            lastMatchType = match.rule.kind
            lastMatchIndex = match.index

            switch match.rule.kind {
            case .begin(let newMode):
                return doBeginMatch(match, newMode: newMode)
            case .illegal where !ignoreIllegals:
                throw EngineError.illegal(
                    lexeme: source.substring(with: lexeme),
                    mode: top.mode.scope
                )
            case .end:
                if let processed = doEndMatch(match) {
                    return processed
                }
            case .illegal:
                break
            }

            // Illegal matched `$` (zero width): step over it, keeping the
            // newline itself in the buffer.
            if case .illegal = match.rule.kind, lexeme.length == 0 {
                if match.index < source.length {
                    bufferAppend(NSRange(location: match.index, length: 1))
                }
                return 1
            }

            if iterations > 100_000, iterations > match.index * 3 {
                throw EngineError.potentialInfiniteLoop
            }

            // An end match that closed nothing (for example vetoed by a
            // callback): consume it as plain buffer text.
            bufferAppend(lexeme)
            return lexeme.length
        }

        // MARK: Main loop

        /// Executes one parser iteration. Factoring this out lets the normal
        /// loop compile without a per-iteration optional cancellation branch;
        /// the async auto-detect loop wraps the same step in its probe. WMO is
        /// left to make the inlining decision from measured cost heuristics.
        mutating func advanceOneIteration() throws -> Bool {
            iterations += 1
            if resumeScanAtSamePosition {
                // only regexes not matched previously will now be
                // considered for a potential match
                resumeScanAtSamePosition = false
            } else {
                cursor.considerAll()
            }
            cursor.lastIndex = index

            guard let match = top.mode.matcher.exec(
                in: sourceString, length: source.length, cursor: &cursor, cache: ruleCache
            ) else {
                return false
            }

            let before = NSRange(location: index, length: match.index - index)
            let processed = try processLexeme(textBefore: before, match: match)
            index = match.index + processed
            return true
        }

        mutating func execute() throws -> InternalResult {
            openContinuationScopes()

            if let cancellationProbe = engine.cancellationProbe {
                if cancellationProbe() { throw CancellationError() }
                var remainingUntilCancellationCheck = HighlightEngine.cancellationCheckStride
                while try advanceOneIteration() {
                    // Keyword and anchored-end ICU progress callbacks retain
                    // their observation on Run; matcher/prefilter callbacks
                    // retain it on the cache. Either source must stop before
                    // another parser iteration, even for a transient test
                    // probe (Task cancellation itself is sticky).
                    if wasCancelled || ruleCache.wasCancelled {
                        throw CancellationError()
                    }
                    remainingUntilCancellationCheck -= 1
                    if remainingUntilCancellationCheck == 0 {
                        if cancellationProbe() { throw CancellationError() }
                        remainingUntilCancellationCheck = HighlightEngine.cancellationCheckStride
                    }
                }
                if ruleCache.wasCancelled || cancellationProbe() {
                    throw CancellationError()
                }
            } else {
                while try advanceOneIteration() {}
            }
            // Zero-width EOF recovery may advance the logical cursor one
            // past the source sentinel. Finalization owns no text there;
            // never manufacture a negative-length NSRange.
            let tailStart = min(index, source.length)
            _ = try processLexeme(
                textBefore: NSRange(
                    location: tailStart,
                    length: source.length - tailStart
                ),
                match: nil
            )
            if wasCancelled || ruleCache.wasCancelled
                || engine.cancellationProbe?() == true {
                throw CancellationError()
            }
            pruneClosedSubLanguageContinuations()

            return InternalResult(
                relevance: relevance,
                tokens: emitter.tokens,
                resumeState: ResumeState(
                    owner: language,
                    topFrame: top,
                    subContinuations: subContinuations,
                    responseData: responseData,
                    keywordHits: keywordHits
                ),
                illegal: false
            )
        }

        /// highlight.js reuses a sub-language continuation by language name
        /// throughout one whole-buffer pass. Across independent editor
        /// chunks, however, state from a host mode that has already closed
        /// must not leak into a later block. Only runs that actually used a
        /// sub-language pay for this shallow stack walk.
        mutating func pruneClosedSubLanguageContinuations() {
            guard !subContinuations.isEmpty else { return }

            func isActive(_ languageName: String) -> Bool {
                var frame: ModeFrame? = top
                while let current = frame {
                    if let names = current.mode.subLanguage,
                       names.count == 1,
                       names[0] == languageName {
                        return true
                    }
                    frame = current.parent
                }
                return false
            }

            // The normal case has one embedded language and no stale
            // entry. Avoid allocating a Set or copying the Dictionary just
            // to discover that there is nothing to prune.
            var staleNames: [String]?
            for name in subContinuations.keys where !isActive(name) {
                if staleNames == nil { staleNames = [] }
                staleNames!.append(name)
            }
            guard let staleNames else { return }
            for name in staleNames {
                subContinuations.removeValue(forKey: name)
            }
        }

        /// Re-opens the scopes of a continuation's mode stack so nested
        /// runs keep their scope context.
        private func openContinuationScopes() {
            var list: [String] = []
            var frame: ModeFrame? = top
            while let current = frame, current.parent != nil {
                if let scope = current.mode.scope {
                    list.append(language.aliasedScope(scope))
                }
                frame = current.parent
            }
            for scope in list.reversed() {
                emitter.openScope(scope)
            }
        }
    }
}
