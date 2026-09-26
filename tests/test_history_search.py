"""The run history search ignores letter case and surrounding spaces."""

from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
window = (root / "HistoryWindow.as").read_text(encoding="utf-8")
matches = window.split("bool HistoryMatches(RunRecord@ run) {", 1)[1].split("\n}", 1)[0]

assert "string query = g_historyMapFilter.Trim().ToLower();" in matches
assert "run.mapName.ToLower().Contains(query)" in matches
assert "run.mapUid.ToLower().Contains(query)" in matches
assert "run.mapName.Contains(g_historyMapFilter)" not in matches
print("History search is case-insensitive: PASS")
