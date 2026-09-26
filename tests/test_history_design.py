"""The run history window uses the HUD's card style throughout."""

from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
window = (root / "HistoryWindow.as").read_text(encoding="utf-8")


def body(signature):
    return window.split(signature, 1)[1].split("\n}", 1)[0]


# Large text uses a bold font loaded once.
assert 'UI::LoadFont("DroidSans-Bold.ttf", 22)' in window

# Section headers are HUD captions with an accent bar, not ImGui separators.
assert "UI::SeparatorText" not in window
assert "UI::Separator()" not in window
header = body("void RenderHistoryHeader(")
assert ".AddRectFilled(" in header and ".AddText(" in header
for caption in ('"ATTEMPTS"', '"SELECTED ATTEMPT"'):
    assert f"RenderHistoryHeader({caption}" in window, caption
assert 'RenderHistoryHeader("JUMPS  " + selected.jumps.Length' in window

# One tile helper draws every stat row.
tiles = body("void RenderHistoryTiles(")
assert "UI::GetWindowDrawList()" in tiles
assert tiles.count(".AddRectFilled(") >= 2  # card and accent strip
assert ".AddText(" in tiles
assert "UI::Dummy(" in tiles

attempt = body("void RenderAttemptTiles(RunRecord@ run) {")
for caption in ("RESULT", "SCORE", "BEST COMBO", "HITS", "MISSES"):
    assert f'"{caption}"' in attempt, caption
assert '"x" + run.bestCombo' in attempt
assert "RenderHistoryTiles(" in attempt

jump = body("void RenderJumpTiles(HistoryJump@ jump) {")
for caption in ("GRADE", "LANDING", "LEAD", "POINTS", "COMBO"):
    assert f'"{caption}"' in jump, caption
assert "GradeColor(jump.label)" in jump
assert "RenderHistoryTiles(" in jump

# The detail line no longer repeats a takeoff grade equal to the result.
detail = body("void RenderHistoryJumps(RunRecord@ selected) {")
assert "jump.preview != jump.label" in detail
assert "RenderJumpTiles(jump);" in detail

# Attempts: coloured status and a per-run grade tally.
attempts = body("void RenderHistoryAttempts() {")
assert 'UI::BeginTable("attemptTable", 5,' in attempts
assert 'UI::TableSetupColumn("Grades"' in attempts
assert "HistoryStatusColor(run.status)" in attempts
assert "RenderGradeTally(run);" in attempts
tally = body("void RenderGradeTally(RunRecord@ run) {")
assert "GradeColor(" in tally and '" missed"' in tally

# Both tables use the gold selection tint; the combo column shows the streak.
assert window.count("PushHistorySelectionColors();") == 2
assert 'UI::TableSetupColumn("Combo"' in detail
assert 'UI::TableSetupColumn("Next"' not in detail

# The clear buttons keep the default Openplanet button style.
clear = body("void RenderHistoryClear() {")
assert "UI::Col::Button" not in clear
print("Run history uses HUD-style cards: PASS")
