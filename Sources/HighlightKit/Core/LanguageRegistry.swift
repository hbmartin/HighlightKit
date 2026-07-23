import Foundation
import Synchronization

private enum LanguageBuildContext {
    /// Descriptor factories construct one self-contained raw grammar. They
    /// must not recursively ask a registry to compile another grammar while
    /// a per-generation compilation gate is held.
    @TaskLocal static var isBuilding = false
}

/// Thread-safe store of language grammars: registration, alias
/// resolution, and lazy compilation with caching.
final class LanguageRegistry: Sendable {
    /// Bounds live child tasks for user-extensible registries. The global
    /// executor cannot run more CPU-bound candidates usefully than active
    /// processors, and a fixed window prevents an arbitrary subset from
    /// allocating an arbitrary number of task records at once.
    static let maximumConcurrentAutodetectTasks = max(
        1,
        ProcessInfo.processInfo.activeProcessorCount
    )

    /// One immutable registration generation. In-flight work retains the
    /// exact generation it started from, so replacing a name cannot let an
    /// old compilation populate the new generation's cache.
    private final class Entry: Sendable {
        private struct CachedUnderlyingError: Error, Sendable, CustomStringConvertible {
            let description: String
        }

        /// Sendable representation of `HighlightError`. The public error's
        /// regex case stores an unconstrained `any Error`, so retain only its
        /// diagnostic text inside shared state and reconstruct the same
        /// HighlightError category for every caller.
        private enum CachedCompilationFailure: Sendable {
            case unknownLanguage(String)
            case invalidRegex(language: String, pattern: String, underlying: String)
            case invalidGrammar(language: String, reason: String)

            init(_ error: any Error, fallbackLanguage: String) {
                switch error {
                case let error as HighlightError:
                    switch error {
                    case .unknownLanguage(let name):
                        self = .unknownLanguage(name)
                    case .invalidRegex(let language, let pattern, let underlying):
                        self = .invalidRegex(
                            language: language,
                            pattern: pattern,
                            underlying: String(describing: underlying)
                        )
                    case .invalidGrammar(let language, let reason):
                        self = .invalidGrammar(language: language, reason: reason)
                    }
                default:
                    self = .invalidGrammar(
                        language: fallbackLanguage,
                        reason: "grammar compilation failed: \(String(describing: error))"
                    )
                }
            }

            func makeError() -> HighlightError {
                switch self {
                case .unknownLanguage(let name):
                    .unknownLanguage(name)
                case .invalidRegex(let language, let pattern, let underlying):
                    .invalidRegex(
                        language: language,
                        pattern: pattern,
                        underlying: CachedUnderlyingError(description: underlying)
                    )
                case .invalidGrammar(let language, let reason):
                    .invalidGrammar(language: language, reason: reason)
                }
            }
        }

        let canonicalName: String
        let aliases: [String]
        let descriptor: LanguageDescriptor

        private enum CompilationState: Sendable {
            case uninitialized
            case succeeded(CompiledLanguage)
            case failed(CachedCompilationFailure)
        }

        /// Authoritative cold-build and failure state for this generation.
        /// Successful graphs are additionally published under the registry's
        /// global `Synchronization.Mutex`, which gives TSan a visible
        /// happens-before edge without making warm readers acquire this
        /// second lock. The performance log records why the otherwise-safe
        /// `AtomicLazyReference` prototype was rejected on this toolchain.
        private let compilation = Mutex(CompilationState.uninitialized)

        init(_ descriptor: LanguageDescriptor) {
            let canonicalName = descriptor.name.lowercased()
            self.canonicalName = canonicalName
            self.descriptor = descriptor

            var seen: Set<String> = []
            var aliases: [String] = []
            aliases.reserveCapacity(descriptor.aliases.count)
            for rawAlias in descriptor.aliases {
                let alias = rawAlias.lowercased()
                guard alias != canonicalName, seen.insert(alias).inserted else { continue }
                aliases.append(alias)
            }
            self.aliases = aliases
        }

