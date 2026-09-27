"""A stored direction that switches after the landing is a miss.

Reversing the steering just before takeoff plays the takeoff cue, but the
smoothed steering needs a few ticks to flip the stored direction. When it has
not flipped by takeoff, there is no preview. A landing with neutral steering
then passes the 30 ms landing-direction capture, and steering the new way
afterwards switches the stored direction on the ground and delays the tire
force (a spin). The force check must see that switch and report MISSED.
"""

from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
transitions = (root / "Transitions.as").read_text(encoding="utf-8")
main = (root / "Main.as").read_text(encoding="utf-8")
reset_body = transitions.split("void Reset() {", 1)[1].split("\n    }\n", 1)[0]
start_body = transitions.split("void StartFlight(", 1)[1].split("\n    }\n", 1)[0]
resolve_body = transitions.split("void ResolveLanding(", 1)[1].split("\n    }\n", 1)[0]
update_body = transitions.split("void Update(", 1)[1]
no_preview = resolve_body.split("} else", 1)[1]

# The cue and the miss reason use the same reversal window.
assert "const int CUE_REVERSAL_WINDOW_MS = 250;" in transitions
assert "takeoffClock - rawReversalAt <= CUE_REVERSAL_WINDOW_MS" in update_body
assert "takeoffReversalLeadMs = -1;" in reset_body
assert "takeoffReversalLeadMs" in start_body
assert "CUE_REVERSAL_WINDOW_MS" in start_body

# Without a preview, a stored switch since takeoff counts like an opposite
# landing steer; icing and the delayed-force check still apply.
assert ("bool storedSwitched = switchedByCheck && snap.mode != 0 &&\n"
        "            snap.mode != takeoffMode;") in resolve_body
assert "storedSwitched && snap.force <= 1.1f" in no_preview
assert "enoughIcing" in no_preview and "snap.force <= 1.1f" in no_preview

# The reason names the late reversal when the cue played.
assert ('"Steering reversed " + takeoffReversalLeadMs +\n'
        '                " ms before takeoff, too late to store the direction; '
        'it switched after the landing"') in no_preview
assert '"Direction switched after the landing with delayed tire force"' in no_preview
assert '"Opposite landing direction with delayed tire force"' in no_preview

# A pending landing that ends without a verdict leaves a debug line.
assert "silentLandingEvent = false;" in reset_body
assert "silentLandingEvent = true;" in resolve_body
assert "silentLandingEvent = false;" in update_body.split("if (snap is null", 1)[0]
assert "if (g_tracker.silentLandingEvent)" in main
assert 'DebugLog("Gorilla Grip Trainer landing resolved without verdict at ' in main
print("A stored switch after the landing is a miss: PASS")
