import Foundation

/// Swift keyword tables. Port of highlight.js `languages/lib/kws_swift.js`.
/// Generated mechanically from the source — do not edit by hand
/// (see `scratchpad/hljs-ref/gen-kws-swift.mjs`).
enum KwsSwift {
    /// Keywords that require a leading dot (pre-wrapped with \b/\B).
    static let dotKeywords: [String] = [
        #"\bProtocol\b"#,
        #"\bType\b"#,
    ]

    /// Keywords that may have a leading dot (pre-wrapped with \b/\B).
    static let optionalDotKeywords: [String] = [
        #"\binit\b"#,
        #"\bself\b"#,
    ]

    /// Should register as keyword, not type.
    static let keywordTypes: [String] = [
        "Any",
        "Self",
    ]

    /// All keyword pattern sources (plain words and regex sources), in
    /// source order — the JS `keywords` array fed through `source()`.
    static let keywords: [String] = [
        #"actor"#,
        #"any"#,
        #"associatedtype"#,
        #"async"#,
        #"await"#,
        #"as\?"#,
        #"as!"#,
        #"as"#,
        #"borrowing"#,
        #"break"#,
        #"case"#,
        #"catch"#,
        #"class"#,
        #"consume"#,
        #"consuming"#,
        #"continue"#,
        #"convenience"#,
        #"copy"#,
        #"default"#,
        #"defer"#,
        #"deinit"#,
        #"didSet"#,
        #"distributed"#,
        #"do"#,
        #"dynamic"#,
        #"each"#,
        #"else"#,
        #"enum"#,
        #"extension"#,
        #"fallthrough"#,
        #"fileprivate\(set\)"#,
        #"fileprivate"#,
        #"final"#,
        #"for"#,
        #"func"#,
        #"get"#,
        #"guard"#,
        #"if"#,
        #"import"#,
        #"indirect"#,
        #"infix"#,
        #"init\?"#,
        #"init!"#,
        #"inout"#,
        #"internal\(set\)"#,
        #"internal"#,
        #"in"#,
        #"is"#,
        #"isolated"#,
        #"nonisolated"#,
        #"lazy"#,
        #"let"#,
        #"macro"#,
        #"mutating"#,
        #"nonmutating"#,
        #"open\(set\)"#,
        #"open"#,
        #"operator"#,
        #"optional"#,
        #"override"#,
        #"package"#,
        #"postfix"#,
        #"precedencegroup"#,
        #"prefix"#,
        #"private\(set\)"#,
        #"private"#,
        #"protocol"#,
        #"public\(set\)"#,
        #"public"#,
        #"repeat"#,
        #"required"#,
        #"rethrows"#,
        #"return"#,
        #"set"#,
        #"some"#,
        #"static"#,
        #"struct"#,
        #"subscript"#,
        #"super"#,
        #"switch"#,
        #"throws"#,
        #"throw"#,
        #"try\?"#,
        #"try!"#,
        #"try"#,
        #"typealias"#,
        #"unowned\(safe\)"#,
        #"unowned\(unsafe\)"#,
        #"unowned"#,
        #"var"#,
        #"weak"#,
        #"where"#,
        #"while"#,
        #"willSet"#,
    ]

    /// The plain-string subset of `keywords`.
    static let plainKeywords: [String] = [
        "actor",
        "any",
        "associatedtype",
        "async",
        "await",
        "as",
        "borrowing",
        "break",
        "case",
        "catch",
        "class",
        "consume",
        "consuming",
        "continue",
        "convenience",
        "copy",
        "default",
        "defer",
        "deinit",
        "didSet",
        "distributed",
        "do",
        "dynamic",
        "each",
        "else",
        "enum",
        "extension",
        "fallthrough",
        "fileprivate",
        "final",
        "for",
        "func",
        "get",
        "guard",
        "if",
        "import",
        "indirect",
        "infix",
        "inout",
        "internal",
        "in",
        "is",
        "isolated",
        "nonisolated",
        "lazy",
        "let",
        "macro",
        "mutating",
        "nonmutating",
        "open",
        "operator",
        "optional",
        "override",
        "package",
        "postfix",
        "precedencegroup",
        "prefix",
        "private",
        "protocol",
        "public",
        "repeat",
        "required",
        "rethrows",
        "return",
        "set",
        "some",
        "static",
        "struct",
        "subscript",
        "super",
        "switch",
        "throws",
        "throw",
        "try",
        "typealias",
        "unowned",
        "var",
        "weak",
        "where",
        "while",
        "willSet",
    ]

