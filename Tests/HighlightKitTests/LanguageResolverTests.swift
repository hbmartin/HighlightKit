import Testing
@testable import HighlightKit

@Suite("Repository language resolution")
struct LanguageResolverTests {
    @Test func metadataIsNormalizedAndExposed() {
        let swift = Highlighter.shared.language(named: "SWIFT")
        #expect(swift?.metadata.fileExtensions.contains("swift") == true)
        #expect(swift?.metadata.filenames.contains("package.swift") == true)
        #expect(Highlighter.shared.languages.count == 71)
    }

    @Test func exactNamesCompoundExtensionsAndMixedCase() async throws {
        #expect(try await Highlighter.shared.resolveLanguage(for: "", path: "Sources/CMakeLists.TXT") == .named("cmake"))
        #expect(try await Highlighter.shared.resolveLanguage(for: "", path: "types/index.D.TS") == .named("typescript"))
        #expect(try await Highlighter.shared.resolveLanguage(for: "", path: "Main.SWIFT") == .named("swift"))
    }

    @Test func overridesAndUnmatchedFiles() async throws {
        #expect(try await Highlighter.shared.resolveLanguage(for: "x", path: "x.swift", override: .plain) == .plain)
        #expect(try await Highlighter.shared.resolveLanguage(for: "x", override: .named("rb")) == .named("ruby"))
        #expect(try await Highlighter.shared.resolveLanguage(for: "x", path: "LICENSE.unknown") == .plain)
    }

    @Test func directAndEnvShebangsResolve() async throws {
        #expect(try await Highlighter.shared.resolveLanguage(for: "#!/usr/bin/python3 -u\nprint(1)") == .named("python"))
        #expect(try await Highlighter.shared.resolveLanguage(for: "#!/usr/bin/env -S fish --no-config\necho hi") == .named("fish"))
        #expect(try await Highlighter.shared.resolveLanguage(for: "#!/usr/bin/env -u PYTHONHOME python3\nprint(1)") == .named("python"))
        #expect(try await Highlighter.shared.resolveLanguage(for: "", interpreter: "/usr/bin/ruby") == .named("ruby"))
    }

    @Test func ambiguousHeadersAndMFilesUseContent() async throws {
        let cpp = try await Highlighter.shared.resolveLanguage(
            for: "template <class T> class Box { public: T value; };",
            path: "Box.h"
        )
        #expect(cpp == .named("cpp"))
        let objc = try await Highlighter.shared.resolveLanguage(
            for: "#import <Foundation/Foundation.h>\n@interface AppDelegate : NSObject\n@end",
            path: "App.m"
        )
        #expect(objc == .named("objectivec"))
        let matlab = try await Highlighter.shared.resolveLanguage(
            for: "function y = square(x)\ny = x.^2;\nend",
            path: "square.m"
        )
        #expect(matlab == .named("matlab"))
        #expect(try await Highlighter.shared.resolveLanguage(for: "", path: "empty.h") == .plain)
    }

    @Test func replacementRebuildsMetadataIndexes() async throws {
        let highlighter = Highlighter(languages: [])
        let first = LanguageDescriptor(
            name: "first",
            metadata: LanguageMetadata(fileExtensions: ["custom"])
        ) { LanguageDefinition(name: "first", root: Mode()) }
        let second = LanguageDescriptor(
            name: "second",
            metadata: LanguageMetadata(fileExtensions: ["custom"])
        ) { LanguageDefinition(name: "second", root: Mode()) }
        highlighter.register(first)
        #expect(try await highlighter.resolveLanguage(for: "", path: "x.custom") == .named("first"))
        highlighter.register(second)
        let selection = try await highlighter.resolveLanguage(for: "", path: "x.custom")
        #expect(selection == .plain)
    }
}
