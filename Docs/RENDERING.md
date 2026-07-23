# Composable rendering

`HighlightRenderer` is reusable: it resolves theme scope fallbacks, base and
trait fonts, and equivalent styles once, then overlays only foreground colors
and/or font traits on caller-owned `NSMutableAttributedString` or
`NSTextStorage`. Backgrounds, links, paragraph styles, and unrelated intraline
attributes remain untouched.

`HighlightRangeMapping` maps equal-length UTF-16 source and destination ranges,
so a caller can render selected source ranges into rebased diff storage.
Explicit mappings are validated and inconsistencies throw. When no mappings
are supplied, the overlay covers the shared prefix of the result's source
length and the destination text, so pairing a result with mismatched text
degrades to a clipped overlay instead of an error. Equivalent adjacent syntax
styles are coalesced before existing font runs are intersected.
`maximumRenderedRuns` is enforced after those intersections and the returned
summary reports exact applied and omitted run counts.
