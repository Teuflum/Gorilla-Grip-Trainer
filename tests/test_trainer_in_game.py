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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--research-root", required=True, type=Path)
    parser.add_argument("--physics-only", action="store_true")
    args = parser.parse_args()
    assert (args.research_root / "work" / "auto_trials.py").is_file()
    log = trial_log(args.research_root, "right_13_from_1126_through_1131")
    assert_exact_takeoff_snapshot(log)
    print("Trainer exact takeoff snapshot: PASS")


if __name__ == "__main__":
    main()
