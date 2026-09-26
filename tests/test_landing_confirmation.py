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

# Force is only expected once the gate is clear and the delay has run out.
assert "snap.forceGateState == 0" in pending_body
assert "snap.gameTime - takeoffModeAt >= recoveryDelayMs" in pending_body

# Deliberate gas-off spins can hold the gate longer; the wait counts from
# whichever comes later, touchdown or the end of the delay.
assert "const int FORCE_GATE_TIMEOUT_MS = 1000;" in transitions
assert "Math::Max(landingClock, takeoffModeAt + recoveryDelayMs)" in pending_body

# A pass still needs the held mode and a rising multiplier.
assert "int(snap.modeAt) == takeoffModeAt" in resolve_body
assert "snap.force > 1.001f" in resolve_body
print("Landing confirmation waits for the delay, not the cutoff: PASS")