        func compiledLanguage() throws -> CompiledLanguage {
            try compilation.withLock { state in
                switch state {
                case .succeeded(let compiled):
                    return compiled
                case .failed(let failure):
                    throw failure.makeError()
                case .uninitialized:
                    break
                }
                do {
                    let compiled = try LanguageBuildContext.$isBuilding.withValue(true) {
                        try ModeCompiler.compile(descriptor.build())
                    }
                    state = .succeeded(compiled)
                    return compiled
                } catch {
                    let failure = CachedCompilationFailure(
                        error,
                        fallbackLanguage: canonicalName
                    )
                    state = .failed(failure)
                    throw failure.makeError()
                }
            }
        }
    }

    /// One canonical table value. Keeping the successful publication beside
    /// its generation removes the second dictionary hash from every warm
    /// canonical lookup; mutation is confined to `state.withLock`.
    private struct Registration: Sendable {
        let entry: Entry
        var compiled: CompiledLanguage?
    }

    private struct State {
        var entries: [String: Registration] = [:]
        var aliases: [String: Entry] = [:]
        var sortedNames: [String] = []
        var filenames: [String: [String]] = [:]
        var fileExtensions: [String: [String]] = [:]
        var interpreters: [String: [String]] = [:]
        var revision: UInt64 = 0

        mutating func rebuildMetadataIndexes() {
            filenames.removeAll(keepingCapacity: true)
            fileExtensions.removeAll(keepingCapacity: true)
            interpreters.removeAll(keepingCapacity: true)
            for name in sortedNames {
                guard let metadata = entries[name]?.entry.descriptor.metadata else { continue }
                for filename in metadata.filenames { filenames[filename, default: []].append(name) }
                for ext in metadata.fileExtensions { fileExtensions[ext, default: []].append(name) }
                for interpreter in metadata.interpreters { interpreters[interpreter, default: []].append(name) }
            }
        }
    }

    /// One generation retained after the global table lock is released.
    /// A warm snapshot holds only the graph; retaining its Entry as well
    /// would add a redundant ARC pair to every highlight and auto candidate.
    private enum GenerationSnapshot: Sendable {
        case compiled(CompiledLanguage)
        case uncompiled(Entry)
    }

    private let state = Mutex(State())

    init(languages: [LanguageDescriptor]) {
        register(languages)
    }

    func register(_ descriptors: [LanguageDescriptor]) {
        // Normalize and allocate outside the global table lock. Registration
        // is rare, but descriptor captures and old compiled graphs can have
        // expensive or user-defined destruction behavior.
        let newEntries = descriptors.map(Entry.init)
        let newAliasCount = newEntries.reduce(into: 0) { count, entry in
            count += entry.aliases.count
        }
        let retired = state.withLock { state -> [Entry] in
            var retired: [Entry] = []
            retired.reserveCapacity(newEntries.count * 2)
            state.entries.reserveCapacity(state.entries.count + newEntries.count)
            state.aliases.reserveCapacity(state.aliases.count + newAliasCount)

            for entry in newEntries {
                if let previous = state.entries.updateValue(
                    Registration(entry: entry, compiled: nil),
                    forKey: entry.canonicalName
                ) {
                    // Keep the old generation alive until after unlocking.
                    retired.append(previous.entry)
                    // The old Entry's CompilationState retains any published
                    // graph until `retired` is released outside the lock.
                    for alias in previous.entry.aliases
                    where state.aliases[alias] === previous.entry {
                        if let removed = state.aliases.removeValue(forKey: alias) {
                            retired.append(removed)
                        }
                    }
                }

                for alias in entry.aliases {
                    if let displaced = state.aliases.updateValue(entry, forKey: alias) {
                        retired.append(displaced)
                    }
                }
            }
            // Registration is the only write path. Pay this tiny sort once
            // here so every auto-detection call receives an O(1), COW
            // snapshot instead of sorting all language names again.
            state.sortedNames = state.entries.keys.sorted()
            state.rebuildMetadataIndexes()
            state.revision &+= 1
            return retired
        }
        // Releasing an Entry may destroy a descriptor factory capture or
        // dismantle a cyclic compiled graph. Neither belongs under `state`.
        withExtendedLifetime(retired) {}
    }

    /// Canonical names of all registered languages, sorted.
    var languageNames: [String] {
        state.withLock { $0.sortedNames }
    }

