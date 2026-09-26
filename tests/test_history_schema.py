"""Validate the history written by a live Gorilla Grip Trainer run.

Run this after a rated attempt; it deliberately reads the plugin's actual
storage file instead of duplicating its serializer in the test.
"""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path


DEFAULT_HISTORY = (
    Path.home() / "OpenplanetNext" / "PluginStorage" /
    "GorillaGripTrainer" / "history.json"
)
LABELS = {"S+", "S", "A", "B", "C", "D", "MISSED", "UNRATED"}
GRADES = "SABCD"
PREVIEWS = {"", "S+"} | set(GRADES) | {
    f"{left}/{right}"
    for i, left in enumerate(GRADES)
    for right in GRADES[i + 1:]
}


def validate(doc: object) -> list[dict]:
    assert isinstance(doc, dict), "History root must be an object"
    assert doc.get("version") == 1, "History schema version must be 1"
    runs = doc.get("runs")
    assert isinstance(runs, list), "History runs must be an array"
    assert len(runs) <= 500, "History must prune after 500 attempts"
    ids: set[str] = set()
    for run in runs:
        assert isinstance(run, dict)
        assert isinstance(run.get("id"), str) and run["id"]
        assert run["id"] not in ids, "Every attempt needs a unique ID"
        ids.add(run["id"])
        assert isinstance(run.get("mapUid"), str)
        assert isinstance(run.get("mapName"), str)
        assert isinstance(run.get("startedAt"), int)
        assert run.get("status") in {"FINISHED", "RESET"}
        if run["status"] == "FINISHED":
            assert isinstance(run.get("finishMs"), int) and run["finishMs"] >= 0
        else:
            assert run.get("finishMs") is None
        for key in ("score", "bestCombo", "hits", "misses"):
            assert isinstance(run.get(key), int) and run[key] >= 0
        jumps = run.get("jumps")
        assert isinstance(jumps, list)
        assert jumps or run["status"] == "FINISHED", (
            "Only finished maps may be stored without a verdict"
        )
        previous = -1
        for jump in jumps:
            assert isinstance(jump, dict)
            assert jump.get("label") in LABELS
            assert jump.get("preview") in PREVIEWS
            assert isinstance(jump.get("takeoffMs"), int)
            assert isinstance(jump.get("landingMs"), int)
            assert previous <= jump["landingMs"]
            assert jump["takeoffMs"] <= jump["landingMs"]
            previous = jump["landingMs"]
            for key in ("leadMinMs", "leadMaxMs", "combo", "points", "spins"):
                assert isinstance(jump.get(key), int), key
            if "scoreAfter" in jump:
                # Earlier local builds wrote -1 for attempts saved before this field existed.
                assert isinstance(jump["scoreAfter"], int) and jump["scoreAfter"] >= -1
            if "timingEstimated" in jump:
                assert isinstance(jump["timingEstimated"], bool)
            assert jump["leadMinMs"] <= jump["leadMaxMs"] or (
                jump["leadMinMs"] == jump["leadMaxMs"] == -1
            )
            assert isinstance(jump.get("reason"), str)
    return runs


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", type=Path, default=DEFAULT_HISTORY)
    args = parser.parse_args()
    assert args.file.is_file(), f"No live Trainer history yet: {args.file}"
    runs = validate(json.loads(args.file.read_text(encoding="utf-8")))
    assert runs, "Run one rated attempt before this integration check"
    empty_finish = copy.deepcopy(runs[0])
    empty_finish["status"] = "FINISHED"
    empty_finish["finishMs"] = 1000
    empty_finish["jumps"] = []
    empty_finish["score"] = 0
    empty_finish["bestCombo"] = 0
    empty_finish["hits"] = 0
    empty_finish["misses"] = 0
    assert len(validate({"version": 1, "runs": [empty_finish]})) == 1
    rated = next((run for run in runs if run["jumps"]), None)
    assert rated is not None
    perfect = copy.deepcopy(rated)
    perfect["jumps"][0]["label"] = "S+"
    perfect["jumps"][0]["preview"] = "S+"
    perfect["jumps"][0]["leadMinMs"] = 0
    perfect["jumps"][0]["leadMaxMs"] = 0
    perfect["jumps"][0]["timingEstimated"] = False
    assert len(validate({"version": 1, "runs": [perfect]})) == 1
    print(f"History v1 schema: PASS ({len(runs)} attempts)")


if __name__ == "__main__":
    main()
