# Async auto-detection scheduling-window campaign

This campaign tests whether allowing more than one active candidate task per
logical processor improves async auto-detection. On the 14-logical-processor
host, `P`, `2P`, and `4P` mean windows of 14, 28, and 56 child tasks. The
decision is to **retain `P` and reject `2P`/`4P`**: neither wider window shows a
repeatable production improvement, while each permits proportionally more
live task records and parser working sets.

## Controlled inputs

Every comparison used the same benchmark host
(`e6d54bd3c8797777a24d47971b04624fa94d9df568cdd4a9f290e46103f62b7f`)
and `Package.swift`
(`d8278bc848dd4ebf18c93683d3b6749553f25f00edb0c9963a14a9c099e9dfb1`).
The source-tree digest is SHA-256 over the lexicographically sorted
`shasum -a 256` records for every regular file under `Sources/`. The trees in
each comparison differ only in
`Sources/HighlightKit/Core/LanguageRegistry.swift`.

| Build | Window | `Sources/` digest | `LanguageRegistry.swift` | Binary |
| --- | ---: | --- | --- | --- |
| production baseline | `P = 14` | `48466387c6a42b84f1195410b82f6d8ff3ec977181933b1298c63e67033589ec` | `cc8364645e4d95264ad39b9cdc95ae8d3cf1985297b7bf07cb3a814b7889ad51` | `8b0325421f09ba30dac3005cc7ff3b85cd53aae48073691c03f0132c51a061ab` |
| production candidate | `2P = 28` | `b95985f068f9282e44826e7edec21db5aed797d24fa152c451ff4777079e8e02` | `fcad972c2e19c20ddda2e300fa5b2d33f1f0abe997a33bfec51c7ebcd25b61cb` | `f06b614baa266eb656e96638c71196678e133542d30ebec2771c5ef1a5d06531` |
| debug baseline | `P = 14` | `48466387c6a42b84f1195410b82f6d8ff3ec977181933b1298c63e67033589ec` | `cc8364645e4d95264ad39b9cdc95ae8d3cf1985297b7bf07cb3a814b7889ad51` | `5df1deec535b589cf2e06f891ac8c476855bec9e3066176a80448a8940084864` |
| debug candidate | `2P = 28` | `8c4b34044d4413d8e4ed7d4a45eb3065a6d86177f8bd88a77d4907faa3548654` | `4f60fc54a33d3d9a34152bc41ca8a6c01b6fba9f1dfa8b3b2402f167bbf2d950` | `238f42427eebfcb3e6087b413570babfd9b5f46bf4e270e85a4c2343da509921` |
| debug candidate | `4P = 56` | `f896c8dc32db3cc825525a40d06a730bdb4f9aab73be6917cd71bbc0c8ec90b5` | `ba6c2e3aff1064f14201e7dbb3574f7379cde531491aecaba7b8a32a78522df9` | `2907225c9d2c067d87f76aebd102b9da86eebf60ac2e651ca06c5a73424fa572` |

## Method and results

Each file contains 15 paired observations. Scenario order and which binary
runs first alternate; one process per binary/scenario is warmed and excluded
before sampling. Timings come from `ContinuousClock` inside the benchmark
host. The reported ratio is the geometric mean of the 15 paired
candidate/baseline latency ratios, with a log-domain 95% Student-t confidence
interval (`df = 14`). Negative change is faster. All five files retained every
completed observation.