    /// Sources of the regex entries of `keywords`, in source order.
    static let regexKeywordSources: [String] = [
        #"as\?"#,
        #"as!"#,
        #"fileprivate\(set\)"#,
        #"init\?"#,
        #"init!"#,
        #"internal\(set\)"#,
        #"open\(set\)"#,
        #"private\(set\)"#,
        #"public\(set\)"#,
        #"try\?"#,
        #"try!"#,
        #"unowned\(safe\)"#,
        #"unowned\(unsafe\)"#,
    ]

    /// Literals.
    static let literals: [String] = [
        "false",
        "nil",
        "true",
    ]

    /// Keywords used in precedence groups.
    static let precedencegroupKeywords: [String] = [
        "assignment",
        "associativity",
        "higherThan",
        "left",
        "lowerThan",
        "none",
        "right",
    ]

    /// Keywords that start with a number sign (#).
    static let numberSignKeywords: [String] = [
        "#colorLiteral",
        "#column",
        "#dsohandle",
        "#else",
        "#elseif",
        "#endif",
        "#error",
        "#file",
        "#fileID",
        "#fileLiteral",
        "#filePath",
        "#function",
        "#if",
        "#imageLiteral",
        "#keyPath",
        "#line",
        "#selector",
        "#sourceLocation",
        "#warning",
    ]

    /// Global functions in the Standard Library.
    static let builtIns: [String] = [
        "abs",
        "all",
        "any",
        "assert",
        "assertionFailure",
        "debugPrint",
        "dump",
        "fatalError",
        "getVaList",
        "isKnownUniquelyReferenced",
        "max",
        "min",
        "numericCast",
        "pointwiseMax",
        "pointwiseMin",
        "precondition",
        "preconditionFailure",
        "print",
        "readLine",
        "repeatElement",
        "sequence",
        "stride",
        "swap",
        "swift_unboxFromSwiftValueWithType",
        "transcode",
        "type",
        "unsafeBitCast",
        "unsafeDowncast",
        "withExtendedLifetime",
        "withUnsafeMutablePointer",
        "withUnsafePointer",
        "withVaList",
        "withoutActuallyEscaping",
        "zip",
    ]

    /// Valid first characters for operators.
    static let operatorHead = #"(?:[/=\-+!*%<>&|^~?]|[\u00A1-\u00A7]|[\u00A9\u00AB]|[\u00AC\u00AE]|[\u00B0\u00B1]|[\u00B6\u00BB\u00BF\u00D7\u00F7]|[\u2016-\u2017]|[\u2020-\u2027]|[\u2030-\u203E]|[\u2041-\u2053]|[\u2055-\u205E]|[\u2190-\u23FF]|[\u2500-\u2775]|[\u2794-\u2BFF]|[\u2E00-\u2E7F]|[\u3001-\u3003]|[\u3008-\u3020]|[\u3030])"#

    /// Valid characters for operators.
    static let operatorCharacter = #"(?:(?:[/=\-+!*%<>&|^~?]|[\u00A1-\u00A7]|[\u00A9\u00AB]|[\u00AC\u00AE]|[\u00B0\u00B1]|[\u00B6\u00BB\u00BF\u00D7\u00F7]|[\u2016-\u2017]|[\u2020-\u2027]|[\u2030-\u203E]|[\u2041-\u2053]|[\u2055-\u205E]|[\u2190-\u23FF]|[\u2500-\u2775]|[\u2794-\u2BFF]|[\u2E00-\u2E7F]|[\u3001-\u3003]|[\u3008-\u3020]|[\u3030])|[\u0300-\u036F]|[\u1DC0-\u1DFF]|[\u20D0-\u20FF]|[\uFE00-\uFE0F]|[\uFE20-\uFE2F])"#

