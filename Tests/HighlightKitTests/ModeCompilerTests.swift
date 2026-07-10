import Foundation
import Testing
@testable import HighlightKit

private final class WeakReference<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value) {
        self.value = value
    }
}

private final class LifetimeProbe: Sendable {}

private final class RawModeHolder: @unchecked Sendable {
    var mode: Mode?
}

private struct CompiledGraphWeakReferences {
    let language: WeakReference<CompiledLanguage>
    let recursiveMode: WeakReference<CompiledMode>
    let startsMode: WeakReference<CompiledMode>
    let matcher: WeakReference<CompiledMatcher>
    let rule: WeakReference<CompiledRule>
}

private final class ContinuationLifetime {
    let language: WeakReference<CompiledLanguage>
    let mode: WeakReference<CompiledMode>
    private var continuation: Continuation?

    init(
        language: WeakReference<CompiledLanguage>,
        mode: WeakReference<CompiledMode>,
        continuation: Continuation
    ) {
        self.language = language
        self.mode = mode
        self.continuation = continuation
    }

    @inline(never)
    func releaseContinuation() {
        continuation = nil
    }
}

@Suite("Mode compiler")
struct ModeCompilerTests {
    private func compile(_ root: Mode, caseInsensitive: Bool = false) throws -> CompiledLanguage {
        try ModeCompiler.compile(LanguageDefinition(name: "test", caseInsensitive: caseInsensitive, root: root))
    }

    /// A function boundary makes every local strong reference disappear
    /// before a weak-reference assertion runs. That is deterministic; RSS
    /// sampling is not a substitute for a reference-cycle regression test.
    @inline(never)
    private func compileRawCycleSuccessfully()
        throws -> (WeakReference<Mode>, WeakReference<Mode>, CompiledLanguage)
    {
        let child = Mode(begin: #"\{"#, end: #"\}"#, contains: [Mode.selfReference])
        let root = Mode(contains: [child])
        let rootReference = WeakReference(root)
        let childReference = WeakReference(child)
        let language = try compile(root)
        return (rootReference, childReference, language)
    }

    @inline(never)
    private func failWhileCompilingRawCycle() -> (WeakReference<Mode>, WeakReference<Mode>) {
        let child = Mode(begin: "(unclosed")
        child.contains = [child]
        let root = Mode(contains: [child])
        let rootReference = WeakReference(root)
        let childReference = WeakReference(child)
        #expect(throws: HighlightError.self) { _ = try compile(root) }
        return (rootReference, childReference)
    }

    @inline(never)
    private func failAfterCompilingRecursiveChild() -> WeakReference<LifetimeProbe> {
        let probe = LifetimeProbe()
        let reference = WeakReference(probe)
        let recursive = Mode(
            begin: "a", end: "b", contains: [Mode.selfReference],
            onBegin: { [probe] _, _ in _ = probe }
        )
        let invalid = Mode(begin: "(unclosed")
        #expect(throws: HighlightError.self) {
            _ = try compile(Mode(contains: [recursive, invalid]))
        }
        return reference
    }

    @inline(never)
    private func compileAndReleaseCyclicGraph() throws -> CompiledGraphWeakReferences {
        let recursive = Mode(begin: #"\{"#, end: #"\}"#, contains: [Mode.selfReference])
        let root = Mode(contains: [recursive])
        let starts = Mode(begin: "a")
        // A top-level starts cycle bypasses contains expansion and exercises
        // an independent strong-edge family in the compiled graph.
        root.starts = starts
        starts.starts = root

        let language = try compile(root)
        let compiledRecursive = language.root.contains[0]
        let compiledStarts = try #require(language.root.starts)
        let matcher = try #require(compiledRecursive.matcher)
        let rule = try #require(matcher.rules.first)

        return CompiledGraphWeakReferences(
            language: WeakReference(language),
            recursiveMode: WeakReference(compiledRecursive),
            startsMode: WeakReference(compiledStarts),
            matcher: WeakReference(matcher),
            rule: WeakReference(rule)
        )
    }

    @inline(never)
    private func makeContinuationLifetime() throws -> ContinuationLifetime {
        let descriptor = LanguageDescriptor(name: "lifetime") {
            let recursive = Mode(
                begin: #"\{"#, end: #"\}"#, contains: [Mode.selfReference]
            )
            return LanguageDefinition(name: "lifetime", root: Mode(contains: [recursive]))
        }
        let highlighter = Highlighter(languages: [descriptor])
        let continuation = try #require(
            highlighter.highlight("{", as: "lifetime").continuation
        )
        return ContinuationLifetime(
            language: WeakReference(continuation.state.owner),
            mode: WeakReference(continuation.state.topFrame.mode),
            continuation: continuation
        )
    }

