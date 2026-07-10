#!/usr/bin/env python3
"""Run an interleaved process-level A/B of HighlightKit's registry paths.

All scenarios are latency measurements, so candidate/baseline ratios below one
are improvements. The contention scenarios also treat descriptor build counts
as correctness invariants: warm caches build exactly once, and cold candidate
caches build exactly once per round.

The checked confidence-interval implementation intentionally supports exactly
15 pairs. Its Student-t critical value is specific to 14 degrees of freedom.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
import platform
import statistics
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SUPPORTED_PAIRS = 15
T_CRITICAL_DF14_975 = 2.1447866879169273
AUTO_LANGUAGE_COUNT = 64


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
        default="registry-generation-ab",
        help="short campaign label stored in the raw output",
    )
    arguments = parser.parse_args()
    if arguments.pairs != SUPPORTED_PAIRS:
        parser.error(
            f"--pairs must be {SUPPORTED_PAIRS}; add the corresponding checked "
            "Student-t critical value before supporting another sample count"
        )
    return arguments


def registry_scenarios() -> list[dict[str, Any]]:
    scenarios: list[dict[str, Any]] = [
        {
            "name": "warm-highlight",
            "arguments": [
                "--registry-bench",
                "warm-highlight",
                "200000",
            ],
            "iterations": 200_000,
            "value_unit": "ns/op",
        },
        {
            "name": "auto-warm",
            "arguments": [
                "--registry-bench",
                "auto-warm",
                "500",
            ],
            "iterations": 500,
            "language_count": AUTO_LANGUAGE_COUNT,
            "value_unit": "ns/op",
        },
        {
            "name": "cold-contention",
            "arguments": [
                "--registry-bench",
                "cold-contention",
                "16",
                "3",
            ],
            "task_count": 16,
            "rounds": 3,
            "value_unit": "ns/round",
        },
    ]
    for task_count in (1, 8, 32):
        scenarios.append(
            {
                "name": f"warm-contention-{task_count}",
                "csv_name": "warm-contention",
                "arguments": [
                    "--registry-bench",
                    "warm-contention",
                    str(task_count),
                    "200000",
                ],
                "task_count": task_count,
                "operation_count": 200_000,
                "value_unit": "ns/op",
            }
        )
    return scenarios


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_integer(field: str, label: str) -> int:
    try:
        value = int(field)
    except ValueError as error:
        raise RuntimeError(f"invalid {label} field: {field!r}") from error
    if value < 0:
        raise RuntimeError(f"negative {label} field: {value}")
    return value


def parse_value(field: str) -> float:
    try:
        value = float(field)
    except ValueError as error:
        raise RuntimeError(f"invalid latency field: {field!r}") from error
    if not math.isfinite(value) or value <= 0:
        raise RuntimeError(f"latency must be finite and positive: {value!r}")
    return value


def parse_registry_output(
    stdout: str,
    scenario: dict[str, Any],
) -> dict[str, Any]:
    try:
        fields = next(csv.reader([stdout], strict=True))
    except (csv.Error, StopIteration) as error:
        raise RuntimeError(f"invalid registry CSV: {stdout!r}") from error

    name = scenario["name"]
    csv_name = scenario.get("csv_name", name)
    expected_field_count = (
        7 if csv_name in ("cold-contention", "warm-contention") else 6
    )
    if len(fields) != expected_field_count:
        raise RuntimeError(
            f"{name} emitted {len(fields)} CSV fields; "
            f"expected {expected_field_count}: {stdout!r}"
        )
    if fields[0] != "registry-bench" or fields[1] != csv_name:
        raise RuntimeError(
            f"unexpected registry scenario header for {name}: {fields[:2]!r}"
        )

    if csv_name == "warm-highlight":
        iterations = parse_integer(fields[2], "iterations")
        if iterations != scenario["iterations"]:
            raise RuntimeError(
                f"warm-highlight iterations changed: {iterations} != "
                f"{scenario['iterations']}"
            )
        return {
            "scenario": name,
            "iterations": iterations,
            "value": parse_value(fields[3]),
            "value_unit": scenario["value_unit"],
            "build_count": parse_integer(fields[4], "build count"),
            "checksum": parse_integer(fields[5], "checksum"),
        }

    if csv_name == "auto-warm":
        iterations = parse_integer(fields[2], "iterations")
        language_count = parse_integer(fields[4], "language count")
        if iterations != scenario["iterations"]:
            raise RuntimeError(
                f"auto-warm iterations changed: {iterations} != "
                f"{scenario['iterations']}"
            )
        if language_count != scenario["language_count"]:
            raise RuntimeError(
                f"auto-warm language count changed: {language_count} != "
                f"{scenario['language_count']}"
            )
        return {
            "scenario": name,
            "iterations": iterations,
            "value": parse_value(fields[3]),
            "value_unit": scenario["value_unit"],
            "language_count": language_count,
            "checksum": parse_integer(fields[5], "checksum"),
        }

    if csv_name == "warm-contention":
        task_count = parse_integer(fields[2], "task count")
        operation_count = parse_integer(fields[3], "operation count")
        if task_count != scenario["task_count"]:
            raise RuntimeError(
                f"{name} task count changed: {task_count} != "
                f"{scenario['task_count']}"
            )
        if operation_count != scenario["operation_count"]:
            raise RuntimeError(
                f"{name} operation count changed: {operation_count} != "
                f"{scenario['operation_count']}"
            )
        return {
            "scenario": name,
            "task_count": task_count,
            "operation_count": operation_count,
            "value": parse_value(fields[4]),
            "value_unit": scenario["value_unit"],
            "build_count": parse_integer(fields[5], "build count"),
            "checksum": parse_integer(fields[6], "checksum"),
        }

    if csv_name == "cold-contention":
        task_count = parse_integer(fields[2], "task count")
        rounds = parse_integer(fields[3], "rounds")
        if task_count != scenario["task_count"]:
            raise RuntimeError(
                f"cold-contention task count changed: {task_count} != "
                f"{scenario['task_count']}"
            )
        if rounds != scenario["rounds"]:
            raise RuntimeError(
                f"cold-contention rounds changed: {rounds} != "
                f"{scenario['rounds']}"
            )
        return {
            "scenario": name,
            "task_count": task_count,
            "rounds": rounds,
            "value": parse_value(fields[4]),
            "value_unit": scenario["value_unit"],
            "build_count": parse_integer(fields[5], "build count"),
            "checksum": parse_integer(fields[6], "checksum"),
        }

    raise RuntimeError(f"unsupported registry scenario: {name!r}")


def invoke(
    binary: Path,
    scenario: dict[str, Any],
) -> dict[str, Any]:
    command = [str(binary), *scenario["arguments"]]
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

    result = parse_registry_output(stdout, scenario)
    result.update(
        {
            "command": command,
            "stdout": stdout,
            "stderr": stderr,
        }
    )
    return result


def expected_checksum(scenario: dict[str, Any]) -> int:
    name = scenario.get("csv_name", scenario["name"])
    if name == "warm-highlight":
        return scenario["iterations"]
    if name == "auto-warm":
        # One token plus relevance 1 is accumulated per auto-detection.
        return scenario["iterations"] * 2
    if name == "warm-contention":
        return scenario["operation_count"]
    return scenario["task_count"] * scenario["rounds"]


def validate_pair(
    scenario: dict[str, Any],
    pair: dict[str, Any],
    context: str,
) -> None:
    baseline = pair["baseline"]
    candidate = pair["candidate"]
    checksum = expected_checksum(scenario)
    if baseline["checksum"] != checksum or candidate["checksum"] != checksum:
        raise RuntimeError(
            f"{context} checksum mismatch: expected {checksum}, got "
            f"baseline={baseline['checksum']}, candidate={candidate['checksum']}"
        )
    if baseline["scenario"] != candidate["scenario"]:
        raise RuntimeError(
            f"{context} scenario mismatch: {baseline['scenario']!r} != "
            f"{candidate['scenario']!r}"
        )
    if baseline["value_unit"] != candidate["value_unit"]:
        raise RuntimeError(
            f"{context} unit mismatch: {baseline['value_unit']!r} != "
            f"{candidate['value_unit']!r}"
        )

    name = scenario.get("csv_name", scenario["name"])
    if name == "warm-highlight":
        if baseline["iterations"] != candidate["iterations"]:
            raise RuntimeError(f"{context} iteration fields differ")
        if baseline["build_count"] != 1 or candidate["build_count"] != 1:
            raise RuntimeError(
                f"{context} warm build count must be one: "
                f"baseline={baseline['build_count']}, "
                f"candidate={candidate['build_count']}"
            )
        return

    if name == "auto-warm":
        if baseline["iterations"] != candidate["iterations"]:
            raise RuntimeError(f"{context} iteration fields differ")
        if baseline["language_count"] != candidate["language_count"]:
            raise RuntimeError(f"{context} language-count fields differ")
        return

    if name == "warm-contention":
        if baseline["task_count"] != candidate["task_count"]:
            raise RuntimeError(f"{context} task-count fields differ")
        if baseline["operation_count"] != candidate["operation_count"]:
            raise RuntimeError(f"{context} operation-count fields differ")
        if baseline["build_count"] != 1 or candidate["build_count"] != 1:
            raise RuntimeError(
                f"{context} warm-contention build count must be one: "
                f"baseline={baseline['build_count']}, "
                f"candidate={candidate['build_count']}"
            )
        return

    if baseline["task_count"] != candidate["task_count"]:
        raise RuntimeError(f"{context} task-count fields differ")
    if baseline["rounds"] != candidate["rounds"]:
        raise RuntimeError(f"{context} round fields differ")

    rounds = scenario["rounds"]
    maximum_builds = rounds * scenario["task_count"]
    if not rounds <= baseline["build_count"] <= maximum_builds:
        raise RuntimeError(
            f"{context} baseline build count is outside [{rounds}, "
            f"{maximum_builds}]: {baseline['build_count']}"
        )
    if candidate["build_count"] != rounds:
        raise RuntimeError(
            f"{context} candidate built {candidate['build_count']} times; "
            f"required exactly one build per round ({rounds})"
        )


def summarize(
    samples: list[dict[str, Any]],
    scenario: dict[str, Any],
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

    if high < 1.0:
        direction = "faster"
    elif low > 1.0:
        direction = "slower"
    else:
        direction = "neutral"

    summary: dict[str, Any] = {
        "value_unit": scenario["value_unit"],
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
        "candidate_better_pairs": sum(
            sample["candidate"]["value"] < sample["baseline"]["value"]
            for sample in samples
        ),
        "log_ratio_mean": mean_log_ratio,
        "log_ratio_standard_error": standard_error,
        "student_t_critical_df14_975": T_CRITICAL_DF14_975,
    }

    if "build_count" in samples[0]["baseline"]:
        baseline_builds = [
            sample["baseline"]["build_count"] for sample in samples
        ]
        candidate_builds = [
            sample["candidate"]["build_count"] for sample in samples
        ]
        summary["build_counts"] = {
            "baseline": baseline_builds,
            "candidate": candidate_builds,
            "baseline_total": sum(baseline_builds),
            "candidate_total": sum(candidate_builds),
            "baseline_range": [min(baseline_builds), max(baseline_builds)],
            "candidate_range": [min(candidate_builds), max(candidate_builds)],
        }
    return summary


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
) -> None:
    for binary in (baseline, candidate):
        if not binary.is_file():
            raise FileNotFoundError(binary)
        if not os.access(binary, os.X_OK):
            raise PermissionError(f"benchmark host is not executable: {binary}")


def main() -> None:
    arguments = parse_arguments()
    baseline = arguments.baseline.expanduser().resolve()
    candidate = arguments.candidate.expanduser().resolve()
    output = arguments.output.expanduser().resolve()
    validate_inputs(baseline, candidate)
    if output in (baseline, candidate):
        raise ValueError("--output must not overwrite a benchmark executable")

    hashes_before = {
        "baseline": sha256(baseline),
        "candidate": sha256(candidate),
    }
    if hashes_before["baseline"] == hashes_before["candidate"]:
        raise ValueError("baseline and candidate executables are byte-identical")

    scenarios = registry_scenarios()
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
        "paths": {
            "baseline": str(baseline),
            "candidate": str(candidate),
        },
        "method": {
            "pairs": arguments.pairs,
            "process_order": (
                "even pair index baseline->candidate; "
                "odd pair index candidate->baseline"
            ),
            "scenario_order": "six scenarios round-robin within every pair",
            "warmup": (
                "each scenario once per binary, alternating the binary-first "
                "order by scenario index"
            ),
            "ratio": "candidate/baseline; exp(mean(log(pair ratio)))",
            "ci": (
                "Student-t df=14 in the log domain, then exponentiated; "
                "t(0.975,14)=2.1447866879169273"
            ),
            "direction": "all values are latency; lower is better",
            "cold_correctness": (
                "candidate build_count must equal rounds; baseline build_count "
                "is retained and may exceed rounds"
            ),
            "warm_contention_correctness": (
                "build_count must equal one and checksum must equal the shared "
                "operation count on both sides"
            ),
            "exclusions": "none; all completed observations are retained",
        },
        "hashes_before": hashes_before,
        "scenario_definitions": scenarios,
        "warmups": {},
        "scenarios": {
            scenario["name"]: {
                "definition": scenario,
                "samples": [],
            }
            for scenario in scenarios
        },
    }
    write_json(output, data)

    for scenario_index, scenario in enumerate(scenarios):
        order = [("baseline", baseline), ("candidate", candidate)]
        if scenario_index % 2:
            order.reverse()
        warmup: dict[str, Any] = {
            "process_order": [label for label, _ in order]
        }
        for label, binary in order:
            result = invoke(binary, scenario)
            warmup[label] = result
            print(
                f"warmup {scenario['name']} {label}: {result['stdout']}",
                flush=True,
            )
        data["warmups"][scenario["name"]] = warmup
        write_json(output, data)
        validate_pair(scenario, warmup, f"{scenario['name']} warmup")

    for pair_index in range(arguments.pairs):
        for scenario in scenarios:
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
            data["scenarios"][scenario["name"]]["samples"].append(pair)
            write_json(output, data)
            validate_pair(
                scenario,
                pair,
                f"{scenario['name']} pair {pair_index + 1}",
            )

    for scenario in scenarios:
        entry = data["scenarios"][scenario["name"]]
        entry["summary"] = summarize(entry["samples"], scenario)

    hashes_after = {
        "baseline": sha256(baseline),
        "candidate": sha256(candidate),
    }
    data["hashes_after"] = hashes_after
    data["hashes_stable"] = hashes_before == hashes_after
    data["completed_at_utc"] = datetime.now(timezone.utc).isoformat()
    write_json(output, data)
    if not data["hashes_stable"]:
        raise RuntimeError(
            "a benchmark executable changed during the campaign; "
            "all results are invalid"
        )

    summaries = {
        name: entry["summary"] for name, entry in data["scenarios"].items()
    }
    print(json.dumps(summaries, indent=2), flush=True)


if __name__ == "__main__":
    main()
