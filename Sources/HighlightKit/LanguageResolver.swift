import Foundation

extension Highlighter {
    /// Resolves a repository file to an explicit language selection.
    public func resolveLanguage(
        for code: String,
        path: String? = nil,
        interpreter: String? = nil,
        override: LanguageSelection? = nil
    ) async throws -> LanguageSelection {
        if let override {
            switch override {
            case .plain:
                return .plain
            case .named(let name):
                guard let canonical = registry.canonicalName(for: name) else {
                    throw HighlightError.unknownLanguage(name)
                }
                return .named(canonical)
            case .automatic:
                return try await resolvedSelection(code: code, candidates: languageNames)
            }
        }

        let filename = path.map { ($0 as NSString).lastPathComponent.lowercased() }
        if let filename {
            let exact = registry.exactFilenameCandidates(filename)
            if !exact.isEmpty { return try await resolvedSelection(code: code, candidates: exact) }
        }

        if let executable = Self.normalizedInterpreter(
            interpreter ?? Self.shebangInterpreter(in: code)
        ) {
            let matches = registry.interpreterCandidates(executable)
            if !matches.isEmpty { return try await resolvedSelection(code: code, candidates: matches) }
        }

        if let filename {
            let matches = registry.extensionCandidates(filename)
            if !matches.isEmpty { return try await resolvedSelection(code: code, candidates: matches) }
        }
        return .plain
    }

    private func resolvedSelection(
        code: String,
        candidates: [String]
    ) async throws -> LanguageSelection {
        let candidates = Array(Set(candidates)).sorted()
        guard let first = candidates.first else { return .plain }
        guard candidates.count > 1 else { return .named(first) }
        let result = try await highlight(
            code,
            selection: .automatic,
            options: HighlightOptions(automaticSubset: candidates)
        )
        guard result.relevance > 0, let language = result.language else { return .plain }
        return .named(language)
    }

    private static func shebangInterpreter(in code: String) -> String? {
        guard code.hasPrefix("#!") else { return nil }
        let line = code.prefix { $0 != "\n" && $0 != "\r" }
        return String(line.dropFirst(2))
    }

    private static func normalizedInterpreter(_ command: String?) -> String? {
        guard let command else { return nil }
        var parts = command.split(whereSeparator: \Character.isWhitespace).map(String.init)
        guard !parts.isEmpty else { return nil }
        if parts[0].hasPrefix("#!") { parts[0].removeFirst(2) }
        var index = 0
        let first = (parts[0] as NSString).lastPathComponent.lowercased()
        if first == "env" {
            index = 1
            while index < parts.count {
                let part = parts[index]
                if part == "-S" { index += 1; continue }
                if part.hasPrefix("-") || part.contains("=") { index += 1; continue }
                break
            }
        }
        guard index < parts.count else { return nil }
        var executable = (parts[index] as NSString).lastPathComponent.lowercased()
        if executable.hasSuffix(".exe") { executable.removeLast(4) }
        return executable.isEmpty ? nil : executable
    }
}
