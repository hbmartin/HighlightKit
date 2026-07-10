import Foundation

/// Compiles a ``LanguageDefinition`` into an immutable ``CompiledLanguage``.
/// Port of highlight.js `mode_compiler.js` and its compiler extensions.
enum ModeCompiler {
    static func compile(_ definition: LanguageDefinition) throws -> CompiledLanguage {
        var context = Context(
            languageName: definition.name,
            caseInsensitive: definition.caseInsensitive,
            classNameAliases: definition.classNameAliases
        )

        // Compilation extensions intentionally mutate the raw grammar and
        // may create reference cycles before a later validation/regex step
        // throws. Always sever those private build-time edges. The partial
        // compiled graph needs separate cleanup because no
        // `CompiledLanguage` owner exists on the failure path.
        defer { tearDownRawTree(definition.root) }

        do {
            if definition.root === Mode.selfReference
                || definition.root.contains?.contains(where: { $0 === Mode.selfReference }) == true
            {
                throw HighlightError.invalidGrammar(
                    language: definition.name,
                    reason: "a top-level language cannot be a `self` reference"
                )
            }

            let root = try compileMode(definition.root, parent: nil, in: &context)
            return CompiledLanguage(
                name: definition.name,
                caseInsensitive: definition.caseInsensitive,
                classNameAliases: definition.classNameAliases,
                disableAutodetect: definition.disableAutodetect,
                supersetOf: definition.supersetOf,
                root: root,
                ruleSlotCount: context.nextRuleSlot
            )
        } catch {
            // A throwing child can already have registered a cyclic compiled
            // mode without appending it to its parent. Start from every
            // context value rather than assuming the partial root reaches it.
            CompiledGraphLifecycle.breakCycles(startingAt: Array(context.compiled.values))
            throw error
        }
    }

    private struct Context {
        let languageName: String
        let caseInsensitive: Bool
        let classNameAliases: [String: String]
        /// Identity map giving each raw mode exactly one compiled form —
        /// the port of the `isCompiled` guard, which also resolves the
        /// `self` cycle.
        var compiled: [ObjectIdentifier: CompiledMode] = [:]
        /// Allocates per-language cache slots for matcher rules.
        var nextRuleSlot = 0

        var regexOptions: NSRegularExpression.Options {
            var options: NSRegularExpression.Options = [.anchorsMatchLines]
            if caseInsensitive { options.insert(.caseInsensitive) }
            return options
        }

        func regex(_ pattern: String) throws -> NSRegularExpression {
            do {
                return try NSRegularExpression(pattern: pattern, options: regexOptions)
            } catch {
                throw HighlightError.invalidRegex(language: languageName, pattern: pattern, underlying: error)
            }
        }
    }

    /// Severs all mode-to-mode references in a raw grammar tree so its
    /// cycles can't keep it alive after compilation.
    private static func tearDownRawTree(_ root: Mode) {
        var seen = Set<ObjectIdentifier>()
        var queue: [Mode] = [root]
        while let mode = queue.popLast() {
            // This process-wide marker is shared by every grammar and is
            // compared only by identity. It must never be mutated by one
            // compilation while another compilation is reading it.
            guard mode !== Mode.selfReference else { continue }
            guard seen.insert(ObjectIdentifier(mode)).inserted else { continue }
            queue.append(contentsOf: mode.contains ?? [])
            queue.append(contentsOf: mode.variants ?? [])
            queue.append(contentsOf: mode.cachedVariants ?? [])
            if let starts = mode.starts { queue.append(starts) }
            mode.contains = nil
            mode.variants = nil
            mode.cachedVariants = nil
            mode.starts = nil
            // Compiled modes own independent strong references to these
            // closures. Clear the raw copies so a callback that captures
            // its source Mode (directly or through a holder) cannot leave
            // the consumed build-time graph in a retain cycle.
            mode.onBegin = nil
            mode.onEnd = nil
            mode.internalBeforeBegin = nil
        }
    }

    // MARK: - Mode compilation