| Artifact | Build / workload | Cold change (95% CI) | Warm change (95% CI) | Result |
| --- | --- | ---: | ---: | --- |
| [`builtin-622-js-15pairs.json`](builtin-622-js-15pairs.json) | production `P` vs `2P`; built-in 622-unit JS; warm 10 | `-1.345751353965008%` (`-2.7261662321176106%`, `+0.05425301873112076%`) | `-1.4232093013301528%` (`-2.8328092555737983%`, `+0.006839654431201048%`) | neutral |
| [`highlight-engine-swift-15pairs.json`](highlight-engine-swift-15pairs.json) | production `P` vs `2P`; 33,698-unit source; warm 3 | `-1.4950366808279436%` (`-5.450149523608849%`, `+2.6255224056044746%`) | `+4.674675797769967%` (`-1.0266624374102973%`, `+10.704438419481344%`) | neutral |
| [`highlight-engine-swift-warm10-15pairs.json`](highlight-engine-swift-warm10-15pairs.json) | production `P` vs `2P`; 33,698-unit source; warm 10 | `-2.6393740054196035%` (`-5.708096693193343%`, `+0.5292200244757961%`) | `+2.887249699626504%` (`-3.2231884734324923%`, `+9.383497800475116%`) | neutral |
| [`paired-auto-p-vs-2p-debug-15.json`](paired-auto-p-vs-2p-debug-15.json) | debug `P` vs `2P`; built-in JS; warm 5 | `+5.717212256273352%` (`-8.880077326182745%`, `+22.652968080814027%`) | `-8.418177405506189%` (`-14.618772658689505%`, `-1.7672796362896315%`) | warm-only debug signal |
| [`paired-auto-p-vs-4p-debug-15.json`](paired-auto-p-vs-4p-debug-15.json) | debug `P` vs `4P`; built-in JS; warm 5 | `+1.600892041012325%` (`-5.096192627583052%`, `+8.770570426341662%`) | `+1.583279236005719%` (`-5.965475342794835%`, `+9.738020774369161%`) | neutral |

The production campaign is decisive for `2P`: for every workload, both cold
and warm candidate/baseline latency-ratio intervals cross `1.0` (equivalently,
all six percent-change intervals cross `0%`), and both source-file warm runs
trend slower. With no demonstrated production gain, `P` is retained because
it has the lower resource ceiling. The isolated, disturbed debug `2P` warm
signal is screening evidence and is not promoted into a production conclusion.
`4P` has no positive debug signal and would quadruple the permitted in-flight
work, so paying for a production WMO build was rejected.

## Semantic checks and disturbances

The runner rejected a sample on any schema, workload, input-checksum,
result-checksum, or observable-result mismatch. Every baseline/candidate pair
matched. The built-in input checksum is `e618317a22b4ca5f`; it detects
JavaScript with relevance 32, 55 tokens, and result checksum
`9f53c72ffe2dc152`. The source input has file SHA-256
`d986fd1809b41a63bcd1761474c787402fdfd3b426796f9d9558ef43f84e8ff4`,
input checksum `ca147e3acaa5b9cd`, and result checksum
`59ec73d5d639a339` (PHP, relevance 498, 859 tokens). Binary and input hashes
were identical before and after every campaign.

These measurements ran on an interactive macOS 26.5.1 arm64 host with normal
desktop background processes. Process snapshots taken before the three
production runs found no concurrent release/WMO Swift build. The two debug
screens overlapped almost completely (`12:38:06Z`–`12:38:15Z`), so they are
deliberately treated as noisy screening evidence, not release-quality proof.
No observation was removed for that or any other disturbance: the JSON method
records `none; all completed observations are retained`.

## Artifact integrity

SHA-256 of the checked-in raw JSON files:

```text
42597dc74627d034253f8e93aae1a103823c8c7c7f99f1435ea902f99ae42989  builtin-622-js-15pairs.json
9a7044d4ef2256eefa6a46a12af281a858efa9a43a1bcaa75de8321427396d6f  highlight-engine-swift-15pairs.json
793ba6a6ef3c6c47ea986ec3029d58a0c8e390a8d63e32f1e3d4ced0f17fe9ae  highlight-engine-swift-warm10-15pairs.json
4121fdcdc165f46ea2c9f09cd3c312376272c0fdc71f7a8518047a0b1d5af256  paired-auto-p-vs-2p-debug-15.json
9950a652a9c1cb654ee8bea43e15005c8e7f4a10442773d2d51aff503790c216  paired-auto-p-vs-4p-debug-15.json
```
