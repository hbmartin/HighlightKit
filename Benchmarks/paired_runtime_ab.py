#!/usr/bin/env python3
"""Run a reproducible, interleaved process-level HighlightKit runtime A/B.

The benchmark host reports internally timed seconds with more useful
resolution than its rounded headline metric. This runner reconstructs MU/s or
microseconds/line from those seconds and the exact workload size, while also
retaining every command and stdout line for audit.

The current confidence-interval implementation intentionally supports exactly
15 pairs: its checked Student-t critical value is for 14 degrees of freedom.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import re
import statistics
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SUPPORTED_PAIRS = 15
T_CRITICAL_DF14_975 = 2.1447866879169273

THROUGHPUT_RE = re.compile(
    r"^(?P<language>[^:]+): (?P<units>\d+) utf16 units × "
    r"(?P<runs>\d+) runs in (?P<seconds>\d+\.\d+)s → "
    r"(?P<display>[0-9.]+) MU/s, (?P<checksum>\d+) tokens$"
)
LATENCY_RE = re.compile(
    r"^incremental (?P<language>[^:]+): "
    r"(?P<calls>\d+) line-highlights in (?P<seconds>\d+\.\d+)s → "
    r"(?P<display>[0-9.]+) µs/line, (?P<checksum>\d+) tokens$"
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--baseline",
        required=True,
        type=Path,
        help="frozen production baseline highlight-bench executable",
    )
    parser.add_argument(
        "--candidate",
        required=True,
        type=Path,
        help="frozen production candidate highlight-bench executable",
    )
    parser.add_argument(
        "--swift-input",
        required=True,
        type=Path,
        help="Swift source used by the real-Swift throughput scenario",
    )
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="raw JSON destination (written incrementally)",
    )
    parser.add_argument(
        "--pairs",
        type=int,
        default=SUPPORTED_PAIRS,
        help=f"paired observations per scenario; currently must be {SUPPORTED_PAIRS}",
    )
    parser.add_argument(
        "--campaign",
        default="runtime-ab",
        help="short campaign label stored in the raw output",
    )
    parser.add_argument(
        "--prose-spaces",
        type=int,
        default=8192,
        help=(
            "length of the generated all-space JavaScript comment workload; "
            "use 0 to disable it (default: 8192)"
        ),
    )
    arguments = parser.parse_args()
    if arguments.pairs != SUPPORTED_PAIRS:
        parser.error(
            f"--pairs must be {SUPPORTED_PAIRS}; add the corresponding checked "
            "Student-t critical value before supporting another sample count"
        )
    if arguments.prose_spaces < 0:
        parser.error("--prose-spaces must be non-negative")
    return arguments


def scenarios(
    swift_input: Path,
    prose_input: Path | None,
) -> list[dict[str, Any]]:
    result = [
        {
            "name": "javascript-throughput",
            "kind": "throughput",
            "args": ["7", "javascript"],
        },
        {
            "name": "typescript-throughput",
            "kind": "throughput",
            "args": ["7", "typescript"],
        },
        {
            "name": "swift-real-throughput",
            "kind": "throughput",
            "args": ["7", "swift", str(swift_input)],
        },
        {
            "name": "sql-control-throughput",
            "kind": "throughput",
            "args": ["25", "sql"],
        },
        {
            "name": "javascript-incremental",
            "kind": "latency",
            "args": ["5", "javascript", "--incremental"],
        },
        {
            "name": "swift-incremental",
            "kind": "latency",
            "args": ["5", "swift", "--incremental"],
        },
    ]
    if prose_input is not None:
        result.append(
            {
                "name": "javascript-all-space-comment",
                "kind": "throughput",
                "args": ["1", "javascript", str(prose_input)],
            }
        )
    return result


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def invoke(
    binary: Path,
    scenario: dict[str, Any],
) -> dict[str, Any]:
    command = [str(binary), *scenario["args"]]
    completed = subprocess.run(
        command,
        check=True,
        capture_output=True,
        text=True,
    )
    stdout = completed.stdout.strip()
    stderr = completed.stderr.strip()
    if "\n" in stdout:
        raise RuntimeError(
            f"unexpected multiline stdout for {command!r}: {stdout!r}"
        )

    regex = THROUGHPUT_RE if scenario["kind"] == "throughput" else LATENCY_RE
    match = regex.fullmatch(stdout)
    if match is None:
        raise RuntimeError(f"could not parse stdout for {command!r}: {stdout!r}")

    fields = match.groupdict()
    seconds = float(fields["seconds"])
    if seconds <= 0:
        raise RuntimeError(f"non-positive elapsed time for {command!r}: {seconds}")

    if scenario["kind"] == "throughput":
        value = (
            int(fields["units"])
            * int(fields["runs"])
            / seconds
            / 1_000_000.0
        )
    else:
        value = seconds / int(fields["calls"]) * 1_000_000.0

    return {
        "command": command,
        "stdout": stdout,
        "stderr": stderr,
        "seconds": seconds,
        "value": value,
        "display_value": float(fields["display"]),
        "checksum": int(fields["checksum"]),
        "fields": fields,
    }


def shape_fields(kind: str) -> tuple[str, ...]:
    if kind == "throughput":
        return ("language", "units", "runs")
    return ("language", "calls")


def validate_pair(
    scenario: dict[str, Any],
    pair: dict[str, Any],
) -> None:
    baseline = pair["baseline"]
    candidate = pair["candidate"]
    if baseline["checksum"] != candidate["checksum"]:
        raise RuntimeError(
            f"checksum mismatch in {scenario['name']}: "
            f"{baseline['checksum']} != {candidate['checksum']}"
        )
    for field in shape_fields(scenario["kind"]):
        if baseline["fields"][field] != candidate["fields"][field]:
            raise RuntimeError(
                f"observable-shape mismatch for {field!r} in "
                f"{scenario['name']}: {baseline['fields'][field]!r} != "
                f"{candidate['fields'][field]!r}"
            )


def summarize(
    samples: list[dict[str, Any]],
    kind: str,
) -> dict[str, Any]:
    if len(samples) != SUPPORTED_PAIRS:
        raise ValueError(
            f"expected {SUPPORTED_PAIRS} pairs for the checked t interval; "
            f"received {len(samples)}"
        )
    log_ratios = [
        math.log(sample["candidate"]["value"] / sample["baseline"]["value"])
        for sample in samples
    ]
    mean_log_ratio = statistics.fmean(log_ratios)
    standard_error = statistics.stdev(log_ratios) / math.sqrt(len(log_ratios))
    margin = T_CRITICAL_DF14_975 * standard_error
    ratio = math.exp(mean_log_ratio)
    low = math.exp(mean_log_ratio - margin)
    high = math.exp(mean_log_ratio + margin)

    if kind == "throughput":
        candidate_better_pairs = sum(
            sample["candidate"]["value"] > sample["baseline"]["value"]
            for sample in samples
        )
        direction = "faster" if low > 1.0 else "slower" if high < 1.0 else "neutral"
    else:
        candidate_better_pairs = sum(
            sample["candidate"]["value"] < sample["baseline"]["value"]
            for sample in samples
        )
        direction = "faster" if high < 1.0 else "slower" if low > 1.0 else "neutral"

    return {
        "baseline_median": statistics.median(
            sample["baseline"]["value"] for sample in samples
        ),
        "candidate_median": statistics.median(
            sample["candidate"]["value"] for sample in samples
        ),
        "paired_geometric_mean_ratio_candidate_over_baseline": ratio,
        "ratio_95_percent_ci": [low, high],
        "percent_change": (ratio - 1.0) * 100.0,
        "percent_change_95_percent_ci": [
            (low - 1.0) * 100.0,
            (high - 1.0) * 100.0,
        ],
        "direction": direction,
        "candidate_better_pairs": candidate_better_pairs,
        "log_ratio_mean": mean_log_ratio,
        "log_ratio_standard_error": standard_error,
        "student_t_critical_df14_975": T_CRITICAL_DF14_975,
    }


def write_json(output: Path, data: dict[str, Any]) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(f".{output.name}.tmp")
    temporary.write_text(
        json.dumps(data, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, output)


def validate_inputs(
    baseline: Path,
    candidate: Path,
    swift_input: Path,
    prose_input: Path | None,
) -> None:
    for binary in (baseline, candidate):
        if not binary.is_file():
            raise FileNotFoundError(binary)
        if not os.access(binary, os.X_OK):
            raise PermissionError(f"benchmark host is not executable: {binary}")
    if not swift_input.is_file():
        raise FileNotFoundError(swift_input)
    if prose_input is not None and not prose_input.is_file():
        raise FileNotFoundError(prose_input)


def write_generated_prose_input(
    output: Path,
    space_count: int,
) -> Path | None:
    if space_count == 0:
        return None
    path = output.with_name(f"{output.stem}.prose-{space_count}.js")
    if path == output:
        raise ValueError("generated prose input would overwrite --output")
    path.parent.mkdir(parents=True, exist_ok=True)
    content = "//" + (" " * space_count)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(content, encoding="utf-8", newline="")
    os.replace(temporary, path)
    return path


def main() -> None:
    arguments = parse_arguments()
    baseline = arguments.baseline.expanduser().resolve()
    candidate = arguments.candidate.expanduser().resolve()
    swift_input = arguments.swift_input.expanduser().resolve()
    output = arguments.output.expanduser().resolve()
    prose_input = write_generated_prose_input(output, arguments.prose_spaces)
    validate_inputs(baseline, candidate, swift_input, prose_input)
    protected_inputs = {baseline, candidate, swift_input}
    if prose_input is not None:
        protected_inputs.add(prose_input)
    if output in protected_inputs:
        raise ValueError("--output must not overwrite an executable or input")

    benchmark_scenarios = scenarios(swift_input, prose_input)
    paths = {
        "baseline": str(baseline),
        "candidate": str(candidate),
        "swift_input": str(swift_input),
    }
    if prose_input is not None:
        paths["generated_prose_input"] = str(prose_input)
    hashes_before = {
        "baseline": sha256(baseline),
        "candidate": sha256(candidate),
        "swift_input": sha256(swift_input),
    }
    if prose_input is not None:
        hashes_before["generated_prose_input"] = sha256(prose_input)
    if hashes_before["baseline"] == hashes_before["candidate"]:
        raise ValueError("baseline and candidate executables are byte-identical")

    uname = platform.uname()
    data: dict[str, Any] = {
        "schema_version": 1,
        "campaign": arguments.campaign,
        "started_at_utc": datetime.now(timezone.utc).isoformat(),
        "platform": {
            "system": uname.system,
            "release": uname.release,
            "machine": uname.machine,
        },
        "paths": paths,
        "method": {
            "pairs": arguments.pairs,
            "process_order": (
                "even pair index baseline->candidate; "
                "odd pair index candidate->baseline"
            ),
            "scenario_order": (
                f"{len(benchmark_scenarios)} scenarios round-robin within every pair"
            ),
            "warmup": (
                "each scenario once per binary, alternating the binary-first "
                "order by scenario index"
            ),
            "ratio": "candidate/baseline; exp(mean(log(pair ratio)))",
            "ci": (
                "Student-t df=14 in the log domain, then exponentiated; "
                "t(0.975,14)=2.1447866879169273"
            ),
            "timing_source": (
                "benchmark-internal elapsed seconds reconstructed into "
                "MU/s or microseconds/line"
            ),
            "exclusions": "none; all completed observations are retained",
            "generated_prose_workload": (
                None
                if prose_input is None
                else {
                    "prefix": "//",
                    "space_count": arguments.prose_spaces,
                    "terminal_newline": False,
                }
            ),
        },
        "hashes_before": hashes_before,
        "scenarios": {},
    }
    write_json(output, data)

    # These separate processes warm OS caches and establish thermal conditions;
    # each benchmark host performs its own grammar warm-up before timed work.
    warmups_by_scenario: dict[str, dict[str, Any]] = {}
    for scenario_index, scenario in enumerate(benchmark_scenarios):
        order = [("baseline", baseline), ("candidate", candidate)]
        if scenario_index % 2:
            order.reverse()
        warmup_pair: dict[str, Any] = {
            "process_order": [label for label, _ in order]
        }
        for label, binary in order:
            result = invoke(binary, scenario)
            warmup_pair[label] = result
            print(
                f"warmup {scenario['name']} {label}: {result['stdout']}",
                flush=True,
            )
        validate_pair(scenario, warmup_pair)
        warmups_by_scenario[scenario["name"]] = warmup_pair
    data["warmups"] = warmups_by_scenario
    write_json(output, data)

    for scenario in benchmark_scenarios:
        data["scenarios"][scenario["name"]] = {
            "kind": scenario["kind"],
            "args": scenario["args"],
            "samples": [],
        }

    for pair_index in range(arguments.pairs):
        for scenario in benchmark_scenarios:
            order = [("baseline", baseline), ("candidate", candidate)]
            if pair_index % 2:
                order.reverse()
            pair: dict[str, Any] = {
                "pair_index": pair_index,
                "process_order": [label for label, _ in order],
            }
            for label, binary in order:
                result = invoke(binary, scenario)
                pair[label] = result
                print(
                    f"pair {pair_index + 1:02d}/{arguments.pairs} "
                    f"{scenario['name']} {label}: {result['stdout']}",
                    flush=True,
                )
            validate_pair(scenario, pair)
            data["scenarios"][scenario["name"]]["samples"].append(pair)
            write_json(output, data)

    for scenario in benchmark_scenarios:
        entry = data["scenarios"][scenario["name"]]
        entry["summary"] = summarize(entry["samples"], scenario["kind"])

    hashes_after = {
        "baseline": sha256(baseline),
        "candidate": sha256(candidate),
        "swift_input": sha256(swift_input),
    }
    if prose_input is not None:
        hashes_after["generated_prose_input"] = sha256(prose_input)
    data["hashes_after"] = hashes_after
    data["hashes_stable"] = hashes_before == hashes_after
    data["completed_at_utc"] = datetime.now(timezone.utc).isoformat()
    write_json(output, data)
    if not data["hashes_stable"]:
        raise RuntimeError(
            "a benchmark executable or the Swift input changed during the "
            "campaign; all results are invalid"
        )

    summaries = {
        name: entry["summary"] for name, entry in data["scenarios"].items()
    }
    print(json.dumps(summaries, indent=2), flush=True)


if __name__ == "__main__":
    main()