    private static func compileMode(_ mode: Mode, parent: CompiledMode?, in context: inout Context) throws -> CompiledMode {
        if let existing = context.compiled[ObjectIdentifier(mode)] {
            return existing
        }
        let cmode = CompiledMode()
        // Register before compiling children so `self` references resolve
        // to the (partially built) compiled mode, exactly like the early
        // `isCompiled = true` in highlight.js.
        context.compiled[ObjectIdentifier(mode)] = cmode

        // -- compiler extensions, in highlight.js order --------------------
        try applyMatchSugar(mode, language: context.languageName)
        applyScopeSugar(mode)
        try applyMultiClass(mode, language: context.languageName)
        try applyBeforeMatch(mode, language: context.languageName)
        applyEndSameAsBegin(mode)
        applyBeginKeywords(mode, parent: parent)
        // -------------------------------------------------------------------

        cmode.scope = mode.scope?.singleName
        cmode.beginScope = compiledScope(from: mode.beginScope)
        cmode.endScope = compiledScope(from: mode.endScope)
        cmode.excludeBegin = mode.excludeBegin
        cmode.excludeEnd = mode.excludeEnd
        cmode.returnBegin = mode.returnBegin
        cmode.returnEnd = mode.returnEnd
        cmode.skip = mode.skip
        cmode.endsParent = mode.endsParent
        cmode.endsWithParent = mode.endsWithParent
        cmode.subLanguage = mode.subLanguage
        cmode.relevance = mode.relevance ?? 1
        cmode.onBegin = mode.onBegin
        cmode.onEnd = mode.onEnd
        cmode.internalBeforeBegin = mode.internalBeforeBegin

        if let keywords = mode.keywords {
            cmode.keywords = KeywordCompiler.compile(keywords, caseInsensitive: context.caseInsensitive)
            cmode.keywordPatternRe = try context.regex(keywords.pattern ?? KeywordCompiler.defaultPattern)
        }

        // JavaScript grammars use `''` to mean "unset" (falsy), for
        // example `end: ''` on template-literal lead-ins.
        if mode.begin?.single?.isEmpty == true { mode.begin = nil }
        if mode.end?.single?.isEmpty == true { mode.end = nil }

        if parent != nil {
            let beginPattern = mode.begin?.single ?? "\\B|\\b"
            cmode.beginPattern = beginPattern
            cmode.beginRe = try context.regex(beginPattern)
            if mode.end == nil && !mode.endsWithParent {
                mode.end = "\\B|\\b"
            }
            if let end = mode.end?.single {
                cmode.endRe = try context.regex(end)
                cmode.terminatorEnd = end
            }
            if mode.endsWithParent, let parent, !parent.terminatorEnd.isEmpty {
                cmode.terminatorEnd += (mode.end != nil ? "|" : "") + parent.terminatorEnd
            }
        }

        if let illegal = mode.illegal, !illegal.isEmpty {
            cmode.illegalPattern = illegal.count == 1 ? illegal[0] : RegexSource.either(illegal)
        }

        // -- children -------------------------------------------------------
        let rawContains = mode.contains ?? []
        let expandedContains = rawContains.flatMap { child in
            expandOrClone(child === Mode.selfReference ? mode : child)
        }
        mode.contains = expandedContains
        for child in expandedContains {
            cmode.contains.append(try compileMode(child, parent: cmode, in: &context))
        }

        if let starts = mode.starts {
            cmode.starts = try compileMode(starts, parent: parent, in: &context)
        }

        cmode.matcher = try buildMatcher(for: cmode, in: &context)
        return cmode
    }

    private static func buildMatcher(for cmode: CompiledMode, in context: inout Context) throws -> CompiledMatcher {
        var rules: [MatchRule] = []
        rules.reserveCapacity(cmode.contains.count + 2)
        for child in cmode.contains {
            rules.append(MatchRule(pattern: child.beginPattern, kind: .begin(child)))
        }
        if !cmode.terminatorEnd.isEmpty {
            rules.append(MatchRule(pattern: cmode.terminatorEnd, kind: .end))
        }
        if let illegal = cmode.illegalPattern {
            rules.append(MatchRule(pattern: illegal, kind: .illegal))
        }
        return try CompiledMatcher(
            rules: rules,
            options: context.regexOptions,
            language: context.languageName,
            nextSlot: &context.nextRuleSlot
        )
    }

    // MARK: - Compiler extensions

    /// `match` sugar → `begin`.
    private static func applyMatchSugar(_ mode: Mode, language: String) throws {
        guard let match = mode.match else { return }
        guard mode.begin == nil, mode.end == nil else {
            throw HighlightError.invalidGrammar(language: language, reason: "begin & end are not supported with match")
        }
        mode.begin = match
        mode.match = nil
    }

    /// `scope: {1: …}` sugar → `beginScope`.
    private static func applyScopeSugar(_ mode: Mode) {
        if case .multi = mode.scope {
            mode.beginScope = mode.scope
            mode.scope = nil
        }
    }

