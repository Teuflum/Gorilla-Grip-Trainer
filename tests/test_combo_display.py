"""Combo displays show the streak of successful landings, starting at x0.

After each successful landing the streak equals the multiplier that landing
scored with; scoring itself stays min(streak + 1, 8) for the next landing.
"""

from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
sources = {path.name: path.read_text(encoding="utf-8") for path in root.glob("*.as")}
session = sources["Session.as"]
widgets = sources["Widgets.as"]

# Scoring is unchanged and separate from what the HUD shows.
assert "int ScoringMultiplier(int completedStreak) {" in session
assert "return Math::Min(completedStreak + 1, 8);" in session
assert "int multiplier = ScoringMultiplier(combo);" in session
for name, text in sources.items():
    assert "DisplayComboMultiplier" not in text, name
    assert "CurrentMultiplier" not in text, name

# Every combo display shows the plain streak.
assert 'RenderStat(layout.Pixels(), "COMBO", "x" + g_session.combo,' in widgets
assert '"x" + g_session.bestCombo,' in widgets
assert '"x" + last.bestCombo}' in widgets
assert '"x" + run.bestCombo}' in sources["Finish.as"]
history = sources["HistoryWindow.as"]
assert 'UI::Text("x" + jump.combo);' in history
assert '"x" + run.bestCombo' in history  # selected-attempt tile
print("Combo displays start at x0 and scoring is unchanged: PASS")
