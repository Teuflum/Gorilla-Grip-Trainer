"""Improve ends the finished attempt at the start countdown, not at 0:00."""

from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
main = (root / "Main.as").read_text(encoding="utf-8")
update = main.split("void Update(float dt) {", 1)[1].split("\n}", 1)[0]

# The finish screen returns before any race-time handling.
assert update.index("if (finishSequence) {") < update.index("int t = ReadRaceTime(vis);")

countdown = update.split("int t = ReadRaceTime(vis);", 1)[1].split("\n    }", 1)[0]
assert countdown.lstrip().startswith("if (t < 0) {"), countdown
guarded = countdown.split("if (g_finish.summary !is null) {", 1)[1]
for step in ("ResetAttemptState();", "g_finish.NewAttempt();", "g_previousRaceTime = -1;"):
    assert step in guarded, step
assert guarded.rstrip().endswith("return;")

# ResetAttemptState stops the looping results music.
reset = main.split("void ResetAttemptState() {", 1)[1].split("\n}", 1)[0]
assert "g_audio.OnReset();" in reset
audio = (root / "AudioDirector.as").read_text(encoding="utf-8")
on_reset = audio.split("void OnReset() {", 1)[1].split("\n    }", 1)[0]
assert "StopResults();" in on_reset
print("Improve stops the finish music at the start countdown: PASS")
