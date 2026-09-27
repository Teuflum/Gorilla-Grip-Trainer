const float STEER_GATE = 0.1f;
// The physics step runs in fixed 10 ms ticks.
const int PHYSICS_TICK_MS = 10;
const int FORCE_SETTLE_MS = 30;
// The force check waits this long after touchdown.
const int LANDING_CHECK_MS = 80;
const uint ALL_WHEELS = 0xf;
// The game stores an opposite landing steer within the first contact ticks.
const int LANDING_STEER_MS = 30;
// A takeoff is rated only if the car slid within this time before it.
const int SLIDE_WINDOW_MS = 500;
// A grounded steering reversal this soon before takeoff plays the takeoff cue.
const int CUE_REVERSAL_WINDOW_MS = 250;
// Smoothed steering follows the input by about 0.2 per tick on ice.
const float SMOOTHED_STEER_STEP = 0.2f;
// Contact bits of the front wheels (0 and 1); only they update the tire-force multiplier.
const uint FRONT_WHEELS = 0x3;
// Counted from touchdown or the end of the recovery delay, whichever is later;
// gas-off spins can hold the force gate for a while.
const int FORCE_GATE_TIMEOUT_MS = 1000;

int SteeringDirection(float steer) {
    if (steer > STEER_GATE) return 2;
    if (steer < -STEER_GATE) return 1;
    return 0;
}

int RawDirection(float steer) {
    if (steer > 0.01f) return 2;
    if (steer < -0.01f) return 1;
    return 0;
}

string GradeLead(int leadMs) {
    NormalizeGradeThresholds();
    if (leadMs < 0 || leadMs > S_DMaxLeadMs) return "";
    // The switch happened on the tick the last wheel left.
    if (leadMs == 0) return "S+";
    if (leadMs <= S_SMaxLeadMs) return "S";
    if (leadMs <= S_AMaxLeadMs) return "A";
    if (leadMs <= S_BMaxLeadMs) return "B";
    if (leadMs <= S_CMaxLeadMs) return "C";
    return "D";
}

// The car's contact clock stops at the takeoff tick, the first tick whose
// previous flags were all clear; sub-tick wheel grazes do not move it. It
// must lie between the two frames.
bool TakeoffClockValid(PhysicsSnapshot@ before, PhysicsSnapshot@ after) {
    return after.contactClock > before.gameTime && after.contactClock <= after.gameTime;
}

// When the game began processing the current contact of the grounded wheels
// in `mask`: the earliest timestamp newer than `after`. A flag set on the
// frame's own tick is processed on the next one; until then the wheel keeps
// its previous timestamp, which can be a graze after takeoff, so only a
// timestamp the car's contact clock has reached counts. -1 when none of them
// touches.
int ContactStart(PhysicsSnapshot@ snap, uint mask, int after) {
    int start = -1;
    for (uint i = 0; i < 4; i++) {
        if ((snap.contactMask & mask & (1 << i)) == 0) continue;
        int at = int(snap.wheelChangedAt[i]);
        if (at <= after || at > snap.contactClock) at = snap.gameTime + PHYSICS_TICK_MS;
        if (start < 0 || at < start) start = at;
    }
    return start;
}

// When the stored direction last changed: modeAt, or for a lapse to neutral,
// which stores an unset modeAt, the tick after the neutral timeout ran out.
// -1 when a lapse cannot be dated.
int StoredChangeTick(PhysicsSnapshot@ snap) {
    int storedAt = int(snap.modeAt);
    if (snap.mode != 0 || storedAt != -1) return storedAt;
    return snap.neutralAt >= 0 && snap.neutralTimeoutMs > 0 ?
        snap.neutralAt + snap.neutralTimeoutMs + PHYSICS_TICK_MS : -1;
}

