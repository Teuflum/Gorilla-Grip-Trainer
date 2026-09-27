"""From the finish screen, restart and ensure the next attempt begins at zero score.

Requires Trackmania, TICK, and GorillaGripLogger. Run while the completed
ANGULAR MOMENTUM attempt is still on its finish screen.
Needs Openplanet developer mode and Settings → Gorilla Grip Trainer → Debug →
Log trainer events.
"""

from pathlib import Path
import re
import time
import uuid
from trainer_log import require_event_logging


def main():
    require_event_logging()
    log_path = Path.home() / "OpenplanetNext/Openplanet.log"
    storage = Path.home() / "OpenplanetNext/PluginStorage/GorillaGripLogger"
    existing = log_path.read_text(encoding="utf-8", errors="replace")
    finish = list(re.finditer(r"Gorilla Grip Trainer finish summary: \d+ms, score (\d+)", existing))
    assert finish, "No Trainer finish found in the Openplanet log"
    prior_score = int(finish[-1].group(1))
    assert prior_score > 500, "Need a completed attempt with a substantial score"
    offset = log_path.stat().st_size
    command_id = uuid.uuid4().hex[:12]
    temporary = storage / "automation_command.tmp"
    temporary.write_text(command_id, encoding="utf-8")
    temporary.replace(storage / "automation_command.txt")

    deadline = time.monotonic() + 70
    while time.monotonic() < deadline:
        with log_path.open("rb") as handle:
            handle.seek(offset)
            log = handle.read().decode("utf-8", "replace")
        status = (storage / "automation_status.txt").read_text(encoding="utf-8")
        if status.startswith(command_id + " error:"):
            raise AssertionError(status)
        restarted = re.search(r"Gorilla Grip Trainer snapshot at (?:\d{1,3}|1\d{3})ms", log)
        verdict = re.search(
            r"Gorilla Grip Trainer verdict at \d+ms: (\w+).*?\| combo (\d+) \| score (\d+)",
            log,
        )
        if restarted and verdict:
            label, combo, score = verdict.group(1), int(verdict.group(2)), int(verdict.group(3))
            assert score < 500, (
                f"Score leaked across restart: previous={prior_score}, "
                f"first new verdict={label}, combo={combo}, score={score}"
            )
            print(f"Post-finish restart: first verdict {label}, combo {combo}, score {score}: PASS")
            return
        time.sleep(0.2)
    raise TimeoutError("No restarted run and first verdict appeared within 70 seconds")


if __name__ == "__main__":
    main()
