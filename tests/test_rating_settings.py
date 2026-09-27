"""Grade timing bounds remain configurable and ordered at runtime."""

from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
settings = (root / "Settings.as").read_text(encoding="utf-8")
transitions = (root / "Transitions.as").read_text(encoding="utf-8")

for grade, default in (("S", 10), ("A", 30), ("B", 60),
                       ("C", 110), ("D", 250)):
    assert f"S_{grade}MaxLeadMs = {default}" in settings
    assert f"S_{grade}MaxLeadMs" in transitions
assert "NormalizeGradeThresholds" in settings
assert '[SettingsTab name="Rating"' in settings
rating_body = settings.split('void RenderSettingsRating() {', 1)[1].split('\n}', 1)[0]
assert 'ConfirmedResetButton("Reset to default", "rating")' in rating_body
# The explanation sits behind a hover hint instead of filling the tab.
assert "UI::TextWrapped" not in rating_body
assert "HelpMarker(" in rating_body
for default in ('0.65f', '50', '100', '10', '30', '60', '110', '250'):
    assert default in rating_body
# Leads are whole physics ticks, so every default limit is one and the
# inputs step by a tick.
for grade in "SABCD":
    default = int(settings.split(f"int S_{grade}MaxLeadMs = ", 1)[1].split(";", 1)[0])
    assert default % 10 == 0, (grade, default)
    assert f'S_{grade}MaxLeadMs, PHYSICS_TICK_MS)' in rating_body
# The icing slider says it is checked at takeoff, and names the fixed
# landing minimum from Transitions.as.
icing_help = rating_body.split('"Minimum average tire icing"', 1)[1].split("HelpMarker(", 1)[1].split(");", 1)[0]
assert "takeoff only" in icing_help
landing_min = transitions.split("LANDING_MIN_ICING = ", 1)[1].split("f;", 1)[0]
assert landing_min in icing_help, landing_min
print("Editable ordered grade timing bounds: PASS")
