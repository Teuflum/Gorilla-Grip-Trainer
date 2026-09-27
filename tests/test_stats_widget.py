"""One Stats card replaces the separate Combo, Score and Best combo cards."""

import re
from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
layout = (root / "Layout.as").read_text(encoding="utf-8")
widgets = (root / "Widgets.as").read_text(encoding="utf-8")

# The Layout tab has one Stats entry and no separate stat entries.
assert 'WidgetLayout("stats", "Stats", vec4(0.030f, 0.701f, 0.160f, 0.130f), true)' in layout
for old in ("combo", "score", "best"):
    assert f'WidgetLayout("{old}"' not in layout, old
    assert f'GetLayout("{old}")' not in widgets, old
assert widgets.count('GetLayout("stats")') == 1

# The old placement settings stay stored so the Stats card can start there.
floats = dict(re.findall(r"\[Setting hidden\] float (S_\w+) = ([0-9.]+)f;", layout))
bools = dict(re.findall(r"\[Setting hidden\] bool (S_\w+) = (true|false);", layout))
for prefix in ("Combo", "Score", "Best"):
    for key in "XYWH":
        assert f"S_{prefix}{key}" in floats, (prefix, key)
    assert f"S_{prefix}Visible" in bools, prefix
assert bools["S_StatsMigrated"] == "false"

init = layout.split("void InitLayout() {", 1)[1].split("\n}", 1)[0]
migration = init.split("if (!S_StatsMigrated) {", 1)[1].split("\n    }", 1)[0]
assert init.index("if (!S_StatsMigrated) {") < init.index("LoadLayoutSettings();")
for line in (
    "float left = Math::Min(S_ComboX, Math::Min(S_ScoreX, S_BestX));",
    "float width = Math::Max(S_ComboW, Math::Max(S_ScoreW, S_BestW));",
    "S_StatsX = left; S_StatsW = width;",
    "S_StatsY = Math::Max(0.0f, bottom - S_StatsH);",
    "S_StatsVisible = S_ComboVisible || S_ScoreVisible || S_BestVisible;",
    "S_StatsMigrated = true;",
):
    assert line in migration, line
for part in ("S_ComboY + S_ComboH", "S_ScoreY + S_ScoreH", "S_BestY + S_BestH"):
    assert part in migration, part

# Migrating the shipped stat boxes lands exactly on the Stats default,
# directly above Last run.
f = {k: float(v) for k, v in floats.items()}
left = min(f["S_ComboX"], f["S_ScoreX"], f["S_BestX"])
width = max(f["S_ComboW"], f["S_ScoreW"], f["S_BestW"])
bottom = max(f[f"S_{p}Y"] + f[f"S_{p}H"] for p in ("Combo", "Score", "Best"))
migrated = (left, bottom - f["S_StatsH"], width, f["S_StatsH"])
default = (f["S_StatsX"], f["S_StatsY"], f["S_StatsW"], f["S_StatsH"])
assert all(abs(a - b) < 1e-6 for a, b in zip(migrated, default)), (migrated, default)
assert f["S_LastY"] - (default[1] + default[3]) < 0.01

# Load and save cover the five widgets in their list order.
load = layout.split("void LoadLayoutSettings() {", 1)[1].split("\n}", 1)[0]
assert "vec4(S_StatsX, S_StatsY, S_StatsW, S_StatsH)" in load
assert "S_StatsVisible" in load
for old in ("S_ComboX", "S_ScoreX", "S_BestX"):
    assert old not in load, old
save = layout.split("void SaveLayoutSettings() {", 1)[1].split("\n}", 1)[0]
assert "S_StatsX = a.x; S_StatsY = a.y; S_StatsW = a.z; S_StatsH = a.w;" in save
for old in ("S_ComboX", "S_ScoreX", "S_BestX"):
    assert old not in save, old

# One card shows all three values, each with its own animation.
assert "void RenderStat(" not in widgets
assert "void RenderStats(" in widgets
stats = widgets.split("void RenderStats(", 1)[1].split("\n}", 1)[0]
for text in ('"SCORE"', '"COMBO"', '"BEST"', '"NEW BEST"', '"BROKEN"', '"+1"',
             '"x" + g_session.combo', '"x" + g_session.bestCombo',
             '"+" + g_statEarned'):
    assert text in stats, text
for pulse in ("scorePulse", "comboPulse", "bestPulse"):
    assert pulse in stats, pulse
print("One Stats card replaces Combo, Score and Best combo: PASS")
