# Tick-exact timing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One TICK replay gets the same grade, lead, reason, spin count and score at any frame rate or game speed.

**Architecture:** The rating tracker (`plugin/Transitions.as`) stops bounding takeoff and landing by rendered frames. It reads the game's own clocks instead: each wheel's contact-change timestamp and the stored mode's switch time (`modeAt`). Parts that have no timestamp (cue reversal, slide window, spins) become gap-safe estimates. A live check (stage 0) confirms the timestamps before any rating code changes.

**Tech Stack:** Openplanet AngelScript plugin; Python 3 source-contract tests (`python tests/<name>.py`); in-game checks through TICK's local API (`Analysis/work/tick_client.py`, `tick_restart.py`).

**Spec:** `docs/superpowers/specs/2026-09-27-tick-exact-timing-design.md`

## Global Constraints

- Work on branch `tick-exact-timing` in `Trainer/`. Plain `git` refuses the folder (other Windows owner): use `git -c safe.directory='*' …` per command; do not change the global Git config.
- The Trainer stays read-only: `Dev::SafeRead*` only, no `Dev::Hook`, no writes to game memory.
- Grade limits, points, combo rules, audio, popup and widgets do not change, except that `A+` and the lead range disappear.
- Wheel timestamp: `vehicle + 0x17b4 + 0xb8·i + 0x6c` (= `0x1820 + 0xb8·i`), 32-bit game clock. Physics clock: `vehicle + 0x4f4`.
- History files keep `leadMinMs`, `leadMaxMs` and `timingEstimated` so older files load; new entries store the same lead in both fields.
- Version 0.3.0.
- Live game automation only after the user says yes, and only through the replay of the revision they loaded. Restore TICK game speed in a `finally`. Do not touch `PluginStorage`.
- A compile failure unloads the Trainer: check any unfamiliar Openplanet call against the strings in `Openplanet.dll` before installing (see the trainer-live-verify skill). Avoid `Math::Round`, `Math::Floor` and `Math::Ceil`; the plan uses integer arithmetic instead.
- Run every offline test after each task:
  `for f in tests/test_*.py; do case $f in *in_game*|*current_input*) continue;; esac; python "$f" >/dev/null || echo "FAIL $f"; done`
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Brief touch between two frames.** A wheel touches and lifts again between frames, so no frame shows contact. The touch must still count: re-take-off, or a landing with a touch that lifted. The landing time is then the lift-off tick, not the touchdown. Test: Task 4 asserts the touch branch in `Update` and `EarliestWheelChange` over all wheels.
2. **Late verdict frame.** At low fps the first frame after the check tick can be hundreds of ms late, and the player may have switched direction in between. The verdict must use `modeAt <= checkClock`. Test: Task 4 asserts `switchedByCheck` and the no-force-check path.
3. **Unset or stale timestamps.** On a fresh car or after a respawn a timestamp can be `0xFFFFFFFF` (read as -1) or older than the previous frame. The takeoff must become `UNRATED` ("Contact timestamps were inconsistent at takeoff"), never a wrong grade. Test: Task 3 asserts `TakeoffStampsValid` rejects a takeoff outside `(before, after]` and a grounded wheel without a new timestamp.
4. **Frame skip left on.** `S_DebugFrameSkip` saved as 5 must have no effect outside developer mode. Test: Task 1 asserts `DebugFrameSkip()` returns 1 under `#else`.
5. **Mode cleared to neutral after the check tick.** A late frame sees mode 0 with an unchanged `modeAt`. It is treated as not held; this is the one remaining frame-dependent verdict edge. Test: Task 4 asserts `stillHeld` requires `snap.mode == takeoffMode`, and Task 7 documents the edge in the main spec.

---

### Task 1: Frame skip, wheel timestamps, and the stage 0 probe line

**Files:**
- Modify: `plugin/Physics.as` (class `PhysicsSnapshot`, `ReadPhysics`)
- Modify: `plugin/Settings.as` (debug settings and Debug tab)
- Modify: `plugin/Main.as` (`Update`)
- Create: `tests/test_tick_timing.py`
- Modify: `tests/test_debug_logging.py:48`

**Interfaces:**
- Produces: `PhysicsSnapshot.wheelChangedAt` (`array<uint>`, 4 entries, contact-bit order), `PhysicsSnapshot.physicsClock` (`int`), `PhysicsSnapshot.probe` (`string`, temporary), `int DebugFrameSkip()`, `bool ProcessThisFrame()`, log lines `Gorilla Grip Trainer frame skip N` and `Gorilla Grip Trainer stamp probe at …` (format below).

- [ ] **Step 1: Write the failing test**

Create `tests/test_tick_timing.py`:

```python
"""Tick-exact timing: the Trainer dates contact changes with the game's own clocks."""

from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
physics = (root / "Physics.as").read_text(encoding="utf-8")
settings = (root / "Settings.as").read_text(encoding="utf-8")
main = (root / "Main.as").read_text(encoding="utf-8")
transitions = (root / "Transitions.as").read_text(encoding="utf-8")
read = physics.split("PhysicsSnapshot@ ReadPhysics(", 1)[1].split("\n}", 1)[0]
update = main.split("void Update(float dt) {", 1)[1].split("\n}", 1)[0]

# Each wheel's block stores the game clock of its last contact change at +0x6c.
assert "array<uint> wheelChangedAt = array<uint>(4);" in physics
assert "uint64 wheel = vehicle + 0x17b4 + 0xb8 * i;" in read
assert "snap.wheelChangedAt[i] = Dev::SafeReadUint32(wheel + 0x6c);" in read
assert "snap.physicsClock = int(Dev::SafeReadUint32(vehicle + 0x4f4));" in read

# Frame skipping simulates a low frame rate, only in developer mode.
assert "[Setting hidden] int S_DebugFrameSkip = 1;" in settings
skip = settings.split("int DebugFrameSkip() {", 1)[1].split("\n}", 1)[0]
assert skip.split() == ["#if", "SIG_DEVELOPER", "return", "Math::Clamp(S_DebugFrameSkip,",
                        "1,", "10);", "#else", "return", "1;", "#endif"], skip
debug_tab = settings.split("void RenderSettingsDebug() {", 1)[1].split("\n}", 1)[0]
assert 'UI::SliderInt("Process every Nth frame", S_DebugFrameSkip, 1, 10)' in debug_tab
assert "S_DebugFrameSkip = 1;" in debug_tab
assert update.index("if (!ProcessThisFrame()) return;") < \
    update.index("PhysicsSnapshot@ next = ReadPhysics(vis, t);")
assert 'DebugLog("Gorilla Grip Trainer frame skip " + frameSkip);' in update
print("Wheel timestamps and frame skip: PASS")

# Stage 0 probe (removed again in Task 5).
assert 'DebugLog("Gorilla Grip Trainer stamp probe at " + t +' in update
assert "vehicle + 0x538 + 4 * i" in read
print("Stage 0 probe line: PASS")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python tests/test_tick_timing.py`
Expected: FAIL with `AssertionError` on the `wheelChangedAt` line.

- [ ] **Step 3: Add the snapshot fields and reads**

In `plugin/Physics.as`, add these fields to `class PhysicsSnapshot`, after `float yaw = 0.0f;`:

```angelscript
    // Game clock of each wheel's last contact change (touchdown or lift-off),
    // in the contact-bit order. The physics step writes it, so it dates a
    // change that happened between two rendered frames.
    array<uint> wheelChangedAt = array<uint>(4);
    // The physics step's own clock (vehicle+0x4f4).
    int physicsClock = -1;
    // Stage 0 only: 32 floats after the car position, to find the angular velocity.
    string probe = "";
```

In `ReadPhysics`, replace the contact loop:

```angelscript
    for (uint i = 0; i < 4; i++) {
        if (Dev::SafeReadUint32(vehicle + 0x17b4 + 0xb8 * i) != 0)
            snap.contactMask |= (1 << i);
    }
```

with:

```angelscript
    for (uint i = 0; i < 4; i++) {
        uint64 wheel = vehicle + 0x17b4 + 0xb8 * i;
        if (Dev::SafeReadUint32(wheel) != 0)
            snap.contactMask |= (1 << i);
        snap.wheelChangedAt[i] = Dev::SafeReadUint32(wheel + 0x6c);
    }
    snap.physicsClock = int(Dev::SafeReadUint32(vehicle + 0x4f4));
    if (DebugForceTraceOn()) {
        for (uint i = 0; i < 32; i++)
            snap.probe += (i == 0 ? "" : ",") +
                Text::Format("%.4f", Dev::SafeReadFloat(vehicle + 0x538 + 4 * i));
    }
```

- [ ] **Step 4: Add the frame-skip setting**

In `plugin/Settings.as`, after `[Setting hidden] bool S_DebugForceTrace = false;`, add:

```angelscript
[Setting hidden] int S_DebugFrameSkip = 1;
int g_frameSkipCounter = 0;
```

After `bool DebugForceTraceOn() { … }`, add:

```angelscript
// Process every Nth frame to simulate a low frame rate; 1 outside developer mode.
int DebugFrameSkip() {
#if SIG_DEVELOPER
    return Math::Clamp(S_DebugFrameSkip, 1, 10);
#else
    return 1;
#endif
}

bool ProcessThisFrame() {
    int n = DebugFrameSkip();
    if (n <= 1) return true;
    g_frameSkipCounter = (g_frameSkipCounter + 1) % n;
    return g_frameSkipCounter == 0;
}
```

In `RenderSettingsDebug`, add `S_DebugFrameSkip = 1;` inside the reset block after `S_DebugForceTrace = false;`, and at the end of the function:

```angelscript
    S_DebugFrameSkip = UI::SliderInt("Process every Nth frame", S_DebugFrameSkip, 1, 10);
    HelpMarker("Skips frames so the rating sees a lower frame rate, for timing tests. 1 processes every frame.");
```

- [ ] **Step 5: Use it in `Update` and log the probe**

In `plugin/Main.as`, add a global after `bool g_eventLoggingOn = false;`:

```angelscript
int g_loggedFrameSkip = -1;
```

In `Update`, directly after the event-logging marker block (`print("Gorilla Grip Trainer event logging " …); }`), add:

```angelscript
    // The frame-skip value is logged whenever it or event logging changes.
    int frameSkip = DebugLoggingOn() ? DebugFrameSkip() : -1;
    if (frameSkip != g_loggedFrameSkip) {
        g_loggedFrameSkip = frameSkip;
        if (frameSkip > 0) DebugLog("Gorilla Grip Trainer frame skip " + frameSkip);
    }
```

Replace:

```angelscript
    g_previousRaceTime = t;
    PhysicsSnapshot@ next = ReadPhysics(vis, t);
    @g_snapshot = next;
```

with:

```angelscript
    g_previousRaceTime = t;
    // Developer frame skipping simulates a low frame rate for timing tests.
    if (!ProcessThisFrame()) return;
    PhysicsSnapshot@ next = ReadPhysics(vis, t);
    @g_snapshot = next;
    if (next.exact && DebugForceTraceOn())
        DebugLog("Gorilla Grip Trainer stamp probe at " + t + "ms: clock " + next.gameTime +
            ", physics " + next.physicsClock + ", contacts " + next.ContactBits() +
            ", stamps " + next.wheelChangedAt[0] + "/" + next.wheelChangedAt[1] + "/" +
            next.wheelChangedAt[2] + "/" + next.wheelChangedAt[3] +
            ", mode " + next.mode + ", modeAt " + next.modeAt +
            ", yaw " + Text::Format("%.5f", next.yaw) + ", probe " + next.probe);
```

- [ ] **Step 6: Update the log-call count**

In `tests/test_debug_logging.py`, change:

```python
assert len(calls) == 31, len(calls)  # 18 routine events, 12 problems, 1 state marker
```

to:

```python
assert len(calls) == 33, len(calls)  # 20 routine events, 12 problems, 1 state marker
```

- [ ] **Step 7: Run the tests**

Run: `python tests/test_tick_timing.py`, then the full offline loop from Global Constraints.
Expected: both PASS lines; no `FAIL`.

- [ ] **Step 8: Install and check the compile**

Follow the trainer-live-verify skill steps 2–4: `py -3 .claude/skills/trainer-live-verify/scripts/install_trainer.py` (from the workspace root), ask the user to reload, then `check_load.py --after-line <mark>`. Expected: exit 0.

- [ ] **Step 9: Commit**

```bash
git -c safe.directory='*' add plugin/Physics.as plugin/Settings.as plugin/Main.as tests/test_tick_timing.py tests/test_debug_logging.py
git -c safe.directory='*' commit -m "Read wheel contact timestamps and add frame skipping"
```

---

### Task 2: Stage 0 live check (gate)

**Files:**
- Create: `Analysis/work/probe_wheel_stamps.py` (research repository)
- Modify: `Trainer/docs/superpowers/specs/2026-09-27-tick-exact-timing-design.md` (append "Stage 0 results")

**Interfaces:**
- Consumes: the `stamp probe` and `frame skip` log lines from Task 1.
- Produces: in the spec, the recorded values `clock source`, `yaw rate offset`, `yaw rate scale` that Tasks 3 and 5 copy.

- [ ] **Step 1: Write the probe script**

Create `Analysis/work/probe_wheel_stamps.py`:

```python
"""Stage 0 of tick-exact timing: do the wheel contact timestamps agree across frame rates?

Replays the loaded TICK revision three times (1x; 4x; 1x with the Trainer
processing every 5th frame) and reads the Trainer's "stamp probe" lines. It
reports whether the timestamps agree across runs, timestamp changes without a
contact change, the physics clock against the frame clock, race time against
game time, each takeoff's lead, and the probe float that tracks the yaw rate.

Needs Trackmania on the revision's map, TICK, and the Trainer in developer mode
with Debug -> Log trainer events and Log every tire-force change turned on.
Only the game speed is changed, and it is restored at the end.

Usage: py -3 probe_wheel_stamps.py --pid <Trackmania PID> [--until-ms 15000]
"""

from __future__ import annotations

import argparse
import math
import re
from collections import Counter
from pathlib import Path

from tick_client import TickClient
from tick_restart import Live, restart


LOG = Path.home() / "OpenplanetNext" / "Openplanet.log"
PROBE = re.compile(
    r"stamp probe at (-?\d+)ms: clock (\d+), physics (-?\d+), contacts ([01]{4}), "
    r"stamps (\d+)/(\d+)/(\d+)/(\d+), mode ([012]), modeAt (\d+), yaw ([-0-9.]+), "
    r"probe ([-0-9.,]+)")
SKIP = re.compile(r"Gorilla Grip Trainer frame skip (\d+)")
UNSET = 0xFFFFFFFF


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


def parse(text: str) -> list[dict]:
    rows = []
    for m in PROBE.finditer(text):
        rows.append({
            "race": int(m[1]), "clock": int(m[2]), "physics": int(m[3]),
            "contacts": m[4], "stamps": tuple(int(m[i]) for i in range(5, 9)),
            "mode": int(m[9]), "modeAt": int(m[10]), "yaw": float(m[11]),
            "probe": [float(x) for x in m[12].split(",")],
        })
    # Keep the replay after the restart only: from the first early frame to
    # the first race-time rewind after it.
    start = next((i for i, r in enumerate(rows) if 0 <= r["race"] < 1000), len(rows))
    rows = rows[start:]
    for i in range(1, len(rows)):
        if rows[i]["race"] < rows[i - 1]["race"]:
            return rows[:i]
    return rows


def run_once(client: TickClient, live: Live, pid: int, speed: float, until_ms: int) -> list[dict]:
    offset = log_size()
    client.request("PUT", "runtime/game-speed", {"requestedGameSpeed": speed})
    restart(pid, client, live)
    live.wait(lambda: live.tick >= until_ms, until_ms / 1000 / speed + 30, f"race {until_ms} ms")
    return parse(log_since(offset))


def to_race(row: dict, clock: int) -> int:
    return clock - row["clock"] + row["race"]


def stamp_events(rows: list[dict]) -> set[tuple[int, int]]:
    """Every (wheel, race time) a timestamp showed, on the race clock."""
    events = set()
    for row in rows:
        for wheel, stamp in enumerate(row["stamps"]):
            if stamp != UNSET and stamp <= row["clock"]:
                events.add((wheel, to_race(row, stamp)))
    return events


def takeoffs(rows: list[dict]) -> list[tuple[int, int]]:
    """(takeoff race time, lead ms) at each grounded-to-all-air frame pair."""
    found = []
    for before, after in zip(rows, rows[1:]):
        if before["contacts"] != "0000" and after["contacts"] == "0000":
            tick = max(s for s in after["stamps"] if s != UNSET)
            found.append((to_race(after, tick), tick - after["modeAt"]))
    return found


def wrap(angle: float) -> float:
    while angle > math.pi:
        angle -= 2 * math.pi
    while angle < -math.pi:
        angle += 2 * math.pi
    return angle


def yaw_rate_fit(rows: list[dict]) -> list[tuple[float, int, float]]:
    """(r2, byte offset, slope) of each probe float against the measured yaw rate."""
    pairs = []
    for before, after in zip(rows, rows[1:]):
        gap = after["clock"] - before["clock"]
        if before["contacts"] == after["contacts"] == "0000" and 0 < gap <= 20:
            rate = wrap(after["yaw"] - before["yaw"]) / gap * 1000
            probe = [(a + b) / 2 for a, b in zip(before["probe"], after["probe"])]
            pairs.append((rate, probe))
    fits = []
    for j in range(32):
        xy = sum(rate * probe[j] for rate, probe in pairs)
        xx = sum(probe[j] ** 2 for _, probe in pairs)
        yy = sum(rate ** 2 for rate, _ in pairs)
        if xx == 0 or yy == 0:
            continue
        slope = xy / xx
        residual = sum((rate - slope * probe[j]) ** 2 for rate, probe in pairs)
        fits.append((1 - residual / yy, 0x538 + 4 * j, slope))
    return sorted(fits, reverse=True)[:3]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--until-ms", type=int, default=15000)
    args = parser.parse_args()
    client = TickClient()
    original_speed = client.get("runtime/game-speed")["requestedGameSpeed"]
    live = Live(client)
    runs = {}
    try:
        assert current_skip() == 1, "Set Debug -> Process every Nth frame to 1 first"
        runs["1x"] = run_once(client, live, args.pid, 1, args.until_ms)
        runs["4x"] = run_once(client, live, args.pid, 4, args.until_ms)
        input("Set Debug -> Process every Nth frame to 5, then press Enter ")
        assert current_skip() == 5, "The Trainer did not log frame skip 5"
        runs["1x skip 5"] = run_once(client, live, args.pid, 1, args.until_ms)
    finally:
        client.request("PUT", "runtime/game-speed", {"requestedGameSpeed": original_speed})
        live.close()
    print("Set Debug -> Process every Nth frame back to 1.")

    base = runs["1x"]
    assert base, "No stamp probe lines; is Log every tire-force change on?"
    for name, rows in runs.items():
        offsets = Counter(r["race"] - r["clock"] for r in rows)
        physics = Counter(r["physics"] - r["clock"] for r in rows)
        print(f"\n== {name}: {len(rows)} frames")
        print(f"  race - clock values: {dict(offsets.most_common(3))}")
        print(f"  physics - clock values: {dict(physics.most_common(3))}")
        print(f"  takeoffs (race ms, lead ms): {takeoffs(rows)}")
        if name != "1x":
            missing = stamp_events(base) - stamp_events(rows)
            extra = stamp_events(rows) - stamp_events(base)
            # A sparse run can skip a short-lived value; a value the dense run
            # never showed is a real disagreement.
            print(f"  timestamps only in 1x: {len(missing)}; only here: {sorted(extra)[:10]}")
    print("\n== timestamp changes without a contact change (1x)")
    for before, after in zip(base, base[1:]):
        for wheel in range(4):
            if before["stamps"][wheel] != after["stamps"][wheel] and \
                    before["contacts"][wheel] == after["contacts"][wheel]:
                print(f"  race {after['race']} wheel {wheel} contacts {before['contacts']}->"
                      f"{after['contacts']} gap {after['clock'] - before['clock']} ms")
    print("\n== yaw rate candidates (r2, offset, slope)")
    for r2, offset, slope in yaw_rate_fit(base):
        print(f"  r2 {r2:.4f}  vehicle+{offset:#x}  slope {slope:+.4f}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Ask the user, then run it**

Ask the user to: load a TICK revision with several gorilla grips and at least one spin; turn on Debug → Log trainer events and Log every tire-force change; confirm the live run. Find the PID with `tasklist /FI "IMAGENAME eq Trackmania.exe"`. Then, from `Analysis/work`:

Run: `py -3 probe_wheel_stamps.py --pid <PID> --until-ms <race ms after the last jump of interest>`
Expected: three run summaries, a timestamp-change list, three yaw-rate candidates.

- [ ] **Step 3: Record the results in the spec**

Append to the spec a `## Stage 0 results` section (date, revision number, run list) that states each of these as a measured fact, with the numbers:

1. **Timestamps agree:** "only here" is empty for 4× and skip 5, and the takeoff lists (race ms, lead ms) are identical across the three runs.
2. **Clock source:** the most common `physics - clock` value. `0` → `clock source: GameTime`; any other constant → `clock source: physics clock`.
3. **Race offset:** `race - clock` has one value per run (derived race times are exact).
4. **Stamp-only changes:** each timestamp change without a contact change, with its explanation. Include the old `jump3` one-tick case: it is either a real touch-and-lift or something else.
5. **Yaw rate:** the best candidate. If `r2 >= 0.98` and the slope is within 5 % of ±1, record `yaw rate offset: 0x…` and `yaw rate scale: +1.0` or `-1.0`. Otherwise record `yaw rate offset: none`.

- [ ] **Step 4: Gate — stop and report to the user**

Show the user the recorded results. Continue with Task 3 only if (1) and (3) hold, and every stamp-only change in (4) is a real contact change (touch and lift inside one gap). If any of those fail, stop: the spec says to research the physics-tick hook instead, which needs a new design round.

- [ ] **Step 5: Commit**

```bash
git -c safe.directory='*' -C ../Analysis add work/probe_wheel_stamps.py
git -c safe.directory='*' -C ../Analysis commit -m "Probe wheel contact timestamps across frame rates"
git -c safe.directory='*' add docs/superpowers/specs/2026-09-27-tick-exact-timing-design.md
git -c safe.directory='*' commit -m "Record stage 0 timestamp results"
```

---

### Task 3: Exact takeoff lead; drop the gap rule and A+

**Files:**
- Modify: `plugin/Transitions.as` (constants, `GradeLead`, `JumpPreview`, helpers, `ObserveSteeringAndMode`, `StartFlight`, `Update`, `PublishUnrated`, `ResolveLanding` preview branch)
- Modify: `plugin/Physics.as` (only if Stage 0 recorded `clock source: physics clock`)
- Modify: `plugin/Session.as` (`JumpVerdict`)
- Modify: `plugin/History.as` (`HistoryJump(JumpVerdict@ …)`)
- Modify: `plugin/HistoryWindow.as` (lead text)
- Modify: `plugin/Widgets.as` (`ShowResult`, `ClearResult`, `RenderGradePreview`, `RenderWidgetCards`, `RenderWidgets`)
- Modify: `plugin/GradeAnimation.as` (`RenderResult`)
- Modify: `plugin/Main.as` (preview log line)
- Modify: `plugin/Settings.as` (rating help text)
- Test: `tests/test_tick_timing.py`, `tests/test_timing_display.py`, `tests/test_slide_check.py`, `tests/test_grade_animation.py`, `tests/test_popup_tab.py`, `tests/test_trainer_in_game.py`

**Interfaces:**
- Consumes: `PhysicsSnapshot.wheelChangedAt`, `PhysicsSnapshot.physicsClock` (Task 1).
- Produces: `const int PHYSICS_TICK_MS = 10;`, `string GradeLead(int leadMs)`, `JumpPreview.leadMs`, `JumpVerdict.leadMs`, `int LatestWheelChange(PhysicsSnapshot@ snap)`, `bool TakeoffStampsValid(PhysicsSnapshot@ before, PhysicsSnapshot@ after, int takeoff)`, `void RenderResult(const vec4 &in r, int age, const string &in label, uint seed)`, `string HistoryLead(HistoryJump@ jump)`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_tick_timing.py`:

```python

# Takeoff is the latest wheel lift-off; the lead is one exact number.
start = transitions.split("void StartFlight(", 1)[1].split("\n    }\n", 1)[0]
valid = transitions.split("bool TakeoffStampsValid(", 1)[1].split("\n}", 1)[0]
assert "const int PHYSICS_TICK_MS = 10;" in transitions
assert "MAX_TIMING_SAMPLE_GAP" not in transitions
assert "contact sample gap" not in transitions
assert "takeoffClock = LatestWheelChange(snap);" in start
assert "bool exactTakeoff = TakeoffStampsValid(previous, snap, takeoffClock);" in start
assert "takeoffRace = snap.raceTime - (snap.gameTime - takeoffClock);" in start
assert '"Contact timestamps were inconsistent at takeoff"' in start
assert "int lead = takeoffClock - switchAt;" in start
assert "string grade = GradeLead(lead);" in start
assert "preview.leadMs = lead;" in start
# A takeoff outside the frame interval, or a grounded wheel without a new
# timestamp, is not exact (Review Focus 3).
assert "if (takeoff <= before.gameTime || takeoff > after.gameTime) return false;" in valid
assert "if (at <= before.gameTime || at > after.gameTime) return false;" in valid
grade = transitions.split("string GradeLead(int leadMs) {", 1)[1].split("\n}", 1)[0]
assert "if (leadMs == 0) return \"S+\";" in grade
assert "string GradeLead(int lo" not in transitions
preview_class = transitions.split("class JumpPreview {", 1)[1].split("\n}", 1)[0]
assert "int leadMs = -1;" in preview_class and "ambiguous" not in preview_class
session = (root / "Session.as").read_text(encoding="utf-8")
verdict_class = session.split("class JumpVerdict {", 1)[1].split("\n}", 1)[0]
assert "int leadMs = -1;" in verdict_class
assert "timingEstimated" not in verdict_class and "leadMinMs" not in verdict_class
# The switch is noticed at any frame gap.
update_body = transitions.split("void Update(PhysicsSnapshot@ snap) {", 1)[1]
assert "\n        ObserveSteeringAndMode(snap);" in update_body
print("Exact takeoff lead: PASS")
```

Replace the whole of `tests/test_timing_display.py` with:

```python
"""The lead is one exact number: no + marker and no lead range on new results."""

from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
widgets = (root / "Widgets.as").read_text(encoding="utf-8")
popup = (root / "GradeAnimation.as").read_text(encoding="utf-8")
settings = (root / "Settings.as").read_text(encoding="utf-8")
history = (root / "HistoryWindow.as").read_text(encoding="utf-8")
main = (root / "Main.as").read_text(encoding="utf-8")

