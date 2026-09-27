"""A jump the rating filters drop leaves a debug line naming the filters.

The icing, slip and speed limits are rating filters, not measured slide
thresholds. Without a trace of the jumps they reject, a limit that is too
strict never shows up, so every dropped switch or late reversal is logged
with the values the filters saw.
"""

from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
transitions = (root / "Transitions.as").read_text(encoding="utf-8")
main = (root / "Main.as").read_text(encoding="utf-8")
reset_body = transitions.split("void Reset() {", 1)[1].split("\n    }\n", 1)[0]
start_body = transitions.split("void StartFlight(", 1)[1].split("\n    }\n", 1)[0]
land_body = transitions.split("void Land(", 1)[1].split("\n    }\n", 1)[0]
misses = transitions.split("string EligibilityMisses(int leadMs) {", 1)[1].split("\n    }\n", 1)[0]
update_body = transitions.split("void Update(", 1)[1]

# The event clears with the other per-frame events and on a reset.
assert "skippedEvent = false;" in reset_body and 'skippedReason = "";' in reset_body
per_frame = update_body.split("if (snap is null", 1)[0]
assert "skippedEvent = false;" in per_frame and 'skippedReason = "";' in per_frame

# Takeoff: only a real switch or a late reversal is worth a line, not every bump.
ineligible = start_body.split("if (!flightEligible) {", 1)[1].split("return;", 1)[0]
assert "switchOldMode != 0 && switchOldMode != takeoffMode" in ineligible
assert "takeoffReversalLeadMs >= 0" in ineligible
assert "pendingSkip = EligibilityMisses(" in ineligible
# Contact that flickers on the ground makes a "takeoff" every tick; only a
# flight long enough to count as a jump is logged.
assert 'pendingSkip = "";' in start_body.split("takeoffClock = snap.contactClock;", 1)[0]
assert "bool longFlight = landingRace - takeoffRace >= S_MinFlight;" in land_body
assert "if (pendingSkip.Length > 0 && longFlight) NoteSkipped(pendingSkip);" in land_body
assert 'pendingSkip = "";' in reset_body and "shortSkipSwitchAt = -1;" in reset_body
# The switch is known before the filters run.
assert start_body.index("bool attempted =") < start_body.index("flightEligible = takeoffMode != 0")

# Every filter in the eligibility rule is named when it fails.
for check in ("takeoffMode == 0",
              "takeoffClock - lastSlideClock > SLIDE_WINDOW_MS",
              "previous.meanIcing < S_MinIcing",
              "previous.speedKmh < float(S_MinSpeed)"):
    assert check in misses, check

# Landing: a graded jump whose flight was too short is dropped silently otherwise.
assert "!longFlight && preview !is null" in land_body
# Repeated short hops after one switch are named once.
assert "preview.modeAt != shortSkipSwitchAt" in land_body
assert '"ms below " + S_MinFlight + "ms"' in land_body

assert "if (g_tracker.skippedEvent)" in main
assert 'DebugLog("Gorilla Grip Trainer jump skipped by the rating filters: " +' in main
print("Skipped jumps are logged with the filters they failed: PASS")
