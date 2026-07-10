import Foundation

extension LanguageCatalog {
    /// Lisp. Port of highlight.js `languages/lisp.js`.
    public static let lisp = LanguageDescriptor(name: "lisp") {
        let lispIdentRe = #"[a-zA-Z_\-+\*\/<=>&#][a-zA-Z0-9_\-+*\/<=>&#!]*"#
        // JS `[^]` (any char) is invalid in ICU — use `[\s\S]`.
        let mecRe = #"\|[\s\S]*?\|"#
        let lispSimpleNumberRe = #"(-|\+)?\d+(\.\d+|\/\d+)?((d|e|f|l|s|D|E|F|L|S)(\+|-)?\d+)?"#
        let literal = Mode(
            scope: "literal",
            begin: #"\b(t{1}|nil)\b"#
        )
        let number = Mode(
            scope: "number",
            variants: [
                Mode(begin: .re(lispSimpleNumberRe), relevance: 0),
                Mode(begin: "#(b|B)[0-1]+(/[0-1]+)?"),
                Mode(begin: "#(o|O)[0-7]+(/[0-7]+)?"),
                Mode(begin: "#(x|X)[0-9a-fA-F]+(/[0-9a-fA-F]+)?"),
                Mode(
                    begin: .re(#"#(c|C)\("# + lispSimpleNumberRe + " +" + lispSimpleNumberRe),
                    end: #"\)"#
                ),
            ]
        )
        let string = CommonModes.quoteStringMode.copied { $0.illegal = nil }
        let comment = CommonModes.comment(";", "$") { $0.relevance = 0 }
        let variable = Mode(
            begin: #"\*"#,
            end: #"\*"#
        )
        let keyword = Mode(
            scope: "symbol",
            begin: .re("[:&]" + lispIdentRe)
        )
        let ident = Mode(
            begin: .re(lispIdentRe),
            relevance: 0
        )
        let mec = Mode(begin: .re(mecRe))
        let quotedList = Mode(
            begin: #"\("#,
            end: #"\)"#,
            contains: [
                Mode.selfReference,
                literal,
                string,
                number,
                ident,
            ]
        )
        let quoted = Mode(
            contains: [
                number,
                string,
                variable,
                keyword,
                quotedList,
                ident,
            ],
            variants: [
                Mode(begin: #"['`]\("#, end: #"\)"#),
                Mode(
                    begin: #"\(quote "#,
                    end: #"\)"#,
                    keywords: ["name": "quote"]
                ),
                Mode(begin: .re("'" + mecRe)),
            ]
        )
        let quotedAtom = Mode(variants: [
            Mode(begin: .re("'" + lispIdentRe)),
            Mode(begin: .re("#'" + lispIdentRe + "(::" + lispIdentRe + ")*")),
        ])
        let list = Mode(
            begin: #"\(\s*"#,
            end: #"\)"#
        )
        let body = Mode(
            relevance: 0,
            endsWithParent: true
        )
        list.contains = [
            Mode(
                scope: "name",
                variants: [
                    Mode(begin: .re(lispIdentRe), relevance: 0),
                    Mode(begin: .re(mecRe)),
                ]
            ),
            body,
        ]
        body.contains = [
            quoted,
            quotedAtom,
            list,
            literal,
            number,
            string,
            comment,
            variable,
            keyword,
            mec,
            ident,
        ]

        return LanguageDefinition(
            name: "lisp",
            root: Mode(
                illegal: [#"\S"#],
                contains: [
                    number,
                    CommonModes.shebang(),
                    literal,
                    string,
                    comment,
                    quoted,
                    quotedAtom,
                    list,
                    ident,
                ]
            )
        )
    }
}