// Dates a raw steering reversal inside a frame gap from how far the smoothed
// steering has moved toward the new side. Once it has reached the input, the
// travel no longer tells when it started: take the earliest possible tick.
int EstimateReversal(PhysicsSnapshot@ before, PhysicsSnapshot@ after) {
    int earliest = Math::Min(before.gameTime + PHYSICS_TICK_MS, after.gameTime);
    if (Math::Abs(after.smoothedSteer - after.rawSteer) < 0.001f) return earliest;
    float travel = Math::Abs(after.smoothedSteer - before.smoothedSteer);
    int ticks = Math::Max(1, int(travel / SMOOTHED_STEER_STEP + 0.999f));
    return Math::Clamp(after.gameTime - (ticks - 1) * PHYSICS_TICK_MS,
        earliest, after.gameTime);
}

class JumpPreview {
    string label;
    int leadMs = -1;
    int takeoffTime = -1;
    int oldMode = 0;
    int newMode = 0;
    int modeAt = -1;
}

class TransitionTracker {
    PhysicsSnapshot@ previous;
    JumpPreview@ preview;
    JumpVerdict@ verdict;
    bool previewEvent = false;
    bool verdictEvent = false;
    bool takeoffCueEvent = false;
    bool landingEvent = false;
    // A pending landing ended without a verdict (same-direction landing).
    bool silentLandingEvent = false;
    // A confirmed landing whose direction held but whose force did not rise.
    bool forceDisagreedEvent = false;
    bool unratedEvent = false;
    string unratedReason = "";

    int switchAt = -1;
    int switchOldMode = 0;
    int switchNewMode = 0;
    int rawReversalAt = -1;
    int lastSlideClock = -1;

    bool inFlight = false;
    bool pendingLanding = false;
    // The first landing contact was followed by more airtime (a brief touch).
    bool landingTouchLifted = false;
    bool flightEligible = false;
    bool flightUncertain = false;
    bool previewPublished = false;
    bool cuePublished = false;
    int takeoffRace = -1;
    int takeoffClock = -1;
    int takeoffMode = 0;
    int takeoffModeAt = -1;
    // Lead of the steering reversal that played the takeoff cue, or -1.
    int takeoffReversalLeadMs = -1;
    int landingRace = -1;
    int landingClock = -1;
    int forceEligibleClock = -1;
    // The tick the landing verdict is decided at, once known.
    int checkClock = -1;
    // Latest frame that showed the backwards-motion gate set, or -1.
    int gateSeenAt = -1;
    // Earliest front-wheel touchdown seen since the landing, or -1.
    int frontTouchAt = -1;
    // First stored-direction change seen since takeoff: when it was stored
    // (-1 if a lapse to neutral cannot be dated) and the mode it stored.
    bool firstChangeSeen = false;
    int firstChangeAt = -1;
    int firstChangeMode = 0;
    int recoveryDelayMs = 400;

    void Reset() {
        @previous = null;
        @preview = null;
        @verdict = null;
        previewEvent = false;
        verdictEvent = false;
        takeoffCueEvent = false;
        landingEvent = false;
        silentLandingEvent = false;
        forceDisagreedEvent = false;
        unratedEvent = false;
        unratedReason = "";
        switchAt = -1;
        switchOldMode = 0;
        switchNewMode = 0;
        rawReversalAt = -1;
        lastSlideClock = -1;
        inFlight = false;
        pendingLanding = false;
        landingTouchLifted = false;
        flightEligible = false;
        flightUncertain = false;
        previewPublished = false;
        cuePublished = false;
        takeoffRace = -1;
        takeoffClock = -1;
        takeoffMode = 0;
        takeoffModeAt = -1;
        takeoffReversalLeadMs = -1;
        landingRace = -1;
        landingClock = -1;
        forceEligibleClock = -1;
        checkClock = -1;
        gateSeenAt = -1;
        frontTouchAt = -1;
        firstChangeSeen = false;
        firstChangeAt = -1;
        firstChangeMode = 0;
    }

