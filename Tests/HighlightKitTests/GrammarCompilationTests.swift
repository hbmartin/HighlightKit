import Foundation
import Testing
@testable import HighlightKit

@Suite("Grammar compilation")
struct GrammarCompilationTests {
    /// Every bundled grammar must compile: all regexes valid ICU, all
    /// structural invariants satisfied.
    @Test(arguments: LanguageCatalog.all.map(\.name))
    func compiles(name: String) throws {
        let registry = LanguageRegistry(languages: LanguageCatalog.all)
        do {
            _ = try registry.compiledLanguage(named: name)
        } catch {
            Issue.record("Grammar '\(name)' failed to compile: \(error)")
        }
    }
}
