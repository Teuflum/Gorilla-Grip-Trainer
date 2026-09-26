"""Check that the first rated jump after Improve starts with a fresh score.

Run after finishing ANGULAR MOMENTUM and pressing Improve. This reads the
Openplanet log from the last finish onward and waits for the first new verdict.
"""

from pathlib import Path
import re
import time


def main():
    log_path = Path.home() / "OpenplanetNext/Openplanet.log"
    finish_pattern = re.compile(r"Gorilla Grip Trainer finish summary: \d+ms, score (\d+)")
    verdict_pattern = re.compile(
        r"Gorilla Grip Trainer verdict at \d+ms: (\w+).*?\| combo (\d+) \| score (\d+)"
    )

    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        log = log_path.read_text(encoding="utf-8", errors="replace")
        finishes = list(finish_pattern.finditer(log))
        assert finishes, "No Trainer finish found in the Openplanet log"
        last_finish = finishes[-1]
        prior_score = int(last_finish.group(1))
        assert prior_score > 500, "Need a completed run with substantial score"
        verdict = verdict_pattern.search(log, last_finish.end())
        if verdict is None:
            time.sleep(0.2)
            continue
        label, combo, score = verdict.group(1), int(verdict.group(2)), int(verdict.group(3))
        assert score < 500, (
            f"Improve kept previous score {prior_score}; first new verdict "
            f"{label}, combo {combo}, score {score}"
        )
        assert combo <= 1, f"Improve kept previous combo: {combo}"
        print(f"Improve reset: prior {prior_score}, first verdict {label}, combo {combo}, score {score}: PASS")
        return
    raise TimeoutError("No verdict after the latest finish within 60 seconds")


if __name__ == "__main__":
    main()