    void ObserveSteeringAndMode(PhysicsSnapshot@ snap) {
        if (previous is null) return;
        bool previousGround = previous.contactMask != 0;
        int beforeRaw = RawDirection(previous.rawSteer);
        int afterRaw = RawDirection(snap.rawSteer);
        // A reversal first seen on the all-air frame may still have happened
        // on the ground; StartFlight keeps it only if it dates before takeoff.
        if (previousGround && beforeRaw != 0 && afterRaw != 0 &&
            beforeRaw != afterRaw && previous.mode == beforeRaw)
            rawReversalAt = EstimateReversal(previous, snap);

        if (!previousGround) return;
        if (previous.mode == 0 || snap.mode == 0 || previous.mode == snap.mode)
            return;
        if (previous.modeAt == snap.modeAt) return;
        int at = int(snap.modeAt);
        if (at < previous.gameTime || at > snap.gameTime) return;
        switchAt = at;
        switchOldMode = previous.mode;
        switchNewMode = snap.mode;
    }

    void StartFlight(PhysicsSnapshot@ snap) {
        inFlight = true;
        pendingLanding = false;
        flightUncertain = false;
        previewPublished = false;
        cuePublished = false;
        @preview = null;
        unratedReason = "";
        takeoffClock = snap.contactClock;
        bool exactTakeoff = TakeoffClockValid(previous, snap);
        if (!exactTakeoff) takeoffClock = snap.gameTime;
        takeoffRace = snap.RaceAt(takeoffClock);
        takeoffMode = snap.mode;
        takeoffModeAt = int(snap.modeAt);
        int reversalLead = takeoffClock - rawReversalAt;
        takeoffReversalLeadMs = rawReversalAt >= 0 && reversalLead >= 0 &&
            reversalLead <= CUE_REVERSAL_WINDOW_MS ? reversalLead : -1;
        recoveryDelayMs = snap.recoveryDelayMs;
        // Only a jump out of an ice slide is a gorilla-grip attempt.
        flightEligible = takeoffMode != 0 &&
            lastSlideClock >= 0 && takeoffClock - lastSlideClock <= SLIDE_WINDOW_MS &&
            previous.meanIcing >= S_MinIcing &&
            previous.speedKmh >= float(S_MinSpeed);
        if (!flightEligible) return;
        bool attempted = switchAt >= 0 && switchNewMode == takeoffMode &&
            takeoffClock - switchAt <= S_DMaxLeadMs;
        if (!exactTakeoff) {
            flightUncertain = true;
            if (attempted) {
                unratedReason = "Contact timestamps were inconsistent at takeoff";
                unratedEvent = true;
            }
            return;
        }
        if (!attempted || switchOldMode == 0 || switchOldMode == takeoffMode ||
            switchAt > takeoffClock) return;
        int lead = takeoffClock - switchAt;
        string grade = GradeLead(lead);
        if (grade.Length == 0) return;
        @preview = JumpPreview();
        preview.label = grade;
        preview.leadMs = lead;
        preview.takeoffTime = takeoffRace;
        preview.oldMode = switchOldMode;
        preview.newMode = switchNewMode;
        preview.modeAt = switchAt;
    }

    void Land(PhysicsSnapshot@ snap) {
        inFlight = false;
        landingEvent = true;
        // The grounded wheels date the touchdown; a touch that already lifted
        // again is dated by the car's contact clock. Only changes after the
        // last all-air frame count: a wheel whose contact is not processed yet
        // can still carry a graze timestamp from the flight.
        int after = previous is null ? takeoffClock : Math::Max(takeoffClock, previous.gameTime);
        landingClock = snap.contactMask != 0 ?
            ContactStart(snap, ALL_WHEELS, after) : snap.contactClock;
        landingRace = snap.RaceAt(landingClock);
        landingTouchLifted = snap.contactMask == 0;
        forceEligibleClock = -1;
        checkClock = -1;
        gateSeenAt = -1;
        frontTouchAt = -1;
        firstChangeSeen = false;
        firstChangeAt = -1;
        firstChangeMode = 0;
        pendingLanding = flightEligible && !flightUncertain &&
            landingRace - takeoffRace >= S_MinFlight;
        if (flightUncertain && (previewPublished || unratedReason.Length > 0))
            PublishUnrated(unratedReason.Length > 0 ? unratedReason :
                "Exact contact timing was lost during flight", landingRace);
    }

