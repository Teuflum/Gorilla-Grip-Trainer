"""Tick-exact timing: the Trainer dates contact changes with the game's own clocks."""

from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
physics = (root / "Physics.as").read_text(encoding="utf-8")
settings = (root / "Settings.as").read_text(encoding="utf-8")
main = (root / "Main.as").read_text(encoding="utf-8")
transitions = (root / "Transitions.as").read_text(encoding="utf-8")
read = physics.split("PhysicsSnapshot@ ReadPhysics(", 1)[1].split("\n}", 1)[0]
update = main.split("void Update(float dt) {", 1)[1].split("\n}", 1)[0]

# Each wheel's block stores the game clock of its last contact change at +0x6c.
assert "array<uint> wheelChangedAt = array<uint>(4);" in physics
assert "uint64 wheel = vehicle + 0x17b4 + 0xb8 * i;" in read
assert "snap.wheelChangedAt[i] = Dev::SafeReadUint32(wheel + 0x6c);" in read
assert "snap.physicsClock = int(Dev::SafeReadUint32(vehicle + 0x4f4));" in read
# The car's last tick with ground contact (vehicle+0x1414): frozen at the
# takeoff tick in flight, and sub-tick wheel grazes do not move it.
assert "snap.contactClock = int(Dev::SafeReadUint32(vehicle + 0x1414));" in read

# Frame skipping simulates a low frame rate, only in developer mode.
assert "[Setting hidden] int S_DebugFrameSkip = 1;" in settings
skip = settings.split("int DebugFrameSkip() {", 1)[1].split("\n}", 1)[0]
assert skip.split() == ["#if", "SIG_DEVELOPER", "return", "Math::Clamp(S_DebugFrameSkip,",
                        "1,", "10);", "#else", "return", "1;", "#endif"], skip
debug_tab = settings.split("void RenderSettingsDebug() {", 1)[1].split("\n}", 1)[0]
assert 'UI::SliderInt("Process every Nth frame", S_DebugFrameSkip, 1, 10)' in debug_tab
assert "S_DebugFrameSkip = 1;" in debug_tab
assert update.index("if (!ProcessThisFrame()) return;") < \
    update.index("PhysicsSnapshot@ next = ReadPhysics(vis, t);")
assert 'DebugLog("Gorilla Grip Trainer frame skip " + frameSkip);' in update
print("Wheel timestamps and frame skip: PASS")

# The stage 0 probe is gone again.
assert "stamp probe" not in main and "probe" not in read
print("Stage 0 probe removed: PASS")

# Everything is timed on the physics clock; ticks convert to race time
# through the frame clock, which advances with race time.
assert "snap.frameClock = snap.gameTime;" in read
assert "snap.gameTime = snap.physicsClock;" in read
assert "int RaceAt(int tick) const { return tick + raceTime - frameClock; }" in physics

# Takeoff is the car's contact clock; the lead is one exact number.
start = transitions.split("void StartFlight(", 1)[1].split("\n    }\n", 1)[0]
valid = transitions.split("bool TakeoffClockValid(", 1)[1].split("\n}", 1)[0]
assert "const int PHYSICS_TICK_MS = 10;" in transitions
assert "MAX_TIMING_SAMPLE_GAP" not in transitions
assert "contact sample gap" not in transitions
assert "takeoffClock = snap.contactClock;" in start
assert "bool exactTakeoff = TakeoffClockValid(previous, snap);" in start
assert "takeoffRace = snap.RaceAt(takeoffClock);" in start
assert '"Contact timestamps were inconsistent at takeoff"' in start
assert "int lead = takeoffClock - switchAt;" in start
assert "string grade = GradeLead(lead);" in start
assert "preview.leadMs = lead;" in start
# A contact clock outside the frame interval is not exact (Review Focus 3).
assert "return after.contactClock > before.gameTime && after.contactClock <= after.gameTime;" in valid
grade = transitions.split("string GradeLead(int leadMs) {", 1)[1].split("\n}", 1)[0]
assert "if (leadMs == 0) return \"S+\";" in grade
assert "string GradeLead(int lo" not in transitions
preview_class = transitions.split("class JumpPreview {", 1)[1].split("\n}", 1)[0]
assert "int leadMs = -1;" in preview_class and "ambiguous" not in preview_class
session = (root / "Session.as").read_text(encoding="utf-8")
verdict_class = session.split("class JumpVerdict {", 1)[1].split("\n}", 1)[0]
assert "int leadMs = -1;" in verdict_class
assert "timingEstimated" not in verdict_class and "leadMinMs" not in verdict_class
# The switch is noticed at any frame gap.
update_body = transitions.split("void Update(PhysicsSnapshot@ snap) {", 1)[1]
assert "\n        ObserveSteeringAndMode(snap);" in update_body
print("Exact takeoff lead: PASS")

