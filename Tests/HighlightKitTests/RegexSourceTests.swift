import Foundation
import Testing
@testable import HighlightKit

@Suite("RegexSource utilities")
struct RegexSourceTests {
    @Test func escapeEscapesMetacharacters() {
        #expect(RegexSource.escape("a.b*c") == #"a\.b\*c"#)
        #expect(RegexSource.escape("(x|y)") == #"\(x\|y\)"#)
        #expect(RegexSource.escape("plain") == "plain")
        #expect(RegexSource.escape("{}[]^$-/\\+?") == #"\{\}\[\]\^\$\-\/\\\+\?"#)
    }

    @Test func combinators() {
        #expect(RegexSource.lookahead("ab") == "(?=ab)")
        #expect(RegexSource.optional("ab") == "(?:ab)?")
        #expect(RegexSource.anyNumberOfTimes("ab") == "(?:ab)*")
        #expect(RegexSource.concat("a", "b", "c") == "abc")
        #expect(RegexSource.either("a", "b") == "(?:a|b)")
        #expect(RegexSource.either("a", "b", capture: true) == "(a|b)")
        #expect(RegexSource.either(["x", "y"]) == "(?:x|y)")
    }

    @Test func countCaptureGroups() {
        #expect(RegexSource.countCaptureGroups("abc") == 0)
        #expect(RegexSource.countCaptureGroups("(a)(b)") == 2)
        #expect(RegexSource.countCaptureGroups("(?:a)(b)") == 1)
        #expect(RegexSource.countCaptureGroups("(?=x)(?!y)") == 0)
        #expect(RegexSource.countCaptureGroups("(?<name>a)") == 1)
        #expect(RegexSource.countCaptureGroups("(?<=a)(?<!b)") == 0)
        #expect(RegexSource.countCaptureGroups("(?'name'a)") == 1)
        // `(` inside a character class does not capture
        #expect(RegexSource.countCaptureGroups("[(](a)") == 1)
        // escaped parens do not capture
        #expect(RegexSource.countCaptureGroups(#"\((a)\)"#) == 1)
        // nested groups all count
        #expect(RegexSource.countCaptureGroups("((a)(b(c)))") == 4)
        // escaped bracket inside a class
        #expect(RegexSource.countCaptureGroups(#"[\](](a)"#) == 1)
    }

    @Test func rewriteBackreferencesJoins() {
        // no backreferences: patterns are just wrapped and joined
        #expect(RegexSource.rewriteBackreferences(["a", "b"], joinedBy: "|") == "(a)|(b)")
        #expect(RegexSource.rewriteBackreferences(["a", "b"], joinedBy: "") == "(a)(b)")
    }

    @Test func rewriteBackreferencesRenumbers() {
        // `(x)\1` as the second alternative: the wrapper of alt 1 is group 1,
        // alt 2's wrapper is group 2, so its inner (x) becomes group 3 and
        // \1 must become \3.
        let combined = RegexSource.rewriteBackreferences(["(a)", #"(x)\1"#], joinedBy: "|")
        #expect(combined == #"((a))|((x)\4)"#)
    }

    @Test func rewriteBackreferencesIgnoresClassesAndEscapes() {
        let combined = RegexSource.rewriteBackreferences([#"[\1](a)\\"#], joinedBy: "|")
        // \1 inside a character class is untouched; escaped backslash too
        #expect(combined == #"([\1](a)\\)"#)
    }

    @Test func backreferencesStillMatchAfterCombining() throws {
        // heredoc-style pattern: the combined alternation must keep
        // backreferences pointing at their own groups
        let combined = RegexSource.rewriteBackreferences(
            ["(b)", #"<<(\w+)[\s\S]*?\1"#], joinedBy: "|"
        )
        let re = try NSRegularExpression(pattern: combined)
        let text = "<<EOF hello EOF"
        let match = re.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        #expect(match != nil)
        #expect(match.map { (text as NSString).substring(with: $0.range) } == "<<EOF hello EOF")
    }
}
