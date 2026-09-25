const float STEER_GATE = 0.1f;

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
    if (lo < 0 || hi < lo || hi > 250) return "";
    if (hi <= 15) return "S";
    if (lo > 15 && hi <= 35) return "A";
    if (lo > 35 && hi <= 65) return "B";
    if (lo > 65 && hi <= 110) return "C";
    if (lo > 110 && hi <= 250) return "D";
    return "";
}

class JumpPreview {
    string label;
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
        takeoffRace = snap.raceTime;
        takeoffClock = snap.gameTime;
        takeoffMode = snap.mode;
        takeoffModeAt = int(snap.modeAt);
        recoveryDelayMs = snap.recoveryDelayMs;
        flightEligible = takeoffMode != 0 &&
            previous.meanIcing >= S_MinIcing &&
            previous.speedKmh >= float(S_MinSpeed);
        if (!flightEligible || previous.gameTime < 0 ||
            snap.gameTime - previous.gameTime > 25) {
            if (snap.gameTime - previous.gameTime > 25) flightUncertain = true;
            return;
        }
        if (switchAt < 0 || switchNewMode != takeoffMode ||
            switchOldMode == 0 || switchOldMode == takeoffMode ||
            switchAt > snap.gameTime || snap.gameTime - switchAt > 250) return;
        int lo = Math::Max(0, previous.gameTime - switchAt);
        int hi = snap.gameTime - switchAt;
        string grade = GradeLead(lo, hi);
        if (grade.Length == 0) return;
        @preview = JumpPreview();
        preview.label = grade;
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
        pendingLanding = flightEligible && !flightUncertain &&
            landingRace - takeoffRace >= S_MinFlight;
    }

    void ResolveLanding(PhysicsSnapshot@ snap) {
        pendingLanding = false;
        if (snap.contactMask == 0 || snap.meanIcing < S_MinIcing) return;
        bool hasPreview = preview !is null && previewPublished;
        bool matchingLanding = landingDirection != 0 &&
            landingDirection == takeoffMode;
        bool recovered = matchingLanding && snap.mode == takeoffMode &&
            int(snap.modeAt) == takeoffModeAt &&
            landingClock - takeoffModeAt >= 2 * recoveryDelayMs &&
            snap.force > 1.001f;
        if (hasPreview) {
            @verdict = JumpVerdict();
            verdict.label = recovered ? preview.label : "MISSED";
            verdict.reason = recovered ? "Pre-takeoff mode held through landing" :
                "Direction or tire force did not recover on contact";
            verdict.leadMinMs = preview.leadMinMs;
            verdict.leadMaxMs = preview.leadMaxMs;
        } else if (landingDirection != 0 && takeoffMode != 0 &&
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
        if (snap is null || !snap.exact || snap.gameTime < 0) {
            if (inFlight || pendingLanding) flightUncertain = true;
            @previous = null;
            return;
        }
        if (previous is null) {
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
        if (sampleGap > 25) {
            switchAt = -1;
            rawReversalAt = -1;
            if (previous.contactMask != snap.contactMask)
                flightUncertain = true;
            if (inFlight) spinReliable = false;
        }

        if (inFlight && previous.contactMask == 0) {
            float turn = snap.yaw - previous.yaw;
            if (turn > Math::PI) turn -= 2.0f * Math::PI;
            if (turn < -Math::PI) turn += 2.0f * Math::PI;
            airSpinRadians += Math::Abs(turn);
        }

        if (sampleGap <= 25) ObserveSteeringAndMode(snap);
        if (previous.contactMask != 0 && snap.contactMask == 0)
            StartFlight(snap);
        else if (previous.contactMask == 0 && snap.contactMask != 0 && inFlight)
            Land(snap);

        if (inFlight && snap.contactMask == 0 && flightEligible &&
            !flightUncertain && snap.raceTime - takeoffRace >= S_MinFlight) {
            if (!cuePublished && rawReversalAt >= 0 &&
                0 <= takeoffClock - rawReversalAt &&
                takeoffClock - rawReversalAt <= 250) {
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
            if (snap.gameTime - landingClock >= 80) {
                if (!flightUncertain) ResolveLanding(snap);
                else pendingLanding = false;
            }
        }
        @previous = snap;
    }
}
