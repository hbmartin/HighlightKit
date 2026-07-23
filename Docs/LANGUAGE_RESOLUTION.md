# Repository language resolution

Language metadata is generated and reviewed from GitHub Linguist
`languages.yml` at commit `821c1654e37491f53842efe398da2d5b1e175899`.
Extensions omit the leading dot; filenames, extensions, and interpreters are
normalized case-insensitively.

`Scripts/generate-language-metadata.rb` audits the checked-in table against a
local copy of that pinned YAML using only Ruby's standard library. Mappings
where HighlightKit and Linguist use different canonical names are explicit in
the script; the generated audit is reviewed before updating the Swift table.

`resolveLanguage(for:path:interpreter:override:)` applies this precedence:
caller override, exact filename, explicit interpreter or shebang, longest
matching extension, then plain text. Ambiguous extensions run automatic
detection only across their candidate languages and resolve zero-relevance
content to `.plain`. Shebang parsing supports direct executables and
`/usr/bin/env`, including `-S`, flags, and environment assignments.
