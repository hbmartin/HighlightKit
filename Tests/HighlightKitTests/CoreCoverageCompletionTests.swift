import Foundation
import Synchronization
import Testing

@testable import HighlightKit

@Suite("Core coverage completion")
struct CoreCoverageCompletionTests {
    private func compiledRule(_ pattern: String, slot: Int = 0) throws -> CompiledRule {
        try CompiledRule(
            pattern: pattern,
            kind: .illegal,
            options: [],
            language: "coverage",
            slot: slot
        )
    }

    private func cache(for source: String, slotCount: Int = 1) -> RuleMatchCache {
        RuleMatchCache(slotCount: slotCount, units: Array(source.utf16))
    }

    @Test func commentConfigurationCanClearInheritedChildren() throws {
        let comment = CommonModes.comment("//", "$") { mode in
            mode.contains = nil
        }
        let children = try #require(comment.contains)
        #expect(children.count == 2)

        let descriptor = LanguageDescriptor(name: "configured-comment") {
            LanguageDefinition(
                name: "configured-comment",
                root: Mode(contains: [
                    CommonModes.comment("//", "$") { mode in
                        mode.contains = nil
                    }
                ])
            )
        }
        let result = Highlighter(languages: [descriptor]).highlight(
            "// TODO: retain helpers",
            as: "configured-comment"
        )
        #expect(result.tokens.contains { $0.scope == "comment" })
        #expect(result.tokens.contains { $0.scope == "doctag" })
    }

    @Test func failedNestedLanguageDropsOnlyItsSavedContinuation() throws {
        let child = LanguageDescriptor(name: "nested-child") {
            LanguageDefinition(
                name: "nested-child",
                root: Mode(contains: [Mode(scope: "keyword", begin: "x")])
            )
        }
        let host = LanguageDescriptor(name: "nested-host") {
            LanguageDefinition(
                name: "nested-host",
                root: Mode(contains: [
                    Mode(begin: "<", end: ">", subLanguage: ["nested-child"])
                ])
            )
        }
        let registry = LanguageRegistry(languages: [host, child])
        let first = try registry.highlight(
            "<x",
            languageName: "nested-host",
            ignoreIllegals: true
        )
        let firstContinuation = try #require(first.continuation)
        #expect(firstContinuation.state.subContinuations["nested-child"] != nil)
        #expect(first.tokens.contains { $0.scope == "keyword" })

        // Put the child in the explicit ancestry chain. The resumed host is
        // still valid, but attempting this child would recurse, so the host
        // must degrade that buffer to plain text and discard the stale child
        // continuation rather than retaining or applying it.
        let compiledChild = try registry.compiledLanguage(named: "nested-child")
        let resumed = try registry.highlight(
            "x",
            languageName: "nested-host",
            ignoreIllegals: true,
            continuation: firstContinuation,
            ancestry: LanguageAncestry(
                language: compiledChild,
                sourceLength: 1,
                initialMode: compiledChild.root,
                parent: nil
            )
        )
        let resumedContinuation = try #require(resumed.continuation)
        #expect(resumed.tokens.isEmpty)
        #expect(resumedContinuation.state.subContinuations.isEmpty)
        #expect(resumedContinuation.state.topFrame.mode.subLanguage == ["nested-child"])
    }

    @Test func topLevelRecursiveAncestryDegradesToAPlainLanguageResult() throws {
        let descriptor = LanguageDescriptor(name: "ancestry-root") {
            LanguageDefinition(
                name: "ancestry-root",
                root: Mode(contains: [Mode(scope: "keyword", begin: "x")])
            )
        }
        let registry = LanguageRegistry(languages: [descriptor])
        let compiled = try registry.compiledLanguage(named: "ancestry-root")
        let result = try registry.highlight(
            "x",
            languageName: "ancestry-root",
            ignoreIllegals: true,
            ancestry: LanguageAncestry(
                language: compiled,
                sourceLength: 1,
                initialMode: compiled.root,
                parent: nil
            )
        )

        #expect(result.language == "ancestry-root")
        #expect(result.tokens.isEmpty)
        #expect(result.relevance == 0)
        #expect(!result.illegal)
        #expect(result.continuation == nil)
    }

