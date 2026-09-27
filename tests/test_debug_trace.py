"""The per-tick force trace stays available behind an off-by-default setting."""

from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
settings = (root / "Settings.as").read_text(encoding="utf-8")
main = (root / "Main.as").read_text(encoding="utf-8")

assert "[Setting hidden] bool S_DebugForceTrace = false;" in settings
assert 'UI::Checkbox("Log every tire-force change", S_DebugForceTrace)' in settings
trace = settings.split("bool DebugForceTraceOn() {", 1)[1].split("\n}", 1)[0]
assert "return DebugLoggingOn() && S_DebugForceTrace;" in trace

snapshot = main.split('DebugLog("Gorilla Grip Trainer snapshot at', 1)[0].rsplit("\n    if (", 1)[1]
# With event logging on, contact changes are logged; force and gate changes need the trace too.
assert "g_previousContactMask != int(next.contactMask)" in snapshot
assert "DebugForceTraceOn()" in snapshot
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
