import Foundation

/// Fragments shared between the JavaScript/TypeScript grammars (and JSON).
/// Port of highlight.js `languages/lib/ecmascript.js`.
enum Ecmascript {
    static let identRe = "[A-Za-z$_][0-9A-Za-z$_]*"

    /// 0x…, decimal, float, NaN, Infinity
    static let extendedNumberRe =
        #"([-+]?)(\b0[xX][a-fA-F0-9]+|(\b\d+(\.\d*)?|\.\d+)([eE][-+]?\d+)?)|NaN|[-+]?Infinity"#

    static var extendedNumberMode: Mode {
        Mode(scope: "number", match: .re(extendedNumberRe), relevance: 0)
    }

    static let keywords: [String] = ["as", "in", "of", "if", "for", "while", "finally", "var", "new", "function", "do", "return", "void", "else", "break", "catch", "instanceof", "with", "throw", "case", "default", "try", "switch", "continue", "typeof", "delete", "let", "yield", "const", "class", "debugger", "async", "await", "static", "import", "from", "export", "extends", "using"]
    static let literals: [String] = ["true", "false", "null", "undefined", "NaN", "Infinity"]
    static let types: [String] = ["Object", "Function", "Boolean", "Symbol", "Math", "Date", "Number", "BigInt", "String", "RegExp", "Array", "Float32Array", "Float64Array", "Int8Array", "Uint8Array", "Uint8ClampedArray", "Int16Array", "Int32Array", "Uint16Array", "Uint32Array", "BigInt64Array", "BigUint64Array", "Set", "Map", "WeakSet", "WeakMap", "ArrayBuffer", "SharedArrayBuffer", "Atomics", "DataView", "JSON", "Promise", "Generator", "GeneratorFunction", "AsyncFunction", "Reflect", "Proxy", "Intl", "WebAssembly"]
    static let errorTypes: [String] = ["Error", "EvalError", "InternalError", "RangeError", "ReferenceError", "SyntaxError", "TypeError", "URIError"]
    static let builtInGlobals: [String] = ["setInterval", "setTimeout", "clearInterval", "clearTimeout", "require", "exports", "eval", "isFinite", "isNaN", "parseFloat", "parseInt", "decodeURI", "decodeURIComponent", "encodeURI", "encodeURIComponent", "escape", "unescape"]
    static let builtInVariables: [String] = ["arguments", "this", "super", "console", "window", "document", "localStorage", "sessionStorage", "module", "global"]
    static let builtIns: [String] = builtInGlobals + types + errorTypes

    /// The value-container lead-in — an operator or `case`/`return`/
    /// `throw` announcing that what follows is a value position (where
    /// `/` starts a regex literal, not division). Named so the engine
    /// can pair it with the operator-table prefilter.
    static let valueContainerLeadIn: String =
        "(" + CommonModes.reStartersRe + #"|\b(case|return|throw)\b)\s*"#

    /// The `functionCall` rule — an identifier that isn't a special
    /// global, followed (through `\s*`) by `(`. Named so the engine can
    /// pair it with the word-before-paren prefilter.
    static let functionCallPattern: String =
        #"\b(?!"#
        + (builtInGlobals + ["super", "import"])
            .map { "\($0)\\s*\\(" }
            .joined(separator: "|")
        + ")"
        + identRe
        + #"(?=\s*\()"#
}
