"""The start countdown begins the next attempt, not the timer reaching 0:00."""

from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
main = (root / "Main.as").read_text(encoding="utf-8")
update = main.split("void Update(float dt) {", 1)[1].split("\n}", 1)[0]

# The finish screen returns before any race-time handling.
assert update.index("if (finishSequence) {") < update.index("int t = ReadRaceTime(vis);")

countdown = update.split("int t = ReadRaceTime(vis);", 1)[1].split("\n    }", 1)[0]
assert countdown.lstrip().startswith("if (t < 0) {"), countdown
# A countdown ends a finished or running attempt; a failed read (-1) does not.
guard = "if (t < -1 && (g_activeRun !is null || g_finish.summary !is null)) {"
assert guard in countdown
reset = countdown.split(guard, 1)[1]
for step in ("ResetAttemptState();",
             "if (g_finish.summary !is null) g_finish.NewAttempt();",
             "g_previousRaceTime = -1;"):
    assert step in reset, step
# Widgets stay up during the countdown; the tracker is not fed.
assert "if (g_activeRun is null) @g_snapshot = ReadPhysics(vis, t);" in countdown
assert "g_tracker.Update" not in countdown
assert countdown.rstrip().endswith("return;")
widgets = (root / "Widgets.as").read_text(encoding="utf-8")
render = widgets.split("void RenderWidgetCards(int previewAge) {", 1)[1].split("\n}", 1)[0]
assert "if (g_snapshot is null) return;" in render
assert "raceTime < 0" not in render

# ResetAttemptState stops the looping results music.
reset_state = main.split("void ResetAttemptState() {", 1)[1].split("\n}", 1)[0]
assert "g_audio.OnReset();" in reset_state
audio = (root / "AudioDirector.as").read_text(encoding="utf-8")
on_reset = audio.split("void OnReset() {", 1)[1].split("\n    }", 1)[0]
assert "StopResults();" in on_reset
print("The start countdown resets the attempt and shows the widgets: PASS")
