import Foundation
import Testing
@testable import HighlightKit

/// Exercises the "resume scanning at the same position" machinery: when a
/// begin match is vetoed by a callback, the engine re-scans the same spot
/// considering only later rules (highlight.js `ResumableMultiRegex`).
@Suite("Matcher resume paths")
struct MatcherResumeTests {
    /// Grammar: rule A matches `foo` but vetoes every match; rule B also
    /// matches `foo`. The veto must not hide rule B (resume path), and
    /// text before/after must be untouched.
    @Test func vetoedRuleYieldsToLaterRuleAtSamePosition() {
        let descriptor = LanguageDescriptor(name: "veto-test") {
            LanguageDefinition(
                name: "veto-test",
                root: Mode(contains: [
                    Mode(
                        scope: "first",
                        begin: "foo",
                        onBegin: { _, response in response.ignoreMatch() }
                    ),
                    Mode(scope: "second", begin: "foo"),
                ])
            )
        }
        let highlighter = Highlighter(languages: [descriptor])
        let result = highlighter.highlight("say foo now foo", as: "veto-test")
        #expect(result.tokens.count == 2)
        #expect(result.tokens.allSatisfy { $0.scope == "second" })
        #expect(result.tokens.map(\.range) == [
            NSRange(location: 4, length: 3),
            NSRange(location: 12, length: 3),
        ])
    }

    /// When the vetoed rule is the *last* rule, there is nothing left to
    /// try at this position and the engine must advance one character
    /// (the `doIgnore` regexIndex == 0 path via cursor wraparound).
    @Test func vetoedLastRuleAdvancesOneCharacter() {
        let descriptor = LanguageDescriptor(name: "veto-last") {
            LanguageDefinition(
                name: "veto-last",
                root: Mode(contains: [
                    Mode(
                        scope: "never",
                        begin: "fo+",
                        onBegin: { _, response in response.ignoreMatch() }
                    ),
                ])
            )
        }
        let highlighter = Highlighter(languages: [descriptor])
        let result = highlighter.highlight("foo foo", as: "veto-last")
        #expect(result.tokens.isEmpty) // everything ends up plain
    }

    /// A veto where an *earlier* rule could match just after the ignored
    /// one — the two-matcher comparison must pick whichever comes first.
    @Test func earlierRuleStillWinsAfterIgnoredMatch() {
        let descriptor = LanguageDescriptor(name: "veto-mixed") {
            LanguageDefinition(
                name: "veto-mixed",
                root: Mode(contains: [
                    Mode(scope: "word", begin: "[a-z]+"),
                    Mode(
                        scope: "digits",
                        begin: "[0-9]+",
                        onBegin: { _, response in response.ignoreMatch() }
                    ),
                ])
            )
        }
        let highlighter = Highlighter(languages: [descriptor])
        let result = highlighter.highlight("123 abc", as: "veto-mixed")
        // digits vetoed (rescanned, then abandoned), abc still highlighted
        #expect(result.tokens.count == 1)
        #expect(result.tokens[0].scope == "word")
        #expect(result.tokens[0].range == NSRange(location: 4, length: 3))
    }

    /// The two-phase resume: with ≥2 begin rules, the first matches at a
    /// position and is vetoed, but the second does *not* match there — so
    /// the resume scan from the vetoed-rule index finds a match further
    /// along, and the engine must fall back to a full scan one position
    /// later to keep alternation order (`exec`'s second-phase branch).
    @Test func twoPhaseResumeAfterVetoWithMultipleRules() {
        let descriptor = LanguageDescriptor(name: "twophase") {
            LanguageDefinition(name: "twophase", root: Mode(contains: [
                // rule 0: matches "xy", always vetoed
                Mode(scope: "veto", begin: "xy", onBegin: { _, r in r.ignoreMatch() }),
                // rule 1: matches a lone "z", elsewhere
                Mode(scope: "z", begin: "z"),
            ]))
        }
        let h = Highlighter(languages: [descriptor])
        // "xy" at 0 is vetoed; resume scan finds "z" at 2 (not at 0), so
        // the full rescan from 1 runs — result still "z" at 2.
        let result = h.highlight("xyz", as: "twophase")
        #expect(result.tokens == [HighlightToken(range: NSRange(location: 2, length: 1), scopes: ["z"])])

        // and a case where the second-phase rescan finds the same rule
        // again at a later position
        let result2 = h.highlight("xy xy z", as: "twophase")
        #expect(result2.tokens == [HighlightToken(range: NSRange(location: 6, length: 1), scopes: ["z"])])
    }
}