    var languageInfos: [LanguageInfo] {
        state.withLock { state in
            state.sortedNames.compactMap { name in
                state.entries[name].map { registration in
                    LanguageInfo(
                        name: name,
                        aliases: registration.entry.aliases,
                        metadata: registration.entry.descriptor.metadata
                    )
                }
            }
        }
    }

    var revision: UInt64 { state.withLock { $0.revision } }

    func exactFilenameCandidates(_ filename: String) -> [String] {
        state.withLock { $0.filenames[filename.lowercased()] ?? [] }
    }

    func extensionCandidates(_ filename: String) -> [String] {
        let filename = filename.lowercased()
        return state.withLock { state in
            var longest = -1
            var candidates: [String] = []
            for (ext, names) in state.fileExtensions {
                guard filename == ext || filename.hasSuffix("." + ext) else { continue }
                if ext.count > longest {
                    longest = ext.count
                    candidates = names
                } else if ext.count == longest {
                    candidates.append(contentsOf: names)
                }
            }
            return Array(Set(candidates)).sorted()
        }
    }

    func interpreterCandidates(_ interpreter: String) -> [String] {
        state.withLock { $0.interpreters[interpreter.lowercased()] ?? [] }
    }

    private func entry(named name: String) -> Entry? {
        if let exact = state.withLock({ state in
            state.entries[name]?.entry ?? state.aliases[name]
        }) {
            return exact
        }

        // Canonical names and built-in aliases are already lowercase on
        // virtually every hot call. Avoid allocating a lowercased String;
        // only retry when ASCII uppercase or a non-ASCII scalar could
        // actually change under Unicode case folding.
        var mightNeedCaseFolding = false
        for byte in name.utf8 where (65...90).contains(byte) || byte >= 0x80 {
            mightNeedCaseFolding = true
            break
        }
        guard mightNeedCaseFolding else { return nil }

        let lowercased = name.lowercased()
        guard lowercased != name else { return nil }
        return state.withLock { state in
            state.entries[lowercased]?.entry ?? state.aliases[lowercased]
        }
    }

    /// Resolves a name and its already-published compiled generation in one
    /// global lock acquisition. Returning both values strongly retains the
    /// exact generation after the lock is released.
    private func resolvedGeneration(
        named name: String
    ) -> GenerationSnapshot? {
        if let exact = state.withLock({ state -> GenerationSnapshot? in
            let registration: Registration?
            if let canonical = state.entries[name] {
                registration = canonical
            } else if let alias = state.aliases[name],
                      let aliased = state.entries[alias.canonicalName],
                      aliased.entry === alias {
                registration = aliased
            } else {
                registration = nil
            }
            guard let registration else { return nil }
            if let compiled = registration.compiled {
                return .compiled(compiled)
            }
            return .uncompiled(registration.entry)
        }) {
            return exact
        }

        var mightNeedCaseFolding = false
        for byte in name.utf8 where (65...90).contains(byte) || byte >= 0x80 {
            mightNeedCaseFolding = true
            break
        }
        guard mightNeedCaseFolding else { return nil }

        let lowercased = name.lowercased()
        guard lowercased != name else { return nil }
        return state.withLock { state in
            let registration: Registration?
            if let canonical = state.entries[lowercased] {
                registration = canonical
            } else if let alias = state.aliases[lowercased],
                      let aliased = state.entries[alias.canonicalName],
                      aliased.entry === alias {
                registration = aliased
            } else {
                registration = nil
            }
            guard let registration else { return nil }
            if let compiled = registration.compiled {
                return .compiled(compiled)
            }
            return .uncompiled(registration.entry)
        }
    }

    /// Publishes a successful cold compilation only if this Entry is still
    /// the current canonical generation. An in-flight old generation remains
    /// valid for its caller but can never populate a replacement's hot cache.
    private func compileAndPublish(_ entry: Entry) throws -> CompiledLanguage {
        let compiled = try entry.compiledLanguage()
        state.withLock { state in
            guard var registration = state.entries[entry.canonicalName],
                  registration.entry === entry,
                  registration.compiled == nil
            else { return }
            registration.compiled = compiled
            state.entries[entry.canonicalName] = registration
        }
        return compiled
    }

