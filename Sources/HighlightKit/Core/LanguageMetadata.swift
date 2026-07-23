import Foundation

/// Repository-oriented hints associated with a language grammar.
public struct LanguageMetadata: Hashable, Sendable {
    public let fileExtensions: [String]
    public let filenames: [String]
    public let interpreters: [String]

    public init(
        fileExtensions: [String] = [],
        filenames: [String] = [],
        interpreters: [String] = []
    ) {
        self.fileExtensions = Self.normalized(fileExtensions) {
            String($0.drop(while: { $0 == "." })).lowercased()
        }
        self.filenames = Self.normalized(filenames) { $0.lowercased() }
        self.interpreters = Self.normalized(interpreters) {
            (($0 as NSString).lastPathComponent as String).lowercased()
        }
    }

    private static func normalized(
        _ values: [String],
        transform: (String) -> String
    ) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let value = transform(value.trimmingCharacters(in: .whitespacesAndNewlines))
            return !value.isEmpty && seen.insert(value).inserted ? value : nil
        }
    }
}

/// Stable, public registration metadata without exposing grammar factories.
public struct LanguageInfo: Hashable, Sendable {
    public let name: String
    public let aliases: [String]
    public let metadata: LanguageMetadata

    public init(name: String, aliases: [String], metadata: LanguageMetadata) {
        self.name = name
        self.aliases = aliases
        self.metadata = metadata
    }
}

// Generated and reviewed from GitHub Linguist languages.yml at
// 821c1654e37491f53842efe398da2d5b1e175899, narrowed to bundled grammars.
extension LanguageMetadata {
    static func bundled(language rawName: String) -> LanguageMetadata {
        let name = rawName.lowercased()
        let values: ([String], [String], [String]) = switch name {
        case "ada": (["adb", "ads", "ada"], [], [])
        case "apache": (["apacheconf", "vhost"], [".htaccess"], [])
        case "applescript": (["applescript", "scpt"], [], ["osascript"])
        case "armasm": (["s", "asm"], [], [])
        case "bash": (["bash", "sh", "bats"], [".bashrc", ".bash_profile", ".profile"], ["bash", "sh"])
        case "basic": (["bas"], [], [])
        case "c": (["c", "h"], [], [])
        case "clojure": (["clj", "cljs", "cljc", "edn"], [], ["clojure"])
        case "cmake": (["cmake"], ["cmakelists.txt"], [])
        case "coffeescript": (["coffee", "litcoffee"], [], ["coffee"])
        case "cpp": (["cc", "cp", "cpp", "cxx", "h", "hh", "hpp", "hxx"], [], [])
        case "csharp": (["cs", "csx"], [], [])
        case "css": (["css"], [], [])
        case "dart": (["dart"], [], ["dart"])
        case "delphi": (["pas", "dpr"], [], [])
        case "diff": (["diff", "patch"], [], [])
        case "dockerfile": (["dockerfile"], ["dockerfile", "containerfile"], [])
        case "dos": (["bat", "cmd"], [], ["cmd"])
        case "elm": (["elm"], [], [])
        case "elixir": (["ex", "exs"], ["mix.exs"], ["elixir"])
        case "erlang": (["erl", "hrl"], ["rebar.config"], ["escript"])
        case "fish": (["fish"], ["config.fish"], ["fish"])
        case "fortran": (["f", "for", "f77", "f90", "f95", "f03", "f08"], [], [])
        case "fsharp": (["fs", "fsi", "fsx"], [], ["dotnet-fsi", "fsi"])
        case "go": (["go"], [], [])
        case "graphql": (["graphql", "gql", "graphqls"], [], [])
        case "groovy": (["groovy", "gradle"], ["jenkinsfile"], ["groovy"])
        case "haskell": (["hs", "lhs"], [], ["runhaskell"])
        case "http": (["http"], [], [])
        case "ini": (["ini", "cfg", "prefs", "pro", "properties", "toml"], [], [])
        case "java": (["java"], [], [])
        case "javascript": (["js", "mjs", "cjs", "jsx"], [], ["node", "nodejs"])
        case "json": (["json", "jsonc", "geojson"], [".babelrc", ".eslintrc", "composer.lock"], [])
        case "kotlin": (["kt", "kts"], [], ["kotlin"])
        case "leaf": (["leaf"], [], [])
        case "less": (["less"], [], [])
        case "lisp": (["lisp", "lsp", "cl"], [], [])
        case "llvm": (["ll"], [], [])
        case "lua": (["lua"], [], ["lua", "luajit"])
        case "makefile": (["mk", "mak"], ["makefile", "gnumakefile", "bsdmakefile"], [])
        case "markdown": (["md", "markdown", "mdown", "mkd"], ["readme"], [])
        case "matlab": (["m"], [], ["matlab"])
        case "nginx": (["nginx", "nginxconf"], ["nginx.conf"], [])
        case "nim": (["nim", "nims", "nimble"], [], ["nim"])
        case "nix": (["nix"], [], ["nix-shell"])
        case "objectivec": (["h", "m", "mm"], [], [])
        case "ocaml": (["ml", "mli"], [], ["ocaml"])
        case "perl": (["pl", "pm", "pod", "t"], [], ["perl"])
        case "php": (["php", "php3", "php4", "php5", "phtml"], ["composer.json"], ["php"])
        case "plaintext": (["txt", "text"], [], [])
        case "powershell": (["ps1", "psm1", "psd1"], [], ["pwsh", "powershell"])
        case "prolog": (["pro", "prolog"], [], ["swipl"])
        case "properties": (["properties"], [], [])
        case "protobuf": (["proto"], [], [])
        case "python": (["py", "pyw", "pyi"], ["sconstruct", "wscript"], ["python", "python2", "python3", "pypy"])
        case "r": (["r", "rmd"], [".rprofile"], ["rscript"])
        case "ruby": (["rb", "rake", "gemspec"], ["gemfile", "rakefile", "podfile", "brewfile"], ["ruby"])
        case "rust": (["rs"], [], [])
        case "scala": (["scala", "sc"], [], ["scala"])
        case "scheme": (["scm", "ss"], [], ["scheme", "guile"])
        case "scss": (["scss"], [], [])
        case "shell": (["shell-session"], [], [])
        case "sql": (["sql"], [], [])
        case "stylus": (["styl"], [], [])
        case "swift": (["swift"], ["package.swift"], ["swift"])
        case "terraform": (["tf", "tfvars", "hcl"], [".terraformrc"], [])
        case "typescript": (["ts", "tsx", "d.ts", "mts", "cts"], [], ["ts-node", "deno"])
        case "vim": (["vim"], [".vimrc", "gvimrc"], ["vim"])
        case "xml": (["xml", "html", "htm", "xhtml", "svg", "plist", "storyboard", "xib"], [], [])
        case "yaml": (["yaml", "yml"], [".clang-format", ".clang-tidy"], [])
        case "zig": (["zig", "zon"], [], [])
        default: ([], [], [])
        }
        return LanguageMetadata(
            fileExtensions: values.0,
            filenames: values.1,
            interpreters: values.2
        )
    }
}
