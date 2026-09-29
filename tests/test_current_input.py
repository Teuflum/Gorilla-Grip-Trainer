"""Live check for the currently selected TICK revision on ANGULAR MOMENTUM.

The first landing must yield a single grade even when fast playback spans a
grade boundary. The historical 16.8 s bounce check is opt-in because the
user's selected input revision can change independently of this script.
The Trainer itself does not need GorillaGripLogger; this test uses the
Logger and TICK's local client (work/tick_client.py) from a local clone of
https://github.com/Teuflum/tm-ice-physics-reverse-engineering
(pass it as --research-root) only to drive the replay.
Needs Openplanet developer mode and Settings → Gorilla Grip Trainer → Debug →
Log trainer events.
"""

from __future__ import annotations

import argparse
import re
import sys
import time
import uuid
from pathlib import Path
from trainer_log import require_event_logging


LOG = Path.home() / "OpenplanetNext" / "Openplanet.log"
STORAGE = Path.home() / "OpenplanetNext" / "PluginStorage" / "GorillaGripLogger"


def run_current(client, speed: float, target_ms: int) -> str:
    before = LOG.stat().st_size
    client.request("PUT", "runtime/game-speed", {"requestedGameSpeed": speed})
    run_id = uuid.uuid4().hex[:12]
    temporary = STORAGE / "automation_command.tmp"
    temporary.write_text(run_id, encoding="utf-8")
    temporary.replace(STORAGE / "automation_command.txt")
    deadline = time.monotonic() + max(70, 70 / speed)
    while time.monotonic() < deadline:
        with LOG.open("rb") as handle:
            handle.seek(before)
            log = handle.read().decode("utf-8", "replace")
        restart = next((match for match in re.finditer(
            r"Gorilla Grip Trainer snapshot at (\d{1,4})ms", log
        ) if int(match.group(1)) < 1500), None)
        if restart is not None:
            current = log[restart.start():]
            snapshots = [int(value) for value in re.findall(
                r"Gorilla Grip Trainer snapshot at (\d+)ms", current
            )]
            if any(value >= target_ms for value in snapshots):
                return current
        status = (STORAGE / "automation_status.txt").read_text(encoding="utf-8")
        if status.startswith(run_id + " error:"):
            raise AssertionError(status)
        time.sleep(0.2)
    else:
        raise TimeoutError(f"TICK current run at {speed}x did not reach {target_ms} ms")


def main() -> None:
    require_event_logging()
    parser = argparse.ArgumentParser()
    parser.add_argument("--research-root", type=Path, required=True)
    parser.add_argument("--expect-16s-s", action="store_true",
                        help="also check the historical S bounce at 16.8 s")
    args = parser.parse_args()
    sys.path.insert(0, str(args.research_root / "work"))
    from tick_client import TickClient

    client = TickClient()
    status = client.get("runtime/status")
    assert status["currentMapUid"] == "xsBIINZa10KzKOtrSt_oxEAnHX5"
    revision = status["loadedInputRevisionId"]
    assert revision, "No current TICK input revision loaded"
    old_speed = client.get("runtime/game-speed")["requestedGameSpeed"]
    try:
        fast = run_current(client, 5, 7000)
        first_result = re.findall(
            r"Gorilla Grip Trainer verdict at (6\d{3})ms: (S\+|S|A|B|C|D)",
            fast,
        )
        assert first_result, "First jump had no single S-D timing grade"
        if args.expect_16s_s:
            normal = run_current(client, 1, 17300)
            assert re.search(r"Gorilla Grip Trainer preview at 16\d{3}ms: S", normal)
            result = re.findall(r"Gorilla Grip Trainer verdict at (16\d{3}|17\d{3})ms: (S\+|\w+)", normal)
            assert any(label in {"S", "S+"} for _, label in result), f"16 s bounce did not confirm S/S+: {result}"
        assert client.get("runtime/status")["loadedInputRevisionId"] == revision
        print(f"Current revision {revision}: first jump graded" +
              (", 16 s bounce S" if args.expect_16s_s else ""))
    finally:
        client.request("PUT", "runtime/game-speed", {"requestedGameSpeed": old_speed})


if __name__ == "__main__":
    main()
