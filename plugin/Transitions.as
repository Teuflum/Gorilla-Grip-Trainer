const float STEER_GATE = 0.1f;
// The physics step runs in fixed 10 ms ticks.
const int PHYSICS_TICK_MS = 10;
const int FORCE_SETTLE_MS = 30;
// A takeoff is rated only if the car slid within this time before it.
const int SLIDE_WINDOW_MS = 500;
// A grounded steering reversal this soon before takeoff plays the takeoff cue.
const int CUE_REVERSAL_WINDOW_MS = 250;
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
    int landingDirection = 0;
    int forceEligibleClock = -1;
    int recoveryDelayMs = 400;
    float airSpinRadians = 0.0f;
    int flightSpinCount = 0;
    bool spinReliable = true;

    void Reset() {
        @previous = null;
        @preview = null;
        @verdict = null;
        previewEvent = false;
        verdictEvent = false;
        takeoffCueEvent = false;
        landingEvent = false;
        silentLandingEvent = false;
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
        landingDirection = 0;
        forceEligibleClock = -1;
        airSpinRadians = 0.0f;
        flightSpinCount = 0;
        spinReliable = true;
    }

    void ObserveSteeringAndMode(PhysicsSnapshot@ snap) {
        if (previous is null) return;
        bool previousGround = previous.contactMask != 0;
        bool currentGround = snap.contactMask != 0;
        int beforeRaw = RawDirection(previous.rawSteer);
        int afterRaw = RawDirection(snap.rawSteer);
        if (previousGround && currentGround && beforeRaw != 0 && afterRaw != 0 &&
            beforeRaw != afterRaw && previous.mode == beforeRaw)
            rawReversalAt = snap.gameTime;

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
        airSpinRadians = 0.0f;
        flightSpinCount = 0;
        spinReliable = true;
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
        flightSpinCount = spinReliable ? int(airSpinRadians / (2.0f * Math::PI)) : 0;
        landingEvent = true;
        landingRace = snap.raceTime;
        landingClock = snap.gameTime;
        landingDirection = SteeringDirection(snap.smoothedSteer);
        landingTouchLifted = false;
        forceEligibleClock = -1;
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
        verdict.spinCount = 0;
        verdict.exact = false;
        verdictEvent = true;
    }

    void ResolveLanding(PhysicsSnapshot@ snap) {
        pendingLanding = false;
        if (snap.contactMask == 0) return;
        bool hasPreview = preview !is null && previewPublished;
        bool enoughIcing = snap.meanIcing >= S_MinIcing;
        bool matchingLanding = landingDirection != 0 &&
            landingDirection == takeoffMode;
        bool recovered = enoughIcing && matchingLanding && snap.mode == takeoffMode &&
            int(snap.modeAt) == takeoffModeAt &&
            forceEligibleClock - takeoffModeAt >= recoveryDelayMs &&
            snap.force > 1.001f;
        // A scrape in flight counts as ground contact and can store the new
        // direction before the real landing; name it instead of a generic miss.
        bool touchSwitched = landingTouchLifted && int(snap.modeAt) != takeoffModeAt;
        const string touchReason = "Direction switched on a brief touch before the landing";
        // The stored direction changes only on the ground: after a neutral
        // landing, steering the other way switches it and delays the force.
        bool storedSwitched = snap.mode != 0 && snap.mode != takeoffMode &&
            int(snap.modeAt) != takeoffModeAt;
        bool oppositeLanding = landingDirection != 0 && landingDirection != takeoffMode;
        if (hasPreview) {
            @verdict = JumpVerdict();
            verdict.label = recovered ? preview.label : "MISSED";
            verdict.reason = recovered ?
                "Pre-takeoff mode held through force-eligible contact" :
                (enoughIcing ? (touchSwitched ? touchReason :
                "Direction or tire force did not recover on force-eligible contact") :
                "Landing icing fell below the rating threshold");
            verdict.leadMs = preview.leadMs;
        } else if (enoughIcing && takeoffMode != 0 &&
            (oppositeLanding || storedSwitched) && snap.force <= 1.1f) {
            @verdict = JumpVerdict();
            verdict.label = "MISSED";
            verdict.reason = touchSwitched ? touchReason :
                storedSwitched && takeoffReversalLeadMs >= 0 ?
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
        verdict.spinCount = flightSpinCount;
        verdict.exact = true;
        verdictEvent = true;
    }

    void Update(PhysicsSnapshot@ snap) {
        previewEvent = false;
        verdictEvent = false;
        takeoffCueEvent = false;
        landingEvent = false;
        silentLandingEvent = false;
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

        int sampleGap = snap.gameTime - previous.gameTime;
        bool crossingTakeoff = previous.contactMask != 0 &&
            snap.contactMask == 0 && !pendingLanding;

        if (inFlight && previous.contactMask == 0) {
            float turn = snap.yaw - previous.yaw;
            if (turn > Math::PI) turn -= 2.0f * Math::PI;
            if (turn < -Math::PI) turn += 2.0f * Math::PI;
            airSpinRadians += Math::Abs(turn);
        }

        // A slide lasts at least until the next frame that shows none.
        if ((snap.contactMask != 0 && snap.slipDeg >= S_MinSlideSlip) ||
            (previous.contactMask != 0 && previous.slipDeg >= S_MinSlideSlip))
            lastSlideClock = snap.gameTime;
        ObserveSteeringAndMode(snap);
        if (crossingTakeoff) StartFlight(snap);
        else if (previous.contactMask == 0 && snap.contactMask != 0 && inFlight)
            Land(snap);

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
            if (landingDirection == 0 &&
                snap.gameTime - landingClock <= 30 &&
                SteeringDirection(snap.smoothedSteer) != 0)
                landingDirection = SteeringDirection(snap.smoothedSteer);
            // The recovery timer started at the pre-takeoff switch, so a landing
            // inside the delay waits on the ground until force can start rising.
            if (snap.contactMask == 0) landingTouchLifted = true;
            if ((snap.contactMask & FRONT_WHEELS) != 0 && snap.forceGateState == 0 &&
                snap.gameTime - takeoffModeAt >= recoveryDelayMs) {
                if (forceEligibleClock < 0) forceEligibleClock = snap.gameTime;
            } else forceEligibleClock = -1;
            if (flightUncertain)
                PublishUnrated("Landing contact timing became uncertain", snap.raceTime);
            else if (snap.gameTime - Math::Max(landingClock, takeoffModeAt + recoveryDelayMs) >
                FORCE_GATE_TIMEOUT_MS)
                PublishUnrated("Tire-force contact never became eligible", snap.raceTime);
            else if (snap.gameTime - landingClock >= 80 &&
                forceEligibleClock >= 0 &&
                snap.gameTime - forceEligibleClock >= FORCE_SETTLE_MS)
                ResolveLanding(snap);
        }
        @previous = snap;
    }
}
