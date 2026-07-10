import Foundation

extension LanguageCatalog {
    /// OCaml. Port of highlight.js `languages/ocaml.js`.
    public static let ocaml = LanguageDescriptor(name: "ocaml", aliases: ["ml"]) {
        /* missing support for heredoc-like string (OCaml 4.0.2+) */
        LanguageDefinition(
            name: "ocaml",
            aliases: ["ml"],
            root: Mode(
                keywords: Keywords(
                    pattern: #"[a-z_]\w*!?"#,
                    [
                        "keyword":
                            "and as assert asr begin class constraint do done downto else end exception external for fun function functor if in include inherit! inherit initializer land lazy let lor lsl lsr lxor match method!|10 method mod module mutable new object of open! open or private rec sig struct then to try type val! val virtual when while with parser value",
                        "built_in":
                            /* built-in types + (some) types in Pervasives */
                            "array bool bytes char exn|5 float int int32 int64 list lazy_t|5 nativeint|5 string unit in_channel out_channel ref",
                        "literal": "true false",
                    ]
                ),
                illegal: [#"\/\/|>>"#],
                contains: [
                    Mode(
                        scope: "literal",
                        begin: #"\[(\|\|)?\]|\(\)"#,
                        relevance: 0
                    ),
                    CommonModes.comment(#"\(\*"#, #"\*\)"#) { $0.contains = [Mode.selfReference] },
                    Mode( /* type variable */
                        scope: "symbol",
                        begin: #"'[A-Za-z_](?!')[\w']*"#
                        /* the grammar is ambiguous on how 'a'b should be interpreted but not the compiler */
                    ),
                    Mode( /* polymorphic variant */
                        scope: "type",
                        begin: #"`[A-Z][\w']*"#
                    ),
                    Mode( /* module or constructor */
                        scope: "type",
                        begin: #"\b[A-Z][\w']*"#,
                        relevance: 0
                    ),
                    Mode( /* don't color identifiers, but safely catch all identifiers with ' */
                        begin: #"[a-z_]\w*'[\w']*"#,
                        relevance: 0
                    ),
                    { let m = CommonModes.aposStringMode; m.scope = "string"; m.relevance = 0; return m }(),
                    { let m = CommonModes.quoteStringMode; m.illegal = nil; return m }(),
                    Mode(
                        scope: "number",
                        begin: #"\b(0[xX][a-fA-F0-9_]+[Lln]?|0[oO][0-7_]+[Lln]?|0[bB][01_]+[Lln]?|[0-9][0-9_]*([Lln]|(\.[0-9_]*)?([eE][-+]?[0-9_]+)?)?)"#,
                        relevance: 0
                    ),
                    Mode(begin: "->"), // relevance booster
                ]
            )
        )
    }
}
