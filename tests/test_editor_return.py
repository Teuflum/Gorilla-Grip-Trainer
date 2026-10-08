"""Returning to the map editor after a validation run ends the finished attempt."""

from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
main = (root / "Main.as").read_text(encoding="utf-8")
update = main.split("void Update(float dt) {", 1)[1].split("\n}", 1)[0]
no_car = update.split("if (vis is null) {", 1)[1].split("\n    }\n", 1)[0]

# The same-map keep applies only outside the editor; otherwise the attempt
# resets, which stops the finish music.
keep = no_car.split("{", 1)[0]
assert "!IsEditingMap()" in keep, keep
assert "CurrentMapUid() == g_finish.summary.mapUid" in keep, keep
assert "ResetAttemptState();" in no_car.split("return;", 1)[1]

finish = (root / "Finish.as").read_text(encoding="utf-8")
editing = finish.split("bool IsEditingMap() {", 1)[1].split("\n}", 1)[0]
assert "app.Editor !is null" in editing
assert "app.CurrentPlayground is null" in editing
print("Returning to the editor resets the finished attempt: PASS")
