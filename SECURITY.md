# Security policy

## Supported versions

The latest minor release receives fixes.

## Reporting a vulnerability

HighlightKit parses untrusted source text, so parser robustness is a
security surface. The engine has an iteration guard against pathological
inputs, and the stress suite (`hostileInputsTerminate`,
`repeatedHighlightingHasStableFootprint`) exercises hostile and
memory-stability cases — but regex-based matching inherits ICU's
worst-case behavior, and inputs that provoke crashes, hangs, or unbounded
memory growth are bugs.

Please report vulnerabilities privately to **security@phrase.so** — do
not open a public issue. We aim to acknowledge within 48 hours. Include a
minimal reproducing input if possible.
