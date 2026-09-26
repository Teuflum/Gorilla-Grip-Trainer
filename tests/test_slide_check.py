"""Only jumps taken out of an ice slide are rated.

A bobsleigh countersteer is ordinary steering with the car moving almost
exactly where its nose points (slip up to 6.6 deg in the traces); every
measured gorilla grip came out of a slide of at least 45 deg within the last
500 ms before takeoff.
"""

from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
physics = (root / "Physics.as").read_text(encoding="utf-8")
transitions = (root / "Transitions.as").read_text(encoding="utf-8")
settings = (root / "Settings.as").read_text(encoding="utf-8")

# Slip angle between heading and horizontal velocity, from VehicleState.
read = physics.split("PhysicsSnapshot@ ReadPhysics(", 1)[1].split("\n}", 1)[0]
assert "float slipDeg = 0.0f;" in physics
assert "vis.WorldVel" in read and "vis.Dir" in read
assert "snap.slipDeg = Math::ToDeg(Math::Atan2(Math::Abs(side), forward));" in read

# A hidden, resettable threshold, like the other eligibility limits.
assert "[Setting hidden] float S_MinSlideSlip = 20.0f;" in settings
rating = settings.split("void RenderSettingsRating() {", 1)[1].split("\n}", 1)[0]
assert "S_MinSlideSlip = 20.0f;" in rating

# Grounded samples above the threshold mark a slide; takeoff needs one within
# the last 500 ms.
assert "const int SLIDE_WINDOW_MS = 500;" in transitions
update = transitions.split("void Update(", 1)[1]
assert "snap.contactMask != 0 && snap.slipDeg >= S_MinSlideSlip" in update
assert "lastSlideClock = snap.gameTime;" in update
start = transitions.split("void StartFlight(", 1)[1].split("\n    }\n", 1)[0]
assert "lastSlideClock >= 0 && snap.gameTime - lastSlideClock <= SLIDE_WINDOW_MS" in start
reset = transitions.split("void Reset() {", 1)[1].split("\n    }\n", 1)[0]
assert "lastSlideClock = -1;" in reset
print("Only jumps out of an ice slide are rated: PASS")