    @inline(never)
    private func failTopLevelValidationWithRawCycle()
        -> (WeakReference<Mode>, WeakReference<Mode>)
    {
        let first = Mode()
        let second = Mode()
        first.contains = [second]
        second.contains = [first]
        let references = (WeakReference(first), WeakReference(second))
        let root = Mode(contains: [Mode.selfReference, first])
        #expect(throws: HighlightError.self) { _ = try compile(root) }
        return references
    }

    @inline(never)
    private func compileAndReleaseRawCallbackCycle() throws -> WeakReference<Mode> {
        let holder = RawModeHolder()
        let raw = Mode(begin: "x")
        holder.mode = raw
        raw.onBegin = { [holder] _, _ in
            _ = holder.mode
        }
        let reference = WeakReference(raw)
        _ = try compile(Mode(contains: [raw]))
        return reference
    }

    @Test func matchSugarBecomesBegin() throws {
        let compiled = try compile(Mode(contains: [Mode(scope: "number", match: "[0-9]+")]))
        #expect(compiled.root.contains.first?.beginPattern == "[0-9]+")
    }

    @Test func matchWithBeginThrows() {
        let child = Mode(match: "a", begin: "b")
        #expect(throws: HighlightError.self) {
            _ = try compile(Mode(contains: [child]))
        }
    }

    @Test func selfAtTopLevelThrows() {
        #expect(throws: HighlightError.self) {
            _ = try compile(Mode(contains: [Mode.selfReference]))
        }
        #expect(throws: HighlightError.self) {
            _ = try compile(Mode.selfReference)
        }
    }

    @Test func rawGraphReleasesAfterSuccessfulCompilation() throws {
        let (root, child, language) = try compileRawCycleSuccessfully()
        #expect(root.value == nil)
        #expect(child.value == nil)
        // Keep the compiled graph alive through both assertions: releasing
        // the raw graph must not depend on releasing its compiled copy.
        withExtendedLifetime(language) {}
    }

    @Test func rawGraphReleasesWhenCompilationThrows() {
        let (root, child) = failWhileCompilingRawCycle()
        #expect(root.value == nil)
        #expect(child.value == nil)
    }

    @Test func rawCallbackCaptureCycleReleasesWithCompiledGraph() throws {
        let raw = try compileAndReleaseRawCallbackCycle()
        #expect(raw.value == nil)
    }

    @Test func earliestValidationFailureAlsoReleasesRawGraph() {
        let (first, second) = failTopLevelValidationWithRawCycle()
        #expect(first.value == nil)
        #expect(second.value == nil)
    }

    @Test func partialCompiledGraphReleasesWhenLaterSiblingThrows() {
        let probe = failAfterCompilingRecursiveChild()
        #expect(probe.value == nil)
    }

    @Test func compiledGraphReleasesEveryStrongEdgeSet() throws {
        let references = try compileAndReleaseCyclicGraph()
        #expect(references.language.value == nil)
        #expect(references.recursiveMode.value == nil)
        #expect(references.startsMode.value == nil)
        #expect(references.matcher.value == nil)
        #expect(references.rule.value == nil)
    }

    @Test func continuationKeepsGraphAliveUntilItIsReleased() throws {
        let lifetime = try makeContinuationLifetime()
        #expect(lifetime.language.value != nil)
        #expect(lifetime.mode.value != nil)

        lifetime.releaseContinuation()

        #expect(lifetime.language.value == nil)
        #expect(lifetime.mode.value == nil)
    }

    @Test func invalidRegexThrowsWithContext() {
        do {
            _ = try compile(Mode(contains: [Mode(begin: "(unclosed")]))
            Issue.record("expected a throw")
        } catch let error as HighlightError {
            guard case .invalidRegex(let language, let pattern, _) = error else {
                Issue.record("wrong error: \(error)")
                return
            }
            #expect(language == "test")
            #expect(pattern.contains("(unclosed"))
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test func variantsExpandInPlace() throws {
        let child = Mode(
            scope: "string",
            variants: [
                Mode(begin: "'", end: "'"),
                Mode(begin: "\"", end: "\""),
            ]
        )
        let compiled = try compile(Mode(contains: [child]))
        #expect(compiled.root.contains.count == 2)
        #expect(compiled.root.contains[0].scope == "string")
        #expect(compiled.root.contains[0].beginPattern == "'")
        #expect(compiled.root.contains[1].beginPattern == "\"")
    }

    @Test func variantCanCancelScope() throws {
        let child = Mode(
            scope: "params",
            variants: [
                Mode(begin: "x"),
                Mode(scope: ScopeRef.none, begin: "y"),
            ]
        )
        let compiled = try compile(Mode(contains: [child]))
        #expect(compiled.root.contains[0].scope == "params")
        #expect(compiled.root.contains[1].scope == nil)
    }

    @Test func variantCanClearContains() throws {
        let inner = Mode(scope: "x", begin: "x")
        let child = Mode(
            begin: "q",
            contains: [inner],
            variants: [
                Mode(begin: "a"),
                Mode(begin: "b", contains: []),
            ]
        )
        let compiled = try compile(Mode(contains: [child]))
        #expect(compiled.root.contains[0].contains.count == 1)
        #expect(compiled.root.contains[1].contains.isEmpty)
    }

    @Test func selfReferenceCompilesToSameInstance() throws {
        let child = Mode(scope: "block", begin: #"\{"#, end: #"\}"#, contains: [Mode.selfReference])
        let compiled = try compile(Mode(contains: [child]))
        let block = compiled.root.contains[0]
        #expect(block.contains.first === block)
        withExtendedLifetime(compiled) {}
    }

    @Test func cyclicStartsDoesNotOverflowCompiler() throws {
        let first = Mode(begin: "a")
        let second = Mode(begin: "b")
        first.starts = second
        second.starts = first

        let compiled = try compile(Mode(contains: [first]))
        let compiledFirst = compiled.root.contains[0]
        #expect(compiledFirst.starts?.starts === compiledFirst)
        withExtendedLifetime(compiled) {}
    }

    @Test func beginKeywordsBuildsWordAlternation() throws {
        let child = Mode(beginKeywords: "class struct")
        let compiled = try compile(Mode(contains: [child]))
        let mode = compiled.root.contains[0]
        #expect(mode.beginPattern == #"\b(class|struct)(?!\.)(?=\b|\s)"#)
        #expect(mode.keywords?["class"]?.scope == "keyword")
        #expect(mode.relevance == 0)
        #expect(mode.internalBeforeBegin != nil)
        withExtendedLifetime(compiled) {}
    }

    @Test func illegalArrayBecomesAlternation() throws {
        let compiled = try compile(Mode(illegal: ["a", "b"]))
        #expect(compiled.root.illegalPattern == "(?:a|b)")
    }

    @Test func endsWithParentInheritsTerminator() throws {
        let inner = Mode(begin: "i", endsWithParent: true)
        let outer = Mode(begin: "o", end: "END", contains: [inner])
        let compiled = try compile(Mode(contains: [outer]))
        let compiledInner = compiled.root.contains[0].contains[0]
        #expect(compiledInner.terminatorEnd == "END")
        withExtendedLifetime(compiled) {}
    }

    @Test func defaultRelevanceIsOne() throws {
        let compiled = try compile(Mode(contains: [Mode(begin: "x")]))
        #expect(compiled.root.contains[0].relevance == 1)
    }

    @Test func emptyPatternsMeanUnset() throws {
        // `end: ""` behaves like no end at all (JS falsiness)
        let child = Mode(begin: "x", end: "")
        let compiled = try compile(Mode(contains: [child]))
        #expect(compiled.root.contains[0].terminatorEnd == #"\B|\b"#)
    }

    @Test func multiPartBeginRequiresScopeMap() {
        let child = Mode(begin: ["a", "b"])
        #expect(throws: HighlightError.self) {
            _ = try compile(Mode(contains: [child]))
        }
    }

    @Test func scopeMapSugarMovesToBeginScope() throws {
        let child = Mode(scope: [1: "keyword", 2: "title"], match: ["(def)", "(\\w+)"])
        let compiled = try compile(Mode(contains: [child]))
        let mode = compiled.root.contains[0]
        guard case .multi(let groups)? = mode.beginScope else {
            Issue.record("expected multi begin scope")
            return
        }
        // part 1 has 1 inner group so part 2 remaps from 2 to 3
        #expect(groups.map(\.group) == [1, 3])
        #expect(groups.map(\.scope) == ["keyword", "title"])
        withExtendedLifetime(compiled) {}
    }

    @Test func beforeMatchRewritesToLookahead() throws {
        let child = Mode(scope: "number", begin: "[0-9]+", beforeMatch: #"\$"#)
        let compiled = try compile(Mode(contains: [child]))
        let wrapper = compiled.root.contains[0]
        #expect(wrapper.beginPattern == #"\$(?=[0-9]+)"#)
        #expect(wrapper.relevance == 0)
        #expect(wrapper.starts != nil)
        #expect(wrapper.starts?.contains.first?.endsParent == true)
        #expect(wrapper.starts?.contains.first?.scope == "number")
        withExtendedLifetime(compiled) {}
    }

    @Test func caseInsensitiveCompilesKeywordsLowercased() throws {
        let compiled = try compile(Mode(keywords: "SELECT"), caseInsensitive: true)
        #expect(compiled.root.keywords?["select"] != nil)
    }
}
