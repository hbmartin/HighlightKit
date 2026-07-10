import Foundation

extension LanguageCatalog {
    /// Matlab. Port of highlight.js `languages/matlab.js`.
    public static let matlab = LanguageDescriptor(name: "matlab") {
        let transposeRe = #"('|\.')+"#
        let transpose = Mode(
            contains: [Mode(begin: .re(transposeRe))],
            relevance: 0
        )

        return LanguageDefinition(
            name: "matlab",
            root: Mode(
                keywords: [
                    "keyword": Keywords.Group(stringLiteral:
                        "arguments break case catch classdef continue else elseif end enumeration events for function "
                        + "global if methods otherwise parfor persistent properties return spmd switch try while"
                    ),
                    "built_in": Keywords.Group(stringLiteral:
                        "sin sind sinh asin asind asinh cos cosd cosh acos acosd acosh tan tand tanh atan "
                        + "atand atan2 atanh sec secd sech asec asecd asech csc cscd csch acsc acscd acsch cot "
                        + "cotd coth acot acotd acoth hypot exp expm1 log log1p log10 log2 pow2 realpow reallog "
                        + "realsqrt sqrt nthroot nextpow2 abs angle complex conj imag real unwrap isreal "
                        + "cplxpair fix floor ceil round mod rem sign airy besselj bessely besselh besseli "
                        + "besselk beta betainc betaln ellipj ellipke erf erfc erfcx erfinv expint gamma "
                        + "gammainc gammaln psi legendre cross dot factor isprime primes gcd lcm rat rats perms "
                        + "nchoosek factorial cart2sph cart2pol pol2cart sph2cart hsv2rgb rgb2hsv zeros ones "
                        + "eye repmat rand randn linspace logspace freqspace meshgrid accumarray size length "
                        + "ndims numel disp isempty isequal isequalwithequalnans cat reshape diag blkdiag tril "
                        + "triu fliplr flipud flipdim rot90 find sub2ind ind2sub bsxfun ndgrid permute ipermute "
                        + "shiftdim circshift squeeze isscalar isvector ans eps realmax realmin pi i|0 inf nan "
                        + "isnan isinf isfinite j|0 why compan gallery hadamard hankel hilb invhilb magic pascal "
                        + "rosser toeplitz vander wilkinson max min nanmax nanmin mean nanmean type table "
                        + "readtable writetable sortrows sort figure plot plot3 scatter scatter3 cellfun "
                        + "legend intersect ismember procrustes hold num2cell "
                    ),
                ],
                illegal: [#"(//|"|#|/\*|\s+/\w+)"#],
                contains: [
                    Mode(
                        scope: "function",
                        beginKeywords: "function",
                        end: "$",
                        contains: [
                            CommonModes.underscoreTitleMode,
                            Mode(
                                scope: "params",
                                variants: [
                                    Mode(begin: #"\("#, end: #"\)"#),
                                    Mode(begin: #"\["#, end: #"\]"#),
                                ]
                            ),
                        ]
                    ),
                    Mode(
                        scope: "built_in",
                        begin: "true|false",
                        starts: transpose,
                        relevance: 0
                    ),
                    Mode(
                        begin: .re("[a-zA-Z][a-zA-Z_0-9]*" + transposeRe),
                        relevance: 0
                    ),
                    Mode(
                        scope: "number",
                        begin: .re(CommonModes.cNumberRe),
                        starts: transpose,
                        relevance: 0
                    ),
                    Mode(
                        scope: "string",
                        begin: "'",
                        end: "'",
                        contains: [Mode(begin: "''")]
                    ),
                    Mode(
                        begin: #"\]|\}|\)"#,
                        starts: transpose,
                        relevance: 0
                    ),
                    Mode(
                        scope: "string",
                        begin: "\"",
                        end: "\"",
                        contains: [Mode(begin: "\"\"")],
                        starts: transpose
                    ),
                    CommonModes.comment(#"^\s*%\{\s*$"#, #"^\s*%\}\s*$"#),
                    CommonModes.comment("%", "$"),
                ]
            )
        )
    }
}
