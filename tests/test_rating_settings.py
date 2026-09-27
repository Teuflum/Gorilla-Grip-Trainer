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
assert '[SettingsTab name="Rating"' in settings
rating_body = settings.split('void RenderSettingsRating() {', 1)[1].split('\n}', 1)[0]
assert 'UI::Button("Reset to default")' in rating_body
# The explanation sits behind a hover hint instead of filling the tab.
assert "UI::TextWrapped" not in rating_body
assert "HelpMarker(" in rating_body
for default in ('0.65f', '50', '100', '15', '35', '65', '110', '250'):
    assert default in rating_body
print("Editable ordered grade timing bounds: PASS")
