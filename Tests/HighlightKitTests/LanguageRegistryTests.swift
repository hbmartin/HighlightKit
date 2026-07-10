import Foundation
import Synchronization
import Testing
@testable import HighlightKit

@Suite("Language registry generations")
struct LanguageRegistryTests {
    private final class BoolSignal: Sendable {
        let value = Mutex(false)
    }

    private actor StartBarrier {
        let participantCount: Int
        var waiters: [CheckedContinuation<Void, Never>] = []

        init(participantCount: Int) {
            self.participantCount = participantCount
            waiters.reserveCapacity(participantCount)
        }

        func wait() async {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
                guard waiters.count == participantCount else { return }
                let ready = waiters
                waiters.removeAll(keepingCapacity: false)
                for waiter in ready { waiter.resume() }
            }
        }
    }

    private final class ReentrantDeinitProbe: @unchecked Sendable {
        weak var registry: LanguageRegistry?
        let didRun: BoolSignal

        init(registry: LanguageRegistry, didRun: BoolSignal) {
            self.registry = registry
            self.didRun = didRun
        }

        deinit {
            // This would deadlock if an Entry (or its compiled graph) were
            // released while the registry's global state Mutex was held.
            _ = registry?.hasLanguage(named: "replacement")
            didRun.value.withLock { $0 = true }
        }
    }

    @Test func oneBuildPerColdGenerationUnderContention() async {
        let builds = Mutex(0)
        let descriptor = LanguageDescriptor(name: "contended") {
            builds.withLock { $0 += 1 }
            return LanguageDefinition(
                name: "contended",
                root: Mode(contains: [Mode(scope: "keyword", begin: "x")])
            )
        }
        let registry = LanguageRegistry(languages: [descriptor])
        let taskCount = 64
        let barrier = StartBarrier(participantCount: taskCount)
        var results: [CompiledLanguage] = []
        results.reserveCapacity(taskCount)

        await withTaskGroup(of: CompiledLanguage?.self) { group in
            for _ in 0..<taskCount {
                group.addTask {
                    await barrier.wait()
                    return try? registry.compiledLanguage(named: "contended")
                }
            }
            for await result in group {
                if let result { results.append(result) }
            }
        }

        #expect(results.count == taskCount)
        #expect(builds.withLock { $0 } == 1)
        if let first = results.first {
            #expect(results.allSatisfy { $0 === first })
        }
    }

    @Test func compilationFailureIsCachedPerGenerationUnderContention() async {
        let builds = Mutex(0)
        let invalid = LanguageDescriptor(name: "invalid-contended") {
            builds.withLock { $0 += 1 }
            return LanguageDefinition(
                name: "invalid-contended",
                root: Mode(contains: [Mode(begin: "(")])
            )
        }
        let registry = LanguageRegistry(languages: [invalid])
        let taskCount = 64
        let barrier = StartBarrier(participantCount: taskCount)
        var failureCount = 0

        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<taskCount {
                group.addTask {
                    await barrier.wait()
                    do {
                        _ = try registry.compiledLanguage(named: "invalid-contended")
                        return false
                    } catch {
                        return true
                    }
                }
            }
            for await failed in group where failed { failureCount += 1 }
        }

        #expect(failureCount == taskCount)
        #expect(builds.withLock { $0 } == 1)
        do {
            _ = try registry.compiledLanguage(named: "invalid-contended")
            Issue.record("cached invalid regex unexpectedly compiled")
        } catch let error as HighlightError {
            if case .invalidRegex = error {
                // expected: cached shared state preserves the error category
            } else {
                Issue.record("cached failure changed category: \(error)")
            }
        } catch {
            Issue.record("cached failure changed type: \(error)")
        }
        #expect(builds.withLock { $0 } == 1)

        let validBuilds = Mutex(0)
        registry.register([
            LanguageDescriptor(name: "invalid-contended") {
                validBuilds.withLock { $0 += 1 }
                return LanguageDefinition(name: "invalid-contended", root: Mode())
            },
        ])
        do {
            _ = try registry.compiledLanguage(named: "invalid-contended")
        } catch {
            Issue.record("replacement generation unexpectedly failed: \(error)")
        }
        #expect(validBuilds.withLock { $0 } == 1)
    }

    @Test func registrationDuringOldBuildCannotPopulateNewGeneration() throws {
        let registrySlot = Mutex<LanguageRegistry?>(nil)
        let replaced = Mutex(false)
        let replacement = LanguageDescriptor(name: "generation") {
            LanguageDefinition(
                name: "generation",
                root: Mode(contains: [Mode(scope: "new", begin: "NEW")])
            )
        }
        let original = LanguageDescriptor(name: "generation") {
            let shouldReplace = replaced.withLock { value in
                defer { value = true }
                return !value
            }
            if shouldReplace {
                registrySlot.withLock { $0 }?.register([replacement])
            }
            return LanguageDefinition(
                name: "generation",
                root: Mode(contains: [Mode(scope: "old", begin: "OLD")])
            )
        }
        let registry = LanguageRegistry(languages: [original])
        registrySlot.withLock { $0 = registry }

        let inFlightOldGeneration = try registry.compiledLanguage(named: "generation")
        let currentGeneration = try registry.compiledLanguage(named: "generation")

        #expect(inFlightOldGeneration !== currentGeneration)
        #expect(inFlightOldGeneration.root.contains.first?.scope == "old")
        #expect(currentGeneration.root.contains.first?.scope == "new")
        registrySlot.withLock { $0 = nil }
    }

    @Test func replacementRemovesOnlyAliasesOwnedByOldGeneration() {
        let original = LanguageDescriptor(
            name: "alpha",
            aliases: ["legacy", "shared"]
        ) {
            LanguageDefinition(name: "alpha", root: Mode())
        }
        let other = LanguageDescriptor(name: "beta", aliases: ["shared"]) {
            LanguageDefinition(name: "beta", root: Mode())
        }
        let registry = LanguageRegistry(languages: [original, other])

        let replacement = LanguageDescriptor(name: "ALPHA", aliases: ["modern", "MODERN"]) {
            LanguageDefinition(name: "alpha", root: Mode())
        }
        registry.register([replacement])

        #expect(registry.canonicalName(for: "legacy") == nil)
        #expect(registry.canonicalName(for: "MoDeRn") == "alpha")
        #expect(registry.canonicalName(for: "shared") == "beta")
    }

    @Test func descriptorCompilationReentryFailsEvenForAWarmLanguage() throws {
        let registrySlot = Mutex<LanguageRegistry?>(nil)
        let observedError = Mutex<String?>(nil)
        let inner = LanguageDescriptor(name: "inner") {
            LanguageDefinition(name: "inner", root: Mode())
        }
        let outer = LanguageDescriptor(name: "outer") {
            do {
                if let registry = registrySlot.withLock({ $0 }) {
                    _ = try registry.compiledLanguage(named: "inner")
                }
                observedError.withLock { $0 = "no error" }
            } catch {
                observedError.withLock { $0 = String(describing: error) }
            }
            return LanguageDefinition(name: "outer", root: Mode())
        }
        let registry = LanguageRegistry(languages: [inner, outer])
        registrySlot.withLock { $0 = registry }

        _ = try registry.compiledLanguage(named: "inner")
        _ = try registry.compiledLanguage(named: "outer")

        #expect(observedError.withLock { $0 }?.contains("must not compile") == true)
        registrySlot.withLock { $0 = nil }
    }

    @Test func caseFoldedColdAndUnknownLookupsPreserveGenerationSemantics() throws {
        let builds = Mutex(0)
        let descriptor = LanguageDescriptor(
            name: "mixed-case-target",
            aliases: ["mixed-shortcut"]
        ) {
            builds.withLock { $0 += 1 }
            return LanguageDefinition(
                name: "mixed-case-target",
                root: Mode(contains: [
                    Mode(scope: "keyword", begin: "x", relevance: 10)
                ])
            )
        }
        let registry = LanguageRegistry(languages: [descriptor])

        for missing in ["DOES-NOT-EXIST", "不存在"] {
            do {
                _ = try registry.compiledLanguage(named: missing)
                Issue.record("unknown language unexpectedly compiled: \(missing)")
            } catch let error as HighlightError {
                guard case .unknownLanguage(let reportedName) = error else {
                    Issue.record("unknown lookup changed error category: \(error)")
                    continue
                }
                #expect(reportedName == missing)
            } catch {
                Issue.record("unknown lookup changed error type: \(error)")
            }
        }

        let cold = try registry.compiledLanguage(named: "MIXED-CASE-TARGET")
        let warm = try registry.compiledLanguage(named: "mixed-case-target")
        let aliased = try registry.compiledLanguage(named: "mixed-shortcut")
        let auto = registry.highlightAuto("x", subset: ["mixed-shortcut"])

        #expect(cold === warm)
        #expect(aliased === warm)
        #expect(auto.language == "mixed-case-target")
        #expect(builds.withLock { $0 } == 1)
    }

    @Test func autoDetectionCandidateUsesOneGenerationSnapshot() {
        let registrySlot = Mutex<LanguageRegistry?>(nil)
        let replaced = Mutex(false)
        let replacement = LanguageDescriptor(name: "snapshot") {
            LanguageDefinition(
                name: "snapshot",
                root: Mode(contains: [Mode(scope: "new", begin: "NEW")])
            )
        }
        let original = LanguageDescriptor(name: "snapshot") {
            let shouldReplace = replaced.withLock { value in
                defer { value = true }
                return !value
            }
            if shouldReplace {
                registrySlot.withLock { $0 }?.register([replacement])
            }
            return LanguageDefinition(
                name: "snapshot",
                root: Mode(contains: [Mode(scope: "old", begin: "OLD")])
            )
        }
        let registry = LanguageRegistry(languages: [original])
        registrySlot.withLock { $0 = registry }

        let detected = registry.highlightAuto("OLD", subset: ["snapshot"])
        let current = try? registry.highlight(
            "NEW",
            languageName: "snapshot",
            ignoreIllegals: true
        )

        #expect(detected.language == "snapshot")
        #expect(detected.tokens.first?.scope == "old")
        #expect(current?.tokens.first?.scope == "new")
        registrySlot.withLock { $0 = nil }
    }

    @Test func autoDetectionCapturesTheWholeRegistrySnapshot() {
        let registrySlot = Mutex<LanguageRegistry?>(nil)
        let replaced = Mutex(false)
        let newVictim = LanguageDescriptor(name: "z-victim") {
            LanguageDefinition(
                name: "z-victim",
                root: Mode(contains: [Mode(scope: "new", begin: "NEW")])
            )
        }
        let added = LanguageDescriptor(name: "m-added") {
            LanguageDefinition(
                name: "m-added",
                root: Mode(contains: [Mode(scope: "added", begin: "ADDED")])
            )
        }
        let trigger = LanguageDescriptor(name: "a-trigger") {
            let shouldReplace = replaced.withLock { value in
                defer { value = true }
                return !value
            }
            if shouldReplace {
                registrySlot.withLock { $0 }?.register([newVictim, added])
            }
            return LanguageDefinition(name: "a-trigger", root: Mode())
        }
        let oldVictim = LanguageDescriptor(name: "z-victim") {
            LanguageDefinition(
                name: "z-victim",
                root: Mode(contains: [Mode(scope: "old", begin: "OLD")])
            )
        }
        let registry = LanguageRegistry(languages: [trigger, oldVictim])
        registrySlot.withLock { $0 = registry }

        let detected = registry.highlightAuto("OLD", subset: nil)
        let current = try? registry.highlight(
            "NEW",
            languageName: "z-victim",
            ignoreIllegals: true
        )

        #expect(detected.language == "z-victim")
        #expect(detected.tokens.first?.scope == "old")
        #expect(current?.tokens.first?.scope == "new")
        #expect(registry.hasLanguage(named: "m-added"))
        registrySlot.withLock { $0 = nil }
    }

    @Test func supersetTieBreakIsStableAndTransitive() {
        func descriptor(_ name: String, supersetOf: String? = nil) -> LanguageDescriptor {
            LanguageDescriptor(name: name) {
                LanguageDefinition(
                    name: name,
                    supersetOf: supersetOf,
                    root: Mode(contains: [Mode(scope: .name(name), begin: "x")])
                )
            }
        }

        // a-superset must follow c-base. Once it is blocked, the earliest
        // available candidate is b-unrelated; the resulting order is
        // b-unrelated, c-base, a-superset. A pairwise comparator produces
        // the non-transitive cycle A < B < C < A for this shape.
        let registry = LanguageRegistry(languages: [
            descriptor("a-superset", supersetOf: "c-base"),
            descriptor("b-unrelated"),
            descriptor("c-base"),
        ])
        let result = registry.highlightAuto("x", subset: nil)
        #expect(result.language == "b-unrelated")
        #expect(result.secondBest?.language == "c-base")

        // Malformed custom cycles degrade deterministically to candidate
        // order instead of violating the sorting contract.
        let cyclic = LanguageRegistry(languages: [
            descriptor("cycle-a", supersetOf: "cycle-b"),
            descriptor("cycle-b", supersetOf: "cycle-a"),
        ])
        let cycleResult = cyclic.highlightAuto("x", subset: nil)
        #expect(cycleResult.language == "cycle-a")
        #expect(cycleResult.secondBest?.language == "cycle-b")
    }

    @Test func illegalAutoDetectionCandidateIsNotReportedAsSecondBest() {
        let descriptor = LanguageDescriptor(name: "illegal-auto") {
            LanguageDefinition(name: "illegal-auto", root: Mode(illegal: ["."]))
        }
        let registry = LanguageRegistry(languages: [descriptor])
        let result = registry.highlightAuto("x", subset: nil)

        #expect(result.language == nil)
        #expect(result.secondBest == nil)
    }

    @Test func retiredEntriesAreDestroyedOutsideTheGlobalMutex() throws {
        let registry = LanguageRegistry(languages: [])
        let didRun = BoolSignal()
        try installCompiledGenerationWithReentrantDeinit(
            in: registry,
            didRun: didRun
        )

        registry.register([
            LanguageDescriptor(name: "replacement") {
                LanguageDefinition(name: "replacement", root: Mode())
            },
            LanguageDescriptor(name: "retired") {
                LanguageDefinition(name: "retired", root: Mode())
            },
        ])

        #expect(didRun.value.withLock { $0 })
    }

    @inline(never)
    private func installCompiledGenerationWithReentrantDeinit(
        in registry: LanguageRegistry,
        didRun: BoolSignal
    ) throws {
        let probe = ReentrantDeinitProbe(registry: registry, didRun: didRun)
        let descriptor = LanguageDescriptor(name: "retired") { [probe] in
            let mode = Mode(begin: "x", onBegin: { [probe] _, _ in
                _ = probe
            })
            return LanguageDefinition(
                name: "retired",
                root: Mode(contains: [mode])
            )
        }
        registry.register([descriptor])
        _ = try registry.compiledLanguage(named: "retired")
    }
}
