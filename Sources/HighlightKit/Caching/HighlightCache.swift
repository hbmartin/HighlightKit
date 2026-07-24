import Foundation
#if canImport(Darwin)
import Dispatch
#endif

/// A caller-owned, namespaced identity for source content.
///
/// The value is deliberately opaque to HighlightKit. A Git client might use
/// `namespace: "git-blob"` and a blob object ID as the value.
public struct HighlightCacheKey: Hashable, Sendable {
    public let namespace: String
    public let value: String

    public init(namespace: String, value: String) {
        self.namespace = namespace
        self.value = value
    }
}

public struct HighlightCacheMetrics: Equatable, Sendable {
    public internal(set) var hits = 0
    public internal(set) var misses = 0
    public internal(set) var coalescedRequests = 0
    public internal(set) var negativeHits = 0
    public internal(set) var bypasses = 0
    public internal(set) var insertions = 0
    public internal(set) var evictions = 0
    public internal(set) var purges = 0
    public internal(set) var count = 0
    public internal(set) var currentCost = 0

    public init() {}
}

struct HighlightCacheRequestKey: Hashable, Sendable {
    let caller: HighlightCacheKey
    let registry: ObjectIdentifier
    let registryRevision: UInt64
    let selection: String
    let ignoreIllegals: Bool
    let sourceLength: Int
    let continuation: ObjectIdentifier?
}

struct HighlightCacheUnknownLanguageKey: Hashable, Sendable {
    let registry: ObjectIdentifier
    let registryRevision: UInt64
    let language: String
}

private enum HighlightCacheEntryKey: Hashable, Sendable {
    case request(HighlightCacheRequestKey)
    case unknownLanguage(HighlightCacheUnknownLanguageKey)
}