    /// Valid operator.
    static let `operator` = #"(?:[/=\-+!*%<>&|^~?]|[\u00A1-\u00A7]|[\u00A9\u00AB]|[\u00AC\u00AE]|[\u00B0\u00B1]|[\u00B6\u00BB\u00BF\u00D7\u00F7]|[\u2016-\u2017]|[\u2020-\u2027]|[\u2030-\u203E]|[\u2041-\u2053]|[\u2055-\u205E]|[\u2190-\u23FF]|[\u2500-\u2775]|[\u2794-\u2BFF]|[\u2E00-\u2E7F]|[\u3001-\u3003]|[\u3008-\u3020]|[\u3030])(?:(?:[/=\-+!*%<>&|^~?]|[\u00A1-\u00A7]|[\u00A9\u00AB]|[\u00AC\u00AE]|[\u00B0\u00B1]|[\u00B6\u00BB\u00BF\u00D7\u00F7]|[\u2016-\u2017]|[\u2020-\u2027]|[\u2030-\u203E]|[\u2041-\u2053]|[\u2055-\u205E]|[\u2190-\u23FF]|[\u2500-\u2775]|[\u2794-\u2BFF]|[\u2E00-\u2E7F]|[\u3001-\u3003]|[\u3008-\u3020]|[\u3030])|[\u0300-\u036F]|[\u1DC0-\u1DFF]|[\u20D0-\u20FF]|[\uFE00-\uFE0F]|[\uFE20-\uFE2F])*"#

    /// Valid first characters for identifiers.
    static let identifierHead = #"(?:[a-zA-Z_]|[\u00A8\u00AA\u00AD\u00AF\u00B2-\u00B5\u00B7-\u00BA]|[\u00BC-\u00BE\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u00FF]|[\u0100-\u02FF\u0370-\u167F\u1681-\u180D\u180F-\u1DBF]|[\u1E00-\u1FFF]|[\u200B-\u200D\u202A-\u202E\u203F-\u2040\u2054\u2060-\u206F]|[\u2070-\u20CF\u2100-\u218F\u2460-\u24FF\u2776-\u2793]|[\u2C00-\u2DFF\u2E80-\u2FFF]|[\u3004-\u3007\u3021-\u302F\u3031-\u303F\u3040-\uD7FF]|[\uF900-\uFD3D\uFD40-\uFDCF\uFDF0-\uFE1F\uFE30-\uFE44]|[\uFE47-\uFEFE\uFF00-\uFFFD])"#

    /// Valid characters for identifiers.
    static let identifierCharacter = #"(?:(?:[a-zA-Z_]|[\u00A8\u00AA\u00AD\u00AF\u00B2-\u00B5\u00B7-\u00BA]|[\u00BC-\u00BE\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u00FF]|[\u0100-\u02FF\u0370-\u167F\u1681-\u180D\u180F-\u1DBF]|[\u1E00-\u1FFF]|[\u200B-\u200D\u202A-\u202E\u203F-\u2040\u2054\u2060-\u206F]|[\u2070-\u20CF\u2100-\u218F\u2460-\u24FF\u2776-\u2793]|[\u2C00-\u2DFF\u2E80-\u2FFF]|[\u3004-\u3007\u3021-\u302F\u3031-\u303F\u3040-\uD7FF]|[\uF900-\uFD3D\uFD40-\uFDCF\uFDF0-\uFE1F\uFE30-\uFE44]|[\uFE47-\uFEFE\uFF00-\uFFFD])|\d|[\u0300-\u036F\u1DC0-\u1DFF\u20D0-\u20FF\uFE20-\uFE2F])"#