assert "ambiguous" not in widgets + popup + main
assert "g_resultTimingEstimated" not in widgets
assert "f.shown = label;" in popup
assert 'preview.leadMs + " ms"' in widgets
assert '" lead " + p.leadMs + "ms"' in main
# Older history entries keep their + marker and range.
assert 'jump.label != "S+" && jump.timingEstimated &&' in history
lead = history.split("string HistoryLead(HistoryJump@ jump) {", 1)[1].split("\n}", 1)[0]
assert 'if (jump.leadMinMs == jump.leadMaxMs) return jump.leadMinMs + " ms";' in lead
assert history.count("HistoryLead(jump)") == 2
assert 'S+ is awarded only for a 0 ms switch lead' in settings
assert "A+" not in settings
print("Exact lead display: PASS")
```

In `tests/test_slide_check.py`, replace:

```python
assert "snap.contactMask != 0 && snap.slipDeg >= S_MinSlideSlip" in update
assert "lastSlideClock = snap.gameTime;" in update
start = transitions.split("void StartFlight(", 1)[1].split("\n    }\n", 1)[0]
assert "lastSlideClock >= 0 && snap.gameTime - lastSlideClock <= SLIDE_WINDOW_MS" in start
```

with:

```python
# A slide lasts until the next frame that shows none, so a low frame rate
# never drops a real slide; the window ends at the exact takeoff tick.
assert "(snap.contactMask != 0 && snap.slipDeg >= S_MinSlideSlip) ||" in update
assert "(previous.contactMask != 0 && previous.slipDeg >= S_MinSlideSlip))" in update
assert "lastSlideClock = snap.gameTime;" in update
start = transitions.split("void StartFlight(", 1)[1].split("\n    }\n", 1)[0]
assert "lastSlideClock >= 0 && takeoffClock - lastSlideClock <= SLIDE_WINDOW_MS" in start
```

In `tests/test_grade_animation.py`, replace both occurrences of `"void RenderResult(const vec4 &in r, int age, const string &in label,\n    bool estimated, uint seed)"` with `"void RenderResult(const vec4 &in r, int age, const string &in label,\n    uint seed)"` (the first one keeps its trailing ` {`), and replace:

```python
assert 'f.shown = estimated && GradeBasePoints(label) > 0 ? label + "+" : label;' in render
```

with:

```python
assert "f.shown = label;" in render
```

In `tests/test_popup_tab.py`, replace `"RenderResult(grade.Pixels(), previewAge, g_popupPreviewLabel, false,\n                PopupPreviewSeed(g_popupPreviewLabel));"` with `"RenderResult(grade.Pixels(), previewAge, g_popupPreviewLabel,\n                PopupPreviewSeed(g_popupPreviewLabel));"`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python tests/test_tick_timing.py; python tests/test_timing_display.py; python tests/test_slide_check.py`
Expected: FAIL on `PHYSICS_TICK_MS`, `ambiguous`, and the slide assertion respectively.

- [ ] **Step 3: Apply the Stage 0 clock result**

Only if Stage 0 recorded `clock source: physics clock`: in `ReadPhysics`, directly after `snap.physicsClock = …;`, add:

```angelscript
    // Stage 0: the frame clock differs from the physics step's clock.
    snap.gameTime = snap.physicsClock;
```

Otherwise leave `ReadPhysics` unchanged.

- [ ] **Step 4: Constants, `GradeLead`, `JumpPreview`, helpers**

In `plugin/Transitions.as`, replace `const int MAX_TIMING_SAMPLE_GAP = 50;` with:

```angelscript
// The physics step runs in fixed 10 ms ticks.
const int PHYSICS_TICK_MS = 10;
```

Replace the whole of `string GradeLead(int lo, int hi) { … }` with:

```angelscript
string GradeLead(int leadMs) {
    NormalizeGradeThresholds();
    if (leadMs < 0 || leadMs > S_DMaxLeadMs) return "";
    // The switch happened on the tick the last wheel left.
    if (leadMs == 0) return "S+";
    if (leadMs <= S_SMaxLeadMs) return "S";
    if (leadMs <= S_AMaxLeadMs) return "A";
    if (leadMs <= S_BMaxLeadMs) return "B";
    if (leadMs <= S_CMaxLeadMs) return "C";
    return "D";
}

// Each wheel's timestamp holds the game clock of its last contact change, so
// once all wheels are airborne the latest one is the takeoff tick.
int LatestWheelChange(PhysicsSnapshot@ snap) {
    int latest = -1;
    for (uint i = 0; i < 4; i++)
        latest = Math::Max(latest, int(snap.wheelChangedAt[i]));
    return latest;
}

// The takeoff must lie between the two frames, and every wheel that was
// grounded on the first frame must have lifted in that interval.
bool TakeoffStampsValid(PhysicsSnapshot@ before, PhysicsSnapshot@ after, int takeoff) {
    if (takeoff <= before.gameTime || takeoff > after.gameTime) return false;
    for (uint i = 0; i < 4; i++) {
        if ((before.contactMask & (1 << i)) == 0) continue;
        int at = int(after.wheelChangedAt[i]);
        if (at <= before.gameTime || at > after.gameTime) return false;
    }
    return true;
}
```

In `class JumpPreview`, replace:

```angelscript
    bool ambiguous = false;
    int leadMinMs = -1;
    int leadMaxMs = -1;
```

with:

```angelscript
    int leadMs = -1;
```

- [ ] **Step 5: `StartFlight`**

Replace the body of `void StartFlight(PhysicsSnapshot@ snap) { … }` with:

```angelscript
    void StartFlight(PhysicsSnapshot@ snap) {
        inFlight = true;
        pendingLanding = false;
        flightUncertain = false;
        airSpinRadians = 0.0f;
        flightSpinCount = 0;
        spinReliable = true;
        previewPublished = false;
        cuePublished = false;
        @preview = null;
        unratedReason = "";
        takeoffClock = LatestWheelChange(snap);
        bool exactTakeoff = TakeoffStampsValid(previous, snap, takeoffClock);
        if (!exactTakeoff) takeoffClock = snap.gameTime;
        takeoffRace = snap.raceTime - (snap.gameTime - takeoffClock);
        takeoffMode = snap.mode;
        takeoffModeAt = int(snap.modeAt);
        int reversalLead = takeoffClock - rawReversalAt;
        takeoffReversalLeadMs = rawReversalAt >= 0 && reversalLead >= 0 &&
            reversalLead <= CUE_REVERSAL_WINDOW_MS ? reversalLead : -1;
        recoveryDelayMs = snap.recoveryDelayMs;
        // Only a jump out of an ice slide is a gorilla-grip attempt.
        flightEligible = takeoffMode != 0 &&
            lastSlideClock >= 0 && takeoffClock - lastSlideClock <= SLIDE_WINDOW_MS &&
            previous.meanIcing >= S_MinIcing &&
            previous.speedKmh >= float(S_MinSpeed);
        if (!flightEligible) return;
        bool attempted = switchAt >= 0 && switchNewMode == takeoffMode &&
            takeoffClock - switchAt <= S_DMaxLeadMs;
        if (!exactTakeoff) {
            flightUncertain = true;
            if (attempted) {
                unratedReason = "Contact timestamps were inconsistent at takeoff";
                unratedEvent = true;
            }
            return;
        }
        if (!attempted || switchOldMode == 0 || switchOldMode == takeoffMode ||
            switchAt > takeoffClock) return;
        int lead = takeoffClock - switchAt;
        string grade = GradeLead(lead);
        if (grade.Length == 0) return;
        @preview = JumpPreview();
        preview.label = grade;
        preview.leadMs = lead;
        preview.takeoffTime = takeoffRace;
        preview.oldMode = switchOldMode;
        preview.newMode = switchNewMode;
        preview.modeAt = switchAt;
    }
```

- [ ] **Step 6: `Update` without the gap rule**

In `Update(PhysicsSnapshot@ snap)`, delete the whole block:

```angelscript
        if (sampleGap > MAX_TIMING_SAMPLE_GAP) {
            …
        }
```

Replace:

```angelscript
        if (snap.contactMask != 0 && snap.slipDeg >= S_MinSlideSlip)
            lastSlideClock = snap.gameTime;
        if (sampleGap <= MAX_TIMING_SAMPLE_GAP) ObserveSteeringAndMode(snap);
        if (crossingTakeoff) {
            StartFlight(snap);
            if (sampleGap > MAX_TIMING_SAMPLE_GAP) switchAt = -1;
        }
```

with:

```angelscript
        // A slide lasts at least until the next frame that shows none.
        if ((snap.contactMask != 0 && snap.slipDeg >= S_MinSlideSlip) ||
            (previous.contactMask != 0 && previous.slipDeg >= S_MinSlideSlip))
            lastSlideClock = snap.gameTime;
        ObserveSteeringAndMode(snap);
        if (crossingTakeoff) StartFlight(snap);
```

`sampleGap` stays: the spin code uses it in Task 5. If the compiler warns that it is unused, leave the warning; Task 5 uses it.

- [ ] **Step 7: Verdict lead fields**

In `plugin/Session.as` `class JumpVerdict`, replace:

```angelscript
    int leadMinMs = -1;
    int leadMaxMs = -1;
```

with `    int leadMs = -1;`, and delete `    bool timingEstimated = false;`.

In `Transitions.as` `PublishUnrated`, replace:

```angelscript
        verdict.leadMinMs = preview is null ? -1 : preview.leadMinMs;
        verdict.leadMaxMs = preview is null ? -1 : preview.leadMaxMs;
        verdict.timingEstimated = preview !is null && preview.ambiguous;
```

with:

```angelscript
        verdict.leadMs = preview is null ? -1 : preview.leadMs;
```

In `ResolveLanding`'s `if (hasPreview)` branch, replace:

```angelscript
            verdict.reason = recovered ? (preview.ambiguous ?
                "Grip recovered; takeoff fell within samples that crossed a grade limit" :
                "Pre-takeoff mode held through force-eligible contact") :
```

with:

```angelscript
            verdict.reason = recovered ?
                "Pre-takeoff mode held through force-eligible contact" :
```

and replace:

```angelscript
            verdict.leadMinMs = preview.leadMinMs;
            verdict.leadMaxMs = preview.leadMaxMs;
            verdict.timingEstimated = preview.ambiguous;
```

with `            verdict.leadMs = preview.leadMs;`.

In `plugin/History.as` `HistoryJump(JumpVerdict@ verdict, …)`, replace:

```angelscript
        leadMinMs = verdict.leadMinMs;
        leadMaxMs = verdict.leadMaxMs;
```

with:

```angelscript
        // New entries store the exact lead in both fields.
        leadMinMs = verdict.leadMs;
        leadMaxMs = verdict.leadMs;
```

and delete `        timingEstimated = verdict.timingEstimated;`.

- [ ] **Step 8: Displays**

`plugin/HistoryWindow.as`: after `string HistoryGrade(HistoryJump@ jump) { … }`, add:

```angelscript
// Older entries may hold a lead range; new ones hold one exact value.
string HistoryLead(HistoryJump@ jump) {
    if (jump.leadMinMs < 0) return "--";
    if (jump.leadMinMs == jump.leadMaxMs) return jump.leadMinMs + " ms";
    return jump.leadMinMs + "-" + jump.leadMaxMs + " ms";
}
```

Replace `jump.leadMinMs < 0 ? "--" : jump.leadMinMs + "-" + jump.leadMaxMs + " ms",` with `HistoryLead(jump),`, and replace:

```angelscript
            UI::Text(jump.leadMinMs < 0 ? "--" :
                jump.leadMinMs + "-" + jump.leadMaxMs + " ms");
```

with `            UI::Text(HistoryLead(jump));`.

`plugin/Widgets.as`: delete `bool g_resultTimingEstimated = false;`, and the lines `    g_resultTimingEstimated = verdict.timingEstimated;` and `    g_resultTimingEstimated = false;`. In `RenderGradePreview`, delete `    string shownLabel = preview !is null && preview.ambiguous ? label + "+" : label;`, change `HudText(cx, cy - 1*s, shownLabel, 48.0f*s, accent, center);` to use `label`, and replace:

```angelscript
    string lead = preview is null ? "0-15 ms" :
        preview.leadMinMs + "-" + preview.leadMaxMs + " ms";
```

with:

```angelscript
    string lead = preview is null ? "12 ms" : preview.leadMs + " ms";
```

In `RenderWidgets`, replace `RenderResult(grade.Pixels(), previewAge, g_popupPreviewLabel, false,` with `RenderResult(grade.Pixels(), previewAge, g_popupPreviewLabel,`. In `RenderWidgetCards`, delete the argument line `                active && g_resultTimingEstimated,`.

`plugin/GradeAnimation.as`: change the signature to:

```angelscript
void RenderResult(const vec4 &in r, int age, const string &in label,
    uint seed) {
```

and replace `    f.shown = estimated && GradeBasePoints(label) > 0 ? label + "+" : label;` with `    f.shown = label;`.

`plugin/Main.as`: replace:

```angelscript
            " lead " + p.leadMinMs + "-" + p.leadMaxMs + "ms" +
            (p.ambiguous ? " conservative" : ""));
```

with:

```angelscript
            " lead " + p.leadMs + "ms");
```

`plugin/Settings.as`: in the rating `HelpMarker`, replace:

`\n\nS+ is awarded only for a confirmed 0-0 ms switch lead, with no separate threshold. It uses S points and sounds.\n\nThe + marker on A-D means takeoff happened between sampled frames that cross a grade limit. A+ still scores A; the true timing may qualify for a higher rank.`

with:

`\n\nS+ is awarded only for a 0 ms switch lead, with no separate threshold. It uses S points and sounds.\n\nTimes come from the game's own physics clock, so they do not depend on frame rate or game speed.`

`tests/test_trainer_in_game.py`: change the `PREVIEW` regex to `r"Gorilla Grip Trainer preview at (\d+)ms: (S\+|[SABCD]) lead (\d+)ms"`, and replace:

```python
            lead_min, lead_max = previews[0].group(3, 4)
            expected_grade = "S+" if (lead_min, lead_max) == ("0", "0") else "S"
            assert previews[0].group(2) == expected_grade, (
                f"Expected {expected_grade} for {lead_min}-{lead_max}ms, got {previews[0].group(2)}"
            )
```

with:

```python
            lead = previews[0].group(3)
            expected_grade = "S+" if lead == "0" else "S"
            assert previews[0].group(2) == expected_grade, (
                f"Expected {expected_grade} for {lead}ms, got {previews[0].group(2)}"
            )
```

- [ ] **Step 9: Run the tests**

Run: the full offline loop. Then `git -c safe.directory='*' diff --check`.
Expected: no `FAIL`, no whitespace errors. `grep -rn "leadMinMs\|ambiguous\|timingEstimated" plugin` shows only `History.as`, `HistoryWindow.as` and `Finish.as` (history fields).

- [ ] **Step 10: Install and check the compile**

trainer-live-verify steps 2–4. Expected: `check_load.py` exit 0.

- [ ] **Step 11: Commit**

```bash
git -c safe.directory='*' add plugin tests
git -c safe.directory='*' commit -m "Grade the takeoff from wheel timestamps"
```

---

### Task 4: Landing from timestamps and the stored mode

**Files:**
- Modify: `plugin/Transitions.as` (constants, helpers, tracker fields, `Reset`, `Land`, `ResolveLanding`, `Update`)
- Modify: `plugin/Main.as` (landing log lines)
- Test: `tests/test_tick_timing.py`, `tests/test_landing_confirmation.py`, `tests/test_touch_switch_reason.py`, `tests/test_late_switch_miss.py`

**Interfaces:**
- Consumes: `PHYSICS_TICK_MS`, `LatestWheelChange`, `takeoffClock` (Task 3).
- Produces: `int EarliestWheelChange(PhysicsSnapshot@ snap, int after)`, `int ContactStart(PhysicsSnapshot@ snap, uint mask, int after)`, `bool TouchedSince(PhysicsSnapshot@ snap, int after)`, tracker fields `int checkClock`, `int gateSeenAt`. `landingDirection` is removed.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_tick_timing.py`:

```python

# Landing: exact touchdown, touches between frames, and the stored direction
# as of a fixed check tick.
land = transitions.split("void Land(", 1)[1].split("\n    }\n", 1)[0]
resolve = transitions.split("void ResolveLanding(", 1)[1].split("\n    }\n", 1)[0]
pending = update_body.split("if (pendingLanding) {", 1)[1].split("\n        }\n", 1)[0]
assert "landingDirection" not in transitions
assert "landingClock = EarliestWheelChange(snap, takeoffClock);" in land
assert "landingRace = snap.raceTime - (snap.gameTime - landingClock);" in land
assert "landingTouchLifted = snap.contactMask == 0;" in land
# Review Focus 1: a touch and lift between two all-air frames.
assert "else if (inFlight && snap.contactMask == 0 && TouchedSince(snap, takeoffClock)) {" in update_body
assert "if (!pendingLanding) StartFlight(snap);" in update_body
assert "int frontSince = ContactStart(snap, FRONT_WHEELS, takeoffClock);" in pending
assert "if (snap.forceGateState != 0) gateSeenAt = snap.gameTime;" in pending
assert "Math::Max(landingClock + LANDING_CHECK_MS, eligibleAt + FORCE_SETTLE_MS)" in pending
assert "snap.gameTime >= checkAt" in pending
# Review Focus 2 and 5: the verdict uses the stored mode as of the check tick.
assert "bool switchedByCheck = storedAt != takeoffModeAt && storedAt <= checkClock;" in resolve
assert "bool stillHeld = snap.mode == takeoffMode && storedAt == takeoffModeAt;" in resolve
assert "(!stillHeld || snap.force > 1.001f)" in resolve
assert "storedAt <= landingClock + LANDING_STEER_MS" in resolve
print("Landing from timestamps and stored mode: PASS")
```

In `tests/test_landing_confirmation.py`, replace everything from `# Force is only expected once` to the end with:

```python
# Force is expected once a front wheel touches (the game updates the
# multiplier only for front wheels), the delay has run out, and the
# backwards-motion gate is clear. Eligibility starts at the exact touchdown.
assert "const uint FRONT_WHEELS = 0x3;" in transitions
assert "int frontSince = ContactStart(snap, FRONT_WHEELS, takeoffClock);" in pending_body
assert "Math::Max(frontSince, takeoffModeAt + recoveryDelayMs)" in pending_body
assert "snap.forceGateState == 0" in pending_body

# Deliberate gas-off spins can hold the gate longer; the wait counts from
# whichever comes later, touchdown or the end of the delay.
assert "const int FORCE_GATE_TIMEOUT_MS = 1000;" in transitions
assert "int deadline = FORCE_GATE_TIMEOUT_MS +" in pending_body
assert "Math::Max(landingClock, takeoffModeAt + recoveryDelayMs);" in pending_body

# A pass still needs the held mode and, while it is held, a rising multiplier.
assert "bool stillHeld = snap.mode == takeoffMode && storedAt == takeoffModeAt;" in resolve_body
assert "snap.force > 1.001f" in resolve_body
print("Landing confirmation waits for the delay, not the cutoff: PASS")
```

In `tests/test_touch_switch_reason.py`, replace:

```python
assert "landingTouchLifted = false;" in land_body
```

with:

```python
assert "landingTouchLifted = snap.contactMask == 0;" in land_body
```

and replace `assert "landingTouchLifted && int(snap.modeAt) != takeoffModeAt" in resolve_body` with `assert "bool touchSwitched = landingTouchLifted && switchedByCheck;" in resolve_body`.

In `tests/test_late_switch_miss.py`, replace:

```python
assert ("bool storedSwitched = snap.mode != 0 && snap.mode != takeoffMode &&\n"
        "            int(snap.modeAt) != takeoffModeAt;") in resolve_body
assert "(oppositeLanding || storedSwitched)" in no_preview
```

with:

```python
assert ("bool storedSwitched = switchedByCheck && snap.mode != 0 &&\n"
        "            snap.mode != takeoffMode;") in resolve_body
assert "storedSwitched && snap.force <= 1.1f" in no_preview
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python tests/test_tick_timing.py; python tests/test_landing_confirmation.py`
Expected: FAIL on `landingDirection` and on `ContactStart`.

- [ ] **Step 3: Constants, helpers, fields**

In `Transitions.as`, after `const int FORCE_SETTLE_MS = 30;`, add:

```angelscript
// The force check waits this long after touchdown.
const int LANDING_CHECK_MS = 80;
// The game stores an opposite landing steer within the first contact ticks.
const int LANDING_STEER_MS = 30;
```

After `bool TakeoffStampsValid(…) { … }`, add:

```angelscript
// Earliest contact change after `after` on any wheel: a touchdown, or the
// lift-off of a touch that already ended. -1 when there is none.
int EarliestWheelChange(PhysicsSnapshot@ snap, int after) {
    int earliest = -1;
    for (uint i = 0; i < 4; i++) {
        int at = int(snap.wheelChangedAt[i]);
        if (at <= after || at > snap.gameTime) continue;
        if (earliest < 0 || at < earliest) earliest = at;
    }
    return earliest;
}

// When the current contact of the grounded wheels in `mask` began: the
// earliest touchdown still in progress. -1 when none of them touches.
int ContactStart(PhysicsSnapshot@ snap, uint mask, int after) {
    int start = -1;
    for (uint i = 0; i < 4; i++) {
        if ((snap.contactMask & mask & (1 << i)) == 0) continue;
        int at = int(snap.wheelChangedAt[i]);
        if (at <= after || at > snap.gameTime) at = snap.gameTime;
        if (start < 0 || at < start) start = at;
    }
    return start;
}

// An airborne wheel whose timestamp is newer than `after` touched and lifted again.
bool TouchedSince(PhysicsSnapshot@ snap, int after) {
    for (uint i = 0; i < 4; i++)
        if ((snap.contactMask & (1 << i)) == 0 && int(snap.wheelChangedAt[i]) > after)
            return true;
    return false;
}
```

In `class TransitionTracker`, delete `    int landingDirection = 0;` and, after `    int forceEligibleClock = -1;`, add:

```angelscript
    // The tick the landing verdict is decided at, once known.
    int checkClock = -1;
    // Latest frame that showed the backwards-motion gate set, or -1.
    int gateSeenAt = -1;
```

In `Reset()`, delete `        landingDirection = 0;` and add after `        forceEligibleClock = -1;`:

```angelscript
        checkClock = -1;
        gateSeenAt = -1;
```

- [ ] **Step 4: `Land`**

Replace the body of `void Land(PhysicsSnapshot@ snap) { … }` with:

```angelscript
    void Land(PhysicsSnapshot@ snap) {
        inFlight = false;
        flightSpinCount = spinReliable ? int(airSpinRadians / (2.0f * Math::PI)) : 0;
        landingEvent = true;
        // The first contact change after takeoff dates the touchdown. A touch
        // that already lifted again only leaves its lift-off tick.
        landingClock = EarliestWheelChange(snap, takeoffClock);
        if (landingClock < 0) landingClock = snap.gameTime;
        landingRace = snap.raceTime - (snap.gameTime - landingClock);
        landingTouchLifted = snap.contactMask == 0;
        forceEligibleClock = -1;
        checkClock = -1;
        gateSeenAt = -1;
        pendingLanding = flightEligible && !flightUncertain &&
            landingRace - takeoffRace >= S_MinFlight;
        if (flightUncertain && (previewPublished || unratedReason.Length > 0))
            PublishUnrated(unratedReason.Length > 0 ? unratedReason :
                "Exact contact timing was lost during flight", landingRace);
    }
```

- [ ] **Step 5: `ResolveLanding`**

Replace the body of `void ResolveLanding(PhysicsSnapshot@ snap) { … }` with:

```angelscript
    void ResolveLanding(PhysicsSnapshot@ snap) {
        pendingLanding = false;
        bool hasPreview = preview !is null && previewPublished;
        bool enoughIcing = snap.meanIcing >= S_MinIcing;
        // The verdict uses the stored direction as of the check tick: a switch
        // stored after that tick had not happened yet.
        int storedAt = int(snap.modeAt);
        bool switchedByCheck = storedAt != takeoffModeAt && storedAt <= checkClock;
        bool stillHeld = snap.mode == takeoffMode && storedAt == takeoffModeAt;
        bool heldAtCheck = stillHeld || (storedAt != takeoffModeAt && !switchedByCheck);
        // Force corroborates only while the direction is still held; a later
        // switch has reset it, and the tick rule above decides.
        bool recovered = enoughIcing && heldAtCheck &&
            forceEligibleClock - takeoffModeAt >= recoveryDelayMs &&
            (!stillHeld || snap.force > 1.001f);
        // A scrape in flight counts as ground contact and can store the new
        // direction before the real landing; name it instead of a generic miss.
        bool touchSwitched = landingTouchLifted && switchedByCheck;
        const string touchReason = "Direction switched on a brief touch before the landing";
        // The stored direction changes only on the ground: after a neutral
        // landing, steering the other way switches it and delays the force.
        bool storedSwitched = switchedByCheck && snap.mode != 0 &&
            snap.mode != takeoffMode;
        bool oppositeLanding = storedSwitched && storedAt <= landingClock + LANDING_STEER_MS;
        if (hasPreview) {
            @verdict = JumpVerdict();
            verdict.label = recovered ? preview.label : "MISSED";
            verdict.reason = recovered ?
                "Pre-takeoff mode held through force-eligible contact" :
                (enoughIcing ? (touchSwitched ? touchReason :
                "Direction or tire force did not recover on force-eligible contact") :
                "Landing icing fell below the rating threshold");
            verdict.leadMs = preview.leadMs;
        } else if (enoughIcing && takeoffMode != 0 &&
            storedSwitched && snap.force <= 1.1f) {
            @verdict = JumpVerdict();
            verdict.label = "MISSED";
            verdict.reason = touchSwitched ? touchReason :
                takeoffReversalLeadMs >= 0 ?
                "Steering reversed " + takeoffReversalLeadMs +
                " ms before takeoff, too late to store the direction; it switched after the landing" :
                oppositeLanding ? "Opposite landing direction with delayed tire force" :
                "Direction switched after the landing with delayed tire force";
        } else {
            silentLandingEvent = true;
            return;
        }
        verdict.takeoffTime = takeoffRace;
        verdict.landingTime = landingRace;
        verdict.spinCount = flightSpinCount;
        verdict.exact = true;
        verdictEvent = true;
    }
```

- [ ] **Step 6: `Update`: touches between frames and the pending check**

Replace:

```angelscript
        if (crossingTakeoff) StartFlight(snap);
        else if (previous.contactMask == 0 && snap.contactMask != 0 && inFlight)
            Land(snap);
```

with:

```angelscript
        if (crossingTakeoff) StartFlight(snap);
        else if (previous.contactMask == 0 && snap.contactMask != 0 && inFlight)
            Land(snap);
        else if (inFlight && snap.contactMask == 0 && TouchedSince(snap, takeoffClock)) {
            // A wheel touched and lifted again between two frames: land, then
            // take off again unless this landing is being rated.
            Land(snap);
            if (!pendingLanding) StartFlight(snap);
        }
```

Replace the whole `if (pendingLanding) { … }` block with:

```angelscript
        if (pendingLanding) {
            if (snap.contactMask == 0) landingTouchLifted = true;
            // The backwards-motion gate has no timestamp; eligibility restarts
            // at the frame that shows it set.
            if (snap.forceGateState != 0) gateSeenAt = snap.gameTime;
            // Recovery waits for a front wheel on the ground and the delay.
            int frontSince = ContactStart(snap, FRONT_WHEELS, takeoffClock);
            int eligibleAt = frontSince < 0 ? -1 :
                Math::Max(Math::Max(frontSince, takeoffModeAt + recoveryDelayMs), gateSeenAt);
            int checkAt = eligibleAt < 0 ? -1 :
                Math::Max(landingClock + LANDING_CHECK_MS, eligibleAt + FORCE_SETTLE_MS);
            int deadline = FORCE_GATE_TIMEOUT_MS +
                Math::Max(landingClock, takeoffModeAt + recoveryDelayMs);
            if (flightUncertain)
                PublishUnrated("Landing contact timing became uncertain", snap.raceTime);
            else if (checkAt >= 0 && checkAt <= deadline && snap.forceGateState == 0 &&
                snap.gameTime >= checkAt) {
                forceEligibleClock = eligibleAt;
                checkClock = checkAt;
                ResolveLanding(snap);
            } else if (snap.gameTime > deadline)
                PublishUnrated("Tire-force contact never became eligible", snap.raceTime);
        }
```

- [ ] **Step 7: Main landing log lines**

In `plugin/Main.as`, replace:

```angelscript
            "ms: takeoff mode " + g_tracker.takeoffMode +
            ", landing steer " + g_tracker.landingDirection);
```

with:

```angelscript
            "ms: takeoff mode " + g_tracker.takeoffMode +
            ", stored mode " + next.mode);
```

and in the `silentLandingEvent` line delete `            ", landing steer " + g_tracker.landingDirection +`.

- [ ] **Step 8: Run the tests**

Run: the full offline loop, then `git -c safe.directory='*' diff --check`.
Expected: no `FAIL`.

- [ ] **Step 9: Install and check the compile**

trainer-live-verify steps 2–4. Expected: exit 0.

- [ ] **Step 10: Commit**

```bash
git -c safe.directory='*' add plugin tests
git -c safe.directory='*' commit -m "Decide landings from timestamps and the stored mode"
```

---

### Task 5: Gap-safe cue estimate and spins; remove the probe

**Files:**
- Modify: `plugin/Physics.as` (yaw-rate read; remove probe)
- Modify: `plugin/Transitions.as` (`EstimateReversal`, `ObserveSteeringAndMode`, `CountSpin`, `Update`, fields)
- Modify: `plugin/Main.as` (remove probe line)
- Test: `tests/test_tick_timing.py`, `tests/test_debug_logging.py:48`

**Interfaces:**
- Consumes: Stage 0 `yaw rate offset` and `yaw rate scale` from the spec; `PHYSICS_TICK_MS`.
- Produces: `PhysicsSnapshot.hasYawRate`, `PhysicsSnapshot.yawRate` (rad/s, same sign as `yaw` change), `int EstimateReversal(PhysicsSnapshot@ before, PhysicsSnapshot@ after)`, `void CountSpin(PhysicsSnapshot@ snap, int gapMs)`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_tick_timing.py`, replace the block from `# Stage 0 probe (removed again in Task 5).` through `print("Stage 0 probe line: PASS")` with:

```python
# The stage 0 probe is gone again.
assert "stamp probe" not in main and "probe" not in read
print("Stage 0 probe removed: PASS")
```

and append:

```python

# Estimates that never decide a grade.
observe = transitions.split("void ObserveSteeringAndMode(", 1)[1].split("\n    }\n", 1)[0]
estimate = transitions.split("int EstimateReversal(", 1)[1].split("\n}", 1)[0]
spin = transitions.split("void CountSpin(", 1)[1].split("\n    }\n", 1)[0]
assert "const float SMOOTHED_STEER_STEP = 0.2f;" in transitions
assert "rawReversalAt = EstimateReversal(previous, snap);" in observe
assert "if (previousGround && beforeRaw != 0" in observe
assert "Math::Clamp(after.gameTime - (ticks - 1) * PHYSICS_TICK_MS," in estimate
assert "if (snap.hasYawRate && previous.hasYawRate) {" in spin
assert "else if (gap > 0.0f && maxYawRate * gap > Math::PI) spinReliable = false;" in spin
assert "if (inFlight && previous.contactMask == 0) CountSpin(snap, sampleGap);" in update_body
assert "const int YAW_RATE_OFFSET = " in physics
print("Gap-safe cue and spins: PASS")
```

In `tests/test_debug_logging.py`, change `33` to `32` and the comment to `# 19 routine events, 12 problems, 1 state marker`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python tests/test_tick_timing.py`
Expected: FAIL on `stamp probe`.

- [ ] **Step 3: Physics: remove the probe, add the yaw rate**

In `plugin/Physics.as`, delete the `probe` field and its comment, and the `if (DebugForceTraceOn()) { … }` probe block in `ReadPhysics`. Above `class PhysicsSnapshot`, add the two Stage 0 values. Copy the offset and scale recorded in the spec's Stage 0 results; if it says `yaw rate offset: none`, use `-1` and `1.0f`:

```angelscript
// Vertical angular velocity on this build (stage 0 of the tick-exact timing
// spec); -1 when the field is unknown.
const int YAW_RATE_OFFSET = 0x5a4;  // example: use the recorded value
// Converts the stored value to rad/s with the sign of the yaw change.
const float YAW_RATE_SCALE = -1.0f;  // example: use the recorded value
```

(The two example values above are illustrative only; the recorded ones replace them.)

Add to `PhysicsSnapshot`, after `float yaw = 0.0f;`:

```angelscript
    // Yaw rate in rad/s, from the physics state; false when unknown.
    bool hasYawRate = false;
    float yawRate = 0.0f;
```

In `ReadPhysics`, after `snap.physicsClock = …;` (and the Task 3 clock line, if present), add:

```angelscript
    if (YAW_RATE_OFFSET >= 0) {
        snap.yawRate = YAW_RATE_SCALE * Dev::SafeReadFloat(vehicle + uint64(YAW_RATE_OFFSET));
        snap.hasYawRate = Math::Abs(snap.yawRate) < 100.0f;
    }
```

In `plugin/Main.as`, delete the `if (next.exact && DebugForceTraceOn()) DebugLog("Gorilla Grip Trainer stamp probe at " …);` statement.

- [ ] **Step 4: Reversal estimate**

In `Transitions.as`, after `const int CUE_REVERSAL_WINDOW_MS = 250;`, add:

```angelscript
// Smoothed steering follows the input by about 0.2 per tick on ice.
const float SMOOTHED_STEER_STEP = 0.2f;
```

After `bool TouchedSince(…) { … }`, add:

```angelscript
// Dates a raw steering reversal inside a frame gap from how far the smoothed
// steering has moved toward the new side. Once it has reached the input, the
// travel no longer tells when it started: take the earliest possible tick.
int EstimateReversal(PhysicsSnapshot@ before, PhysicsSnapshot@ after) {
    int earliest = Math::Min(before.gameTime + PHYSICS_TICK_MS, after.gameTime);
    if (Math::Abs(after.smoothedSteer - after.rawSteer) < 0.001f) return earliest;
    float travel = Math::Abs(after.smoothedSteer - before.smoothedSteer);
    int ticks = Math::Max(1, int(travel / SMOOTHED_STEER_STEP + 0.999f));
    return Math::Clamp(after.gameTime - (ticks - 1) * PHYSICS_TICK_MS,
        earliest, after.gameTime);
}
```

In `ObserveSteeringAndMode`, replace:

```angelscript
        bool previousGround = previous.contactMask != 0;
        bool currentGround = snap.contactMask != 0;
        int beforeRaw = RawDirection(previous.rawSteer);
        int afterRaw = RawDirection(snap.rawSteer);
        if (previousGround && currentGround && beforeRaw != 0 && afterRaw != 0 &&
            beforeRaw != afterRaw && previous.mode == beforeRaw)
            rawReversalAt = snap.gameTime;
```

with:

```angelscript
        bool previousGround = previous.contactMask != 0;
        int beforeRaw = RawDirection(previous.rawSteer);
        int afterRaw = RawDirection(snap.rawSteer);
        // A reversal first seen on the all-air frame may still have happened
        // on the ground; StartFlight keeps it only if it dates before takeoff.
        if (previousGround && beforeRaw != 0 && afterRaw != 0 &&
            beforeRaw != afterRaw && previous.mode == beforeRaw)
            rawReversalAt = EstimateReversal(previous, snap);
```

- [ ] **Step 5: Spins**

In `class TransitionTracker`, after `    bool spinReliable = true;`, add:

```angelscript
    // Fastest yaw rate seen in this flight, for the no-yaw-rate fallback.
    float maxYawRate = 0.0f;
```

Add `        maxYawRate = 0.0f;` to `Reset()` (after `spinReliable = true;`) and to `StartFlight` (after `spinReliable = true;`).

Add the method, before `void Update(PhysicsSnapshot@ snap)`:

```angelscript
    // Adds the yaw turned since the previous airborne frame. With the yaw rate
    // known, the turn is unwrapped to the whole-turn count the rate predicts,
    // so a long frame gap cannot lose or add a turn. Without it, a gap long
    // enough to hide half a turn makes the count unreliable.
    void CountSpin(PhysicsSnapshot@ snap, int gapMs) {
        float turn = snap.yaw - previous.yaw;
        if (turn > Math::PI) turn -= 2.0f * Math::PI;
        if (turn < -Math::PI) turn += 2.0f * Math::PI;
        float gap = float(gapMs) / 1000.0f;
        if (snap.hasYawRate && previous.hasYawRate) {
            float expected = 0.5f * (snap.yawRate + previous.yawRate) * gap;
            float turns = (expected - turn) / (2.0f * Math::PI);
            int whole = int(turns >= 0.0f ? turns + 0.5f : turns - 0.5f);
            turn += 2.0f * Math::PI * float(whole);
        } else if (gap > 0.0f && maxYawRate * gap > Math::PI) spinReliable = false;
        if (gap > 0.0f) maxYawRate = Math::Max(maxYawRate, Math::Abs(turn) / gap);
        airSpinRadians += Math::Abs(turn);
    }
```

In `Update`, replace:

```angelscript
        if (inFlight && previous.contactMask == 0) {
            float turn = snap.yaw - previous.yaw;
            if (turn > Math::PI) turn -= 2.0f * Math::PI;
            if (turn < -Math::PI) turn += 2.0f * Math::PI;
            airSpinRadians += Math::Abs(turn);
        }
```

with:

```angelscript
        if (inFlight && previous.contactMask == 0) CountSpin(snap, sampleGap);
```

- [ ] **Step 6: Run the tests**

Run: the full offline loop, then `git -c safe.directory='*' diff --check`.
Expected: no `FAIL`.

- [ ] **Step 7: Install and check the compile**

trainer-live-verify steps 2–4. Expected: exit 0.

- [ ] **Step 8: Commit**

```bash
git -c safe.directory='*' add plugin tests
git -c safe.directory='*' commit -m "Estimate cue reversals and count spins across frame gaps"
```

---

### Task 6: Frame-independence check in game

**Files:**
- Modify: `plugin/Main.as` (verdict log line)
- Create: `tests/test_frame_independence_in_game.py`
- Test: `tests/test_tick_timing.py`

**Interfaces:**
- Consumes: `JumpVerdict.leadMs`, `takeoffTime`, `landingTime` (Tasks 3–4); `frame skip` log line (Task 1); `tick_client.TickClient`, `tick_restart.Live`, `tick_restart.restart` from the research repository.
- Produces: verdict lines ending in `| takeoff Tms | landing Lms | lead Nms`.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_tick_timing.py`:

```python

# Verdict lines carry the exact takeoff, landing and lead for comparison runs.
verdict_log = main.split('DebugLog("Gorilla Grip Trainer verdict at', 1)[1].split(";", 1)[0]
assert '" | score " + g_session.score +' in verdict_log
assert '" | takeoff " + v.takeoffTime + "ms | landing " + v.landingTime +' in verdict_log
assert '"ms | lead " + v.leadMs + "ms"' in verdict_log
print("Verdict lines carry exact times: PASS")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python tests/test_tick_timing.py`
Expected: FAIL on the `takeoff` assertion.

- [ ] **Step 3: Extend the verdict line**

In `plugin/Main.as`, replace:

```angelscript
            " | spins " + v.spinCount + " | combo " + g_session.combo +
            " | score " + g_session.score);
```

with:

```angelscript
            " | spins " + v.spinCount + " | combo " + g_session.combo +
            " | score " + g_session.score +
            " | takeoff " + v.takeoffTime + "ms | landing " + v.landingTime +
            "ms | lead " + v.leadMs + "ms");
```

- [ ] **Step 4: Write the in-game check**

Create `tests/test_frame_independence_in_game.py`:

```python
"""One TICK replay must get the same results at any frame rate or game speed.

Replays the loaded TICK revision four times: 1x; 4x; 1x with the Trainer
processing every 5th frame; 4x every 3rd frame. Every verdict must match the
first run: grade, reason, spins, combo, score, takeoff, landing, and lead. The
"Steering reversed N ms" number in a reason is an estimate and is masked.

Needs Trackmania, TICK, and a local clone of
https://github.com/Teuflum/tm-gorilla-grip-reverse-engineering (for
work/tick_client.py and work/tick_restart.py), passed as --research-root.
Needs Openplanet developer mode and Settings -> Gorilla Grip Trainer -> Debug
-> Log trainer events. Only the game speed changes; it is restored at the end.

Usage: py -3 tests/test_frame_independence_in_game.py --research-root <path>
       --pid <Trackmania PID> --until-ms <race ms after the last jump>
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from trainer_log import LOG, require_event_logging


VERDICT = re.compile(
    r"Gorilla Grip Trainer verdict at (-?\d+)ms: (\S+) \| (.*?) \| force .*?"
    r"\| spins (\d+) \| combo (\d+) \| score (\d+) \| takeoff (-?\d+)ms \| "
    r"landing (-?\d+)ms \| lead (-?\d+)ms")
SKIP = re.compile(r"Gorilla Grip Trainer frame skip (\d+)")
RUNS = [("1x", 1, 1), ("4x", 4, 1), ("1x every 5th frame", 1, 5), ("4x every 3rd frame", 4, 3)]


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


def verdicts(text: str) -> list[tuple]:
    rows = []
    for m in VERDICT.finditer(text):
        reason = re.sub(r"reversed \d+ ms", "reversed N ms", m[3])
        rows.append((m[2], reason, int(m[4]), int(m[5]), int(m[6]),
                     int(m[7]), int(m[8]), int(m[9])))
    return rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--research-root", required=True, type=Path)
    parser.add_argument("--pid", required=True, type=int)
    parser.add_argument("--until-ms", required=True, type=int)
    args = parser.parse_args()
    require_event_logging()
    sys.path.insert(0, str(args.research_root / "work"))
    from tick_client import TickClient
    from tick_restart import Live, restart

    client = TickClient()
    original_speed = client.get("runtime/game-speed")["requestedGameSpeed"]
    live = Live(client)
    results: dict[str, list[tuple]] = {}
    try:
        for name, speed, skip in RUNS:
            if current_skip() != skip:
                input(f"Set Debug -> Process every Nth frame to {skip}, then press Enter ")
            assert current_skip() == skip, f"The Trainer did not log frame skip {skip}"
            offset = log_size()
            client.request("PUT", "runtime/game-speed", {"requestedGameSpeed": speed})
            restart(args.pid, client, live)
            live.wait(lambda: live.tick >= args.until_ms,
                      args.until_ms / 1000 / speed + 30, f"race {args.until_ms} ms")
            results[name] = verdicts(log_since(offset))
            print(f"{name}: {len(results[name])} verdicts")
    finally:
        client.request("PUT", "runtime/game-speed", {"requestedGameSpeed": original_speed})
        live.close()
        print("Set Debug -> Process every Nth frame back to 1.")

    base = results["1x"]
    assert len(base) >= 3, "Pick a revision with at least three rated jumps"
    if not any(row[2] > 0 for row in base):
        print("Note: no spin in this revision; spin counting was not compared.")
    if not any(row[0] == "MISSED" for row in base):
        print("Note: no MISSED in this revision; the miss path was not compared.")
    failed = False
    for name, rows in results.items():
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


if __name__ == "__main__":
    main()
```

- [ ] **Step 5: Run the offline tests, install, check the compile**

Run: the full offline loop; then trainer-live-verify steps 2–4.
Expected: no `FAIL`; `check_load.py` exit 0.

- [ ] **Step 6: Ask the user, then run the in-game check**

Ask the user to load a revision with at least three rated jumps, ideally including a spin and a miss, and to confirm the live run. From `Trainer/`:

Run: `py -3 tests/test_frame_independence_in_game.py --research-root ../Analysis --pid <PID> --until-ms <ms>`
Expected: four run counts, then `Same results at every frame rate and game speed: PASS`. On a difference, use the trainer-run-analysis skill on the differing jump before changing code.

- [ ] **Step 7: Commit**

```bash
git -c safe.directory='*' add plugin/Main.as tests/test_tick_timing.py tests/test_frame_independence_in_game.py
git -c safe.directory='*' commit -m "Check results match across frame rates and game speeds"
```

---

### Task 7: Documentation and version

**Files:**
- Modify: `docs/superpowers/specs/2026-09-25-gorilla-grip-trainer.md` (timing paragraphs, lines 25, 27, 40, 42)
- Modify: `README.md` (rating section)
- Modify: `plugin/info.toml` (version)
- Modify: `tests/test_readme_setup.py`
- Modify: `../Analysis/outputs/gorilla_grip_mechanism.md` (research repository)
- Modify: `../.claude/skills/trainer-run-analysis/references/state-machine.md` (workspace skill, stored in Google Drive)

**Interfaces:**
- Consumes: Stage 0 results (spec), final code from Tasks 3–6.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_readme_setup.py`:

```python
# Grades come from the game's physics clock; A+ is gone.
assert "don't depend on frame rate or game speed" in readme
assert "`A+`" not in readme
info = (Path(__file__).resolve().parents[1] / "plugin" / "info.toml").read_text(encoding="utf-8")
assert 'version = "0.3.0"' in info
```

(If `Path` is not yet imported in that file, add `from pathlib import Path` at the top.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `python tests/test_readme_setup.py`
Expected: FAIL on the frame-rate sentence.

- [ ] **Step 3: README and version**

In `README.md` under "How a jump is rated", delete the bullet that starts ``- **`A+`:**``, and add after the grade table's bullets:

```markdown
Timing comes from the game's own physics clock, so grades don't depend on frame rate or game speed.
```

In `plugin/info.toml`, set `version = "0.3.0"`.

- [ ] **Step 4: Main design spec**

In `docs/superpowers/specs/2026-09-25-gorilla-grip-trainer.md`:
- Line 25: replace the last sentence ("If the exact mode transition was missed because sampling was too sparse …") with: "If the wheel timestamps at takeoff are inconsistent, the attempt is `UNRATED`, not a guessed grade."
- Line 27: replace the paragraph with a description of the takeoff tick (the latest of the four wheel timestamps at `vehicle + 0x1820 + 0xb8·i` on the first all-air frame, valid only inside the frame interval), the exact lead `takeoffTick − modeAt`, and a pointer to `2026-09-27-tick-exact-timing-design.md`. Keep the +13 example as the evidence that the switch and the last lift-off can share a tick (lead 0 = S+).
- Line 40: replace "S+ requires the fixed, confirmed `0–0 ms` lead interval" with "S+ requires a 0 ms lead", and drop the sentence "The 10 ms physics tick and display sampling do not justify sub-tick precision claims." Replace "a conservative timing grade requires a valid bounded interval" with "timing comes from the physics timestamps, not from display frames".
- Line 42: rewrite the landing paragraph to the rules of the tick-exact spec's *Landing* section: landing tick, touches between frames, stored-mode direction, the check tick `max(landing + 80 ms, eligible + 30 ms)`, force corroboration only while the mode is held, the backwards-motion gate sampled per frame, the neutral-landing behaviour change, and the one remaining edge (mode cleared to neutral between the check tick and a late frame counts as not held).

- [ ] **Step 5: Research note and skill reference**

In `../Analysis/outputs/gorilla_grip_mechanism.md`, after the "Live HUD timing" paragraph, add a paragraph: each wheel's block at `vehicle + 0x17b4 + 0xb8·i` holds, at `+0x6c`, the game clock of that wheel's last contact change; the eight takeoff captures and the Stage 0 runs (cite their date and numbers from the spec) show it records the exact tick even between samples, so the last-wheel departure tick is the latest of the four once all are airborne. Replace "The HUD still samples at display-frame resolution, so it does not identify the exact last-wheel physics tick." with "The Trainer reads these per-wheel timestamps (below), so it identifies the exact last-wheel physics tick at any frame rate."

In `../.claude/skills/trainer-run-analysis/references/state-machine.md`:
- Replace the lead-bounds sentence ("Lead bounds are `max(0, lastContactClock − modeAt)` … the lower grade when bounds straddle a limit.") with: "The lead is `takeoffTick − modeAt`, where `takeoffTick` is the latest wheel timestamp (`vehicle+0x1820+0xb8·i`) on the first all-air frame; `GradeLead` maps it to S+/S/A/B/C/D."
- Replace "grounded samples where raw steering flips sign" with "frames starting grounded where raw steering flips sign; the tick is estimated from the smoothed-steering travel (0.2 per tick)".
- Replace `preview at … lead lo-hi ms` with `preview at … lead N ms`, and "a sample gap in flight makes it unreliable" with "unwrapped with the yaw rate; without it, a gap that could hide half a turn makes it unreliable".
- In the no-preview MISSED rule, replace "the landing steer is opposite or the stored mode switched since takeoff" with "the stored mode switched between takeoff and the check tick".

- [ ] **Step 6: Run the tests**

Run: the full offline loop and `git -c safe.directory='*' diff --check`.
Expected: no `FAIL`.

- [ ] **Step 7: Commit**

```bash
git -c safe.directory='*' add README.md plugin/info.toml tests/test_readme_setup.py docs/superpowers/specs/2026-09-25-gorilla-grip-trainer.md
git -c safe.directory='*' commit -m "Document tick-exact timing and bump to 0.3.0"
git -c safe.directory='*' -C ../Analysis add outputs/gorilla_grip_mechanism.md
git -c safe.directory='*' -C ../Analysis commit -m "Note the per-wheel contact timestamps"
```

The skill reference lives in Google Drive and is not in either repository; it needs no commit.
