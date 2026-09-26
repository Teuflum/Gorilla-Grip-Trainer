const float STEER_GATE = 0.1f;
const int MAX_TIMING_SAMPLE_GAP = 50;
const int FORCE_SETTLE_MS = 30;
const int FORCE_GATE_TIMEOUT_MS = 500;

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

string GradeLead(int lo, int hi) {
    NormalizeGradeThresholds();
    if (lo < 0 || hi < lo || hi > S_DMaxLeadMs) return "";
    if (hi <= S_SMaxLeadMs) return "S";
    if (lo > S_SMaxLeadMs && hi <= S_AMaxLeadMs) return "A";
    if (lo > S_AMaxLeadMs && hi <= S_BMaxLeadMs) return "B";
    if (lo > S_BMaxLeadMs && hi <= S_CMaxLeadMs) return "C";
    if (lo > S_CMaxLeadMs && hi <= S_DMaxLeadMs) return "D";
    return "";
}

class JumpPreview {
    string label;
    bool ambiguous = false;
    int leadMinMs = -1;
    int leadMaxMs = -1;
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
    bool unratedEvent = false;
    string unratedReason = "";

    int switchAt = -1;
    int switchOldMode = 0;
    int switchNewMode = 0;
    int rawReversalAt = -1;

    bool inFlight = false;
    bool pendingLanding = false;
    bool flightEligible = false;
    bool flightUncertain = false;
    bool previewPublished = false;
    bool cuePublished = false;
    int takeoffRace = -1;
    int takeoffClock = -1;
    int takeoffMode = 0;
    int takeoffModeAt = -1;
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
        unratedEvent = false;
        unratedReason = "";
        switchAt = -1;
        switchOldMode = 0;
        switchNewMode = 0;
        rawReversalAt = -1;
        inFlight = false;
        pendingLanding = false;
        flightEligible = false;
        flightUncertain = false;
        previewPublished = false;
        cuePublished = false;
        takeoffRace = -1;
        takeoffClock = -1;
        takeoffMode = 0;
        takeoffModeAt = -1;
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
        takeoffRace = snap.raceTime;
        takeoffClock = snap.gameTime;
        takeoffMode = snap.mode;
        takeoffModeAt = int(snap.modeAt);
        recoveryDelayMs = snap.recoveryDelayMs;
        flightEligible = takeoffMode != 0 &&
            previous.meanIcing >= S_MinIcing &&
            previous.speedKmh >= float(S_MinSpeed);
        if (!flightEligible || previous.gameTime < 0 ||
            snap.gameTime - previous.gameTime > MAX_TIMING_SAMPLE_GAP) {
            if (snap.gameTime - previous.gameTime > MAX_TIMING_SAMPLE_GAP) {
                flightUncertain = true;
                if (flightEligible && switchAt >= 0 &&
                    switchNewMode == takeoffMode &&
                    snap.gameTime - switchAt <= S_DMaxLeadMs) {
                    unratedReason = "contact sample gap exceeded 50 ms";
                    unratedEvent = true;
                }
            }
            return;
        }
        if (switchAt < 0 || switchNewMode != takeoffMode ||
            switchOldMode == 0 || switchOldMode == takeoffMode ||
            switchAt > snap.gameTime || snap.gameTime - switchAt > S_DMaxLeadMs) return;
        int lo = Math::Max(0, previous.gameTime - switchAt);
        int hi = snap.gameTime - switchAt;
        string grade = GradeLead(lo, hi);
        @preview = JumpPreview();
        if (grade.Length == 0) {
            preview.label = GradeLead(hi, hi);
            preview.ambiguous = true;
            if (preview.label.Length == 0) {
                @preview = null;
                return;
            }
        } else preview.label = grade;
        preview.leadMinMs = lo;
        preview.leadMaxMs = hi;
        preview.takeoffTime = snap.raceTime;
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
        verdict.leadMinMs = preview is null ? -1 : preview.leadMinMs;
        verdict.leadMaxMs = preview is null ? -1 : preview.leadMaxMs;
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
            forceEligibleClock - takeoffModeAt >= 2 * recoveryDelayMs &&
            snap.force > 1.001f;
        if (hasPreview) {
            @verdict = JumpVerdict();
            verdict.label = recovered ? preview.label : "MISSED";
            verdict.reason = recovered ? (preview.ambiguous ?
                "Grip recovered; conservative grade from timing range" :
                "Pre-takeoff mode held through force-eligible contact") :
                (enoughIcing ?
                "Direction or tire force did not recover on force-eligible contact" :
                "Landing icing fell below the rating threshold");
            verdict.leadMinMs = preview.leadMinMs;
            verdict.leadMaxMs = preview.leadMaxMs;
            verdict.timingEstimated = preview.ambiguous;
        } else if (enoughIcing && landingDirection != 0 && takeoffMode != 0 &&
            landingDirection != takeoffMode && snap.force <= 1.1f) {
            @verdict = JumpVerdict();
            verdict.label = "MISSED";
            verdict.reason = "Opposite landing direction with delayed tire force";
        } else return;
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
        if (sampleGap > MAX_TIMING_SAMPLE_GAP) {
            // Keep a recent grounded switch until StartFlight can report the
            // uncertain takeoff. It cannot receive a timing grade from this gap.
            if (!crossingTakeoff) switchAt = -1;
            rawReversalAt = -1;
            if (previous.contactMask != snap.contactMask)
                flightUncertain = true;
            if (pendingLanding) flightUncertain = true;
            if (inFlight) spinReliable = false;
        }

        if (inFlight && previous.contactMask == 0) {
            float turn = snap.yaw - previous.yaw;
            if (turn > Math::PI) turn -= 2.0f * Math::PI;
            if (turn < -Math::PI) turn += 2.0f * Math::PI;
            airSpinRadians += Math::Abs(turn);
        }

        if (sampleGap <= MAX_TIMING_SAMPLE_GAP) ObserveSteeringAndMode(snap);
        if (crossingTakeoff) {
            StartFlight(snap);
            if (sampleGap > MAX_TIMING_SAMPLE_GAP) switchAt = -1;
        }
        else if (previous.contactMask == 0 && snap.contactMask != 0 && inFlight)
            Land(snap);

        if (inFlight && snap.contactMask == 0 && flightEligible &&
            !flightUncertain && snap.raceTime - takeoffRace >= S_MinFlight) {
            if (!cuePublished && (preview !is null ||
                (rawReversalAt >= 0 &&
                0 <= takeoffClock - rawReversalAt &&
                takeoffClock - rawReversalAt <= 250))) {
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
            if (snap.contactMask != 0 && snap.forceGateState == 0) {
                if (forceEligibleClock < 0) forceEligibleClock = snap.gameTime;
            } else forceEligibleClock = -1;
            if (flightUncertain)
                PublishUnrated("Landing contact timing became uncertain", snap.raceTime);
            else if (snap.gameTime - landingClock > FORCE_GATE_TIMEOUT_MS)
                PublishUnrated("Tire-force contact never became eligible", snap.raceTime);
            else if (snap.gameTime - landingClock >= 80 &&
                forceEligibleClock >= 0 &&
                snap.gameTime - forceEligibleClock >= FORCE_SETTLE_MS)
                ResolveLanding(snap);
        }
        @previous = snap;
    }
}