    /// Valid identifier.
    static let identifier = #"(?:[a-zA-Z_]|[\u00A8\u00AA\u00AD\u00AF\u00B2-\u00B5\u00B7-\u00BA]|[\u00BC-\u00BE\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u00FF]|[\u0100-\u02FF\u0370-\u167F\u1681-\u180D\u180F-\u1DBF]|[\u1E00-\u1FFF]|[\u200B-\u200D\u202A-\u202E\u203F-\u2040\u2054\u2060-\u206F]|[\u2070-\u20CF\u2100-\u218F\u2460-\u24FF\u2776-\u2793]|[\u2C00-\u2DFF\u2E80-\u2FFF]|[\u3004-\u3007\u3021-\u302F\u3031-\u303F\u3040-\uD7FF]|[\uF900-\uFD3D\uFD40-\uFDCF\uFDF0-\uFE1F\uFE30-\uFE44]|[\uFE47-\uFEFE\uFF00-\uFFFD])(?:(?:[a-zA-Z_]|[\u00A8\u00AA\u00AD\u00AF\u00B2-\u00B5\u00B7-\u00BA]|[\u00BC-\u00BE\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u00FF]|[\u0100-\u02FF\u0370-\u167F\u1681-\u180D\u180F-\u1DBF]|[\u1E00-\u1FFF]|[\u200B-\u200D\u202A-\u202E\u203F-\u2040\u2054\u2060-\u206F]|[\u2070-\u20CF\u2100-\u218F\u2460-\u24FF\u2776-\u2793]|[\u2C00-\u2DFF\u2E80-\u2FFF]|[\u3004-\u3007\u3021-\u302F\u3031-\u303F\u3040-\uD7FF]|[\uF900-\uFD3D\uFD40-\uFDCF\uFDF0-\uFE1F\uFE30-\uFE44]|[\uFE47-\uFEFE\uFF00-\uFFFD])|\d|[\u0300-\u036F\u1DC0-\u1DFF\u20D0-\u20FF\uFE20-\uFE2F])*"#

    /// Valid type identifier.
    static let typeIdentifier = #"[A-Z](?:(?:[a-zA-Z_]|[\u00A8\u00AA\u00AD\u00AF\u00B2-\u00B5\u00B7-\u00BA]|[\u00BC-\u00BE\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u00FF]|[\u0100-\u02FF\u0370-\u167F\u1681-\u180D\u180F-\u1DBF]|[\u1E00-\u1FFF]|[\u200B-\u200D\u202A-\u202E\u203F-\u2040\u2054\u2060-\u206F]|[\u2070-\u20CF\u2100-\u218F\u2460-\u24FF\u2776-\u2793]|[\u2C00-\u2DFF\u2E80-\u2FFF]|[\u3004-\u3007\u3021-\u302F\u3031-\u303F\u3040-\uD7FF]|[\uF900-\uFD3D\uFD40-\uFDCF\uFDF0-\uFE1F\uFE30-\uFE44]|[\uFE47-\uFEFE\uFF00-\uFFFD])|\d|[\u0300-\u036F\u1DC0-\u1DFF\u20D0-\u20FF\uFE20-\uFE2F])*"#

    /// `identifier` followed by a colon — a tuple element or argument
    /// label. Named so the engine can pair it with a prefilter.
    static let identifierWithColon = identifier + #"\s*:"#

