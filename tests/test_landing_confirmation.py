"""A landing keeps its grade when the pre-takeoff mode survives it.

The recovery timer starts at the pre-takeoff switch, so a landing before the
400 ms delay still recovers early. Confirmation waits until force can rise
(gate clear and mode age at least the delay), not until the 800 ms cutoff.
"""

from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
transitions = (root / "Transitions.as").read_text(encoding="utf-8")
resolve_body = transitions.split("void ResolveLanding(", 1)[1].split("\n    }\n", 1)[0]
update_body = transitions.split("void Update(", 1)[1]
pending_body = update_body.split("if (pendingLanding) {", 1)[1].split("\n        }\n", 1)[0]

# The 800 ms cutoff is not a pass condition any more.
assert "2 * recoveryDelayMs" not in transitions

# Force is expected once a front wheel touches (the game updates the
# multiplier only for front wheels), the delay has run out, and the
# backwards-motion gate is clear. Eligibility starts at the exact touchdown.
assert "const uint FRONT_WHEELS = 0x3;" in transitions
assert "int front = ContactStart(snap, FRONT_WHEELS, landingClock - 1);" in pending_body
assert "Math::Max(frontTouchAt, takeoffModeAt + recoveryDelayMs)" in pending_body
assert "snap.forceGateState == 0" in pending_body

# Deliberate gas-off spins can hold the gate longer; the wait counts from
# whichever comes later, touchdown or the end of the delay.
assert "const int FORCE_GATE_TIMEOUT_MS = 1000;" in transitions
assert "int deadline = FORCE_GATE_TIMEOUT_MS +" in pending_body
assert "Math::Max(landingClock, takeoffModeAt + recoveryDelayMs);" in pending_body

# A pass needs the direction held as of the check tick; tire force only
# confirms, and a disagreement is logged.
assert "bool recovered = enoughIcing && !switchedByCheck &&" in resolve_body
assert "forceEligibleClock - takeoffModeAt >= recoveryDelayMs" in resolve_body
assert "snap.force > 1.001f" not in resolve_body
# The minimum icing is a takeoff filter. Tires lose icing in flight (a
# 2.75 s jump landed at 54% with full force on RoadIce and was once marked
# MISSED), so the landing only needs some icing left.
assert "bool enoughIcing = snap.meanIcing > 0.0f;" in resolve_body
assert "S_MinIcing" not in resolve_body

# The force disagreement line needs a front wheel down since eligibility; a
# front bounce after the delay (landing at 13.54 s, force 1.0 at the check,
# then +0.05 per tick) is not a disagreement.
assert "int frontSince = ContactStart(snap, FRONT_WHEELS, landingClock - 1);" in resolve_body
assert "frontSince >= 0 && frontSince <= forceEligibleClock" in resolve_body
print("Landing confirmation waits for the delay, not the cutoff: PASS")
