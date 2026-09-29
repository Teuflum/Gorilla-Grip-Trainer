"""Exercise Gorilla Grip Trainer against the controlled ANGULAR MOMENTUM replay.

This integration check needs Trackmania and TICK running.
The Trainer itself does not need GorillaGripLogger; this test uses the
Logger and TICK's local client (work/tick_client.py) from a local clone of
https://github.com/Teuflum/tm-ice-physics-reverse-engineering
(pass it as --research-root) only to drive the replay.
It reads only fresh Openplanet log lines produced by its own TICK replay.
Needs Openplanet developer mode and Settings → Gorilla Grip Trainer → Debug →
Log trainer events.
"""

from __future__ import annotations

import argparse
import atexit
import json
import re
import subprocess
import sys
import time
import uuid
from pathlib import Path
from trainer_log import require_event_logging


LOG = Path.home() / "OpenplanetNext" / "Openplanet.log"
HISTORY = Path.home() / "OpenplanetNext" / "PluginStorage" / "GorillaGripTrainer" / "history.json"
SNAPSHOT = re.compile(
    r"Gorilla Grip Trainer snapshot at (\d+)ms: exact true, "
    r"mode ([012]), steer ([+-]?[0-9.]+), contacts ([01]{4}), "
    r"modeAt (\d+), clock (\d+), delay (\d+)"
)
PREVIEW = re.compile(r"Gorilla Grip Trainer preview at (\d+)ms: (S\+|[SABCD]) lead (\d+)ms")
VERDICT = re.compile(r"Gorilla Grip Trainer verdict at (\d+)ms: (S\+|[SABCD]|MISSED)")
LANDING = re.compile(r"Gorilla Grip Trainer landing at (\d+)ms:")
UNRATED = re.compile(r"Gorilla Grip Trainer timing unrated at (\d+)ms: (.+)")


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


def history_runs() -> list[dict]:
    if not HISTORY.is_file():
        return []
    return json.loads(HISTORY.read_text(encoding="utf-8"))["runs"]


def preserve_loaded_input(research_root: Path) -> None:
    """Restore the user's loaded TICK input after any rating case, including failures."""
    sys.path.insert(0, str(research_root / "work"))
    from tick_client import TickClient, encoded

    client = TickClient()
    collection_id = client.get("settings")["activeInputCollectionId"]
    revision_id = client.get("runtime/status")["loadedInputRevisionId"]

    def restore() -> None:
        if not collection_id or not revision_id:
            return
        settings = client.get("settings")
        if settings["activeInputCollectionId"] != collection_id:
            client.patch("settings", {
                "expectedRevision": settings["revision"],
                "activeInputCollectionId": collection_id,
            })
        if client.get("runtime/status")["loadedInputRevisionId"] != revision_id:
            collection = client.get(f"input-collections/{encoded(collection_id)}")
            client.post(
                f"input-revisions/{encoded(revision_id)}/load?"
                f"expectedCollectionRevision={collection['node']['revision']}"
            )

    atexit.register(restore)


