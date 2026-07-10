import Foundation

extension LanguageCatalog {
    /// Clojure. Port of highlight.js `languages/clojure.js`.
    public static let clojure = LanguageDescriptor(name: "clojure", aliases: ["clj", "edn"]) {
        let symbolStart = #"a-zA-Z_\-!.?+*=<>&'"#
        let symbolRe = "[#]?[" + symbolStart + "][" + symbolStart + "0-9/;:$#]*"
        let globals = "def defonce defprotocol defstruct defmulti defmethod defn- defn defmacro deftype defrecord"
        let keywords = Keywords(
            pattern: symbolRe,
            [
                "built_in": Keywords.Group(stringLiteral:
                    // Clojure keywords
                    globals + " "
                    + "cond apply if-not if-let if not not= =|0 <|0 >|0 <=|0 >=|0 ==|0 +|0 /|0 *|0 -|0 rem "
                    + "quot neg? pos? delay? symbol? keyword? true? false? integer? empty? coll? list? "
                    + "set? ifn? fn? associative? sequential? sorted? counted? reversible? number? decimal? "
                    + "class? distinct? isa? float? rational? reduced? ratio? odd? even? char? seq? vector? "
                    + "string? map? nil? contains? zero? instance? not-every? not-any? libspec? -> ->> .. . "
                    + "inc compare do dotimes mapcat take remove take-while drop letfn drop-last take-last "
                    + "drop-while while intern condp case reduced cycle split-at split-with repeat replicate "
                    + "iterate range merge zipmap declare line-seq sort comparator sort-by dorun doall nthnext "
                    + "nthrest partition eval doseq await await-for let agent atom send send-off release-pending-sends "
                    + "add-watch mapv filterv remove-watch agent-error restart-agent set-error-handler error-handler "
                    + "set-error-mode! error-mode shutdown-agents quote var fn loop recur throw try monitor-enter "
                    + "monitor-exit macroexpand macroexpand-1 for dosync and or "
                    + "when when-not when-let comp juxt partial sequence memoize constantly complement identity assert "
                    + "peek pop doto proxy first rest cons cast coll last butlast "
                    + "sigs reify second ffirst fnext nfirst nnext meta with-meta ns in-ns create-ns import "
                    + "refer keys select-keys vals key val rseq name namespace promise into transient persistent! conj! "
                    + "assoc! dissoc! pop! disj! use class type num float double short byte boolean bigint biginteger "
                    + "bigdec print-method print-dup throw-if printf format load compile get-in update-in pr pr-on newline "
                    + "flush read slurp read-line subvec with-open memfn time re-find re-groups rand-int rand mod locking "
                    + "assert-valid-fdecl alias resolve ref deref refset swap! reset! set-validator! compare-and-set! alter-meta! "
                    + "reset-meta! commute get-validator alter ref-set ref-history-count ref-min-history ref-max-history ensure sync io! "
                    + "new next conj set! to-array future future-call into-array aset gen-class reduce map filter find empty "
                    + "hash-map hash-set sorted-map sorted-map-by sorted-set sorted-set-by vec vector seq flatten reverse assoc dissoc list "
                    + "disj get union difference intersection extend extend-type extend-protocol int nth delay count concat chunk chunk-buffer "
                    + "chunk-append chunk-first chunk-rest max min dec unchecked-inc-int unchecked-inc unchecked-dec-inc unchecked-dec unchecked-negate "
                    + "unchecked-add-int unchecked-add unchecked-subtract-int unchecked-subtract chunk-next chunk-cons chunked-seq? prn vary-meta "
                    + "lazy-seq spread list* str find-keyword keyword symbol gensym force rationalize"
                ),
            ]
        )

        let symbol = Mode(
            begin: .re(symbolRe),
            relevance: 0
        )
        let number = Mode(
            scope: "number",
            variants: [
                Mode(match: #"[-+]?0[xX][0-9a-fA-F]+N?"#), // hexadecimal                 // 0x2a
                Mode(match: #"[-+]?0[0-7]+N?"#), // octal                       // 052
                Mode(match: #"[-+]?[1-9][0-9]?[rR][0-9a-zA-Z]+N?"#), // variable radix from 2 to 36 // 2r101010, 8r52, 36r16
                Mode(match: #"[-+]?[0-9]+\/[0-9]+N?"#), // ratio                       // 1/2
                Mode(match: #"[-+]?[0-9]+((\.[0-9]*([eE][+-]?[0-9]+)?M?)|([eE][+-]?[0-9]+M?|M))"#), // float        // 0.42 4.2E-1M 42E1 42M
                Mode(match: #"[-+]?([1-9][0-9]*|0)N?"#), // int (don't match leading 0) // 42 42N
            ],
            relevance: 0
        )
        let character = Mode(
            scope: "character",
            variants: [
                Mode(match: #"\\o[0-3]?[0-7]{1,2}"#), // Unicode Octal 0 - 377
                Mode(match: #"\\u[0-9a-fA-F]{4}"#), // Unicode Hex 0000 - FFFF
                Mode(match: #"\\(newline|space|tab|formfeed|backspace|return)"#), // special characters
                // any non-whitespace char
                Mode(match: #"\\\S"#, relevance: 0),
            ]
        )
        let regex = Mode(
            scope: "regex",
            begin: #"#""#,
            end: "\"",
            contains: [CommonModes.backslashEscape]
        )
        let string = CommonModes.quoteStringMode.copied { $0.illegal = nil }
        let comma = Mode(
            scope: "punctuation",
            match: ",",
            relevance: 0
        )
        let comment = CommonModes.comment(";", "$") { $0.relevance = 0 }
        let literal = Mode(
            scope: "literal",
            begin: #"\b(true|false|nil)\b"#
        )
        let collection = Mode(
            begin: .re(#"\[|(#::?"# + symbolRe + #")?\{"#),
            end: #"[\]\}]"#,
            relevance: 0
        )
        let key = Mode(
            scope: "symbol",
            begin: .re("[:]{1,2}" + symbolRe)
        )
        let list = Mode(
            begin: #"\("#,
            end: #"\)"#
        )
        let body = Mode(
            relevance: 0,
            endsWithParent: true
        )
        let name = Mode(
            scope: "name",
            begin: .re(symbolRe),
            keywords: keywords,
            starts: body,
            relevance: 0
        )
        let defaultContains: [Mode] = [
            comma,
            list,
            character,
            regex,
            string,
            comment,
            key,
            collection,
            number,
            literal,
            symbol,
        ]

        let global = Mode(
            beginKeywords: globals,
            end: #"(\[|#|\d|"|:|\{|\)|\(|$)"#,
            keywords: Keywords(
                pattern: symbolRe,
                ["keyword": Keywords.Group(stringLiteral: globals)]
            ),
            contains: [
                Mode(
                    scope: "title",
                    begin: .re(symbolRe),
                    relevance: 0,
                    excludeEnd: true,
                    // we can only have a single title
                    endsParent: true
                ),
            ] + defaultContains
        )

        list.contains = [
            global,
            name,
            body,
        ]
        body.contains = defaultContains
        collection.contains = defaultContains

        return LanguageDefinition(
            name: "clojure",
            aliases: ["clj", "edn"],
            root: Mode(
                illegal: [#"\S"#],
                contains: [
                    comma,
                    list,
                    character,
                    regex,
                    string,
                    comment,
                    key,
                    collection,
                    number,
                    literal,
                ]
            )
        )
    }
}
