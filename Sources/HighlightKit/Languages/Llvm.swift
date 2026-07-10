import Foundation

extension LanguageCatalog {
    /// LLVM IR. Port of highlight.js `languages/llvm.js`.
    public static let llvm = LanguageDescriptor(name: "llvm") {
        let identRe = #"([-a-zA-Z$._][\w$.-]*)"#
        let type = Mode(
            scope: "type",
            begin: #"\bi\d+(?=\s|\b)"#
        )
        let operatorMode = Mode(
            scope: "operator",
            begin: "=",
            relevance: 0
        )
        let punctuation = Mode(
            scope: "punctuation",
            begin: ",",
            relevance: 0
        )
        let number = Mode(
            scope: "number",
            variants: [
                Mode(begin: "[su]?0[xX][KMLHR]?[a-fA-F0-9]+"),
                Mode(begin: #"[-+]?\d+(?:[.]\d+)?(?:[eE][-+]?\d+(?:[.]\d+)?)?"#),
            ],
            relevance: 0
        )
        let label = Mode(
            scope: "symbol",
            variants: [
                Mode(begin: #"^\s*[a-z]+:"#), // labels
            ],
            relevance: 0
        )
        let variable = Mode(
            scope: "variable",
            variants: [
                Mode(begin: .re("%" + identRe)),
                Mode(begin: #"%\d+"#),
                Mode(begin: #"#\d+"#),
            ]
        )
        let function = Mode(
            scope: "title",
            variants: [
                Mode(begin: .re("@" + identRe)),
                Mode(begin: #"@\d+"#),
                Mode(begin: .re("!" + identRe)),
                Mode(begin: .re(#"!\d+"# + identRe)),
                // https://llvm.org/docs/LangRef.html#namedmetadatastructure
                // obviously a single digit can also be used in this fashion
                Mode(begin: #"!\d+"#),
            ]
        )

        return LanguageDefinition(
            name: "llvm",
            root: Mode(
                // TODO: split into different categories of keywords
                keywords: Keywords([
                    "keyword": Keywords.Group(stringLiteral: "begin end true false declare define global "
                        + "constant private linker_private internal "
                        + "available_externally linkonce linkonce_odr weak "
                        + "weak_odr appending dllimport dllexport common "
                        + "default hidden protected extern_weak external "
                        + "thread_local zeroinitializer undef null to tail "
                        + "target triple datalayout volatile nuw nsw nnan "
                        + "ninf nsz arcp fast exact inbounds align "
                        + "addrspace section alias module asm sideeffect "
                        + "gc dbg linker_private_weak attributes blockaddress "
                        + "initialexec localdynamic localexec prefix unnamed_addr "
                        + "ccc fastcc coldcc x86_stdcallcc x86_fastcallcc "
                        + "arm_apcscc arm_aapcscc arm_aapcs_vfpcc ptx_device "
                        + "ptx_kernel intel_ocl_bicc msp430_intrcc spir_func "
                        + "spir_kernel x86_64_sysvcc x86_64_win64cc x86_thiscallcc "
                        + "cc c signext zeroext inreg sret nounwind "
                        + "noreturn noalias nocapture byval nest readnone "
                        + "readonly inlinehint noinline alwaysinline optsize ssp "
                        + "sspreq noredzone noimplicitfloat naked builtin cold "
                        + "nobuiltin noduplicate nonlazybind optnone returns_twice "
                        + "sanitize_address sanitize_memory sanitize_thread sspstrong "
                        + "uwtable returned type opaque eq ne slt sgt "
                        + "sle sge ult ugt ule uge oeq one olt ogt "
                        + "ole oge ord uno ueq une x acq_rel acquire "
                        + "alignstack atomic catch cleanup filter inteldialect "
                        + "max min monotonic nand personality release seq_cst "
                        + "singlethread umax umin unordered xchg add fadd "
                        + "sub fsub mul fmul udiv sdiv fdiv urem srem "
                        + "frem shl lshr ashr and or xor icmp fcmp "
                        + "phi call trunc zext sext fptrunc fpext uitofp "
                        + "sitofp fptoui fptosi inttoptr ptrtoint bitcast "
                        + "addrspacecast select va_arg ret br switch invoke "
                        + "unwind unreachable indirectbr landingpad resume "
                        + "malloc alloca free load store getelementptr "
                        + "extractelement insertelement shufflevector getresult "
                        + "extractvalue insertvalue atomicrmw cmpxchg fence "
                        + "argmemonly"),
                    "type": Keywords.Group(stringLiteral: "void half bfloat float double fp128 x86_fp80 ppc_fp128 "
                        + "x86_amx x86_mmx ptr label token metadata opaque"),
                ]),
                contains: [
                    type,
                    // this matches "empty comments"...
                    // ...because it's far more likely this is a statement terminator in
                    // another language than an actual comment
                    CommonModes.comment(#";\s*$"#, "") { $0.relevance = 0 },
                    CommonModes.comment(";", "$"),
                    Mode(
                        scope: "string",
                        begin: "\"",
                        end: "\"",
                        contains: [
                            Mode(scope: "char.escape", match: #"\\\d\d"#),
                        ]
                    ),
                    function,
                    punctuation,
                    operatorMode,
                    variable,
                    label,
                    number,
                ]
            )
        )
    }
}
