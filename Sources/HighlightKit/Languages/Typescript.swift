import Foundation

extension LanguageCatalog {
    /// TypeScript. Port of highlight.js `languages/typescript.js`.
    ///
    /// The upstream grammar calls `javascript(hljs)` and mutates the
    /// returned mode tree in place (swapping labeled modes, extending
    /// keyword tables and `PARAMS_CONTAINS`). `Mode` is a reference type,
    /// so mutating the tree returned by `JavascriptGrammar.make()` mirrors
    /// the JavaScript object mutation; `Keywords` and `[Mode]` are value
    /// types, so the shared-object updates (`Object.assign(keywords, …)`,
    /// `PARAMS_CONTAINS.push(…)`) are replayed by walking the tree and
    /// patching every mode that held the shared value.
    public static let typescript = LanguageDescriptor(name: "typescript", aliases: ["ts", "tsx", "mts", "cts"]) {
        let exports = JavascriptGrammar.make()
        var tsLanguage = exports.definition

        let identRe = Ecmascript.identRe
        let types = [
            "any",
            "void",
            "number",
            "boolean",
            "string",
            "object",
            "never",
            "symbol",
            "bigint",
            "unknown",
        ]
        let namespace = Mode(
            begin: ["namespace", #"\s+"#, CommonModes.identRe],
            beginScope: [1: "keyword", 3: "title.class"]
        )
        let interfaceMode = Mode(
            beginKeywords: "interface",
            end: #"\{"#,
            keywords: Keywords([
                "keyword": "interface extends",
                "built_in": Keywords.Group(words: types),
            ]),
            contains: [exports.classReference],
            excludeEnd: true
        )
        let useStrict = Mode(
            scope: "meta",
            begin: #"^\s*['"]use strict['"]"#,
            relevance: 10
        )
        let tsSpecificKeywords = [
            "type",
            // "namespace",
            "interface",
            "public",
            "private",
            "protected",
            "implements",
            "declare",
            "abstract",
            "readonly",
            "enum",
            "override",
            "satisfies",
        ]
        // namespace is a TS keyword but it's fine to use it as a variable
        // name too.
        // "void" appears both in the ECMAScript keyword list and in TYPES
        // (built_in). highlight.js compiles keyword groups in insertion
        // order, so the later `built_in` entry wins; `Keywords.groups` is
        // an unordered dictionary, so drop the shadowed keyword entry to
        // reproduce the same compiled table deterministically.
        let keywords = Keywords(
            pattern: identRe,
            [
                "keyword": Keywords.Group(words: (Ecmascript.keywords + tsSpecificKeywords).filter { $0 != "void" }),
                "literal": Keywords.Group(words: Ecmascript.literals),
                "built_in": Keywords.Group(words: Ecmascript.builtIns + types),
                "variable.language": Keywords.Group(words: Ecmascript.builtInVariables),
            ]
        )

        let decorator = Mode(
            scope: "meta",
            begin: .re("@" + identRe)
        )

        // Walks every reachable mode once (contains / variants / starts).
        func walkModes(_ root: Mode, _ visit: (Mode) -> Void) {
            var seen = Set<ObjectIdentifier>()
            func go(_ mode: Mode) {
                if mode === Mode.selfReference { return }
                guard seen.insert(ObjectIdentifier(mode)).inserted else { return }
                visit(mode)
                mode.contains?.forEach(go)
                mode.variants?.forEach(go)
                if let starts = mode.starts { go(starts) }
            }
            go(root)
        }

        func swapMode(_ mode: Mode, label: String, replacement: Mode) {
            guard var contains = mode.contains,
                  let index = contains.firstIndex(where: { $0.label == label })
            else {
                fatalError("can not find mode to replace")
            }
            contains[index] = replacement
            mode.contains = contains
        }

        // this should update anywhere keywords is used since in the
        // upstream source it is the same actual JS object; here the shared
        // keyword table is identified by its `$pattern`.
        walkModes(tsLanguage.root) { mode in
            if mode.keywords?.pattern == identRe {
                mode.keywords = keywords
            }
        }

        // highlight the function params
        let rootContains = tsLanguage.root.contains ?? []
        let attributeHighlight = rootContains.first { mode in
            if case .name("attr")? = mode.scope { return true }
            return false
        }!

        // take default attr rule and extend it to support optionals
        let optionalKeyOrArgument = attributeHighlight.copied { mode in
            mode.match = .re(identRe + RegexSource.lookahead(#"\s*\?:"#))
        }

        // tsLanguage.exports.PARAMS_CONTAINS.push(DECORATOR) and
        // .push([CLASS_REFERENCE, ATTRIBUTE_HIGHLIGHT, OPTIONAL_KEY_OR_ARGUMENT])
        // — the pushed nested array is flattened by the mode compiler, so
        // the effective additions are these four modes, appended to every
        // mode that held the shared PARAMS_CONTAINS array.
        let paramsAdditions: [Mode] = [
            decorator,
            exports.classReference, // class reference for highlighting the params types
            attributeHighlight, // highlight the params key
            optionalKeyOrArgument, // Added for optional property assignment highlighting
        ]
        let paramsContains = exports.paramsContains
        walkModes(tsLanguage.root) { mode in
            guard let contains = mode.contains,
                  contains.count == paramsContains.count,
                  zip(contains, paramsContains).allSatisfy({ $0 === $1 })
            else { return }
            mode.contains = contains + paramsAdditions
        }

        // Add the optional property assignment highlighting for objects or classes
        tsLanguage.root.contains = (tsLanguage.root.contains ?? []) + [
            decorator,
            namespace,
            interfaceMode,
            optionalKeyOrArgument, // Added for optional property assignment highlighting
        ]

        // TS gets a simpler shebang rule than JS
        swapMode(tsLanguage.root, label: "shebang", replacement: CommonModes.shebang())
        // JS use strict rule purposely excludes `asm` which makes no sense
        swapMode(tsLanguage.root, label: "use_strict", replacement: useStrict)

        let functionDeclaration = tsLanguage.root.contains!.first { $0.label == "func.def" }!
        functionDeclaration.relevance = 0 // () => {} is more typical in TypeScript

        tsLanguage.name = "typescript"
        tsLanguage.aliases = ["ts", "tsx", "mts", "cts"]
        return tsLanguage
    }
}
