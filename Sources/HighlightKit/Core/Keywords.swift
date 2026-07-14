import Foundation

/// Raw keyword declarations for a mode, as written in a grammar.
///
/// Mirrors highlight.js keyword syntax: a plain list of words is shorthand
/// for the `keyword` scope; a dictionary maps scope names (`keyword`,
/// `literal`, `built_in`, `type`, …) to word lists. Each word may carry an
/// explicit relevance using the `word|relevance` form (for example
/// `"unless|10"`).
public struct Keywords: Sendable {
    /// A single scope's word list. Expressible as `"a b c"` (space
    /// separated) or `["a", "b", "c"]`.
    public struct Group: Sendable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation, ExpressibleByArrayLiteral {
        public var words: [String]

        public init(words: [String]) {
            self.words = words
        }

        public init(stringLiteral value: String) {
            self.words = value.split(separator: " ").map(String.init)
        }

        public init(arrayLiteral elements: String...) {
            self.words = elements
        }
    }

    /// Custom pattern used to split candidate words out of plain text.
    /// Defaults to `\w+` when nil (highlight.js `$pattern`).
    public var pattern: String?

    /// Scope name → word list.
    public var groups: [String: Group]

    public init(pattern: String? = nil, _ groups: [String: Group]) {
        self.pattern = pattern
        self.groups = groups
    }

    /// Shorthand for keywords that all belong to the default
    /// `keyword` scope.
    public init(pattern: String? = nil, keyword words: Group) {
        self.pattern = pattern
        self.groups = ["keyword": words]
    }
}

extension Keywords: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self.init(keyword: Group(stringLiteral: value))
    }
}

extension Keywords: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: String...) {
        self.init(keyword: Group(words: elements))
    }
}

extension Keywords: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, Group)...) {
        self.init(Dictionary(uniqueKeysWithValues: elements))
    }
}

/// Compiled keyword table: word → (scope, relevance, hit counter).
///
/// Two views of the same entries. The `String`-keyed dictionary is the
/// source of truth and the fallback path; the flat UTF-16 open-addressing
/// table answers the parse loop's per-word lookups straight from the raw
/// input units — no `NSString` substring, no `String` allocation, no
/// Unicode hashing per word. Keys are stored post-fold (the compiler
/// lowercases them for case-insensitive languages), so a probe folds only
/// ASCII input units; a word containing a non-ASCII unit in a
/// case-insensitive language must take the `String` path, where full
/// Unicode case folding applies.
struct CompiledKeywords {
    struct Entry {
        let scope: String
        let relevance: Double
        /// Dense per-language index of this word's relevance-saturation
        /// counter, shared across every mode that lists the word (hit
        /// counts are per word text per run, exactly as in highlight.js).
        /// −1 for zero-relevance words, which allocate no counter.
        let hitIndex: Int32
    }

