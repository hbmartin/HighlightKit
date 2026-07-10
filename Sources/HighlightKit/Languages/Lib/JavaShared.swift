import Foundation

/// Fragments shared between the Java and Kotlin grammars.
/// Port of highlight.js `languages/lib/java.js`.
enum JavaShared {
    // https://docs.oracle.com/javase/specs/jls/se15/html/jls-3.html#jls-3.10
    private static let decimalDigits = "[0-9](_*[0-9])*"
    private static let frac = #"\.("# + decimalDigits + ")"
    private static let hexDigits = "[0-9a-fA-F](_*[0-9a-fA-F])*"

    static var numeric: Mode {
        Mode(
            scope: "number",
            variants: [
                // DecimalFloatingPointLiteral
                // including ExponentPart
                Mode(begin: .re("(\\b(\(decimalDigits))((\(frac))|\\.)?|(\(frac)))"
                    + "[eE][+-]?(\(decimalDigits))[fFdD]?\\b")),
                // excluding ExponentPart
                Mode(begin: .re("\\b(\(decimalDigits))((\(frac))[fFdD]?\\b|\\.([fFdD]\\b)?)")),
                Mode(begin: .re("(\(frac))[fFdD]?\\b")),
                Mode(begin: .re("\\b(\(decimalDigits))[fFdD]\\b")),

                // HexadecimalFloatingPointLiteral
                Mode(begin: .re("\\b0[xX]((\(hexDigits))\\.?|(\(hexDigits))?\\.(\(hexDigits)))"
                    + "[pP][+-]?(\(decimalDigits))[fFdD]?\\b")),

                // DecimalIntegerLiteral
                Mode(begin: "\\b(0|[1-9](_*[0-9])*)[lL]?\\b"),

                // HexIntegerLiteral
                Mode(begin: .re("\\b0[xX](\(hexDigits))[lL]?\\b")),

                // OctalIntegerLiteral
                Mode(begin: "\\b0(_*[0-7])*[lL]?\\b"),

                // BinaryIntegerLiteral
                Mode(begin: "\\b0[bB][01](_*[01])*[lL]?\\b"),
            ],
            relevance: 0
        )
    }
}
