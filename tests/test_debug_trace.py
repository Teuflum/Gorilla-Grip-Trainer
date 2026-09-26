"""The per-tick force trace stays available behind an off-by-default setting."""

from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
settings = (root / "Settings.as").read_text(encoding="utf-8")
main = (root / "Main.as").read_text(encoding="utf-8")

assert '[Setting category="Debug" name="Log every tire-force change"' in settings
assert "bool S_DebugForceTrace = false;" in settings

snapshot = main.split('DebugLog("Gorilla Grip Trainer snapshot at', 1)[0].rsplit("\n    if (", 1)[1]
# With event logging on, contact changes are logged; force and gate changes need the trace too.
assert "g_previousContactMask != int(next.contactMask)" in snapshot
assert "S_DebugForceTrace" in snapshot
assert "g_previousForce != next.force" in snapshot
assert "g_previousForceGate != next.forceGateState" in snapshot
print("Debug force trace is opt-in: PASS")

# Snapshot lines carry each wheel's ground material, icing and the speed, so
# landings on non-ice surfaces can be told apart in a trace.
physics = (root / "Physics.as").read_text(encoding="utf-8")
for wheel in ("FL", "FR", "RR", "RL"):
    assert f"tostring(vis.{wheel}GroundContactMaterial)" in physics, wheel
line = main.split('DebugLog("Gorilla Grip Trainer snapshot at', 1)[1].split(";", 1)[0]
for part in ('", materials " + next.materials', '", icing "', '", speed "'):
    assert part in line, part
print("Snapshot lines include materials, icing and speed: PASS")
