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
