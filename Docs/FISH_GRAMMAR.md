# Fish grammar provenance

HighlightKit's Fish grammar is first-party. It was authored against the Fish
source and documentation at commit
`20569c43d851ad65c77798434ccccb5610dbe3a1`; no third-party highlight.js Fish
grammar is bundled.

`Scripts/reference-grammars/fish.cjs` is the executable reference definition.
The Swift grammar is maintained token-for-token against it through fixtures
and seeded differential testing. Fish is intentionally excluded from global
automatic detection because ordinary shell snippets otherwise produce too
many Bash-like false positives. Explicit name, filename, extension, and
shebang resolution remain supported.