    /// Captures every generation used by one auto-detection operation under
    /// a single global-lock acquisition. Compilation and parsing then retain
    /// these exact Entries even if registration changes concurrently.
    private func detectionEntries(subset: [String]?) -> [GenerationSnapshot] {
        guard let subset else {
            return state.withLock { state in
                state.sortedNames.compactMap { name in
                    state.entries[name].map { registration in
                        if let compiled = registration.compiled {
                            return .compiled(compiled)
                        }
                        return .uncompiled(registration.entry)
                    }
                }
            }
        }

        let lookups = subset.map { name -> (exact: String, folded: String?) in
            var mightNeedCaseFolding = false
            for byte in name.utf8 where (65...90).contains(byte) || byte >= 0x80 {
                mightNeedCaseFolding = true
                break
            }
            guard mightNeedCaseFolding else { return (name, nil) }
            let folded = name.lowercased()
            return (name, folded == name ? nil : folded)
        }
        return state.withLock { state in
            lookups.compactMap { lookup in
                let registration: Registration?
                if let canonical = state.entries[lookup.exact] {
                    registration = canonical
                } else if let alias = state.aliases[lookup.exact],
                          let aliased = state.entries[alias.canonicalName],
                          aliased.entry === alias {
                    registration = aliased
                } else if let folded = lookup.folded,
                          let canonical = state.entries[folded] {
                    registration = canonical
                } else if let folded = lookup.folded,
                          let alias = state.aliases[folded],
                          let aliased = state.entries[alias.canonicalName],
                          aliased.entry === alias {
                    registration = aliased
                } else {
                    registration = nil
                }
                return registration.map { registration in
                    if let compiled = registration.compiled {
                        return .compiled(compiled)
                    }
                    return .uncompiled(registration.entry)
                }
            }
        }
    }

    /// Resolves a name or alias to the canonical language name.
    func canonicalName(for name: String) -> String? {
        entry(named: name)?.canonicalName
    }

    func hasLanguage(named name: String) -> Bool {
        canonicalName(for: name) != nil
    }

    /// Returns the compiled grammar, building it on first use.
    func compiledLanguage(named name: String) throws -> CompiledLanguage {
        // Check before even loading a warm cache so descriptor re-entry
        // never succeeds or deadlocks based on incidental warm-up order.
        guard !LanguageBuildContext.isBuilding else {
            throw HighlightError.invalidGrammar(
                language: name,
                reason: "a LanguageDescriptor factory must not compile languages recursively"
            )
        }
        guard let generation = resolvedGeneration(named: name) else {
            throw HighlightError.unknownLanguage(name)
        }
        switch generation {
        case .compiled(let compiled):
            return compiled
        case .uncompiled(let entry):
            return try compileAndPublish(entry)
        }
    }

    private func compiledLanguage(
        from generation: GenerationSnapshot
    ) throws -> CompiledLanguage {
        guard !LanguageBuildContext.isBuilding else {
            let name = switch generation {
            case .compiled(let compiled): compiled.name
            case .uncompiled(let entry): entry.canonicalName
            }
            throw HighlightError.invalidGrammar(
                language: name,
                reason: "a LanguageDescriptor factory must not compile languages recursively"
            )
        }
        switch generation {
        case .compiled(let compiled):
            return compiled
        case .uncompiled(let entry):
            return try compileAndPublish(entry)
        }
    }

    func descriptor(named name: String) -> LanguageDescriptor? {
        entry(named: name)?.descriptor
    }

    // MARK: - Highlighting entry points

    /// Highlights `code` as `languageName`. On illegal input (when
    /// honored) or engine failure, degrades to an unhighlighted result —
    /// mirroring highlight.js safe mode.
    func highlight(
        _ code: String,
        languageName: String,
        ignoreIllegals: Bool,
        continuation: Continuation? = nil,
        ancestry: LanguageAncestry? = nil,
        cancellationProbe: HighlightEngine.CancellationProbe? = nil
    ) throws -> HighlightResult {
        let language = try compiledLanguage(named: languageName)
        return try highlight(
            code,
            language: language,
            ignoreIllegals: ignoreIllegals,
            continuation: continuation,
            ancestry: ancestry,
            cancellationProbe: cancellationProbe
        )
    }

