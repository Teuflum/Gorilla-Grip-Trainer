"""The Last Run widget shows this map's latest rated attempt from the history."""

from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
sources = {path.name: path.read_text(encoding="utf-8") for path in root.glob("*.as")}
widgets = sources["Widgets.as"]

# No separate in-memory summary that starts empty on every load.
for name, text in sources.items():
    assert "LastRunSummary" not in text, name
    assert "g_lastRun" not in text, name

lookup = widgets.split("RunRecord@ LastRatedRun() {", 1)[1].split("\n}", 1)[0]
assert "CurrentMapUid()" in lookup
assert "run.mapUid == mapUid && run.hits + run.misses > 0" in lookup
assert "for (int i = int(g_history.runs.Length) - 1; i >= 0; i--)" in lookup
# Recompute only when the map or the newest saved attempt changes; the
# history is capped, so the count alone can stay the same.
assert "g_history.runs[g_history.runs.Length - 1].id" in lookup

render = widgets.split("void RenderLast(const vec4 &in r, RunRecord@ last) {", 1)[1].split("\n}", 1)[0]
assert 'Time::FormatString("%Y-%m-%d %H:%M", last.startedAt / 1000)' in render
assert "RenderLast(layout.Pixels(), LastRatedRun());" in widgets
print("Last Run widget reads this map's history: PASS")