    /// The `functionParameterName` lead-in: an external (and optionally
    /// internal) parameter name, as a zero-width lookahead.
    static let functionParameterNameLookahead = RegexSource.either(
        RegexSource.lookahead(identifierWithColon),
        RegexSource.lookahead(identifier + #"\s+"# + identifierWithColon)
    )

    /// Patterns whose every match — or zero-width lookahead success —
    /// begins at a unit satisfying `identifierHead` (an ASCII letter,
    /// `_`, or a non-ASCII unit). The engine keys its
    /// `identifierHeadStart` prefilter on exact membership here, so the
    /// grammar itself is the single source of truth (see
    /// `MultiMatcher.analyzePrefilter`).
    static let identifierHeadAnchored: Set<String> = [
        identifier,
        identifierWithColon,
        functionParameterNameLookahead,
    ]

    /// The built-in call rule — a stdlib function name followed by `(`.
    /// Named so the engine can pair it with the word-before-paren
    /// prefilter.
    static let builtInCallPattern: String =
        #"\b"# + RegexSource.either(builtIns) + #"(?=\()"#

    /// The first UTF-16 unit of every `builtIns` entry (all plain ASCII
    /// identifiers).
    static let builtInFirstUnits: Set<UInt16> = Set(builtIns.map { $0.utf16.first! })

    /// The protocol-composition separator `\s+&\s+(?=TypeIdentifier)`.
    /// Named so the engine can pair it with the `&`-anchored prefilter.
    static let protocolCompositionPattern: String =
        #"\s+&\s+"# + RegexSource.lookahead(typeIdentifier)

    /// Port of kws_swift.js `keywordWrapper`: `\b<kw>\b` when the
    /// keyword ends in a word character, `\b<kw>\B` otherwise.
    static func keywordWrapper(_ keyword: String) -> String {
        let endsWithWordChar = keyword.range(of: #"\w$"#, options: .regularExpression) != nil
        return #"\b"# + keyword + (endsWithWordChar ? #"\b"# : #"\B"#)
    }

    /// The regex-keyword rule: punctuated keywords (`as?`, `try!`,
    /// `open(set)`, …) plus `Any`/`Self` and the optional-dot keywords,
    /// as one alternation. Named so the engine can pair it with a
    /// first-letter prefilter.
    static let regexKeywordPattern: String = RegexSource.either(
        (regexKeywordSources + keywordTypes).map(keywordWrapper) + optionalDotKeywords
    )

    /// Built-in attributes (highlighted as keywords); pattern sources.
    static let keywordAttributes: [String] = [
        #"attached"#,
        #"autoclosure"#,
        #"convention\((?:swift|block|c)\)"#,
        #"discardableResult"#,
        #"dynamicCallable"#,
        #"dynamicMemberLookup"#,
        #"escaping"#,
        #"freestanding"#,
        #"frozen"#,
        #"GKInspectable"#,
        #"IBAction"#,
        #"IBDesignable"#,
        #"IBInspectable"#,
        #"IBOutlet"#,
        #"IBSegueAction"#,
        #"inlinable"#,
        #"main"#,
        #"nonobjc"#,
        #"NSApplicationMain"#,
        #"NSCopying"#,
        #"NSManaged"#,
        #"objc\((?:[a-zA-Z_]|[\u00A8\u00AA\u00AD\u00AF\u00B2-\u00B5\u00B7-\u00BA]|[\u00BC-\u00BE\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u00FF]|[\u0100-\u02FF\u0370-\u167F\u1681-\u180D\u180F-\u1DBF]|[\u1E00-\u1FFF]|[\u200B-\u200D\u202A-\u202E\u203F-\u2040\u2054\u2060-\u206F]|[\u2070-\u20CF\u2100-\u218F\u2460-\u24FF\u2776-\u2793]|[\u2C00-\u2DFF\u2E80-\u2FFF]|[\u3004-\u3007\u3021-\u302F\u3031-\u303F\u3040-\uD7FF]|[\uF900-\uFD3D\uFD40-\uFDCF\uFDF0-\uFE1F\uFE30-\uFE44]|[\uFE47-\uFEFE\uFF00-\uFFFD])(?:(?:[a-zA-Z_]|[\u00A8\u00AA\u00AD\u00AF\u00B2-\u00B5\u00B7-\u00BA]|[\u00BC-\u00BE\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u00FF]|[\u0100-\u02FF\u0370-\u167F\u1681-\u180D\u180F-\u1DBF]|[\u1E00-\u1FFF]|[\u200B-\u200D\u202A-\u202E\u203F-\u2040\u2054\u2060-\u206F]|[\u2070-\u20CF\u2100-\u218F\u2460-\u24FF\u2776-\u2793]|[\u2C00-\u2DFF\u2E80-\u2FFF]|[\u3004-\u3007\u3021-\u302F\u3031-\u303F\u3040-\uD7FF]|[\uF900-\uFD3D\uFD40-\uFDCF\uFDF0-\uFE1F\uFE30-\uFE44]|[\uFE47-\uFEFE\uFF00-\uFFFD])|\d|[\u0300-\u036F\u1DC0-\u1DFF\u20D0-\u20FF\uFE20-\uFE2F])*\)"#,
        #"objc"#,
        #"objcMembers"#,
        #"propertyWrapper"#,
        #"requires_stored_property_inits"#,
        #"resultBuilder"#,
        #"Sendable"#,
        #"testable"#,
        #"UIApplicationMain"#,
        #"unchecked"#,
        #"unknown"#,
        #"usableFromInline"#,
        #"warn_unqualified_access"#,
    ]

    /// Contextual keywords used in @available and #(un)available.
    static let availabilityKeywords: [String] = [
        "iOS",
        "iOSApplicationExtension",
        "macOS",
        "macOSApplicationExtension",
        "macCatalyst",
        "macCatalystApplicationExtension",
        "watchOS",
        "watchOSApplicationExtension",
        "tvOS",
        "tvOSApplicationExtension",
        "swift",
    ]
}