/// An explicit cost-bounded LRU cache for theme-independent highlight
/// results. The cache retains tokens and continuations, never source text.
public actor HighlightCache {
    private enum StoredValue: Sendable {
        case result(HighlightResult)
        case unknownLanguage
    }

    private struct Entry: Sendable {
        let value: StoredValue
        let cost: Int
        var lastAccess: UInt64
    }

    private struct Failure: @unchecked Sendable {
        let error: any Error
    }

    private enum FlightOutcome: Sendable {
        case success(HighlightResult)
        case failure(Failure)
    }

    private typealias Waiter = CheckedContinuation<HighlightResult, any Error>

    private struct Flight {
        let id: UUID
        var producer: Task<Void, Never>?
        var waiters: [UUID: Waiter]
        var allowsInsertion: Bool
    }

    public let costLimit: Int
    public let countLimit: Int?

    private var entries: [HighlightCacheEntryKey: Entry] = [:]
    private var flights: [HighlightCacheRequestKey: Flight] = [:]
    private var clock: UInt64 = 0
    /// Sum of `entries` costs, maintained incrementally so limit checks and
    /// metrics never rescan the table.
    private var trackedCost = 0
    private var statistics = HighlightCacheMetrics()

#if canImport(Darwin)
    private var memoryPressureMonitor: MemoryPressureMonitor?
#endif

    public init(
        costLimit: Int,
        countLimit: Int? = nil,
        automaticallyPurgesOnMemoryPressure: Bool = true
    ) {
        precondition(costLimit >= 0, "costLimit must not be negative")
        if let countLimit {
            precondition(countLimit >= 0, "countLimit must not be negative")
        }
        self.costLimit = costLimit
        self.countLimit = countLimit

#if canImport(Darwin)
        if automaticallyPurgesOnMemoryPressure {
            Task { [weak self] in
                await self?.installMemoryPressureMonitor()
            }
        }
#else
        _ = automaticallyPurgesOnMemoryPressure
#endif
    }

    public var metrics: HighlightCacheMetrics {
        var snapshot = statistics
        snapshot.count = entries.count
        snapshot.currentCost = trackedCost
        return snapshot
    }

    /// Removes all completed entries. In-flight requests remain active.
    public func purge() {
        entries.removeAll(keepingCapacity: true)
        trackedCost = 0
        statistics.purges += 1
    }

    /// Exposes the same path as a platform memory-pressure notification so
    /// applications and tests can deterministically exercise purge behavior.
    public func handleMemoryPressure() {
        purge()
    }

    func recordBypass() {
        statistics.bypasses += 1
    }

    /// Atomically checks or inserts an unknown-language failure. Returning
    /// true means the failure was already cached for this registry revision.
    func recordUnknownLanguage(for key: HighlightCacheUnknownLanguageKey) -> Bool {
        let entryKey = HighlightCacheEntryKey.unknownLanguage(key)
        if let entry = entries[entryKey],
           case .unknownLanguage = entry.value {
            statistics.negativeHits += 1
            touch(entryKey)
            return true
        }
        statistics.misses += 1
        insert(.unknownLanguage, for: entryKey, cost: 1)
        return false
    }

    func value(
        for key: HighlightCacheRequestKey,
        allowsInsertion: Bool,
        producer: @escaping @Sendable () async throws -> HighlightResult
    ) async throws -> HighlightResult {
        try Task.checkCancellation()
        let entryKey = HighlightCacheEntryKey.request(key)
        if let entry = entries[entryKey], case .result(let result) = entry.value {
            statistics.hits += 1
            touch(entryKey)
            return result
        }

        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if var flight = flights[key] {
                    statistics.coalescedRequests += 1
                    flight.waiters[waiterID] = continuation
                    flight.allowsInsertion = flight.allowsInsertion || allowsInsertion
                    flights[key] = flight
                    return
                }

                statistics.misses += 1
                if !allowsInsertion { statistics.bypasses += 1 }
                let flightID = UUID()
                flights[key] = Flight(
                    id: flightID,
                    producer: nil,
                    waiters: [waiterID: continuation],
                    allowsInsertion: allowsInsertion
                )
                let task = Task.detached { [weak self] in
                    let outcome: FlightOutcome
                    do {
                        outcome = .success(try await producer())
                    } catch {
                        outcome = .failure(Failure(error: error))
                    }
                    await self?.finishFlight(flightID, for: key, outcome: outcome)
                }
                flights[key]?.producer = task
            }
        } onCancel: {
            Task { [weak self] in
                await self?.cancelWaiter(waiterID, for: key)
            }
        }
    }

    private func cancelWaiter(_ waiterID: UUID, for key: HighlightCacheRequestKey) {
        guard var flight = flights[key],
              let continuation = flight.waiters.removeValue(forKey: waiterID)
        else { return }
        continuation.resume(throwing: CancellationError())
        if flight.waiters.isEmpty {
            flights.removeValue(forKey: key)
            flight.producer?.cancel()
        } else {
            flights[key] = flight
        }
    }

    private func finishFlight(
        _ flightID: UUID,
        for key: HighlightCacheRequestKey,
        outcome: FlightOutcome
    ) {
        guard let flight = flights[key], flight.id == flightID else { return }
        flights.removeValue(forKey: key)
        switch outcome {
        case .success(let result):
            if flight.allowsInsertion, !result.isTruncated {
                insert(
                    .result(result),
                    for: .request(key),
                    cost: Self.cost(of: result)
                )
            }
            for continuation in flight.waiters.values {
                continuation.resume(returning: result)
            }
        case .failure(let failure):
            for continuation in flight.waiters.values {
                continuation.resume(throwing: failure.error)
            }
        }
    }

    private func touch(_ key: HighlightCacheEntryKey) {
        guard var entry = entries[key] else { return }
        clock &+= 1
        entry.lastAccess = clock
        entries[key] = entry
    }

    private func insert(
        _ value: StoredValue,
        for key: HighlightCacheEntryKey,
        cost: Int
    ) {
        guard cost <= costLimit, countLimit != 0 else { return }
        clock &+= 1
        if let previous = entries.updateValue(
            Entry(value: value, cost: cost, lastAccess: clock),
            forKey: key
        ) {
            trackedCost -= previous.cost
        }
        trackedCost += cost
        statistics.insertions += 1
        evictIfNeeded()
    }

    private func evictIfNeeded() {
        while trackedCost > costLimit
            || countLimit.map({ entries.count > $0 }) == true {
            guard let victim = entries.min(by: {
                $0.value.lastAccess < $1.value.lastAccess
            }) else { break }
            entries.removeValue(forKey: victim.key)
            trackedCost -= victim.value.cost
            statistics.evictions += 1
        }
    }

    private static func cost(of result: HighlightResult) -> Int {
        result.tokens.reduce(into: 64) { cost, token in
            cost += 32
            for scope in token.scopes {
                cost += scope.utf8.count
            }
        }
    }

#if canImport(Darwin)
    private func installMemoryPressureMonitor() {
        guard memoryPressureMonitor == nil else { return }
        memoryPressureMonitor = MemoryPressureMonitor { [weak self] in
            Task { await self?.handleMemoryPressure() }
        }
    }
#endif
}

#if canImport(Darwin)
private final class MemoryPressureMonitor: @unchecked Sendable {
    private let source: any DispatchSourceMemoryPressure

    init(handler: @escaping @Sendable () -> Void) {
        source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )
        source.setEventHandler(handler: handler)
        source.activate()
    }

    deinit {
        source.cancel()
    }
}
#endif