    /// Multi-part begin/end: concatenates the parts (renumbering
    /// backreferences) and validates the scope maps.
    private static func applyMultiClass(_ mode: Mode, language: String) throws {
        if case .parts(let parts) = mode.begin {
            guard case .multi(let names) = mode.beginScope else {
                throw HighlightError.invalidGrammar(language: language, reason: "multi-part begin requires a group scope map")
            }
            guard !mode.skip, !mode.excludeBegin, !mode.returnBegin else {
                throw HighlightError.invalidGrammar(
                    language: language, reason: "skip, excludeBegin, returnBegin not compatible with beginScope: {}"
                )
            }
            mode.beginScope = remapScopeNames(names, parts: parts)
            mode.begin = .re(RegexSource.rewriteBackreferences(parts, joinedBy: ""))
        }
        if case .parts(let parts) = mode.end {
            guard case .multi(let names) = mode.endScope else {
                throw HighlightError.invalidGrammar(language: language, reason: "multi-part end requires a group scope map")
            }
            guard !mode.skip, !mode.excludeEnd, !mode.returnEnd else {
                throw HighlightError.invalidGrammar(
                    language: language, reason: "skip, excludeEnd, returnEnd not compatible with endScope: {}"
                )
            }
            mode.endScope = remapScopeNames(names, parts: parts)
            mode.end = .re(RegexSource.rewriteBackreferences(parts, joinedBy: ""))
        }
    }

    /// Renumbers a `{part index: scope}` map to capture-group indexes in
    /// the concatenated pattern, accounting for capture groups nested
    /// inside each part (port of `remapScopeNames`).
    private static func remapScopeNames(_ names: [Int: String], parts: [String]) -> ScopeRef {
        var remapped: [Int: String] = [:]
        var offset = 0
        for i in 1...parts.count {
            if let name = names[i] {
                remapped[i + offset] = name
            } else {
                // top-level group with no scope: keep the key with an
                // empty marker so the emitter still keyword-processes it
                remapped[i + offset] = ""
            }
            offset += RegexSource.countCaptureGroups(parts[i - 1])
        }
        return .multi(remapped)
    }

    private static func compiledScope(from scope: ScopeRef?) -> CompiledScope? {
        switch scope {
        case nil:
            return nil
        case .name(let name):
            return .wrap(name)
        case .multi(let map):
            let groups = map.keys.sorted().map { key in
                (group: key, scope: map[key]!.isEmpty ? nil : map[key])
            }
            return .multi(groups: groups)
        case .some(.none):
            return nil
        }
    }

    /// `beforeMatch` sugar: rewrites the mode into a zero-relevance
    /// wrapper that requires `beforeMatch` directly before `begin`, then
    /// enters the original mode (port of `beforeMatchExt`).
    private static func applyBeforeMatch(_ mode: Mode, language: String) throws {
        guard let beforeMatch = mode.beforeMatch else { return }
        guard mode.starts == nil else {
            throw HighlightError.invalidGrammar(language: language, reason: "beforeMatch cannot be used with starts")
        }
        guard case .re(let before) = beforeMatch, case .re(let begin)? = mode.begin else {
            throw HighlightError.invalidGrammar(language: language, reason: "beforeMatch requires single-pattern begin")
        }

        let original = mode.copied()
        original.beforeMatch = nil
        original.endsParent = true

        let keywords = mode.keywords
        // reset the wrapper in place
        let replacement = Mode(
            begin: .re(before + RegexSource.lookahead(begin)),
            keywords: keywords,
            starts: Mode(contains: [original], relevance: 0),
            relevance: 0
        )
        mode.assign(from: replacement)
    }

    /// `endSameAsBegin` sugar: the end match must equal the begin match's
    /// first capture group (port of the `END_SAME_AS_BEGIN` helper).
    private static func applyEndSameAsBegin(_ mode: Mode) {
        guard mode.endSameAsBegin else { return }
        mode.endSameAsBegin = false
        mode.onBegin = { match, response in
            response.data["_beginMatch"] = match[1] ?? ""
        }
        mode.onEnd = { match, response in
            if response.data["_beginMatch"] != (match[1] ?? "") {
                response.ignoreMatch()
            }
        }
    }

    /// `beginKeywords` sugar (port of the `beginKeywords` extension).
    private static func applyBeginKeywords(_ mode: Mode, parent: CompiledMode?) {
        guard parent != nil, let beginKeywords = mode.beginKeywords else { return }

        // A word boundary alone is not enough for keywords containing
        // non-word characters, so also require a boundary or whitespace
        // after the keyword — and veto matches preceded by a dot.
        mode.begin = .re("\\b(" + beginKeywords.split(separator: " ").joined(separator: "|") + ")(?!\\.)(?=\\b|\\s)")
        mode.internalBeforeBegin = { match, response in
            if match.precedingUnit == unichar(UInt8(ascii: ".")) {
                response.ignoreMatch()
            }
        }
        if mode.keywords == nil {
            mode.keywords = Keywords(stringLiteral: beginKeywords)
        }
        mode.beginKeywords = nil
        if mode.relevance == nil {
            mode.relevance = 0
        }
    }