    private let byWord: [String: Entry]
    /// Open-addressing slots (power-of-two count): index into the entry
    /// arrays, or −1 when empty. Linear probing; the table never mutates
    /// after construction and is sized at ≥ 2× occupancy.
    private let slots: [Int32]
    /// Per-entry key spans into `keyUnits`, parallel to `entries`.
    private let keyOffsets: [Int32]
    private let keyUnits: [UInt16]
    private let entries: [Entry]

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }

    /// The `String` path — construction-time semantics, verbatim.
    subscript(word: String) -> Entry? { byWord[word] }

    init(byWord: [String: Entry]) {
        self.byWord = byWord

        var keyOffsets: [Int32] = [0]
        keyOffsets.reserveCapacity(byWord.count + 1)
        var keyUnits: [UInt16] = []
        var entries: [Entry] = []
        entries.reserveCapacity(byWord.count)
        for (word, entry) in byWord {
            keyUnits.append(contentsOf: word.utf16)
            keyOffsets.append(Int32(keyUnits.count))
            entries.append(entry)
        }

        var capacity = 8
        while capacity < byWord.count * 2 { capacity <<= 1 }
        var slots = [Int32](repeating: -1, count: capacity)
        let mask = capacity - 1
        for index in entries.indices {
            let start = Int(keyOffsets[index])
            let end = Int(keyOffsets[index + 1])
            var slot = Int(truncatingIfNeeded: Self.hash(keyUnits[start..<end])) & mask
            while slots[slot] >= 0 {
                slot = (slot + 1) & mask
            }
            slots[slot] = Int32(index)
        }

        self.slots = slots
        self.keyOffsets = keyOffsets
        self.keyUnits = keyUnits
        self.entries = entries
    }

    /// Case-sensitive lookup of `units[location ..< location + length]`
    /// without materializing a `String`. Exact for any input, including
    /// non-ASCII units — keys and word are compared unit-for-unit.
    func lookup(in units: [UInt16], location: Int, length: Int) -> Entry? {
        let mask = slots.count - 1
        var hash: UInt64 = 0xCBF29CE484222325
        for i in location..<(location + length) {
            hash = (hash ^ UInt64(units[i])) &* 0x100000001B3
        }
        var slot = Int(truncatingIfNeeded: hash) & mask
        while true {
            let index = slots[slot]
            if index < 0 { return nil }
            let start = Int(keyOffsets[Int(index)])
            if Int(keyOffsets[Int(index) + 1]) - start == length {
                var matched = true
                for offset in 0..<length
                where keyUnits[start + offset] != units[location + offset] {
                    matched = false
                    break
                }
                if matched { return entries[Int(index)] }
            }
            slot = (slot + 1) & mask
        }
    }

    /// Case-insensitive lookup result: `.nonASCII` means the word cannot
    /// be decided by ASCII folding and must take the `String` path.
    enum FoldedLookup {
        case found(Entry)
        case missing
        case nonASCII
    }

    /// Case-insensitive lookup, folding ASCII `A-Z` while probing —
    /// mirrors the compile-time `lowercased()` for ASCII-only words and
    /// bails out on the first non-ASCII unit (full Unicode folding can
    /// change such a word, e.g. U+212A KELVIN SIGN → `k`).
    func lookupFoldingASCII(
        in units: [UInt16], location: Int, length: Int
    ) -> FoldedLookup {
        let mask = slots.count - 1
        var hash: UInt64 = 0xCBF29CE484222325
        for i in location..<(location + length) {
            let u = units[i]
            if u >= 0x80 { return .nonASCII }
            hash = (hash ^ UInt64(Self.fold(u))) &* 0x100000001B3
        }
        var slot = Int(truncatingIfNeeded: hash) & mask
        while true {
            let index = slots[slot]
            if index < 0 { return .missing }
            let start = Int(keyOffsets[Int(index)])
            if Int(keyOffsets[Int(index) + 1]) - start == length {
                var matched = true
                for offset in 0..<length
                where keyUnits[start + offset] != Self.fold(units[location + offset]) {
                    matched = false
                    break
                }
                if matched { return .found(entries[Int(index)]) }
            }
            slot = (slot + 1) & mask
        }
    }

    /// ASCII `A-Z` → `a-z`; every other unit unchanged.
    @inline(__always)
    private static func fold(_ u: UInt16) -> UInt16 {
        (u >= 65 && u <= 90) ? u | 0x20 : u
    }

    /// FNV-1a over the (post-fold) key units — matches `lookup`'s probe.
    private static func hash(_ units: ArraySlice<UInt16>) -> UInt64 {
        var hash: UInt64 = 0xCBF29CE484222325
        for u in units {
            hash = (hash ^ UInt64(u)) &* 0x100000001B3
        }
        return hash
    }
}

enum KeywordCompiler {
    /// Keywords so common in prose or as identifiers that matching them
    /// contributes no relevance by default.
    static let commonKeywords: Set<String> = [
        "of", "and", "for", "in", "not", "or", "if", "then",
        "parent", "list", "value",
    ]

    static let defaultPattern = "\\w+"

    /// Port of highlight.js `compileKeywords`. `hitIndices` assigns each
    /// relevance-carrying word one dense per-language counter index,
    /// shared across modes — saturation is per word text per run.
    static func compile(
        _ keywords: Keywords,
        caseInsensitive: Bool,
        hitIndices: inout [String: Int32]
    ) -> CompiledKeywords {
        var compiled = [String: CompiledKeywords.Entry](
            minimumCapacity: keywords.groups.values.reduce(0) { $0 + $1.words.count }
        )
        // Sorted so a word listed under two scope groups resolves
        // deterministically. highlight.js resolves by object insertion
        // order, which `Keywords.groups` (a Dictionary) cannot observe —
        // see FIDELITY.md; no bundled grammar declares such a duplicate.
        for scope in keywords.groups.keys.sorted() {
            let group = keywords.groups[scope]!
            for entry in group.words {
                var word = entry
                var relevance: Double?
                if let bar = entry.firstIndex(of: "|") {
                    word = String(entry[..<bar])
                    relevance = Double(entry[entry.index(after: bar)...])
                }
                if caseInsensitive {
                    word = word.lowercased()
                }
                let resolved = relevance
                    ?? (commonKeywords.contains(word.lowercased()) ? 0 : 1)
                var hitIndex: Int32 = -1
                if resolved != 0 {
                    if let existing = hitIndices[word] {
                        hitIndex = existing
                    } else {
                        hitIndex = Int32(hitIndices.count)
                        hitIndices[word] = hitIndex
                    }
                }
                compiled[word] = CompiledKeywords.Entry(
                    scope: scope, relevance: resolved, hitIndex: hitIndex
                )
            }
        }
        return CompiledKeywords(byWord: compiled)
    }
}