    /// Runs one immutable compiled-language generation. Auto-detection uses
    /// this overload so metadata checks, parsing, and tie-breaking cannot
    /// straddle a concurrent re-registration.
    private func highlight(
        _ code: String,
        language: CompiledLanguage,
        ignoreIllegals: Bool,
        continuation: Continuation? = nil,
        ancestry: LanguageAncestry? = nil,
        cancellationProbe: HighlightEngine.CancellationProbe? = nil
    ) throws -> HighlightResult {
        let engine = HighlightEngine(
            registry: self,
            ancestry: ancestry,
            cancellationProbe: cancellationProbe
        )
        do {
            let result = try engine.highlight(
                code as NSString,
                language: language,
                ignoreIllegals: ignoreIllegals,
                continuation: continuation?.state
            )
            return HighlightResult(
                language: language.name,
                relevance: result.relevance,
                illegal: false,
                tokens: result.tokens,
                sourceLength: code.utf16.count,
                continuation: Continuation(state: result.resumeState)
            )
        } catch let error as HighlightEngine.EngineError {
            switch error {
            case .illegal:
                return HighlightResult(
                    language: language.name,
                    relevance: 0,
                    illegal: true,
                    tokens: [],
                    sourceLength: code.utf16.count
                )
            case .potentialInfiniteLoop, .recursiveSubLanguage:
                return HighlightResult(
                    language: language.name,
                    relevance: 0,
                    illegal: false,
                    tokens: [],
                    sourceLength: code.utf16.count
                )
            }
        }
    }

    /// Highlights with automatic language detection.
    func highlightAuto(
        _ code: String,
        subset: [String]?,
        ancestry: LanguageAncestry? = nil,
        cancellationProbe: HighlightEngine.CancellationProbe? = nil
    ) -> HighlightResult {
        // Nested auto-detection inherits the parent candidate's probe. Stop
        // before retaining generation snapshots or walking a potentially
        // large native String to count its UTF-16 units when cancellation is
        // already known. The ordinary synchronous API passes nil and pays
        // only this once-per-call optional check, never a per-candidate one.
        if cancellationProbe?() == true { return .plain() }
        let entries = detectionEntries(subset: subset)
        // Nested auto-detection evaluates the same source against several
        // candidates. Count its UTF-16 units once for the progress guard;
        // the top-level hot path has no ancestry and avoids this work.
        let nestedSourceLength = ancestry == nil ? nil : code.utf16.count
        var candidates = [DetectionCandidate(result: .plain(), supersetOf: nil, order: 0)]
        candidates.reserveCapacity(entries.count + 1)
        if let cancellationProbe {
            for (index, entry) in entries.enumerated() {
                if cancellationProbe() { break }
                guard let candidate = autodetectCandidate(
                    code,
                    entry: entry,
                    ancestry: ancestry,
                    sourceLength: nestedSourceLength,
                    cancellationProbe: cancellationProbe,
                    order: index + 1
                ) else { continue }
                candidates.append(candidate)
            }
        } else {
            // Keep ordinary synchronous auto-detection free of a per-language
            // optional-probe branch.
            for (index, entry) in entries.enumerated() {
                guard let candidate = autodetectCandidate(
                    code,
                    entry: entry,
                    ancestry: ancestry,
                    sourceLength: nestedSourceLength,
                    order: index + 1
                ) else { continue }
                candidates.append(candidate)
            }
        }
        return selectBest(candidates)
    }