# Landing: exact touchdown, touches between frames, and the stored direction
# as of a fixed check tick.
land = transitions.split("void Land(", 1)[1].split("\n    }\n", 1)[0]
resolve = transitions.split("void ResolveLanding(", 1)[1].split("\n    }\n", 1)[0]
pending = update_body.split("if (pendingLanding) {", 1)[1].split("\n        }\n", 1)[0]
assert "landingDirection" not in transitions
# A wheel whose contact is not processed yet can still carry a graze
# timestamp from the flight: only changes after the last all-air frame date
# the touchdown, and a front wheel cannot touch down before the landing.
assert "int after = previous is null ? takeoffClock : Math::Max(takeoffClock, previous.gameTime);" in land
assert "ContactStart(snap, ALL_WHEELS, after) : snap.contactClock;" in land
assert "landingRace = snap.RaceAt(landingClock);" in land
assert "landingTouchLifted = snap.contactMask == 0;" in land
# A grounded wheel whose contact is not processed yet counts from the next tick.
contact_start = transitions.split("int ContactStart(", 1)[1].split("\n}", 1)[0]
assert "at = snap.gameTime + PHYSICS_TICK_MS;" in contact_start
# A wheel whose flag is set but not processed yet still carries its previous
# timestamp, possibly a graze after takeoff; only a timestamp the car's
# contact clock has reached dates a touchdown.
assert "if (at <= after || at > snap.contactClock) at = snap.gameTime + PHYSICS_TICK_MS;" in contact_start
assert "TouchedSince" not in transitions and "EarliestWheelChange" not in transitions
# Review Focus 1: a touch the game processed between two all-air frames.
assert "else if (inFlight && snap.contactMask == 0 && snap.contactClock > takeoffClock) {" in update_body
assert "if (!pendingLanding) StartFlight(snap);" in update_body
# Final review 3: the earliest front touchdown since the landing sets the
# check tick, so a later bounce seen on a late frame cannot move it.
assert "int front = ContactStart(snap, FRONT_WHEELS, landingClock - 1);" in pending
assert "if (front >= 0 && (frontTouchAt < 0 || front < frontTouchAt)) frontTouchAt = front;" in pending
assert "if (snap.forceGateState != 0) gateSeenAt = snap.gameTime;" in pending
assert "Math::Max(landingClock + LANDING_CHECK_MS, eligibleAt + FORCE_SETTLE_MS)" in pending
assert "snap.gameTime >= checkAt" in pending
# Review Focus 2 and 5: the verdict uses the stored mode as of the check
# tick; a lapse to neutral is dated from the neutral timer; force only confirms.
assert "snap.neutralAt = int(Dev::SafeReadUint32(vehicle + 0x14e0));" in physics
assert "Dev::SafeReadUint32(model + 0x1198)" in physics
# Final review 1: the first stored-direction change seen since takeoff is
# recorded on every pending frame, so a second change before a late frame
# cannot hide it.
assert "if (!firstChangeSeen && int(snap.modeAt) != takeoffModeAt) {" in pending
assert "firstChangeAt = StoredChangeTick(snap);" in pending
assert "bool switchedByCheck = firstChangeSeen && firstChangeAt <= checkClock;" in resolve
stored_change = transitions.split("int StoredChangeTick(", 1)[1].split("\n}", 1)[0]
assert "snap.neutralAt + snap.neutralTimeoutMs + PHYSICS_TICK_MS" in stored_change
assert "bool recovered = enoughIcing && !switchedByCheck &&" in resolve
assert "snap.force > 1.001f" not in resolve
assert "forceDisagreedEvent = true;" in resolve
assert "forceDisagreedEvent = false;" in update_body.split("if (snap is null", 1)[0]
assert 'DebugLog("Gorilla Grip Trainer force did not rise although the direction held at "' in main
assert "firstChangeAt <= landingClock + LANDING_STEER_MS" in resolve
# Final review 2: no-preview misses use the tick rule, not a late force read.
assert "snap.force <= 1.1f" not in resolve
assert "checkClock - firstChangeAt < recoveryDelayMs" in resolve
print("Landing from timestamps and stored mode: PASS")

# Estimates that never decide a grade.
observe = transitions.split("void ObserveSteeringAndMode(", 1)[1].split("\n    }\n", 1)[0]
estimate = transitions.split("int EstimateReversal(", 1)[1].split("\n}", 1)[0]
assert "const float SMOOTHED_STEER_STEP = 0.2f;" in transitions
assert "rawReversalAt = EstimateReversal(previous, snap);" in observe
assert "if (previousGround && beforeRaw != 0" in observe
assert "Math::Clamp(after.gameTime - (ticks - 1) * PHYSICS_TICK_MS," in estimate
# Spins are not counted or scored.
assert "Spin" not in transitions and "spinCount" not in session
assert "yaw" not in physics.lower()
print("Gap-safe cue, no spins: PASS")

# Verdict lines carry the exact takeoff, landing and lead for comparison runs.
verdict_log = main.split('DebugLog("Gorilla Grip Trainer verdict at', 1)[1].split(";", 1)[0]
assert '" | score " + g_session.score +' in verdict_log
assert '" | takeoff " + v.takeoffTime + "ms | landing " + v.landingTime +' in verdict_log
assert '"ms | lead " + v.leadMs + "ms"' in verdict_log
print("Verdict lines carry exact times: PASS")
