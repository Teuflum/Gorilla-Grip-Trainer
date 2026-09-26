"""Grade timing bounds remain configurable and ordered at runtime."""

from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
settings = (root / "Settings.as").read_text(encoding="utf-8")
transitions = (root / "Transitions.as").read_text(encoding="utf-8")

for grade, default in (("S", 15), ("A", 35), ("B", 65),
                       ("C", 110), ("D", 250)):
    assert f"S_{grade}MaxLeadMs = {default}" in settings
    assert f"S_{grade}MaxLeadMs" in transitions
assert "NormalizeGradeThresholds" in settings
assert '[SettingsTab name="Rating"]' in settings
print("Editable ordered grade timing bounds: PASS")