    void PublishUnrated(const string &in reason, int raceTime) {
        bool attempted = (previewPublished && preview !is null) ||
            unratedReason.Length > 0;
        unratedReason = reason;
        unratedEvent = true;
        inFlight = false;
        pendingLanding = false;
        if (!attempted) return;
        @verdict = JumpVerdict();
        verdict.label = "UNRATED";
        verdict.reason = reason;
        verdict.takeoffTime = takeoffRace;
        verdict.landingTime = Math::Max(takeoffRace, raceTime);
        verdict.leadMs = preview is null ? -1 : preview.leadMs;
        verdict.exact = false;
        verdictEvent = true;
    }

    void ResolveLanding(PhysicsSnapshot@ snap) {
        pendingLanding = false;
        bool hasPreview = preview !is null && previewPublished;
        bool enoughIcing = snap.meanIcing >= S_MinIcing;
        // The verdict uses the stored direction as of the check tick: the first
        // change seen since takeoff (every tire-force reset writes modeAt), and
        // only if it was stored by then. A later frame may already show a
        // second change; the recorded first one still decides.
        bool switchedByCheck = firstChangeSeen && firstChangeAt <= checkClock;
        // Tire force does not decide: without a reset, a low force means a low
        // target (light steering, low speed), not a delayed grip.
        bool recovered = enoughIcing && !switchedByCheck &&
            forceEligibleClock - takeoffModeAt >= recoveryDelayMs;
        if (hasPreview && recovered && !firstChangeSeen && snap.force <= 1.001f)
            forceDisagreedEvent = true;
        // A scrape in flight counts as ground contact and can store the new
        // direction before the real landing; name it instead of a generic miss.
        bool touchSwitched = landingTouchLifted && switchedByCheck;
        const string touchReason = "Direction switched on a brief touch before the landing";
        // The stored direction changes only on the ground: after a neutral
        // landing, steering the other way switches it and delays the force.
        bool storedSwitched = switchedByCheck && firstChangeMode != 0 &&
            firstChangeMode != takeoffMode;
        bool oppositeLanding = storedSwitched && firstChangeAt <= landingClock + LANDING_STEER_MS;
        if (hasPreview) {
            @verdict = JumpVerdict();
            verdict.label = recovered ? preview.label : "MISSED";
            verdict.reason = recovered ?
                "Pre-takeoff mode held through force-eligible contact" :
                (enoughIcing ? (touchSwitched ? touchReason :
                "Direction or tire force did not recover on force-eligible contact") :
                "Landing icing fell below the rating threshold");
            verdict.leadMs = preview.leadMs;
        } else if (enoughIcing && takeoffMode != 0 && storedSwitched &&
            // The switch reset the force and holds it for the recovery delay.
            checkClock - firstChangeAt < recoveryDelayMs) {
            @verdict = JumpVerdict();
            verdict.label = "MISSED";
            verdict.reason = touchSwitched ? touchReason :
                takeoffReversalLeadMs >= 0 ?
                "Steering reversed " + takeoffReversalLeadMs +
                " ms before takeoff, too late to store the direction; it switched after the landing" :
                oppositeLanding ? "Opposite landing direction with delayed tire force" :
                "Direction switched after the landing with delayed tire force";
        } else {
            silentLandingEvent = true;
            return;
        }
        verdict.takeoffTime = takeoffRace;
        verdict.landingTime = landingRace;
        verdict.exact = true;
        verdictEvent = true;
    }

