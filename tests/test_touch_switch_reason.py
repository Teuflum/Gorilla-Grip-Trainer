"""A direction switch on a brief mid-air touch is named in the miss reason.

Scraping a block in flight counts as ground contact, so it can store the new
direction before the real landing. The jump stays MISSED when no switch was
made before takeoff; the reason says the touch switched it.
"""

from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
transitions = (root / "Transitions.as").read_text(encoding="utf-8")
land_body = transitions.split("void Land(", 1)[1].split("\n    }\n", 1)[0]
resolve_body = transitions.split("void ResolveLanding(", 1)[1].split("\n    }\n", 1)[0]
update_body = transitions.split("void Update(", 1)[1]
pending_body = update_body.split("if (pendingLanding) {", 1)[1].split("\n        }\n", 1)[0]

# Each landing starts without a lift-off; leaving the ground again while the
# landing is still pending marks the first contact as a brief touch.
assert "landingTouchLifted = snap.contactMask == 0;" in land_body
assert "if (snap.contactMask == 0) landingTouchLifted = true;" in pending_body

# A touch that also changed the stored direction gets its own miss reason,
# on both miss paths, and never turns a miss into a pass.
reason = '"Direction switched on a brief touch before the landing"'
assert "bool touchSwitched = landingTouchLifted && switchedByCheck;" in resolve_body
assert resolve_body.count(reason) == 1
assert 'verdict.label = "MISSED";' in resolve_body
print("Mid-air touch switches are named in the miss reason: PASS")
