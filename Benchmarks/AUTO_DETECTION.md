# Async auto-detection benchmark

`highlight-bench --auto-bench` is the machine-readable benchmark for the
async `highlightAuto` path. It emits exactly one JSON object on stdout:

```sh
.build/release/highlight-bench --auto-bench cold 1 /path/to/input.swift
.build/release/highlight-bench --auto-bench warm 10 /path/to/input.swift
```

`cold` creates a fresh `Highlighter` inside every timed operation, so the
measurement includes registry and grammar compilation. `warm` creates one
dedicated `Highlighter`, performs one excluded async auto-detection warm-up,
then times the requested operations. Stable FNV-1a checksums cover the input,
detected language, relevance, illegality, second-best result, and every token
range/scope. Checksumming itself is outside the timed regions.

For a formal A/B, build both executables from the same benchmark-host revision
but link each against its frozen baseline or candidate `HighlightKit` sources.
Then run:

```sh
python3 Benchmarks/paired_auto_ab.py \
  --baseline /path/to/baseline/highlight-bench \
  --candidate /path/to/candidate/highlight-bench \
  --input Sources/HighlightKit/Core/HighlightEngine.swift \
  --output /path/to/auto-ab.json \
  --pairs 15 \
  --campaign bounded-auto-detection-final
```

The input is optional, but a checked-in file is recommended for a published
campaign. If omitted, both hosts use the built-in paste-sized JavaScript
sample and the runner still verifies its host-reported input checksum.

The runner alternates process and scenario order, performs excluded warm-up
processes, and writes its JSON output atomically after every completed pair.
It rejects schema, workload, semantic-checksum, or observable-result mismatches
before accepting a timing. Binary and input hashes are checked before and
after sampling. The final statistics are paired candidate/baseline geometric
mean latency ratios with a log-domain 95% Student-t interval for 15 pairs; no
completed observation is excluded.

## Async-overload integrity

`Highlighter.highlightAuto` intentionally has synchronous and asynchronous
overloads with the same base signature. At top level, writing
`await highlighter.highlightAuto(code)` is not sufficient evidence that Swift
selected the asynchronous overload: top-level `await` does not itself provide
the overload-selection context, so the synchronous overload can be chosen
(usually with a “no async operations occur” diagnostic).

The benchmark host therefore crosses the explicitly `async`
`concurrentAutoResult(_:code:)` helper for every timed async operation. Keep
that boundary in benchmark changes, and treat any async-overload diagnostic as
a failed build rather than publishing measurements from a host that may have
timed the sequential path.

## Published campaigns

- [2026-07-10 `P`/`2P`/`4P` scheduling-window campaign](Results/2026-07-10-auto-window/README.md): release and debug paired evidence; wider windows rejected, `P` retained.