    @Test func ancestryBoundsDistinctEqualSizedInvocationStates() throws {
        let descriptor = LanguageDescriptor(name: "ancestry-states") {
            LanguageDefinition(
                name: "ancestry-states",
                root: Mode(contains: [Mode(begin: "x")])
            )
        }
        let registry = LanguageRegistry(languages: [descriptor])
        let language = try registry.compiledLanguage(named: "ancestry-states")
        let nestedMode = try #require(language.root.contains.first)
        let nestedStart = LanguageAncestry(
            language: language,
            sourceLength: 10,
            initialMode: nestedMode,
            parent: nil
        )

        // One equal-sized transition into a previously unseen start mode is
        // progress (the incremental XML case), but repeating either state is
        // a cycle. Growing input is never progress; shrinking input is.
        #expect(!nestedStart.wouldNotProgress(
            language,
            sourceLength: 10,
            initialMode: language.root
        ))
        let rootStart = LanguageAncestry(
            language: language,
            sourceLength: 10,
            initialMode: language.root,
            parent: nestedStart
        )
        #expect(rootStart.wouldNotProgress(
            language,
            sourceLength: 10,
            initialMode: nestedMode
        ))
        #expect(rootStart.wouldNotProgress(
            language,
            sourceLength: 11,
            initialMode: nestedMode
        ))
        #expect(!rootStart.wouldNotProgress(
            language,
            sourceLength: 9,
            initialMode: language.root
        ))
    }

    @Test func ancestryHardDepthCapRejectsAnOtherwiseAcyclicCandidate() throws {
        let hostDescriptor = LanguageDescriptor(name: "depth-host") {
            LanguageDefinition(name: "depth-host", root: Mode())
        }
        let candidateDescriptor = LanguageDescriptor(name: "depth-candidate") {
            LanguageDefinition(
                name: "depth-candidate",
                root: Mode(contains: [Mode(scope: "keyword", begin: "x")])
            )
        }
        let registry = LanguageRegistry(languages: [hostDescriptor, candidateDescriptor])
        let host = try registry.compiledLanguage(named: "depth-host")
        let candidate = try registry.compiledLanguage(named: "depth-candidate")

        var ancestry: LanguageAncestry?
        for _ in 0..<LanguageAncestry.maximumDepth {
            ancestry = LanguageAncestry(
                language: host,
                sourceLength: 1,
                initialMode: host.root,
                parent: ancestry
            )
        }
        let cappedAncestry = try #require(ancestry)
        #expect(cappedAncestry.depth == LanguageAncestry.maximumDepth)

        do {
            _ = try HighlightEngine(registry: registry, ancestry: cappedAncestry).highlight(
                "x" as NSString,
                language: candidate,
                ignoreIllegals: true
            )
            Issue.record("the ancestry hard-depth cap accepted a depth-64 candidate")
        } catch let error as HighlightEngine.EngineError {
            guard case .recursiveSubLanguage = error else {
                Issue.record("depth cap changed error category: \(error)")
                return
            }
        }

        // The immediately preceding depth remains legal. The candidate is a
        // different compiled language, so cycle detection cannot mask an
        // off-by-one error in the independent hard-depth guard.
        let permittedAncestry = try #require(cappedAncestry.parent)
        #expect(permittedAncestry.depth == LanguageAncestry.maximumDepth - 1)
        let result = try HighlightEngine(
            registry: registry,
            ancestry: permittedAncestry
        ).highlight(
            "x" as NSString,
            language: candidate,
            ignoreIllegals: true
        )
        #expect(result.tokens == [
            HighlightToken(range: NSRange(location: 0, length: 1), scopes: ["keyword"]),
        ])
    }

    @Test func permanentlyVetoedZeroWidthEndTripsTheLoopFuse() throws {
        let descriptor = LanguageDescriptor(name: "loop-fuse") {
            LanguageDefinition(
                name: "loop-fuse",
                root: Mode(contains: [
                    Mode(
                        begin: "x",
                        end: "$",
                        onEnd: { _, response in response.ignoreMatch() }
                    )
                ])
            )
        }
        let registry = LanguageRegistry(languages: [descriptor])
        let compiled = try registry.compiledLanguage(named: "loop-fuse")
        let engine = HighlightEngine(registry: registry)

        do {
            _ = try engine.highlight(
                "x" as NSString,
                language: compiled,
                ignoreIllegals: true
            )
            Issue.record("a permanently vetoed zero-width end did not trip the loop fuse")
        } catch let error as HighlightEngine.EngineError {
            guard case .potentialInfiniteLoop = error else {
                Issue.record("loop fuse changed error category: \(error)")
                return
            }
        }
    }

    @Test func emptyEndCallbackStateDoesNotEraseAnotherFrame() throws {
        let descriptor = LanguageDescriptor(name: "callback-frames") {
            let inner = Mode(
                scope: "inner",
                begin: "x",
                end: "y",
                onEnd: { _, response in
                    // There is deliberately no onBegin data for this frame.
                    // Its first end must receive an independent empty response.
                    if response.data.isEmpty { response.ignoreMatch() }
                }
            )
            let outer = Mode(
                scope: "outer",
                begin: "<",
                end: ">",
                contains: [inner],
                onBegin: { _, response in response.data["owner"] = "outer" }
            )
            return LanguageDefinition(
                name: "callback-frames",
                root: Mode(contains: [outer])
            )
        }

        let result = Highlighter(languages: [descriptor]).highlight(
            "<xy",
            as: "callback-frames"
        )
        let state = try #require(result.continuation?.state)
        #expect(state.topFrame.mode.scope == "inner")
        #expect(state.responseData.count == 1)
        #expect(state.responseData.values.first?["owner"] == "outer")
        #expect(result.tokens.last?.scope == "inner")
    }

    @Test func invalidGrammarFailureIsMemoizedWithItsCategory() {
        let buildCount = Mutex(0)
        let descriptor = LanguageDescriptor(name: "invalid-grammar-cache") {
            buildCount.withLock { $0 += 1 }
            return LanguageDefinition(
                name: "invalid-grammar-cache",
                root: Mode(contains: [Mode.selfReference])
            )
        }
        let registry = LanguageRegistry(languages: [descriptor])
        var reasons: [String] = []

        for _ in 0..<2 {
            do {
                _ = try registry.compiledLanguage(named: "invalid-grammar-cache")
                Issue.record("invalid grammar unexpectedly compiled")
            } catch let error as HighlightError {
                guard case .invalidGrammar(let language, let reason) = error else {
                    Issue.record("cached error changed category: \(error)")
                    continue
                }
                #expect(language == "invalid-grammar-cache")
                reasons.append(reason)
            } catch {
                Issue.record("cached error changed type: \(error)")
            }
        }

        #expect(buildCount.withLock { $0 } == 1)
        #expect(reasons.count == 2)
        #expect(reasons.first == reasons.last)
        #expect(reasons.first?.contains("top-level") == true)
    }

    @Test func autoDetectionSubsetCaseFoldsCanonicalNamesAndAliases() {
        let descriptor = LanguageDescriptor(
            name: "casefold",
            aliases: ["shortcut"]
        ) {
            LanguageDefinition(
                name: "casefold",
                root: Mode(contains: [
                    Mode(scope: "keyword", begin: "x", relevance: 10)
                ])
            )
        }
        let registry = LanguageRegistry(languages: [descriptor])

        let canonical = registry.highlightAuto("x", subset: ["CASEFOLD"])
        let alias = registry.highlightAuto("x", subset: ["SHORTCUT"])
        let unchangedUnicodeMiss = registry.highlightAuto("x", subset: ["不存在"])

        #expect(canonical.language == "casefold")
        #expect(alias.language == "casefold")
        #expect(canonical.tokens.first?.scope == "keyword")
        #expect(alias.tokens.first?.scope == "keyword")
        #expect(unchangedUnicodeMiss.language == nil)
        #expect(unchangedUnicodeMiss.tokens.isEmpty)
        #expect(!registry.hasLanguage(named: "不存在"))
    }

    @Test func equalSizedNestedContinuationMapsStillCompareTheirKeys() throws {
        let descriptor = LanguageDescriptor(name: "continuation-map") {
            LanguageDefinition(name: "continuation-map", root: Mode())
        }
        let original = Highlighter(languages: [descriptor]).highlight(
            "",
            as: "continuation-map"
        )
        let base = try #require(original.continuation?.state)
        let left = Continuation(
            state: ResumeState(
                owner: base.owner,
                topFrame: base.topFrame,
                subContinuations: ["left": base],
                responseData: base.responseData,
                keywordHits: base.keywordHits
            )
        )
        let right = Continuation(
            state: ResumeState(
                owner: base.owner,
                topFrame: base.topFrame,
                subContinuations: ["right": base],
                responseData: base.responseData,
                keywordHits: base.keywordHits
            )
        )

        #expect(left != right)

        let changedNestedState = ResumeState(
            owner: base.owner,
            topFrame: base.topFrame,
            subContinuations: base.subContinuations,
            responseData: base.responseData,
            keywordHits: ["changed": 1]
        )
        let sameKeyLeft = Continuation(
            state: ResumeState(
                owner: base.owner,
                topFrame: base.topFrame,
                subContinuations: ["nested": base],
                responseData: base.responseData,
                keywordHits: base.keywordHits
            )
        )
        let sameKeyRight = Continuation(
            state: ResumeState(
                owner: base.owner,
                topFrame: base.topFrame,
                subContinuations: ["nested": changedNestedState],
                responseData: base.responseData,
                keywordHits: base.keywordHits
            )
        )
        #expect(sameKeyLeft != sameKeyRight)

        let equalNestedCopy = ResumeState(
            owner: base.owner,
            topFrame: base.topFrame,
            subContinuations: base.subContinuations,
            responseData: base.responseData,
            keywordHits: base.keywordHits
        )
        let structurallyEqual = Continuation(
            state: ResumeState(
                owner: base.owner,
                topFrame: base.topFrame,
                subContinuations: ["nested": equalNestedCopy],
                responseData: base.responseData,
                keywordHits: base.keywordHits
            )
        )
        #expect(sameKeyLeft == structurallyEqual)
    }

    @Test func factoryAutoDetectionReentryFailsClosedWithoutDeadlocking() throws {
        let registrySlot = Mutex<LanguageRegistry?>(nil)
        let observed = Mutex("not-run")
        let coldBuilds = Mutex(0)
        let warm = LanguageDescriptor(name: "warm") {
            LanguageDefinition(
                name: "warm",
                root: Mode(contains: [Mode(scope: "keyword", begin: "x")])
            )
        }
        let cold = LanguageDescriptor(name: "cold") {
            coldBuilds.withLock { $0 += 1 }
            return LanguageDefinition(
                name: "cold",
                root: Mode(contains: [Mode(scope: "keyword", begin: "x")])
            )
        }
        let outer = LanguageDescriptor(name: "reentrant-auto") {
            if let registry = registrySlot.withLock({ $0 }) {
                // Exercise both GenerationSnapshot cases while a descriptor
                // factory is active. Neither a published graph nor a cold
                // generation may bypass the same re-entry contract.
                let result = registry.highlightAuto("x", subset: ["warm", "cold"])
                observed.withLock { $0 = result.language ?? "plain" }
            }
            return LanguageDefinition(name: "reentrant-auto", root: Mode())
        }
        let registry = LanguageRegistry(languages: [warm, cold, outer])
        registrySlot.withLock { $0 = registry }

        let before = try registry.compiledLanguage(named: "warm")
        _ = try registry.compiledLanguage(named: "reentrant-auto")
        let after = try registry.compiledLanguage(named: "warm")

        #expect(observed.withLock { $0 } == "plain")
        #expect(coldBuilds.withLock { $0 } == 0)
        #expect(before === after)
        #expect(registry.hasLanguage(named: "reentrant-auto"))
        registrySlot.withLock { $0 = nil }
    }

    @Test func endsParentCannotPopTheRootSentinel() throws {
        let descriptor = LanguageDescriptor(name: "root-sentinel") {
            LanguageDefinition(
                name: "root-sentinel",
                root: Mode(contains: [
                    Mode(scope: "child", begin: "x", end: "y", endsParent: true)
                ])
            )
        }
        let result = Highlighter(languages: [descriptor]).highlight("xy", as: "root-sentinel")

        #expect(result.tokens == [
            HighlightToken(range: NSRange(location: 0, length: 2), scopes: ["child"])
        ])
        #expect(result.continuation != nil)
    }

    @Test func cancellationDuringCandidateDropsTheCompletedResult() async {
        let builds = Mutex(0)
        let descriptor = LanguageDescriptor(name: "self-cancelling") {
            builds.withLock { $0 += 1 }
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return LanguageDefinition(
                name: "self-cancelling",
                root: Mode(contains: [Mode(scope: "keyword", begin: "x", relevance: 10)])
            )
        }
        let registry = LanguageRegistry(languages: [descriptor])

        let result = await registry.highlightAuto("x", subset: ["self-cancelling"])

        #expect(result.language == nil)
        #expect(result.tokens.isEmpty)
        #expect(builds.withLock { $0 } == 1)
    }

    @Test func emptyBeginAndEndAtEOFTerminatesWithoutPastEndMatching() {
        let descriptor = LanguageDescriptor(name: "empty-eof") {
            LanguageDefinition(
                name: "empty-eof",
                root: Mode(contains: [
                    Mode(scope: "empty", begin: "", end: "")
                ])
            )
        }
        let result = Highlighter(languages: [descriptor]).highlight("", as: "empty-eof")

        #expect(result.tokens.isEmpty)
        #expect(!result.illegal)
        #expect(result.continuation != nil)
    }

    @Test func emptyBeginHasTheSameRuntimeMeaningAsAnUnsetBegin() throws {
        let empty = LanguageDescriptor(name: "empty-begin") {
            LanguageDefinition(
                name: "empty-begin",
                root: Mode(contains: [
                    Mode(scope: "empty", begin: "", end: "x")
                ])
            )
        }
        let unset = LanguageDescriptor(name: "unset-begin") {
            LanguageDefinition(
                name: "unset-begin",
                root: Mode(contains: [
                    Mode(scope: "empty", end: "x")
                ])
            )
        }
        let emptyHighlighter = Highlighter(languages: [empty])
        let unsetHighlighter = Highlighter(languages: [unset])
        let emptyResult = emptyHighlighter.highlight("x", as: "empty-begin")
        let unsetResult = unsetHighlighter.highlight("x", as: "unset-begin")

        let compiled = try emptyHighlighter.registry.compiledLanguage(named: "empty-begin")
        #expect(compiled.root.contains.first?.beginPattern == #"\B|\b"#)
        #expect(emptyResult.tokens == unsetResult.tokens)
        #expect(emptyResult.tokens.first?.scope == "empty")
        #expect(emptyResult.illegal == unsetResult.illegal)
    }

    @Test func explicitNoneBeginAndEndScopesApplyNoWrapper() throws {
        let descriptor = LanguageDescriptor(name: "none-scopes") {
            LanguageDefinition(
                name: "none-scopes",
                root: Mode(contains: [
                    Mode(
                        scope: "container",
                        begin: "x",
                        beginScope: ScopeRef.none,
                        end: "y",
                        endScope: ScopeRef.none
                    )
                ])
            )
        }
        let highlighter = Highlighter(languages: [descriptor])
        let compiled = try highlighter.registry.compiledLanguage(named: "none-scopes")
        let mode = try #require(compiled.root.contains.first)
        #expect(mode.beginScope == nil)
        #expect(mode.endScope == nil)

        let result = highlighter.highlight("xyz", as: "none-scopes")
        #expect(
            result.tokens == [
                HighlightToken(range: NSRange(location: 0, length: 2), scopes: ["container"])
            ])
    }

    @Test func multipartRegexHasNoMisleadingSinglePatternView() {
        let multipart: RegexRef = ["a", "b"]
        #expect(multipart.single == nil)
    }

    @Test func synthesizedCallbackMatchRejectsNonzeroCaptureGroups() {
        let match = CallbackMatch(
            source: "x" as NSString,
            groups: .none,
            matchRange: NSRange(location: 0, length: 1)
        )

        #expect(match[0] == "x")
        #expect(match[1] == nil)
        #expect(match[-1] == nil)
    }

    @Test func group1CallbackMatchExposesExactlyItsLeadingGroup() {
        // The value-starter shape: full match "==  ", group 1 = "==".
        let match = CallbackMatch(
            source: "a ==  b" as NSString,
            groups: .group1(length: 2),
            matchRange: NSRange(location: 2, length: 4)
        )

        #expect(match[0] == "==  ")
        #expect(match[1] == "==")
        #expect(match[2] == nil) // non-participating, like ICU's group 2
        #expect(match[3] == nil) // out of range clamps, like JS match[N]
    }

    @Test func variantMergeCarriesEveryRuntimeControlField() throws {
        let variant = Mode(
            endScope: "terminator",
            starts: Mode(scope: "after", begin: "b"),
            subLanguage: ["plaintext"],
            label: "selected-variant",
            returnBegin: true,
            endsWithParent: true
        )
        let definition = LanguageDefinition(
            name: "variant-controls",
            root: Mode(contains: [
                Mode(begin: "a", end: "z", variants: [variant])
            ])
        )
        let compiled = try ModeCompiler.compile(definition)
        let mode = try #require(compiled.root.contains.first)

        guard case .wrap(let endScope)? = mode.endScope else {
            Issue.record("variant end scope was not compiled")
            return
        }
        #expect(endScope == "terminator")
        #expect(mode.starts?.scope == "after")
        #expect(mode.subLanguage == ["plaintext"])
        #expect(mode.returnBegin)
        #expect(mode.endsWithParent)
        withExtendedLifetime(compiled) {}
    }

    @Test func cycleDependencyFindsAnUnvisitedEndsWithParentNode() throws {
        let head = Mode(begin: "h")
        let first = Mode(begin: "a")
        let second = Mode(begin: "b")
        let third = Mode(begin: "c", endsWithParent: true)
        head.starts = first
        first.starts = second
        second.starts = third
        third.starts = first

        let compiled = try ModeCompiler.compile(
            LanguageDefinition(
                name: "cycle-parent-dependency",
                root: Mode(contains: [head])
            )
        )
        let compiledThird = compiled.root.contains.first?.starts?.starts?.starts
        #expect(compiledThird?.endsWithParent == true)
        // Parent-dependent entry modes are copied per use site; the copied
        // first node then rejoins the immutable shared cycle at its successor.
        #expect(compiledThird?.starts !== compiled.root.contains.first?.starts)
        #expect(compiledThird?.starts?.starts === compiled.root.contains.first?.starts?.starts)
        withExtendedLifetime(compiled) {}
    }

    @Test func endSameAsBeginWithoutCaptureUsesEmptySentinel() {
        let descriptor = LanguageDescriptor(name: "captureless-delimiter") {
            LanguageDefinition(
                name: "captureless-delimiter",
                root: Mode(contains: [
                    Mode(
                        scope: "string",
                        begin: "<",
                        end: ">",
                        endSameAsBegin: true
                    )
                ])
            )
        }
        let source = "<body>tail"
        let result = Highlighter(languages: [descriptor]).highlight(
            source,
            as: "captureless-delimiter"
        )
        let nsSource = source as NSString
        let highlighted = result.tokens
            .filter { $0.scope == "string" }
            .map { nsSource.substring(with: $0.range) }
            .joined()

        #expect(highlighted == "<body>")
        #expect(result.tokens.allSatisfy { NSMaxRange($0.range) <= 6 })
    }

    @Test func beginKeywordsRejectsMemberAccessButAcceptsBareKeyword() {
        let descriptor = LanguageDescriptor(name: "keyword-veto") {
            LanguageDefinition(
                name: "keyword-veto",
                root: Mode(contains: [
                    Mode(scope: "declaration", beginKeywords: "class")
                ])
            )
        }
        let source = ".class class"
        let result = Highlighter(languages: [descriptor]).highlight(
            source,
            as: "keyword-veto"
        )
        let nsSource = source as NSString
        let keywordTokens = result.tokens.filter { $0.scope == "keyword" }

        #expect(keywordTokens.count == 1)
        #expect(keywordTokens.first?.range == NSRange(location: 7, length: 5))
        #expect(keywordTokens.map { nsSource.substring(with: $0.range) } == ["class"])
        #expect(result.tokens.allSatisfy { $0.range.location >= 7 })
    }

    @Test func compiledRulePreservesInvalidRegexContext() {
        do {
            _ = try compiledRule("(unclosed")
            Issue.record("invalid rule unexpectedly compiled")
        } catch let error as HighlightError {
            guard case .invalidRegex(let language, let pattern, _) = error else {
                Issue.record("wrong error category: \(error)")
                return
            }
            #expect(language == "coverage")
            #expect(pattern == "(unclosed")
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test func semanticEscapeDoesNotBecomeALiteralPrefilter() throws {
        let rule = try compiledRule(#".?\d"#)
        guard case .none = rule.prefilter else {
            Issue.record("a character-class escape was treated as a literal")
            return
        }

        let source = "xa1"
        let match = try #require(
            cache(for: source).firstMatch(
                for: rule,
                in: source,
                length: (source as NSString).length,
                from: 0
            )
        )
        #expect(match.range == NSRange(location: 1, length: 2))
        #expect((source as NSString).substring(with: match.range) == "a1")
    }

    @Test func literalPrefilterDecodesNewlineAndCarriageReturnEscapes() throws {
        for (pattern, source) in [(#".?\n"#, "x\n"), (#".?\r"#, "x\r")] {
            let rule = try compiledRule(pattern)
            guard case .dotOptionalLiteral = rule.prefilter else {
                Issue.record("control escape did not produce a literal prefilter")
                continue
            }
            let match = try #require(
                cache(for: source).firstMatch(
                    for: rule,
                    in: source,
                    length: (source as NSString).length,
                    from: 0
                )
            )
            #expect(match.range == NSRange(location: 0, length: 2))
        }

        do {
            _ = try compiledRule(#".?\"#)
            Issue.record("dangling regex escape unexpectedly compiled")
        } catch let error as HighlightError {
            guard case .invalidRegex(_, let pattern, _) = error else {
                Issue.record("dangling escape changed error category: \(error)")
                return
            }
            #expect(pattern == #".?\"#)
        }
    }

    @Test func malformedKeywordShapesAreRejectedStructurally() {
        #expect(CompiledRule.KeywordTable(sources: [#"\bword\x"#]) == nil)
        #expect(CompiledRule.KeywordTable(sources: [#"\bword\\b"#]) == nil)
    }

    @Test func malformedDoctagShapeFallsBackToICU() throws {
        let pattern = #"[ ]*(?=(TODO|T0DO):)"#
        let rule = try compiledRule(pattern)
        guard case .none = rule.prefilter else {
            Issue.record("nonliteral doctag branch unexpectedly received a prefilter")
            return
        }
        let source = " T0DO:"
        let match = try #require(
            cache(for: source).firstMatch(
                for: rule,
                in: source,
                length: (source as NSString).length,
                from: 0
            )
        )
        #expect(match.range == NSRange(location: 0, length: 1))
    }

    @Test func multiMatchGroupZeroIsAlwaysTheWholeRuleRange() throws {
        let rule = try compiledRule("x")
        let match = MultiMatch(
            range: NSRange(location: 3, length: 2),
            groups: .none,
            rule: rule,
            position: 0
        )
        #expect(match.groupRange(0) == NSRange(location: 3, length: 2))
        #expect(match.groupRange(1).location == NSNotFound)
        #expect(match.groupRange(-1).location == NSNotFound)
    }

    @Test func multiMatchGroup1ShapeAnswersOnlyItsLeadingGroup() throws {
        let rule = try compiledRule("x")
        let match = MultiMatch(
            range: NSRange(location: 3, length: 4),
            groups: .group1(length: 2),
            rule: rule,
            position: 0
        )
        #expect(match.groupRange(0) == NSRange(location: 3, length: 4))
        #expect(match.groupRange(1) == NSRange(location: 3, length: 2))
        #expect(match.groupRange(2).location == NSNotFound)
        #expect(match.groupRange(-1).location == NSNotFound)
    }

    @Test func unicodeSecondParameterFallsBackToTheRegexEngine() throws {
        let source = "first é:"
        let rule = try compiledRule(KwsSwift.functionParameterNameLookahead)
        let match = try #require(
            cache(for: source).firstMatch(
                for: rule,
                in: source,
                length: (source as NSString).length,
                from: 0
            )
        )
        #expect(match.range == NSRange(location: 0, length: 0))
    }

    @Test func matchCacheAnswersQueriesBeforeItsInitialScan() throws {
        let source = "a---a"
        let rule = try compiledRule("a")
        let matchCache = cache(for: source)
        let length = (source as NSString).length

        let later = try #require(
            matchCache.firstMatch(for: rule, in: source, length: length, from: 4)
        )
        let earlier = try #require(
            matchCache.firstMatch(for: rule, in: source, length: length, from: 0)
        )

        #expect(later.range == NSRange(location: 4, length: 1))
        #expect(earlier.range == NSRange(location: 0, length: 1))
    }

    @Test func matchCacheRejectsAQueryPastTheDeclaredLength() throws {
        let source = "abc"
        let rule = try compiledRule("a")
        let match = cache(for: source).firstMatch(
            for: rule,
            in: source,
            length: (source as NSString).length,
            from: (source as NSString).length + 1
        )
        #expect(match == nil)
    }

    @Test func matchCacheUsesICUProgressCallbacksForCancellation() throws {
        let source = String(
            repeating: "a",
            count: RuleMatchCache.cancellationProgressMinimumLength
        )
        let probeCalls = Mutex(0)
        let cache = RuleMatchCache(
            slotCount: 1,
            units: Array(source.utf16),
            cancellationProbe: {
                probeCalls.withLock { calls in
                    calls += 1
                    return calls >= 2
                }
            }
        )

        let match = cache.firstMatch(
            for: try compiledRule("z"),
            in: source,
            length: source.utf16.count,
            from: 0
        )

        #expect(match == nil)
        #expect(probeCalls.withLock { $0 } >= 2)
    }

    @Test func parserChecksCancellationInsideAMatchDenseRun() throws {
        let matchCount = Mutex(0)
        let descriptor = LanguageDescriptor(name: "cancellable-parser") {
            LanguageDefinition(
                name: "cancellable-parser",
                root: Mode(contains: [
                    Mode(begin: "x", onBegin: { _, _ in
                        matchCount.withLock { $0 += 1 }
                    })
                ])
            )
        }
        let registry = LanguageRegistry(languages: [descriptor])
        let language = try registry.compiledLanguage(named: "cancellable-parser")
        let parserCancellationChecks = Mutex(0)
        let engine = HighlightEngine(
            registry: registry,
            cancellationProbe: {
                // Entry/materialization probes happen while no match has
                // run. Arm cancellation from observable parser progress so
                // this test keeps pinning the 64-iteration cadence when new
                // allocation-boundary checks are added elsewhere.
                guard matchCount.withLock({ $0 })
                    >= HighlightEngine.cancellationCheckStride / 2
                else { return false }
                parserCancellationChecks.withLock { $0 += 1 }
                return true
            }
        )

        do {
            _ = try engine.highlight(
                String(repeating: "x", count: 100_000) as NSString,
                language: language,
                ignoreIllegals: true
            )
            Issue.record("a cancelled match-dense parse ran to completion")
        } catch is CancellationError {
            // Each child activation consumes one begin iteration and one
            // end iteration, so the engine's 64-iteration probe observes
            // exactly 32 onBegin callbacks.
            #expect(
                matchCount.withLock { $0 }
                    == HighlightEngine.cancellationCheckStride / 2
            )
            #expect(parserCancellationChecks.withLock { $0 } == 1)
        } catch {
            Issue.record("cancellation changed error category: \(error)")
        }
    }

    @Test func matchCacheResumesAcrossItsWindowBoundary() throws {
        let source = String(repeating: "a", count: RuleMatchCache.windowSize + 3)
        let rule = try compiledRule("a")
        let matchCache = cache(for: source)
        let length = (source as NSString).length

        let first = try #require(
            matchCache.firstMatch(for: rule, in: source, length: length, from: 0)
        )
        let afterWindow = try #require(
            matchCache.firstMatch(
                for: rule,
                in: source,
                length: length,
                from: RuleMatchCache.windowSize
            )
        )

        #expect(first.range.location == 0)
        #expect(afterWindow.range == NSRange(location: RuleMatchCache.windowSize, length: 1))
    }

    @Test func identifierPrefilterSkipsDigitPrefixWhenBackingUpFromColon() throws {
        let source = "123abc:"
        let rule = try compiledRule("[A-Za-z$_][0-9A-Za-z$_]*(?=:)")
        let match = try #require(
            cache(for: source).firstMatch(
                for: rule,
                in: source,
                length: (source as NSString).length,
                from: 0
            )
        )

        #expect(match.range == NSRange(location: 3, length: 3))
        #expect((source as NSString).substring(with: match.range) == "abc")
    }

    @Test func danglingRegexEscapeDoesNotInventACaptureGroup() {
        #expect(RegexSource.countCaptureGroups("\\") == 0)
        #expect(RegexSource.countCaptureGroups("(a)\\") == 1)
        #expect(RegexSource.countCaptureGroups(#"(a)\12"#) == 1)
    }

    @Test func overflowingBackreferenceIsPreservedVerbatim() {
        let parseOverflow = "\\" + String(repeating: "9", count: 100)
        let additionOverflow = "\\\(Int.max)"
        for original in [parseOverflow, additionOverflow] {
            let rewritten = RegexSource.rewriteBackreferences([original], joinedBy: "")
            #expect(rewritten == "(\(original))")
            #expect(RegexSource.countCaptureGroups(original) == 0)
        }
    }

    @Test func tokenEmitterDropsZeroLengthSublanguageRuns() {
        let emitter = TokenEmitter()
        emitter.addSublanguage(
            [HighlightToken(range: NSRange(location: 0, length: 0), scopes: ["keyword"])],
            length: 0
        )
        #expect(emitter.tokens.isEmpty)
        #expect(emitter.cursor == 0)
    }
}
