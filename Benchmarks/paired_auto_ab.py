#!/usr/bin/env python3
"""Run a reproducible process-level A/B of async language auto-detection.

The benchmark host emits one strict JSON record per invocation. This runner
alternates process order, validates every observable result field, retains all
raw observations, and reports a paired log-domain 95% confidence interval.

The checked confidence-interval implementation intentionally supports exactly
15 pairs: its Student-t critical value is specific to 14 degrees of freedom.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import statistics
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SUPPORTED_PAIRS = 15
T_CRITICAL_DF14_975 = 2.1447866879169273
RECORD_KEYS = {
    "schema_version",
    "benchmark",
    "scenario",
    "iterations",
    "utf16_units",
    "language_count",
    "total_elapsed_seconds",
    "nanoseconds_per_operation",
    "input_checksum",
    "semantic_checksum",
    "result_checksum",
    "detected_language",
    "relevance",
    "token_count",
}
OBSERVABLE_KEYS = (
    "schema_version",
    "benchmark",
    "scenario",
    "iterations",
    "utf16_units",
    "language_count",
    "input_checksum",
    "semantic_checksum",
    "result_checksum",
    "detected_language",
    "relevance",
    "token_count",
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
        "--output",
        required=True,
        type=Path,
        help="raw JSON destination (written atomically after every pair)",
    )
    parser.add_argument(
        "--input",
        type=Path,
        help="optional UTF-8 input; both hosts use their built-in paste sample if omitted",
    )
    parser.add_argument(
        "--cold-iterations",
        type=int,
        default=1,
        help="fresh Highlighter/grammar-compilation operations per process (default: 1)",
    )
    parser.add_argument(
        "--warm-iterations",
        type=int,
        default=10,
        help="timed operations after one excluded async warm-up (default: 10)",
    )
    parser.add_argument(
        "--pairs",
        type=int,
        default=SUPPORTED_PAIRS,
        help=f"paired observations per scenario; must be {SUPPORTED_PAIRS}",
    )
    parser.add_argument(
        "--campaign",
        default="async-auto-detection-ab",
        help="short campaign label stored in the raw output",
    )
    arguments = parser.parse_args()
    if arguments.pairs != SUPPORTED_PAIRS:
        parser.error(
            f"--pairs must be {SUPPORTED_PAIRS}; add the corresponding "
            "checked Student-t critical value before supporting another count"
        )
    if arguments.cold_iterations <= 0 or arguments.warm_iterations <= 0:
        parser.error("iteration counts must be positive")
    return arguments


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def scenarios(arguments: argparse.Namespace) -> list[dict[str, Any]]:
    return [
        {
            "name": "cold",
            "iterations": arguments.cold_iterations,
            "value_unit": "ns/op",
        },
        {
            "name": "warm",
            "iterations": arguments.warm_iterations,
            "value_unit": "ns/op",
        },
    ]


def parse_record(stdout: str, expected: dict[str, Any]) -> dict[str, Any]:
    try:
        record = json.loads(stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"invalid auto-benchmark JSON: {stdout!r}") from error
    if not isinstance(record, dict):
        raise RuntimeError(f"auto-benchmark record is not an object: {record!r}")
    if set(record) != RECORD_KEYS:
        raise RuntimeError(
            "auto-benchmark schema mismatch: "
            f"missing={sorted(RECORD_KEYS - set(record))!r}, "
            f"extra={sorted(set(record) - RECORD_KEYS)!r}"
        )
    if record["schema_version"] != 1:
        raise RuntimeError(f"unsupported host schema: {record['schema_version']!r}")
    if record["benchmark"] != "async-auto-detect":
        raise RuntimeError(f"unexpected benchmark: {record['benchmark']!r}")
    if record["scenario"] != expected["name"]:
        raise RuntimeError(
            f"scenario changed: {record['scenario']!r} != {expected['name']!r}"
        )
    if record["iterations"] != expected["iterations"]:
        raise RuntimeError(
            f"iterations changed: {record['iterations']!r} != "
            f"{expected['iterations']!r}"
        )

    for key in ("utf16_units", "language_count", "token_count"):
        if not isinstance(record[key], int) or record[key] < 0:
            raise RuntimeError(f"{key} must be a non-negative integer: {record[key]!r}")
    if record["utf16_units"] == 0 or record["language_count"] == 0:
        raise RuntimeError("the auto-detection workload and registry must be non-empty")
    for key in ("input_checksum", "semantic_checksum", "result_checksum"):
        value = record[key]
        if (
            not isinstance(value, str)
            or len(value) != 16
            or any(character not in "0123456789abcdef" for character in value)
        ):
            raise RuntimeError(f"{key} is not a lowercase 64-bit hex value: {value!r}")
    if record["detected_language"] is not None and not isinstance(
        record["detected_language"], str
    ):
        raise RuntimeError("detected_language must be a string or null")

    elapsed = record["total_elapsed_seconds"]
    reported_value = record["nanoseconds_per_operation"]
    relevance = record["relevance"]
    for label, value in (
        ("total_elapsed_seconds", elapsed),
        ("nanoseconds_per_operation", reported_value),
        ("relevance", relevance),
    ):
        if not isinstance(value, (int, float)) or not math.isfinite(value):
            raise RuntimeError(f"{label} must be finite: {value!r}")
    if elapsed <= 0 or reported_value <= 0:
        raise RuntimeError("elapsed time and latency must be positive")
    reconstructed = elapsed / record["iterations"] * 1_000_000_000.0
    if not math.isclose(reported_value, reconstructed, rel_tol=1e-12, abs_tol=1e-6):
        raise RuntimeError(
            f"host latency is inconsistent: {reported_value!r} != {reconstructed!r}"
        )
    record["value"] = reconstructed
    record["value_unit"] = expected["value_unit"]
    return record


def invoke(
    binary: Path,
    scenario: dict[str, Any],
    input_path: Path | None,
) -> dict[str, Any]:
    command = [
        str(binary),
        "--auto-bench",
        scenario["name"],
        str(scenario["iterations"]),
    ]
    if input_path is not None:
        command.append(str(input_path))
    wall_start = time.perf_counter()
    completed = subprocess.run(
        command,
        check=True,
        capture_output=True,
        text=True,
    )
    wall_seconds = time.perf_counter() - wall_start
    stdout = completed.stdout.strip()
    stderr = completed.stderr.strip()
    if "\n" in stdout:
        raise RuntimeError(f"unexpected multiline stdout for {command!r}: {stdout!r}")
    return {
        "command": command,
        "stdout": stdout,
        "stderr": stderr,
        "process_wall_seconds": wall_seconds,
        "record": parse_record(stdout, scenario),
    }


def validate_pair(scenario: dict[str, Any], pair: dict[str, Any]) -> None:
    baseline = pair["baseline"]["record"]
    candidate = pair["candidate"]["record"]
    for key in OBSERVABLE_KEYS:
        if baseline[key] != candidate[key]:
            raise RuntimeError(
                f"observable mismatch for {key!r} in {scenario['name']}: "
                f"{baseline[key]!r} != {candidate[key]!r}"
            )


def summarize(samples: list[dict[str, Any]]) -> dict[str, Any]:
    if len(samples) != SUPPORTED_PAIRS:
        raise ValueError(f"expected {SUPPORTED_PAIRS} paired observations")
    baseline_values = [sample["baseline"]["record"]["value"] for sample in samples]
    candidate_values = [sample["candidate"]["record"]["value"] for sample in samples]
    log_ratios = [
        math.log(candidate / baseline)
        for baseline, candidate in zip(baseline_values, candidate_values, strict=True)
    ]
    mean_log_ratio = statistics.fmean(log_ratios)
    standard_error = statistics.stdev(log_ratios) / math.sqrt(len(log_ratios))
    margin = T_CRITICAL_DF14_975 * standard_error
    ratio = math.exp(mean_log_ratio)
    low = math.exp(mean_log_ratio - margin)
    high = math.exp(mean_log_ratio + margin)
    return {
        "baseline_median_ns_per_operation": statistics.median(baseline_values),
        "candidate_median_ns_per_operation": statistics.median(candidate_values),
        "paired_geometric_mean_ratio_candidate_over_baseline": ratio,
        "ratio_95_percent_ci": [low, high],
        "percent_change": (ratio - 1.0) * 100.0,
        "percent_change_95_percent_ci": [
            (low - 1.0) * 100.0,
            (high - 1.0) * 100.0,
        ],
        "direction": ("faster" if high < 1.0 else "slower" if low > 1.0 else "neutral"),
        "candidate_better_pairs": sum(
            candidate < baseline
            for baseline, candidate in zip(
                baseline_values, candidate_values, strict=True
            )
        ),
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
    output: Path,
    input_path: Path | None,
) -> None:
    for binary in (baseline, candidate):
        if not binary.is_file():
            raise FileNotFoundError(binary)
        if not os.access(binary, os.X_OK):
            raise PermissionError(f"benchmark host is not executable: {binary}")
    if input_path is not None and not input_path.is_file():
        raise FileNotFoundError(input_path)
    protected = {baseline, candidate}
    if input_path is not None:
        protected.add(input_path)
    if output in protected:
        raise ValueError("--output must not overwrite an executable or input")


def main() -> None:
    arguments = parse_arguments()
    baseline = arguments.baseline.expanduser().resolve()
    candidate = arguments.candidate.expanduser().resolve()
    output = arguments.output.expanduser().resolve()
    input_path = (
        arguments.input.expanduser().resolve() if arguments.input is not None else None
    )
    validate_inputs(baseline, candidate, output, input_path)

    paths = {
        "baseline": str(baseline),
        "candidate": str(candidate),
        "input": str(input_path) if input_path is not None else None,
    }
    hashes_before = {
        "baseline": sha256(baseline),
        "candidate": sha256(candidate),
        "input": sha256(input_path) if input_path is not None else None,
    }
    if hashes_before["baseline"] == hashes_before["candidate"]:
        raise ValueError("baseline and candidate executables are byte-identical")

    benchmark_scenarios = scenarios(arguments)
    uname = platform.uname()
    data: dict[str, Any] = {
        "schema_version": 1,
        "campaign": arguments.campaign,
        "started_at_utc": datetime.now(timezone.utc).isoformat(),
        "environment": {
            "system": uname.system,
            "release": uname.release,
            "version": uname.version,
            "machine": uname.machine,
            "processor": uname.processor,
            "platform": platform.platform(),
            "python_implementation": platform.python_implementation(),
            "python_version": platform.python_version(),
            "logical_cpu_count": os.cpu_count(),
            "runner_pid": os.getpid(),
            "working_directory": os.getcwd(),
        },
        "paths": paths,
        "hashes_before": hashes_before,
        "method": {
            "pairs": arguments.pairs,
            "scenario_order": (
                "cold->warm on even pair indices; warm->cold on odd indices"
            ),
            "process_order": (
                "alternated by pair plus scenario index so each binary runs "
                "first equally often"
            ),
            "warmup": "one excluded process per scenario and binary",
            "cold_definition": (
                "each timed operation creates a fresh Highlighter and compiles "
                "the grammars required by async auto-detection"
            ),
            "warm_definition": (
                "one dedicated Highlighter per process; one async auto-detect "
                "warm-up is excluded before timed operations"
            ),
            "timing_source": "ContinuousClock inside the benchmark host",
            "ratio": "candidate/baseline; exp(mean(log(pair ratio)))",
            "ci": (
                "Student-t df=14 in the log domain, then exponentiated; "
                "t(0.975,14)=2.1447866879169273"
            ),
            "exclusions": "none; all completed observations are retained",
        },
        "warmups": {},
        "scenarios": {
            scenario["name"]: {
                "iterations": scenario["iterations"],
                "value_unit": scenario["value_unit"],
                "samples": [],
            }
            for scenario in benchmark_scenarios
        },
    }
    write_json(output, data)

    for scenario_index, scenario in enumerate(benchmark_scenarios):
        order = [("baseline", baseline), ("candidate", candidate)]
        if scenario_index % 2:
            order.reverse()
        pair: dict[str, Any] = {
            "process_order": [label for label, _ in order],
        }
        for label, binary in order:
            pair[label] = invoke(binary, scenario, input_path)
            print(
                f"warmup {scenario['name']} {label}: "
                f"{pair[label]['record']['value']:.3f} ns/op",
                flush=True,
            )
        validate_pair(scenario, pair)
        data["warmups"][scenario["name"]] = pair
        write_json(output, data)

    for pair_index in range(arguments.pairs):
        ordered_scenarios = (
            benchmark_scenarios
            if pair_index % 2 == 0
            else list(reversed(benchmark_scenarios))
        )
        for scenario in ordered_scenarios:
            scenario_index = 0 if scenario["name"] == "cold" else 1
            order = [("baseline", baseline), ("candidate", candidate)]
            if (pair_index + scenario_index) % 2:
                order.reverse()
            pair = {
                "pair_index": pair_index,
                "process_order": [label for label, _ in order],
            }
            for label, binary in order:
                pair[label] = invoke(binary, scenario, input_path)
                print(
                    f"pair {pair_index + 1:02d}/{arguments.pairs} "
                    f"{scenario['name']} {label}: "
                    f"{pair[label]['record']['value']:.3f} ns/op",
                    flush=True,
                )
            validate_pair(scenario, pair)
            data["scenarios"][scenario["name"]]["samples"].append(pair)
            write_json(output, data)

    for scenario in benchmark_scenarios:
        entry = data["scenarios"][scenario["name"]]
        entry["summary"] = summarize(entry["samples"])

    hashes_after = {
        "baseline": sha256(baseline),
        "candidate": sha256(candidate),
        "input": sha256(input_path) if input_path is not None else None,
    }
    data["hashes_after"] = hashes_after
    data["hashes_stable"] = hashes_before == hashes_after
    data["completed_at_utc"] = datetime.now(timezone.utc).isoformat()
    write_json(output, data)
    if not data["hashes_stable"]:
        raise RuntimeError("a benchmark executable or input changed during sampling")

    summaries = {name: entry["summary"] for name, entry in data["scenarios"].items()}
    print(json.dumps(summaries, indent=2), flush=True)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("interrupted", file=sys.stderr)
        raise SystemExit(130)