    void Update(PhysicsSnapshot@ snap) {
        previewEvent = false;
        verdictEvent = false;
        takeoffCueEvent = false;
        landingEvent = false;
        silentLandingEvent = false;
        forceDisagreedEvent = false;
        unratedEvent = false;
        if (snap is null || !snap.exact || snap.gameTime < 0) {
            if (pendingLanding)
                PublishUnrated("Exact physics read was lost after landing", landingRace);
            else if (inFlight) flightUncertain = true;
            @previous = null;
            return;
        }
        if (previous is null) {
            if (inFlight && snap.contactMask != 0) Land(snap);
            @previous = snap;
            return;
        }
        if (snap.gameTime < previous.gameTime ||
            snap.raceTime < previous.raceTime - 50) {
            Reset();
            @previous = snap;
            return;
        }

        bool crossingTakeoff = previous.contactMask != 0 &&
            snap.contactMask == 0 && !pendingLanding;

        // A slide lasts at least until the next frame that shows none.
        if ((snap.contactMask != 0 && snap.slipDeg >= S_MinSlideSlip) ||
            (previous.contactMask != 0 && previous.slipDeg >= S_MinSlideSlip))
            lastSlideClock = snap.gameTime;
        ObserveSteeringAndMode(snap);
        if (crossingTakeoff) StartFlight(snap);
        else if (previous.contactMask == 0 && snap.contactMask != 0 && inFlight)
            Land(snap);
        else if (inFlight && snap.contactMask == 0 && snap.contactClock > takeoffClock) {
            // The game processed a touch between two frames: land, then take
            // off again unless this landing is being rated.
            Land(snap);
            if (!pendingLanding) StartFlight(snap);
        }

        if (inFlight && snap.contactMask == 0 && flightEligible &&
            !flightUncertain && snap.raceTime - takeoffRace >= S_MinFlight) {
            if (!cuePublished && (preview !is null ||
                (rawReversalAt >= 0 &&
                0 <= takeoffClock - rawReversalAt &&
                takeoffClock - rawReversalAt <= CUE_REVERSAL_WINDOW_MS))) {
                cuePublished = true;
                takeoffCueEvent = true;
            }
            if (!previewPublished && preview !is null) {
                previewPublished = true;
                previewEvent = true;
            }
        }
        if (pendingLanding) {
            if (snap.contactMask == 0) landingTouchLifted = true;
            if (!firstChangeSeen && int(snap.modeAt) != takeoffModeAt) {
                firstChangeSeen = true;
                firstChangeMode = snap.mode;
                firstChangeAt = StoredChangeTick(snap);
            }
            // The backwards-motion gate has no timestamp; eligibility restarts
            // at the frame that shows it set.
            if (snap.forceGateState != 0) gateSeenAt = snap.gameTime;
            // Recovery waits for a front wheel on the ground and the delay; its
            // contact cannot have started before the landing. The earliest front
            // touchdown is kept, so a later bounce cannot move the check tick.
            int front = ContactStart(snap, FRONT_WHEELS, landingClock - 1);
            if (front >= 0 && (frontTouchAt < 0 || front < frontTouchAt)) frontTouchAt = front;
            int eligibleAt = frontTouchAt < 0 ? -1 :
                Math::Max(Math::Max(frontTouchAt, takeoffModeAt + recoveryDelayMs), gateSeenAt);
            int checkAt = eligibleAt < 0 ? -1 :
                Math::Max(landingClock + LANDING_CHECK_MS, eligibleAt + FORCE_SETTLE_MS);
            int deadline = FORCE_GATE_TIMEOUT_MS +
                Math::Max(landingClock, takeoffModeAt + recoveryDelayMs);
            if (flightUncertain)
                PublishUnrated("Landing contact timing became uncertain", snap.raceTime);
            else if (checkAt >= 0 && checkAt <= deadline && snap.forceGateState == 0 &&
                snap.gameTime >= checkAt) {
                forceEligibleClock = eligibleAt;
                checkClock = checkAt;
                ResolveLanding(snap);
            } else if (snap.gameTime > deadline)
                PublishUnrated("Tire-force contact never became eligible", snap.raceTime);
        }
        @previous = snap;
    }
}
