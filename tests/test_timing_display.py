"""Uncertain frame timing keeps the lower internal rank and gets a quiet + marker."""

from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
widgets = (root / "Widgets.as").read_text(encoding="utf-8")
settings = (root / "Settings.as").read_text(encoding="utf-8")
history = (root / "HistoryWindow.as").read_text(encoding="utf-8")
transitions = (root / "Transitions.as").read_text(encoding="utf-8")

assert 'preview.ambiguous ? label + "+" : label' in widgets
assert 'g_resultTimingEstimated = verdict.timingEstimated' in widgets
assert 'estimated && GradeBasePoints(label) > 0' in widgets
assert 'showPlus ? label + "+" : label' in widgets
assert '"CONSERVATIVE PREVIEW"' not in widgets
assert '"CONSERVATIVE TIMING"' not in widgets
assert 'jump.label != "S+" && jump.timingEstimated &&' in history
assert 'uncertainGrade ? "+" : ""' in history
assert 'S+ is awarded only for a confirmed 0-0 ms switch lead' in settings
assert 'A+ still scores A' in settings
assert 'preview.label = GradeLead(hi, hi)' in transitions
unrated_body = transitions.split('void PublishUnrated(', 1)[1].split('void ResolveLanding(', 1)[0]
assert 'verdict.timingEstimated = preview !is null && preview.ambiguous' in unrated_body
assert 'conservative grade' not in transitions
print("Uncertain timing display keeps the lower rank and uses +: PASS")
