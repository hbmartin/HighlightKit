import Foundation

/// A compiled scope assignment.
enum CompiledScope {
    /// Wrap the whole begin/end lexeme in a single scope.
    case wrap(String)
    /// Assign scopes per top-level capture group of a multi-part match.
    /// `groups` is ordered by group number; a `nil` scope means the group's
    /// text is emitted through keyword processing instead.
    case multi(groups: [(group: Int, scope: String?)])
}

/// The compiled, immutable form of a ``Mode``.
///
/// Instances are created by ``ModeCompiler`` and never mutated afterwards;
/// the whole compiled-language graph (which is cyclic through `contains`
/// self references) is safe to share across threads.
final class CompiledMode: @unchecked Sendable {
    var scope: String?
    var beginPattern = ""
    var beginRe: NSRegularExpression?
    var endRe: NSRegularExpression?
    /// Pattern that can terminate this mode (its own `end` plus any parent
    /// terminators inherited via `endsWithParent`).
    var terminatorEnd = ""
    var illegalPattern: String?

    var keywords: CompiledKeywords?
    var keywordPatternRe: NSRegularExpression?

    var contains: [CompiledMode] = []
    var starts: CompiledMode?
    var subLanguage: [String]?
    var relevance: Double = 1

    var beginScope: CompiledScope?
    var endScope: CompiledScope?

    var excludeBegin = false
    var excludeEnd = false
    var returnBegin = false
    var returnEnd = false
    var skip = false
    var endsParent = false
    var endsWithParent = false

    var onBegin: ModeCallback?
    var onEnd: ModeCallback?
    var internalBeforeBegin: ModeCallback?

    /// Combined begin/end/illegal matcher for scanning inside this mode.
    var matcher: CompiledMatcher!
}

/// Owns the exceptional mutation needed to dismantle immutable compiled
/// grammar graphs. Grammars can contain self/mutual references, and every
/// matcher duplicates each `contains` edge in `MatchKind.begin`; ARC cannot
/// reclaim those graphs without explicitly severing both edge sets.
///
/// Callers must prove the graph is unpublished (failed compilation) or has
/// no remaining language owner (`CompiledLanguage.deinit`). Consequently no
/// synchronization is needed and adding a lock here would not make an
/// invalid mode-only lifetime safe.
enum CompiledGraphLifecycle {
    static func breakCycles(startingAt roots: [CompiledMode]) {
        var pending = roots
        var visited = Set<ObjectIdentifier>()
        visited.reserveCapacity(roots.count)

        while let mode = pending.popLast() {
            guard visited.insert(ObjectIdentifier(mode)).inserted else { continue }

            // Save every outgoing edge before releasing it. Matcher edges
            // are included independently: clearing only `contains` leaves
            // `mode -> matcher -> begin rule -> mode` cycles alive.
            pending.append(contentsOf: mode.contains)
            if let starts = mode.starts { pending.append(starts) }
            if let matcher = mode.matcher {
                for rule in matcher.rules {
                    if case .begin(let target) = rule.kind {
                        pending.append(target)
                    }
                }
            }

            // Assignment releases any uniquely or multiply referenced COW
            // buffer directly; mutating removal can needlessly copy it.
            mode.contains = []
            mode.starts = nil
            mode.matcher = nil
        }
    }
}

/// The compiled top level of a language.
final class CompiledLanguage: @unchecked Sendable {
    let name: String
    let caseInsensitive: Bool
    let classNameAliases: [String: String]
    let disableAutodetect: Bool
    let supersetOf: String?
    let root: CompiledMode
    /// Number of matcher-rule cache slots the engine must allocate per
    /// run (see ``RuleMatchCache``).
    let ruleSlotCount: Int

    init(
        name: String,
        caseInsensitive: Bool,
        classNameAliases: [String: String],
        disableAutodetect: Bool,
        supersetOf: String?,
        root: CompiledMode,
        ruleSlotCount: Int
    ) {
        self.name = name
        self.caseInsensitive = caseInsensitive
        self.classNameAliases = classNameAliases
        self.disableAutodetect = disableAutodetect
        self.supersetOf = supersetOf
        self.root = root
        self.ruleSlotCount = ruleSlotCount
    }

    func aliasedScope(_ scope: String) -> String {
        classNameAliases[scope] ?? scope
    }

    deinit {
        // Production code never lets a `CompiledMode` outlive its owner:
        // active runs hold `Run.language`, and continuations hold
        // `ResumeState.owner`. The last owner therefore proves there can be
        // no concurrent reader while the graph is dismantled.
        CompiledGraphLifecycle.breakCycles(startingAt: [root])
    }
}

/// Errors raised while compiling a grammar.
public enum HighlightError: Error, CustomStringConvertible {
    case unknownLanguage(String)
    case invalidRegex(language: String, pattern: String, underlying: any Error)
    case invalidGrammar(language: String, reason: String)

    public var description: String {
        switch self {
        case .unknownLanguage(let name):
            return "Unknown language: \(name)"
        case .invalidRegex(let language, let pattern, let underlying):
            return "Invalid regex in language '\(language)': /\(pattern)/ — \(underlying)"
        case .invalidGrammar(let language, let reason):
            return "Invalid grammar '\(language)': \(reason)"
        }
    }
}