    /// Concurrent auto-detection: candidate grammars run in a processor-
    /// bounded window of child tasks. Results are reassembled in candidate order and
    /// ranked by the same ``selectBest(_:)``, so for the same input this
    /// returns exactly what the sequential overload returns — concurrency
    /// changes latency, never the answer. Cancelling the surrounding task
    /// skips not-yet-started candidates; the ranking then covers whatever
    /// completed.
    func highlightAuto(_ code: String, subset: [String]?) async -> HighlightResult {
        guard !Task.isCancelled else { return .plain() }

        let entries = detectionEntries(subset: subset)
        // Cancellation can arrive while a large custom registry snapshot is
        // retained. Recheck before allocating the equally large result-slot
        // buffer and creating child tasks.
        guard !Task.isCancelled else { return .plain() }
        var slots = [DetectionCandidate?](repeating: nil, count: entries.count)
        await withTaskGroup(of: (index: Int, candidate: DetectionCandidate?).self) { group in
            let parallelism = min(
                entries.count,
                Self.maximumConcurrentAutodetectTasks
            )
            var nextIndex = 0
            while nextIndex < parallelism {
                let index = nextIndex
                let entry = entries[index]
                let added = group.addTaskUnlessCancelled {
                    self.concurrentAutodetectCandidate(
                        code,
                        entry: entry,
                        index: index
                    )
                }
                if !added { break }
                nextIndex += 1
            }

            while let (index, candidate) = await group.next() {
                slots[index] = candidate
                if Task.isCancelled {
                    group.cancelAll()
                    continue
                }
                guard nextIndex < entries.count else { continue }
                let newIndex = nextIndex
                let entry = entries[newIndex]
                let added = group.addTaskUnlessCancelled {
                    self.concurrentAutodetectCandidate(
                        code,
                        entry: entry,
                        index: newIndex
                    )
                }
                if added {
                    nextIndex += 1
                } else {
                    group.cancelAll()
                }
            }
        }
        var candidates = [DetectionCandidate(result: .plain(), supersetOf: nil, order: 0)]
        candidates.reserveCapacity(entries.count + 1)
        for candidate in slots {
            if let candidate { candidates.append(candidate) }
        }
        return selectBest(candidates)
    }

    private struct DetectionCandidate: Sendable {
        let result: HighlightResult
        let supersetOf: String?
        let order: Int
    }

    private func concurrentAutodetectCandidate(
        _ code: String,
        entry: GenerationSnapshot,
        index: Int
    ) -> (index: Int, candidate: DetectionCandidate?) {
        guard !Task.isCancelled else { return (index, nil) }
        // NSRegularExpression autoreleases match objects; drain per candidate
        // so parallel runs do not pool them until the whole task group exits.
        let candidate = autoreleasepool {
            autodetectCandidate(
                code,
                entry: entry,
                cancellationProbe: { Task.isCancelled },
                order: index + 1
            )
        }
        return Task.isCancelled ? (index, nil) : (index, candidate)
    }

    /// One auto-detection candidate: nil when the language is unknown,
    /// opted out of detection, or the code is illegal for it.
    private func autodetectCandidate(
        _ code: String,
        entry: GenerationSnapshot,
        ancestry: LanguageAncestry? = nil,
        sourceLength: Int? = nil,
        cancellationProbe: HighlightEngine.CancellationProbe? = nil,
        order: Int
    ) -> DetectionCandidate? {
        if cancellationProbe?() == true { return nil }
        guard let compiled = try? compiledLanguage(from: entry),
              !compiled.disableAutodetect
        else { return nil }
        if cancellationProbe?() == true { return nil }
        if let ancestry {
            let length = sourceLength ?? code.utf16.count
            guard ancestry.depth < LanguageAncestry.maximumDepth,
                  !ancestry.wouldNotProgress(
                      compiled,
                      sourceLength: length,
                      initialMode: compiled.root
                  )
            else { return nil }
        }
        guard let result = try? highlight(
            code,
            language: compiled,
            ignoreIllegals: false,
            ancestry: ancestry,
            cancellationProbe: cancellationProbe
        ), !result.illegal else { return nil }
        return DetectionCandidate(
            result: result,
            supersetOf: compiled.supersetOf,
            order: order
        )
    }

    /// Ranks candidate results (highest relevance first; a base language
    /// precedes its supersets; then candidate order) and folds the
    /// runner-up into ``HighlightResult/secondBest``. Superset constraints
    /// are resolved as a stable topological order rather than inside a sort
    /// comparator, where they are not transitive for arbitrary custom
    /// graphs.
    private func selectBest(_ candidates: [DetectionCandidate]) -> HighlightResult {
        let firstGroup = highestRankedGroup(in: candidates, below: nil)
        let best = firstGroup[0].result
        let second: HighlightResult? = if firstGroup.count > 1 {
            firstGroup[1].result
        } else {
            highestRankedGroup(
                in: candidates,
                below: best.relevance
            ).first?.result
        }
        let secondBest = second.flatMap { result in
            result.language.map { ($0, result.relevance) }
        }
        return HighlightResult(
            language: best.language,
            relevance: best.relevance,
            illegal: best.illegal,
            tokens: best.tokens,
            continuation: best.continuation,
            secondBest: secondBest
        )
    }

