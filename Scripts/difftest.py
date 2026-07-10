#!/usr/bin/env python3
"""Differentially compare HighlightKit with a highlight.js source checkout.

Usage:
    HIGHLIGHTJS_DIR=/path/to/highlight.js \
        python3 Scripts/difftest.py <language> [count] [seed]
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import random
import subprocess


REPOSITORY = Path(__file__).resolve().parents[1]
FIXTURES = REPOSITORY / "Tests" / "HighlightKitTests" / "Fixtures"
REFERENCE_RUNNER = Path(__file__).with_name("tokenize-batch.mjs")
DEFAULT_SWIFT_BINARY = REPOSITORY / ".build" / "release" / "highlight-bench"


def corpus(language: str) -> list[str]:
    directory = FIXTURES / language
    if not directory.is_dir():
        return []
    return [
        path.read_text(encoding="utf-8")
        for path in sorted(directory.glob("*.code.txt"))
    ]


def mutate(rng: random.Random, base: str, *, include_unicode: bool) -> str:
    characters = list(base)
    specials = list('{}[]()<>"\'`\\/*#;:.,$@%&|!?=+-~^ \n\t')
    for _ in range(rng.randint(1, max(1, len(characters) // 8 + 1))):
        if not characters:
            characters = [rng.choice(specials)]
            continue
        operation = rng.randint(0, 4)
        index = rng.randrange(len(characters))
        if operation == 0:
            del characters[index]
        elif operation == 1:
            characters.insert(index, rng.choice(specials))
        elif operation == 2:
            characters.insert(index, characters[index])
        elif operation == 3:
            characters = characters[:index]
        else:
            replacements = ["\0"]
            if include_unicode:
                replacements += ["é", "中", "😀", "‍", "ﬀ"]
            characters.insert(index, rng.choice(replacements))
    return "".join(characters)


def random_input(rng: random.Random) -> str:
    alphabet = 'abcdefgh {}[]()<>"\'`\\/*#;:.=+-\n\t012'
    return "".join(rng.choice(alphabet) for _ in range(rng.randint(0, 60)))


def build_inputs(
    language: str,
    count: int,
    rng: random.Random,
    *,
    include_unicode: bool,
) -> list[str]:
    examples = corpus(language)
    inputs = [
        "", " ", "\n", "\n\n", "\t", "a", "//", "/*", "*/", '"', "'", "`",
        "{", "}", "(", ")", "\\", "$", "#", ";", ":", "0", "0x", "1.", ".5",
    ]
    for example in examples:
        inputs.append(example)
        for _ in range(2):
            if example:
                inputs.append(example[: rng.randint(0, len(example))])
    for _ in range(count):
        if examples and rng.random() < 0.7:
            inputs.append(
                mutate(rng, rng.choice(examples), include_unicode=include_unicode)
            )
        else:
            inputs.append(random_input(rng))
    return inputs


def run_engine(
    command: list[str],
    inputs: list[str],
    language: str,
    *,
    environment: dict[str, str] | None = None,
) -> list[dict[str, object]]:
    payload = "\n".join(
        json.dumps({"lang": language, "code": code}) for code in inputs
    ) + "\n"
    result = subprocess.run(
        command,
        input=payload,
        capture_output=True,
        text=True,
        timeout=300,
        env=environment,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"{command[0]} exited {result.returncode}: {result.stderr[:500]}"
        )
    return [json.loads(line) for line in result.stdout.splitlines() if line.strip()]


def utf16_length(value: str) -> int:
    return len(value.encode("utf-16-le", errors="surrogatepass")) // 2


def token_stream_error(
    result: dict[str, object],
    code: str,
) -> str | None:
    tokens = result.get("tokens")
    if not isinstance(tokens, list):
        return "missing token array"
    limit = utf16_length(code)
    previous_end = 0
    for index, token in enumerate(tokens):
        if not isinstance(token, dict):
            return f"token {index} is not an object"
        start = token.get("start")
        length = token.get("length")
        if not isinstance(start, int) or not isinstance(length, int):
            return f"token {index} has non-integer range"
        end = start + length
        if start < previous_end:
            return f"token {index} overlaps or is out of order"
        if start < 0 or length <= 0 or end > limit:
            return (
                f"token {index} range [{start}, {end}) is outside "
                f"UTF-16 length {limit}"
            )
        previous_end = end
    return None


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("language")
    parser.add_argument("count", nargs="?", type=int, default=200)
    parser.add_argument("seed", nargs="?", type=int, default=1)
    parser.add_argument(
        "--unicode",
        action="store_true",
        help="include Unicode mutations (ICU/JavaScript boundary differences are expected)",
    )
    parser.add_argument(
        "--reference",
        type=Path,
        default=os.environ.get("HIGHLIGHTJS_DIR"),
        help="highlight.js checkout root (or set HIGHLIGHTJS_DIR)",
    )
    parser.add_argument(
        "--swift-binary",
        type=Path,
        default=Path(os.environ.get("HIGHLIGHT_BENCH", DEFAULT_SWIFT_BINARY)),
        help="release highlight-bench executable",
    )
    arguments = parser.parse_args()
    if arguments.reference is None:
        parser.error("pass --reference or set HIGHLIGHTJS_DIR")
    return arguments


def main() -> None:
    arguments = parse_arguments()
    reference = arguments.reference.expanduser().resolve()
    swift_binary = arguments.swift_binary.expanduser().resolve()
    if not (reference / "build" / "lib" / "core.js").is_file():
        raise SystemExit(
            f"missing highlight.js Node build under {reference}; "
            "run `npm ci && npm run build` in that checkout"
        )
    if not swift_binary.is_file():
        raise SystemExit(
            f"missing {swift_binary}; run `swift build -c release` first"
        )

    rng = random.Random(arguments.seed)
    inputs = build_inputs(
        arguments.language,
        arguments.count,
        rng,
        include_unicode=arguments.unicode,
    )
    swift = run_engine(
        [str(swift_binary), "--tokens-batch"], inputs, arguments.language
    )
    reference_environment = os.environ.copy()
    reference_environment["HIGHLIGHTJS_DIR"] = str(reference)
    upstream = run_engine(
        ["node", str(REFERENCE_RUNNER)],
        inputs,
        arguments.language,
        environment=reference_environment,
    )
    if len(swift) != len(inputs) or len(upstream) != len(inputs):
        raise RuntimeError(
            "result count mismatch: "
            f"swift={len(swift)} reference={len(upstream)} inputs={len(inputs)}"
        )

    differences: list[tuple[str, str, str]] = []
    reference_eof_units_clipped = 0
    for code, actual, expected in zip(inputs, swift, upstream):
        if "error" in actual:
            differences.append(("SWIFT_ERROR", str(actual["error"]), code))
            continue
        if "error" in expected:
            differences.append(("REFERENCE_ERROR", str(expected["error"]), code))
            continue
        if error := token_stream_error(actual, code):
            differences.append(("SWIFT_INVALID_TOKENS", error, code))
            continue
        if error := token_stream_error(expected, code):
            differences.append(("REFERENCE_INVALID_TOKENS", error, code))
            continue
        reference_eof_units_clipped += int(
            expected.get("referenceEOFUnitsClipped", 0)
        )
        if actual["tokens"] != expected["tokens"]:
            actual_tokens = actual["tokens"]
            expected_tokens = expected["tokens"]
            limit = max(len(actual_tokens), len(expected_tokens))
            index = next(
                position
                for position in range(limit)
                if (actual_tokens[position] if position < len(actual_tokens) else None)
                != (expected_tokens[position] if position < len(expected_tokens) else None)
            )
            actual_token = actual_tokens[index] if index < len(actual_tokens) else None
            expected_token = expected_tokens[index] if index < len(expected_tokens) else None
            differences.append(
                ("TOKEN_DIFF", f"#{index} swift={actual_token} reference={expected_token}", code)
            )
            continue
        if abs(float(actual["relevance"]) - float(expected["relevance"])) > 1e-6:
            differences.append(
                (
                    "RELEVANCE",
                    f"swift={actual['relevance']} reference={expected['relevance']}",
                    code,
                )
            )

    if not differences:
        print(
            f"{arguments.language}: OK ({len(inputs)} inputs, seed {arguments.seed})"
        )
        if reference_eof_units_clipped:
            print(
                "  normalized reference synthetic EOF units: "
                f"{reference_eof_units_clipped}"
            )
        return

    print(
        f"{arguments.language}: {len(differences)} divergence(s) / {len(inputs)} inputs"
    )
    if reference_eof_units_clipped:
        print(
            "  normalized reference synthetic EOF units: "
            f"{reference_eof_units_clipped}"
        )
    for kind, detail, code in differences[:6]:
        print(f"  [{kind}] {detail}")
        print(f"    input={code!r}")
    raise SystemExit(1)


if __name__ == "__main__":
    main()
