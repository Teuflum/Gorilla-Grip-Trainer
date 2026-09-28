"""The trainer warns when it loads but can't read the physics.

Four offsets are fixed, not found in the game code: the car pointer, its
position, the physics clock and the wheel contact times. If an update moves one
of the first three, ReadPhysics never passes its checks and no jump is rated;
a moved wheel timestamp only dates landings by frame. Both get the same amber
warning as a missing code pattern, once, and only in the Stadium car, whose
reads the checks are built for.
"""

from pathlib import Path


root = Path(__file__).resolve().parents[1]
physics = (root / "plugin" / "Physics.as").read_text(encoding="utf-8")
main = (root / "plugin" / "Main.as").read_text(encoding="utf-8")
widgets = (root / "plugin" / "Widgets.as").read_text(encoding="utf-8")
readme = (root / "README.md").read_text(encoding="utf-8")

# Every rejected read names the check that rejected it; an exact one names none.
read = physics.split("PhysicsSnapshot@ ReadPhysics(", 1)[1].split("\n}\n", 1)[0]
read = read.split("if (!g_supportedBuild) return snap;", 1)[1]
checks = read.split("snap.rawSteer = raw;", 1)[0]
for check in ("GameTerminals.Length == 0", "l.wheelCount) != 4", "model < 0x10000",
              "(pos - vis.Position).Length() > 4.0f", "delay < 100 || delay > 1000",
              "Math::Abs(physicsClock - snap.gameTime) > 1000"):
    before = checks.split(check, 1)[0]
    assert "snap.failure = " in before.rsplit("return snap;", 1)[-1], check
assert 'snap.failure = "";\n    snap.exact = true;' in read

monitor = physics.split("class PhysicsReadMonitor {", 1)[1].split("\n}\n", 1)[0]
observe = monitor.split("void Observe(PhysicsSnapshot@ snap) {", 1)[1].split("\n    }\n", 1)[0]
# Only a failure that never had a good read since load warns: a game update
# needs a restart, so later failures are loading screens or spectating.
assert "if (everExact || readWarned) return;" in observe
assert "snap.raceTime - failingSince < READ_FAILURE_WARN_MS" in observe
assert "const int READ_FAILURE_WARN_MS = 3000;" in physics
assert "WarnPhysics(" in observe and "print(" in observe and "failure" in observe
# Same amber notification as a missing code pattern.
warn = physics.split("void WarnPhysics(", 1)[1].split("\n}\n", 1)[0]
assert "vec4(0.72f, 0.36f, 0.07f, 1.0f)" in warn
assert "vec4(0.72f, 0.36f, 0.07f, 1.0f)" in main
# Wheel timestamps: a run of contact changes none of them dated warns once.
stamps = monitor.split("void ObserveStamps(PhysicsSnapshot@ snap) {", 1)[1]
assert "unstampedRun = 0;" in stamps and "unstampedRun++;" in stamps
assert "if (stampWarned || unstampedRun < UNSTAMPED_CHANGES_WARN) return;" in stamps
assert "WarnPhysics(" in stamps

# Only Stadium-car frames during a run feed it; another car pauses it.
update = main.split("void Update(float dt) {", 1)[1].split("\n}\n", 1)[0]
gate = update.split("bool stadiumCar = IsStadiumCar(vis);", 1)[1]
off = gate.split("if (!stadiumCar) {", 1)[1].split("}", 1)[0]
assert "g_readMonitor.Pause();" in off and "return;" in off
assert update.count("g_readMonitor.Observe(") == 1
assert gate.index("g_readMonitor.Observe(next);") < gate.index("g_tracker.Update(next);")

# The Physics widget keeps saying so after the notification fades.
diagnostics = widgets.split("void RenderDiagnostics(", 1)[1].split("\n}", 1)[0]
assert "!snap.exact && g_readMonitor.ReadFailing()" in diagnostics
assert '"PHYSICS READ FAILED"' in diagnostics

assert "PHYSICS READ FAILED" in readme
print("Physics read warning: PASS")