    // MARK: - Variants and cloning

    private static func dependencyOnParent(_ mode: Mode?) -> Bool {
        var current = mode
        var slow = mode
        var fast = mode
        while let candidate = current {
            if candidate.endsWithParent { return true }

            current = candidate.starts
            slow = slow?.starts
            fast = fast?.starts?.starts
            if let slow, let fast, slow === fast {
                // Floyd's cycle check avoids both recursive stack growth and
                // a Set allocation for the overwhelmingly common short
                // starts chain. A collision can precede our first visit to
                // every cycle node when there is a non-cyclic prefix, so
                // walk exactly one cycle before deciding none depends on its
                // parent.
                var cycleNode = slow
                repeat {
                    if cycleNode.endsWithParent { return true }
                    // Floyd can collide only inside a cycle, so `starts`
                    // cannot be nil before returning to the collision node.
                    cycleNode = cycleNode.starts!
                } while cycleNode !== slow
                return false
            }
        }
        return false
    }

    /// Port of `expandOrCloneMode`: explodes `variants` into standalone
    /// modes and clones modes that depend on their parent so each use
    /// site compiles independently.
    private static func expandOrClone(_ mode: Mode) -> [Mode] {
        if let variants = mode.variants, mode.cachedVariants == nil {
            mode.cachedVariants = variants.map { variant in
                merged(base: mode, variant: variant)
            }
        }
        if let cached = mode.cachedVariants {
            return cached
        }
        if dependencyOnParent(mode) {
            return [mode.copied { $0.starts = $0.starts?.copied() }]
        }
        return [mode]
    }

    /// Shallow merge of a variant over its base mode — the port of
    /// `inherit(mode, { variants: null }, variant)`: every field the
    /// variant sets wins; everything else comes from the base.
    private static func merged(base: Mode, variant: Mode) -> Mode {
        let m = base.copied()
        m.variants = variant.variants
        m.cachedVariants = nil

        if let v = variant.scope { m.scope = v }
        if let v = variant.match { m.match = v }
        if let v = variant.begin { m.begin = v }
        if let v = variant.beginScope { m.beginScope = v }
        if let v = variant.beginKeywords { m.beginKeywords = v }
        if let v = variant.beforeMatch { m.beforeMatch = v }
        if let v = variant.end { m.end = v }
        if let v = variant.endScope { m.endScope = v }
        if variant.endSameAsBegin { m.endSameAsBegin = true }
        if let v = variant.keywords { m.keywords = v }
        if let v = variant.illegal { m.illegal = v }
        if let v = variant.contains { m.contains = v }
        if let v = variant.starts { m.starts = v }
        if let v = variant.subLanguage { m.subLanguage = v }
        if let v = variant.relevance { m.relevance = v }
        if let v = variant.label { m.label = v }
        if variant.excludeBegin { m.excludeBegin = true }
        if variant.excludeEnd { m.excludeEnd = true }
        if variant.returnBegin { m.returnBegin = true }
        if variant.returnEnd { m.returnEnd = true }
        if variant.skip { m.skip = true }
        if variant.endsParent { m.endsParent = true }
        if variant.endsWithParent { m.endsWithParent = true }
        if let v = variant.onBegin { m.onBegin = v }
        if let v = variant.onEnd { m.onEnd = v }
        return m
    }
}

extension ScopeRef {
    var singleName: String? {
        if case .name(let name) = self { return name }
        return nil
    }
}

extension Mode {
    /// Replaces all of this mode's fields with `other`'s (used by the
    /// `beforeMatch` rewrite, which must mutate the mode in place because
    /// other modes may already reference it).
    func assign(from other: Mode) {
        scope = other.scope
        match = other.match
        begin = other.begin
        beginScope = other.beginScope
        beginKeywords = other.beginKeywords
        beforeMatch = other.beforeMatch
        end = other.end
        endScope = other.endScope
        endSameAsBegin = other.endSameAsBegin
        keywords = other.keywords
        illegal = other.illegal
        contains = other.contains
        variants = other.variants
        starts = other.starts
        subLanguage = other.subLanguage
        relevance = other.relevance
        label = other.label
        excludeBegin = other.excludeBegin
        excludeEnd = other.excludeEnd
        returnBegin = other.returnBegin
        returnEnd = other.returnEnd
        skip = other.skip
        endsParent = other.endsParent
        endsWithParent = other.endsWithParent
        onBegin = other.onBegin
        onEnd = other.onEnd
        internalBeforeBegin = other.internalBeforeBegin
        cachedVariants = other.cachedVariants
    }
}