    private func highestRankedGroup(
        in candidates: [DetectionCandidate],
        below upperBound: Double?
    ) -> [DetectionCandidate] {
        var highest: Double?
        for candidate in candidates {
            let relevance = candidate.result.relevance
            if let upperBound, relevance >= upperBound { continue }
            if let current = highest {
                if relevance > current { highest = relevance }
            } else {
                highest = relevance
            }
        }
        guard let highest else { return [] }

        let group = candidates.filter { $0.result.relevance == highest }
        return orderSupersetsAfterBases(group)
    }

    private func orderSupersetsAfterBases(
        _ group: [DetectionCandidate]
    ) -> [DetectionCandidate] {
        guard group.count > 1 else { return group }

        var blockers = [Int](repeating: 0, count: group.count)
        var hasConstraint = false
        for candidateIndex in group.indices {
            guard let baseName = group[candidateIndex].supersetOf else { continue }
            for baseIndex in group.indices
            where baseIndex != candidateIndex
                && group[baseIndex].result.language == baseName {
                blockers[candidateIndex] += 1
                hasConstraint = true
            }
        }
        guard hasConstraint else { return group }

        var emitted = [Bool](repeating: false, count: group.count)
        var ordered: [DetectionCandidate] = []
        ordered.reserveCapacity(group.count)
        while ordered.count < group.count {
            var selected: Int?
            for index in group.indices where !emitted[index] && blockers[index] == 0 {
                if let current = selected {
                    if group[index].order < group[current].order { selected = index }
                } else {
                    selected = index
                }
            }
            // A malformed custom superset cycle has no zero-indegree node.
            // Break it deterministically by original order.
            if selected == nil {
                for index in group.indices where !emitted[index] {
                    if let current = selected {
                        if group[index].order < group[current].order { selected = index }
                    } else {
                        selected = index
                    }
                }
            }

            guard let selected else { break }
            emitted[selected] = true
            ordered.append(group[selected])
            if let selectedLanguage = group[selected].result.language {
                for index in group.indices
                where !emitted[index]
                    && group[index].supersetOf == selectedLanguage
                    && blockers[index] > 0 {
                    blockers[index] -= 1
                }
            }
        }
        return ordered
    }
}

/// Immutable call chain used only while one language delegates to another.
/// Identity checks make cycle detection independent of aliases and grammar
/// names. A language may legally delegate a strictly smaller slice back to
/// itself, or resume an equal-sized incremental chunk in a different parser
/// mode. Growing input, or an equal-sized call that repeats an initial mode,
/// is rejected as a non-progressing cycle. The hard depth bound also protects
/// pathological shrinking or acyclic chains assembled from custom grammars.
final class LanguageAncestry: Sendable {
    static let maximumDepth = 64

    let language: CompiledLanguage
    let sourceLength: Int
    let initialMode: CompiledMode
    let parent: LanguageAncestry?
    let depth: Int

    init(
        language: CompiledLanguage,
        sourceLength: Int,
        initialMode: CompiledMode,
        parent: LanguageAncestry?
    ) {
        self.language = language
        self.sourceLength = sourceLength
        self.initialMode = initialMode
        self.parent = parent
        self.depth = (parent?.depth ?? 0) + 1
    }

    func wouldNotProgress(
        _ candidate: CompiledLanguage,
        sourceLength: Int,
        initialMode: CompiledMode
    ) -> Bool {
        var node: LanguageAncestry? = self
        while let current = node {
            if current.language === candidate {
                if sourceLength > current.sourceLength { return true }
                if sourceLength == current.sourceLength,
                   current.initialMode === initialMode {
                    return true
                }
            }
            node = current.parent
        }
        return false
    }
}
