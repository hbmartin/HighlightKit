# Consumer-highlighting snapshot — 2026-07-23

This is a single-process release-build baseline for the new consumer-oriented
benchmark host. It is a reproducibility and gross-regression snapshot, not a
paired A/B campaign and not a confidence-interval performance claim.

## Environment

- MacBook Pro `Mac16,7`, Apple M4 Pro (14 cores), 48 GB RAM
- macOS 15.7.7 (24G720)
- Apple Swift 6.2.4 / Xcode 26.3 toolchain
- HighlightKit parent commit
  `62b85575fbda6653e3ff81da4fd74b785f0eb2fa`, plus the benchmark/documentation
  changes in the following commit
- Release executable SHA-256:
  `6e41e568af3503585ccc69b18cab0487f714f6c785c57d28421147a445bd23c1`

## Command

```sh
swift build -c release -j 1
.build/release/highlight-bench --consumer-bench 5 all
```

The WMO release build completed successfully in 400.89 seconds. Raw JSONL is
checked in as `results.jsonl`; every timing has an observable checksum.

## Snapshot

| Scenario | Result |
|---|---:|
| 40 old/new hunk pairs | 50.0 µs per small highlight |
| Cold result-cache miss | 9.90 ms |
| Warm result-cache hit | 20.2 µs |
| Cache eviction path | 8.61 ms per request |
| Eight-way single flight | 1.06 ms per waiter |
| Theme-only rerender from cached tokens | 1.85 ms |
| Token budget of 100 | 8.48 ms |
| Rendered-run budget of 200 | 529 µs |
| Retained cache results | 32.4 resident bytes per cached token |
| Retained attributed output | 45.0 resident bytes per attributed run |
| TextKit layout/draw, 40 viewports | 240.4 ms |

The token-budget timing remains close to the cold parse by design: token caps
do not stop parsing, so relevance and continuation stay exact. The retained
memory rows use process physical-footprint deltas and are allocator-sensitive;
repeat them in fresh processes for comparisons. `retained-cache-results` also
places the cache's deterministic estimated cost in `checksum` so retained-cost
policy remains observable even when RSS granularity changes.

The TextKit row highlights 62,200 UTF-16 units into 5,500 tokens / 10,500
attributed runs, installs the overlay directly in `NSTextStorage`, forces full
layout, scrolls 40 evenly spaced viewports, and forces each viewport through
`cacheDisplay`. It deliberately measures downstream layout and drawing, not
only attributed-string construction.
