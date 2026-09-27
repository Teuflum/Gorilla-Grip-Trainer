"""One TICK replay must get the same results at any frame rate or game speed.

Replays the loaded TICK revision four times: 1x; 4x; 1x with the Trainer
processing every 5th frame; 4x every 3rd frame. Every verdict must match the
first run: grade, reason, spins, combo, score, takeoff, landing, and lead. The
"Steering reversed N ms" number in a reason is an estimate and is masked.

Needs Trackmania, TICK, and a local clone of
https://github.com/Teuflum/tm-gorilla-grip-reverse-engineering (for
work/tick_client.py and work/tick_restart.py), passed as --research-root.
Needs Openplanet developer mode and Settings -> Gorilla Grip Trainer -> Debug
-> Log trainer events. Only the game speed changes; it is restored after each
run.

One run per call, so Debug -> Process every Nth frame can be changed in
between; each run's verdicts are saved to --data-dir (keep it outside the
repository):

  py -3 tests/test_frame_independence_in_game.py --research-root <path> --pid <PID>
      --until-ms <race ms after the last jump> --data-dir <dir> --run 1x
  ... --run 4x
  (set Process every Nth frame to 5)  ... --run 1x-skip5
  (set it to 3)                       ... --run 4x-skip3
  py -3 tests/test_frame_independence_in_game.py --data-dir <dir> --compare
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from trainer_log import LOG, require_event_logging


VERDICT = re.compile(
    r"Gorilla Grip Trainer verdict at (-?\d+)ms: (\S+) \| (.*?) \| force .*?"
    r"\| spins (\d+) \| combo (\d+) \| score (\d+) \| takeoff (-?\d+)ms \| "
    r"landing (-?\d+)ms \| lead (-?\d+)ms")
SKIP = re.compile(r"Gorilla Grip Trainer frame skip (\d+)")
# Run name -> (game speed, Trainer frame skip).
RUNS = {"1x": (1, 1), "4x": (4, 1), "1x-skip5": (1, 5), "4x-skip3": (4, 3)}


def log_size() -> int:
    return LOG.stat().st_size


def log_since(offset: int) -> str:
    with LOG.open("rb") as handle:
        handle.seek(offset)
        return handle.read().decode("utf-8", "replace")


def current_skip() -> int:
    text = LOG.read_text(encoding="utf-8", errors="replace")
    found = SKIP.findall(text.rsplit("Loaded plugin 'GorillaGripTrainer'", 1)[-1])
    return int(found[-1]) if found else 1


def verdicts(text: str) -> list[list]:
    rows = []
    for m in VERDICT.finditer(text):
        reason = re.sub(r"reversed \d+ ms", "reversed N ms", m[3])
        rows.append([m[2], reason, int(m[4]), int(m[5]), int(m[6]),
                     int(m[7]), int(m[8]), int(m[9])])
    return rows


def run(args: argparse.Namespace) -> None:
    require_event_logging()
    sys.path.insert(0, str(args.research_root / "work"))
    from tick_client import TickClient
    from tick_restart import Live, restart

    speed, skip = RUNS[args.run]
    assert current_skip() == skip, f"Set Debug -> Process every Nth frame to {skip} first"
    client = TickClient()
    original_speed = client.get("runtime/game-speed")["requestedGameSpeed"]
    live = Live(client)
    try:
        offset = log_size()
        # Restart at normal speed: TICK sometimes missed a restart made at 4x.
        client.request("PUT", "runtime/game-speed", {"requestedGameSpeed": 1})
        restart(args.pid, client, live)
        client.request("PUT", "runtime/game-speed", {"requestedGameSpeed": speed})
        live.wait(lambda: live.tick >= args.until_ms,
                  args.until_ms / 1000 / speed + 30, f"race {args.until_ms} ms")
        rows = verdicts(log_since(offset))
    finally:
        client.request("PUT", "runtime/game-speed", {"requestedGameSpeed": original_speed})
        live.close()
    (args.data_dir / f"{args.run}.json").write_text(json.dumps(rows), encoding="utf-8")
    print(f"{args.run}: {len(rows)} verdicts saved")


def compare(args: argparse.Namespace) -> None:
    results = {name: json.loads((args.data_dir / f"{name}.json").read_text(encoding="utf-8"))
               for name in RUNS if (args.data_dir / f"{name}.json").exists()}
    assert set(results) == set(RUNS), f"Missing runs: {sorted(set(RUNS) - set(results))}"
    base = results["1x"]
    assert len(base) >= 3, "Pick a revision with at least three rated jumps"
    if not any(row[2] > 0 for row in base):
        print("Note: no spin in this revision; spin counting was not compared.")
    if not any(row[0] == "MISSED" for row in base):
        print("Note: no MISSED in this revision; the miss path was not compared.")
    failed = False
    for name, rows in results.items():
        print(f"{name}: {len(rows)} verdicts")
        if rows != base:
            failed = True
            print(f"\n{name} differs from 1x:")
            for index in range(max(len(rows), len(base))):
                want = base[index] if index < len(base) else None
                got = rows[index] if index < len(rows) else None
                if want != got:
                    print(f"  #{index + 1}: 1x {want}\n       {name} {got}")
    assert not failed, "Results depend on frame rate or game speed"
    print("Same results at every frame rate and game speed: PASS")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--research-root", type=Path)
    parser.add_argument("--pid", type=int)
    parser.add_argument("--until-ms", type=int)
    parser.add_argument("--data-dir", required=True, type=Path)
    parser.add_argument("--run", choices=list(RUNS))
    parser.add_argument("--compare", action="store_true")
    args = parser.parse_args()
    args.data_dir.mkdir(parents=True, exist_ok=True)
    if args.run:
        assert args.research_root and args.pid and args.until_ms, \
            "--run needs --research-root, --pid and --until-ms"
        run(args)
    if args.compare:
        compare(args)


if __name__ == "__main__":
    main()