def assert_full_finish(research_root: Path, finish_revision_id: str) -> None:
    sys.path.insert(0, str(research_root / "work"))
    from tick_client import TickClient, encoded

    client = TickClient()
    original_settings = client.get("settings")
    original_collection = original_settings["activeInputCollectionId"]
    original_loaded = client.get("runtime/status")["loadedInputRevisionId"]
    assert client.get("runtime/status")["currentMapUid"] == "xsBIINZa10KzKOtrSt_oxEAnHX5"
    finish_revision = client.get(f"input-revisions/{encoded(finish_revision_id)}")
    finish_collection = finish_revision["collectionId"]

    before = {run["id"] for run in history_runs()}
    log_offset = LOG.stat().st_size
    finished: list[dict] = []
    try:
        if original_collection != finish_collection or original_settings["disableFinishEnabled"]:
            settings = client.get("settings")
            client.patch("settings", {
                "expectedRevision": settings["revision"],
                "activeInputCollectionId": finish_collection,
                "disableFinishEnabled": False,
            })
        collection = client.get(f"input-collections/{encoded(finish_collection)}")
        client.post(
            f"input-revisions/{encoded(finish_revision_id)}/load?"
            f"expectedCollectionRevision={collection['node']['revision']}"
        )
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if client.get("runtime/status")["loadedInputRevisionId"] == finish_revision_id:
                break
            time.sleep(0.2)
        else:
            raise AssertionError("Selected finishing replay did not load")

        storage = Path.home() / "OpenplanetNext" / "PluginStorage" / "GorillaGripLogger"
        command_id = uuid.uuid4().hex[:12]
        command = storage / "automation_command.txt"
        temporary = command.with_suffix(".tmp")
        temporary.write_text(command_id, encoding="utf-8")
        temporary.replace(command)
        deadline = time.monotonic() + 70
        while time.monotonic() < deadline:
            status = (storage / "automation_status.txt").read_text(encoding="utf-8")
            if status.startswith(command_id + " "):
                if " error:" in status:
                    raise AssertionError(status)
                if " complete " in status:
                    break
            time.sleep(0.2)
        else:
            raise AssertionError("Full replay never started through the logger")

        # The logger stops at 13.5 seconds, but TICK continues the replay to the finish.
        deadline = time.monotonic() + 55
        while time.monotonic() < deadline:
            finished = [
                run for run in history_runs()
                if run["id"] not in before and run["status"] == "FINISHED"
            ]
            if finished:
                break
            time.sleep(0.5)
        assert len(finished) == 1, "Selected replay did not record one FINISHED attempt"
        assert finished[0]["finishMs"] >= 40000
        with LOG.open("rb") as handle:
            handle.seek(log_offset)
            log = handle.read().decode("utf-8", "replace")
        assert log.count("Gorilla Grip Trainer finish summary:") == 1
        assert len(re.findall(
            r"Gorilla Grip Trainer audio: results sound .+ started, length ",
            log,
        )) == 1
        deadline = time.monotonic() + 35
        while time.monotonic() < deadline:
            with LOG.open("rb") as handle:
                handle.seek(log_offset)
                log = handle.read().decode("utf-8", "replace")
            if "Gorilla Grip Trainer audio: results loop started" in log or \
                    "Gorilla Grip Trainer audio: results loop restarted via rewind" in log:
                break
            time.sleep(0.25)
        assert (log.count("Gorilla Grip Trainer audio: results loop started") +
                log.count("Gorilla Grip Trainer audio: results loop restarted via rewind")) == 1
    finally:
        settings = client.get("settings")
        if (settings["activeInputCollectionId"] != original_collection or
                settings["disableFinishEnabled"] != original_settings["disableFinishEnabled"]):
            client.patch("settings", {
                "expectedRevision": settings["revision"],
                "activeInputCollectionId": original_collection,
                "disableFinishEnabled": original_settings["disableFinishEnabled"],
            })
        if original_loaded is not None:
            collection = client.get(f"input-collections/{encoded(original_collection)}")
            client.post(
                f"input-revisions/{encoded(original_loaded)}/load?"
                f"expectedCollectionRevision={collection['node']['revision']}"
            )
    print("Trainer true finish, summary, results music, and first loop: PASS")


def main() -> None:
    require_event_logging()
    parser = argparse.ArgumentParser()
    parser.add_argument("--research-root", required=True, type=Path)
    parser.add_argument("--physics-only", action="store_true")
    parser.add_argument(
        "--case", choices=["plus13", "plus12", "same", "no-presteer", "all", "finish"],
        default="plus13",
    )
    parser.add_argument("--finish-revision-id", help="TICK revision known to finish the map")
    args = parser.parse_args()
    assert (args.research_root / "work" / "auto_trials.py").is_file()
    if args.case == "finish":
        if not args.finish_revision_id:
            parser.error("--case finish requires --finish-revision-id for a run that reaches the finish")
        assert_full_finish(args.research_root, args.finish_revision_id)
        return
    variants = {
        "plus13": "right_13_from_1126_through_1131",
        "plus12": "right_12_from_1126_through_1131",
        "same": "no_presteer_same_landing",
        "no-presteer": "no_presteer_opposite_landing",
    }
    preserve_loaded_input(args.research_root)
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
            assert len(previews) == 1, f"Expected one +13 preview, found {len(previews)}"
            lead = previews[0].group(3)
            expected_grade = "S+" if lead == "0" else "S"
            assert previews[0].group(2) == expected_grade, (
                f"Expected {expected_grade} for {lead}ms, got {previews[0].group(2)}"
            )
            assert len(verdicts) == 1 and verdicts[0].group(2) == expected_grade, (
                f"Expected one {expected_grade} landing verdict for +13, "
                f"found {[(m.group(1), m.group(2)) for m in verdicts]}"
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
            if early_verdicts:
                assert len(early_verdicts) == 1
                assert 0 <= int(early_verdicts[0].group(1)) - early_landings[0] <= 120
            else:
                uncertain = [
                    m for m in UNRATED.finditer(log)
                    if 5200 <= int(m.group(1)) <= 5400
                ]
                assert len(uncertain) == 1 and "contact sample gap" in uncertain[0].group(2), (
                    "A first jump without a grade needs a genuine contact-sampling failure"
                )
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
