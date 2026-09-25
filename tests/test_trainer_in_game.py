"""Exercise Gorilla Grip Trainer against the controlled ANGULAR MOMENTUM replay.

This integration check needs Trackmania, TICK, and GorillaGripLogger running.
It reads only fresh Openplanet log lines produced by its own TICK replay.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


LOG = Path.home() / "OpenplanetNext" / "Openplanet.log"
SNAPSHOT = re.compile(
    r"Gorilla Grip Trainer snapshot at (\d+)ms: exact true, "
    r"mode ([012]), steer ([+-]?[0-9.]+), contacts ([01]{4}), "
    r"modeAt (\d+), clock (\d+), delay (\d+)"
)
PREVIEW = re.compile(r"Gorilla Grip Trainer preview at (\d+)ms: ([SABCD]) lead (\d+)-(\d+)ms")
VERDICT = re.compile(r"Gorilla Grip Trainer verdict at (\d+)ms: ([SABCD]|MISSED)")
LANDING = re.compile(r"Gorilla Grip Trainer landing at (\d+)ms:")


def trial_log(research_root: Path, variant: str) -> str:
    offset = LOG.stat().st_size
    completed = subprocess.run(
        [sys.executable, str(research_root / "work" / "auto_trials.py"), variant],
        cwd=research_root,
        capture_output=True,
        text=True,
        timeout=180,
        check=False,
    )
    assert completed.returncode == 0, (
        f"TICK {variant} failed:\n{completed.stdout}\n{completed.stderr}"
    )
    with LOG.open("rb") as handle:
        handle.seek(offset)
        return handle.read().decode("utf-8", "replace")


def assert_exact_takeoff_snapshot(log: str) -> None:
    matches = [
        match
        for match in SNAPSHOT.finditer(log)
        if 11100 <= int(match.group(1)) <= 11400
    ]
    assert matches, "No exact Trainer physics snapshot near target takeoff"
    assert any(match.group(4) == "0000" for match in matches), (
        "Trainer did not observe all-wheel airtime at target takeoff"
    )
    assert any(
        match.group(4) == "0000"
        and match.group(2) == "2"
        and float(match.group(3)) > 0.1
        for match in matches
    ), "Successful +13 reversal did not commit right mode before all-air"
    assert all(int(match.group(7)) == 400 for match in matches), (
        "Trainer read the wrong recovery delay on the tested build"
    )
    assert any(
        match.group(4) == "0000"
        and 0 <= int(match.group(6)) - int(match.group(5)) <= 1000
        for match in matches
    ), "Mode-change timestamp does not share the reported game clock"


def target_events(log: str) -> tuple[list[re.Match[str]], list[re.Match[str]]]:
    previews = [
        match for match in PREVIEW.finditer(log)
        if 11300 <= int(match.group(1)) <= 11600
    ]
    verdicts = [
        match for match in VERDICT.finditer(log)
        if 12550 <= int(match.group(1)) <= 12800
    ]
    return previews, verdicts


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--research-root", required=True, type=Path)
    parser.add_argument("--physics-only", action="store_true")
    parser.add_argument(
        "--case", choices=["plus13", "plus12", "same", "no-presteer", "all"],
        default="plus13",
    )
    args = parser.parse_args()
    assert (args.research_root / "work" / "auto_trials.py").is_file()
    variants = {
        "plus13": "right_13_from_1126_through_1131",
        "plus12": "right_12_from_1126_through_1131",
        "same": "no_presteer_same_landing",
        "no-presteer": "no_presteer_opposite_landing",
    }
    cases = list(variants) if args.case == "all" else [args.case]
    for case in cases:
        log = trial_log(args.research_root, variants[case])
        if case == "plus13":
            assert_exact_takeoff_snapshot(log)
            print("Trainer exact takeoff snapshot: PASS")
        if args.physics_only:
            continue
        previews, verdicts = target_events(log)
        if case == "plus13":
            assert len(previews) == 1 and previews[0].group(2) == "S", (
                f"Expected one S preview for +13, found {[(m.group(1), m.group(2)) for m in previews]}"
            )
            assert len(verdicts) == 1 and verdicts[0].group(2) == "S", (
                f"Expected one S landing verdict for +13, found {[(m.group(1), m.group(2)) for m in verdicts]}"
            )
            early_landings = [
                int(m.group(1)) for m in LANDING.finditer(log)
                if 6150 <= int(m.group(1)) <= 6250
            ]
            early_verdicts = [
                m for m in VERDICT.finditer(log)
                if 6150 <= int(m.group(1)) <= 6350
            ]
            assert len(early_landings) == 1, "First landing time was not logged"
            assert len(early_verdicts) == 1, "First landing must receive one timely grade"
            assert 0 <= int(early_verdicts[0].group(1)) - early_landings[0] <= 120
        elif case in ("plus12", "no-presteer"):
            assert not previews, f"{case} must have no air grade preview"
            assert len(verdicts) == 1 and verdicts[0].group(2) == "MISSED", (
                f"{case} must confirm MISSED on landing, found {[(m.group(1), m.group(2)) for m in verdicts]}"
            )
        else:
            assert not previews and not verdicts, (
                "Same-direction transition must not change the rating"
            )
        print(f"Trainer {case} rating: PASS")


if __name__ == "__main__":
    main()
