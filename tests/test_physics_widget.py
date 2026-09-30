"""The physics widget shows per-wheel contact and icing without header labels."""

from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
physics = (root / "Physics.as").read_text(encoding="utf-8")
widgets = (root / "Widgets.as").read_text(encoding="utf-8")
diagnostics = widgets.split("void RenderDiagnostics(", 1)[1].split("\n}", 1)[0]

# Per-wheel icing in the game's wheel order (FL, FR, RR, RL = contact bits 0-3).
wheel = physics.split("float WheelIcing(uint wheel) const {", 1)[1].split("\n    }", 1)[0]
for field in ("icingFL", "icingFR", "icingRR", "icingRL"):
    assert field in wheel, field
for source in ("vis.FLIcing01", "vis.FRIcing01", "vis.RRIcing01", "vis.RLIcing01"):
    assert source in physics, source

# The header labels are gone; the plugin unloads on unsupported builds anyway.
assert '"GORILLA GRIP"' not in diagnostics
assert '"EXACT PHYSICS"' not in diagnostics

# A 2x2 wheel grid: front contact gold, rear contact blue, air dim; the tile
# fill shows that wheel's icing.
tile = widgets.split("void RenderWheelTile(", 1)[1].split("\n}", 1)[0]
assert "front ? HudColor(1.0f, 0.85f, 0.36f) : HudColor(0.47f, 0.82f, 1.0f)" in tile
assert "Math::Clamp(icing, 0.0f, 1.0f)" in tile
# Grid order FL FR / RL RR maps to the game's wheel indices 0 1 / 3 2.
assert 'array<string> names = {"FL", "FR", "RL", "RR"};' in diagnostics
assert "array<uint> wheels = {0, 1, 3, 2};" in diagnostics
assert "wheel < 2" in diagnostics  # indices 0 and 1 are the front wheels
assert "snap.WheelIcing(" in diagnostics
assert "(snap.contactMask & (1 << " in diagnostics
assert '"ICE AVG "' in diagnostics

# The backwards-motion hold (+0x1600) pins the force at 1.0 until gas returns,
# on the ground and in the air; the force line names it instead of the timer.
force = diagnostics.split("string forceText;", 1)[1].split("HudText(cr, r.y + 124*s, forceText", 1)[0]
held = "bool held = snap.exact && snap.forceGateState != 0;"
assert held in diagnostics
assert 'forceText = "FORCE HELD " + Text::Format("%.2fx", snap.force);' in force
assert 'forceText = "GAS HOLD";' in force
# Only a touching front wheel updates the force, so with rear-only contact the
# stored value (often still the pre-jump 2.0) is stale and is not shown.
assert "bool rearOnly = (snap.contactMask & 3) == 0 && (snap.contactMask & 12) != 0;" in diagnostics
assert 'forceText = "REAR ONLY";' in force
assert '"REAR ONLY " +' not in force
# The hold wins over the timer states and over rear-only contact.
assert force.index('"GAS HOLD"') < force.index('"NO MODE TIMER"')
assert force.index('"FORCE HELD "') < force.index('"REAR ONLY"')
explanation = diagnostics.split("string explanation =", 1)[1].split(";", 1)[0]
assert 'held ? "GAS OFF WHILE BACKWARDS | GAS RELEASES IT"' in explanation
assert explanation.index("readFailing") < explanation.index("held ?")
assert '!g_tracker.inFlight && rearOnly ? "FORCE UPDATES ON FRONT WHEEL CONTACT"' in explanation
assert explanation.index("held ?") < explanation.index("rearOnly ?")
print("Physics widget shows per-wheel contact and icing: PASS")
