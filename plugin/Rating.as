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
// Landing icing needed to confirm a grade, about what still starts an ice
// slide. The configured minimum applies at takeoff: tires lose icing in the
// air (a 2.75 s flight took them from 100% to 54%).
const float LANDING_MIN_ICING = 0.34f;
// Slip angle that marks an ice slide before takeoff; bobsleigh steering stays far below.
const float MIN_SLIDE_SLIP_DEG = 20.0f;

SlideMode RawDirection(float steer) {
    if (steer > 0.01f) return SlideMode::Right;
    if (steer < -0.01f) return SlideMode::Left;
    return SlideMode::Neutral;
}

// Grade::None when the lead is outside every grade.
Grade GradeLead(int leadMs) {
    if (leadMs < 0 || leadMs > S_DMaxLeadMs) return Grade::None;
    // The switch happened on the tick the last wheel left.
    if (leadMs == 0) return Grade::SPlus;
    if (leadMs <= S_SMaxLeadMs) return Grade::S;
    if (leadMs <= S_AMaxLeadMs) return Grade::A;
    if (leadMs <= S_BMaxLeadMs) return Grade::B;
    if (leadMs <= S_CMaxLeadMs) return Grade::C;
    return Grade::D;
}

// The car's contact clock stops at the takeoff tick, the first tick whose
// previous flags were all clear; sub-tick wheel grazes do not move it. It
// must lie between the two frames.
bool TakeoffClockValid(PhysicsSnapshot@ before, PhysicsSnapshot@ after) {
    return after.contactClock > before.tick && after.contactClock <= after.tick;
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
        if (at <= after || at > snap.contactClock) at = snap.tick + PHYSICS_TICK_MS;
        if (start < 0 || at < start) start = at;
    }
    return start;
}

// When the stored direction last changed: modeAt, or for a lapse to neutral,
// which stores an unset modeAt, the tick after the neutral timeout ran out.
// -1 when a lapse cannot be dated.
int StoredChangeTick(PhysicsSnapshot@ snap) {
    int storedAt = int(snap.modeAt);
    if (snap.mode != SlideMode::Neutral || storedAt != -1) return storedAt;
    return snap.neutralAt >= 0 && snap.neutralTimeoutMs > 0 ?
        snap.neutralAt + snap.neutralTimeoutMs + PHYSICS_TICK_MS : -1;
}

// Dates a raw steering reversal inside a frame gap from how far the smoothed
// steering has moved toward the new side. Once it has reached the input, the
// travel no longer tells when it started: take the earliest possible tick.
int EstimateReversal(PhysicsSnapshot@ before, PhysicsSnapshot@ after) {
    int earliest = Math::Min(before.tick + PHYSICS_TICK_MS, after.tick);
    if (Math::Abs(after.smoothedSteer - after.rawSteer) < 0.001f) return earliest;
    float travel = Math::Abs(after.smoothedSteer - before.smoothedSteer);
    int ticks = Math::Max(1, int(travel / SMOOTHED_STEER_STEP + 0.999f));
    return Math::Clamp(after.tick - (ticks - 1) * PHYSICS_TICK_MS,
        earliest, after.tick);
}

class JumpPreview {
    Grade grade = Grade::None;
    int leadMs = -1;
    int modeAt = -1;
}

// One flight, from the takeoff that started it.
class Flight {
    int takeoffRace = -1;
    int takeoffTick = -1;
    SlideMode takeoffMode = SlideMode::Neutral;
    int takeoffModeAt = -1;
    int recoveryDelayMs = 400;
    // Lead of the steering reversal that played the takeoff cue, or -1.
    int reversalLeadMs = -1;
    bool eligible = false;
    bool uncertain = false;
    JumpPreview@ preview;
    bool previewPublished = false;
    bool cuePublished = false;
    // Why this flight's timing cannot be rated, and the HUD caption.
    string unratedReason = "";
    string unratedCaption = "";
    // Filters an ineligible takeoff failed; logged only if the flight is long
    // enough to be a jump, not a wheel flickering on the ground.
    string pendingSkip = "";
}

// The check of one landing, from its touchdown.
class LandingCheck {
    int race = -1;
    int tick = -1;
    // The first landing contact was followed by more airtime (a brief touch).
    bool touchLifted = false;
    int forceEligibleTick = -1;
    // The tick the verdict is decided at, once known.
    int checkTick = -1;
    // Latest frame that showed the backwards-motion gate set, or -1.
    int gateSeenAt = -1;
    // Earliest front-wheel touchdown seen since the landing, or -1.
    int frontTouchAt = -1;
    // First stored-direction change seen since takeoff: when it was stored
    // (-1 if a lapse to neutral cannot be dated) and the mode it stored.
    bool firstChangeSeen = false;
    int firstChangeAt = -1;
    SlideMode firstChangeMode = SlideMode::Neutral;
}

class JumpTracker {
    PhysicsSnapshot@ previous;
    Flight@ flight = Flight();
    LandingCheck@ landing = LandingCheck();
    JumpVerdict@ verdict;
    bool verdictEvent = false;
    bool takeoffCueEvent = false;
    bool inFlight = false;
    bool pendingLanding = false;
    // Switch already logged as a too-short flight, so a hop is named once.
    int shortSkipSwitchAt = -1;
    int switchAt = -1;
    SlideMode switchOldMode = SlideMode::Neutral;
    SlideMode switchNewMode = SlideMode::Neutral;
    int rawReversalAt = -1;
    int lastSlideTick = -1;

    void ObserveSteeringAndMode(PhysicsSnapshot@ snap) {
        if (previous is null) return;
        bool previousGround = previous.contactMask != 0;
        SlideMode beforeRaw = RawDirection(previous.rawSteer);
        SlideMode afterRaw = RawDirection(snap.rawSteer);
        // A reversal first seen on the all-air frame may still have happened
        // on the ground; StartFlight keeps it only if it dates before takeoff.
        if (previousGround && beforeRaw != SlideMode::Neutral &&
            afterRaw != SlideMode::Neutral &&
            beforeRaw != afterRaw && previous.mode == beforeRaw)
            rawReversalAt = EstimateReversal(previous, snap);

        if (!previousGround) return;
        if (previous.mode == SlideMode::Neutral || snap.mode == SlideMode::Neutral ||
            previous.mode == snap.mode) return;
        if (previous.modeAt == snap.modeAt) return;
        int at = int(snap.modeAt);
        if (at < previous.tick || at > snap.tick) return;
        switchAt = at;
        switchOldMode = previous.mode;
        switchNewMode = snap.mode;
    }

    void StartFlight(PhysicsSnapshot@ snap) {
        inFlight = true;
        pendingLanding = false;
        @flight = Flight();
        bool exactTakeoff = TakeoffClockValid(previous, snap);
        flight.takeoffTick = exactTakeoff ? snap.contactClock : snap.tick;
        flight.takeoffRace = snap.RaceAt(flight.takeoffTick);
        flight.takeoffMode = snap.mode;
        flight.takeoffModeAt = int(snap.modeAt);
        int reversalLead = flight.takeoffTick - rawReversalAt;
        flight.reversalLeadMs = rawReversalAt >= 0 && reversalLead >= 0 &&
            reversalLead <= CUE_REVERSAL_WINDOW_MS ? reversalLead : -1;
        flight.recoveryDelayMs = snap.recoveryDelayMs;
        bool attempted = switchAt >= 0 && switchNewMode == flight.takeoffMode &&
            flight.takeoffTick - switchAt <= S_DMaxLeadMs;
        // Only a jump out of an ice slide is a gorilla-grip attempt.
        flight.eligible = flight.takeoffMode != SlideMode::Neutral &&
            lastSlideTick >= 0 && flight.takeoffTick - lastSlideTick <= SLIDE_WINDOW_MS &&
            previous.meanIcing >= S_MinIcing &&
            previous.speedKmh >= float(S_MinSpeed);
        if (!flight.eligible) {
            // Name the filters that dropped a switch or a late reversal, so
            // their limits can be checked against real jumps.
            bool switched = attempted && switchOldMode != SlideMode::Neutral &&
                switchOldMode != flight.takeoffMode;
            if (switched || flight.reversalLeadMs >= 0)
                flight.pendingSkip = EligibilityMisses(switched ? flight.takeoffTick - switchAt : -1);
            return;
        }
        if (!exactTakeoff) {
            flight.uncertain = true;
            if (attempted) MarkUnrated("Contact timestamps were inconsistent at takeoff",
                "TIMING UNVERIFIED", snap.raceTime);
            return;
        }
        if (!attempted || switchOldMode == SlideMode::Neutral ||
            switchOldMode == flight.takeoffMode || switchAt > flight.takeoffTick) return;
        int lead = flight.takeoffTick - switchAt;
        Grade grade = GradeLead(lead);
        if (grade == Grade::None) return;
        @flight.preview = JumpPreview();
        flight.preview.grade = grade;
        flight.preview.leadMs = lead;
        flight.preview.modeAt = switchAt;
    }

    void Land(PhysicsSnapshot@ snap) {
        inFlight = false;
        @landing = LandingCheck();
        // The grounded wheels date the touchdown; a touch that already lifted
        // again is dated by the car's contact clock. Only changes after the
        // last all-air frame count: a wheel whose contact is not processed yet
        // can still carry a graze timestamp from the flight.
        int after = previous is null ? flight.takeoffTick :
            Math::Max(flight.takeoffTick, previous.tick);
        landing.tick = snap.contactMask != 0 ?
            ContactStart(snap, ALL_WHEELS, after) : snap.contactClock;
        landing.race = snap.RaceAt(landing.tick);
        DebugLog("Landing at " + landing.race + "ms: takeoff mode " + flight.takeoffMode +
            ", stored mode " + snap.mode);
        landing.touchLifted = snap.contactMask == 0;
        int flightMs = landing.race - flight.takeoffRace;
        bool longFlight = flightMs >= S_MinFlight;
        pendingLanding = flight.eligible && !flight.uncertain && longFlight;
        if (flight.pendingSkip.Length > 0 && longFlight) NoteSkipped(flight.pendingSkip);
        flight.pendingSkip = "";
        JumpPreview@ preview = flight.preview;
        if (flight.eligible && !flight.uncertain && !longFlight && preview !is null &&
            preview.modeAt != shortSkipSwitchAt) {
            shortSkipSwitchAt = preview.modeAt;
            NoteSkipped("lead " + preview.leadMs + "ms | flight " + flightMs +
                "ms below " + S_MinFlight + "ms");
        }
        if (flight.uncertain && flight.unratedReason.Length > 0)
            PublishUnrated(flight.unratedReason, flight.unratedCaption, landing.race);
        else if (flight.uncertain && flight.previewPublished)
            PublishUnrated("Exact contact timing was lost during flight",
                "CONTACT TIMING LOST", landing.race);
    }

    // The rating filters this takeoff failed, with the values they saw.
    string EligibilityMisses(int leadMs) {
        string misses = leadMs >= 0 ? "lead " + leadMs + "ms" :
            "steering reversed " + flight.reversalLeadMs + "ms before takeoff";
        if (flight.takeoffMode == SlideMode::Neutral) misses += " | no stored direction";
        if (lastSlideTick < 0 || flight.takeoffTick - lastSlideTick > SLIDE_WINDOW_MS)
            misses += " | no slip of " + Text::Format("%.0f", MIN_SLIDE_SLIP_DEG) +
                " deg in the last " + SLIDE_WINDOW_MS + "ms (" +
                Text::Format("%.0f", previous.slipDeg) + " deg at takeoff)";
        if (previous.meanIcing < S_MinIcing)
            misses += " | icing " + Text::Format("%.2f", previous.meanIcing) +
                " below " + Text::Format("%.2f", S_MinIcing);
        if (previous.speedKmh < float(S_MinSpeed))
            misses += " | speed " + Text::Format("%.0f", previous.speedKmh) +
                " below " + S_MinSpeed + " km/h";
        return misses;
    }

    void NoteSkipped(const string &in reason) {
        DebugLog("Jump skipped by the rating filters: takeoff " + flight.takeoffRace +
            "ms | " + reason);
    }

    void MarkUnrated(const string &in reason, const string &in caption, int raceTime) {
        flight.unratedReason = reason;
        flight.unratedCaption = caption;
        DebugLog("Timing unrated at " + raceTime + "ms: " + reason);
    }

    void PublishUnrated(const string &in reason, const string &in caption, int raceTime) {
        bool attempted = (flight.previewPublished && flight.preview !is null) ||
            flight.unratedReason.Length > 0;
        MarkUnrated(reason, caption, raceTime);
        inFlight = false;
        pendingLanding = false;
        if (!attempted) return;
        @verdict = JumpVerdict();
        verdict.grade = Grade::Unrated;
        verdict.reason = reason;
        verdict.caption = caption;
        verdict.takeoffTime = flight.takeoffRace;
        verdict.landingTime = Math::Max(flight.takeoffRace, raceTime);
        verdict.leadMs = flight.preview is null ? -1 : flight.preview.leadMs;
        verdict.exact = false;
        verdictEvent = true;
    }

    void ResolveLanding(PhysicsSnapshot@ snap) {
        pendingLanding = false;
        JumpPreview@ preview = flight.previewPublished ? flight.preview : null;
        bool enoughIcing = snap.meanIcing >= LANDING_MIN_ICING;
        // The verdict uses the stored direction as of the check tick: the first
        // change seen since takeoff (every tire-force reset writes modeAt), and
        // only if it was stored by then. A later frame may already show a
        // second change; the recorded first one still decides.
        bool switchedByCheck = landing.firstChangeSeen && landing.firstChangeAt <= landing.checkTick;
        // Tire force does not decide: without a reset, a low force means a low
        // target (light steering, low speed), not a delayed grip.
        bool recovered = enoughIcing && !switchedByCheck &&
            landing.forceEligibleTick - flight.takeoffModeAt >= flight.recoveryDelayMs;
        // Only a front wheel down since eligibility ramps the force; one that
        // bounced and came back later has not ramped it yet.
        int frontSince = ContactStart(snap, FRONT_WHEELS, landing.tick - 1);
        if (preview !is null && recovered && !landing.firstChangeSeen && snap.force <= 1.001f &&
            frontSince >= 0 && frontSince <= landing.forceEligibleTick)
            DebugLog("Force did not rise although the direction held at " + snap.raceTime +
                "ms: force " + Text::Format("%.3f", snap.force) + ", gate " + snap.forceGateState +
                ", steer " + Text::Format("%.3f", snap.smoothedSteer));
        // A scrape in flight counts as ground contact and can store the new
        // direction before the real landing; name it instead of a generic miss.
        bool touchSwitched = landing.touchLifted && switchedByCheck;
        const string touchReason = "Direction switched on a brief touch before the landing";
        // The stored direction changes only on the ground: after a neutral
        // landing, steering the other way switches it and delays the force.
        bool storedSwitched = switchedByCheck && landing.firstChangeMode != SlideMode::Neutral &&
            landing.firstChangeMode != flight.takeoffMode;
        bool oppositeLanding = storedSwitched &&
            landing.firstChangeAt <= landing.tick + LANDING_STEER_MS;
        if (preview !is null) {
            @verdict = JumpVerdict();
            verdict.grade = recovered ? preview.grade : Grade::Missed;
            verdict.reason = recovered ?
                "Pre-takeoff mode held through force-eligible contact" :
                (enoughIcing ? (touchSwitched ? touchReason :
                "Direction or tire force did not recover on force-eligible contact") :
                "Landing icing fell below 34%");
            verdict.leadMs = preview.leadMs;
        } else if (enoughIcing && flight.takeoffMode != SlideMode::Neutral && storedSwitched &&
            // The switch reset the force and holds it for the recovery delay.
            landing.checkTick - landing.firstChangeAt < flight.recoveryDelayMs) {
            @verdict = JumpVerdict();
            verdict.grade = Grade::Missed;
            verdict.reason = touchSwitched ? touchReason :
                flight.reversalLeadMs >= 0 ?
                "Steering reversed " + flight.reversalLeadMs +
                " ms before takeoff, too late to store the direction; it switched after the landing" :
                oppositeLanding ? "Opposite landing direction with delayed tire force" :
                "Direction switched after the landing with delayed tire force";
        } else {
            DebugLog("Landing resolved without verdict at " + snap.raceTime +
                "ms: takeoff mode " + flight.takeoffMode + ", stored mode " + snap.mode +
                ", force " + Text::Format("%.3f", snap.force) +
                ", gate " + snap.forceGateState);
            return;
        }
        verdict.takeoffTime = flight.takeoffRace;
        verdict.landingTime = landing.race;
        verdict.exact = true;
        verdictEvent = true;
    }

    // In the air on a rated flight: the takeoff cue, then the preview.
    void PublishAirEvents(PhysicsSnapshot@ snap) {
        if (!inFlight || snap.contactMask != 0 || !flight.eligible || flight.uncertain ||
            snap.raceTime - flight.takeoffRace < S_MinFlight) return;
        int reversalLead = flight.takeoffTick - rawReversalAt;
        if (!flight.cuePublished && (flight.preview !is null ||
            (rawReversalAt >= 0 && 0 <= reversalLead && reversalLead <= CUE_REVERSAL_WINDOW_MS))) {
            flight.cuePublished = true;
            takeoffCueEvent = true;
        }
        if (!flight.previewPublished && flight.preview !is null) {
            flight.previewPublished = true;
            DebugLog("Preview at " + snap.raceTime + "ms: " + GradeName(flight.preview.grade) +
                " lead " + flight.preview.leadMs + "ms");
        }
    }

    // After a rated touchdown: wait for the tick the verdict is decided at.
    void UpdateLandingCheck(PhysicsSnapshot@ snap) {
        if (snap.contactMask == 0) landing.touchLifted = true;
        if (!landing.firstChangeSeen && int(snap.modeAt) != flight.takeoffModeAt) {
            landing.firstChangeSeen = true;
            landing.firstChangeMode = snap.mode;
            landing.firstChangeAt = StoredChangeTick(snap);
        }
        // The backwards-motion gate has no timestamp; eligibility restarts
        // at the frame that shows it set.
        if (snap.forceGateState != 0) landing.gateSeenAt = snap.tick;
        // Recovery waits for a front wheel on the ground and the delay; its
        // contact cannot have started before the landing. The earliest front
        // touchdown is kept, so a later bounce cannot move the check tick.
        int front = ContactStart(snap, FRONT_WHEELS, landing.tick - 1);
        if (front >= 0 && (landing.frontTouchAt < 0 || front < landing.frontTouchAt))
            landing.frontTouchAt = front;
        int delayEnd = flight.takeoffModeAt + flight.recoveryDelayMs;
        int eligibleAt = landing.frontTouchAt < 0 ? -1 :
            Math::Max(Math::Max(landing.frontTouchAt, delayEnd), landing.gateSeenAt);
        int checkAt = eligibleAt < 0 ? -1 :
            Math::Max(landing.tick + LANDING_CHECK_MS, eligibleAt + FORCE_SETTLE_MS);
        int deadline = FORCE_GATE_TIMEOUT_MS + Math::Max(landing.tick, delayEnd);
        if (flight.uncertain)
            PublishUnrated("Landing contact timing became uncertain",
                "CONTACT TIMING LOST", snap.raceTime);
        else if (checkAt >= 0 && checkAt <= deadline && snap.forceGateState == 0 &&
            snap.tick >= checkAt) {
            landing.forceEligibleTick = eligibleAt;
            landing.checkTick = checkAt;
            ResolveLanding(snap);
        } else if (snap.tick > deadline)
            PublishUnrated("Tire-force contact never became eligible",
                "FORCE CHECK UNAVAILABLE", snap.raceTime);
    }

    // False when the clocks ran backwards (a rewind); start a new tracker then.
    bool Update(PhysicsSnapshot@ snap) {
        verdictEvent = false;
        takeoffCueEvent = false;
        if (snap is null || !snap.exact || snap.tick < 0) {
            if (pendingLanding)
                PublishUnrated("Exact physics read was lost after landing",
                    "PHYSICS READ LOST", landing.race);
            else if (inFlight) flight.uncertain = true;
            @previous = null;
            return true;
        }
        if (previous is null) {
            if (inFlight && snap.contactMask != 0) Land(snap);
            @previous = snap;
            return true;
        }
        if (snap.tick < previous.tick || snap.raceTime < previous.raceTime - 50)
            return false;

        bool crossingTakeoff = previous.contactMask != 0 &&
            snap.contactMask == 0 && !pendingLanding;
        // A slide lasts at least until the next frame that shows none.
        if ((snap.contactMask != 0 && snap.slipDeg >= MIN_SLIDE_SLIP_DEG) ||
            (previous.contactMask != 0 && previous.slipDeg >= MIN_SLIDE_SLIP_DEG))
            lastSlideTick = snap.tick;
        ObserveSteeringAndMode(snap);
        if (crossingTakeoff) StartFlight(snap);
        else if (previous.contactMask == 0 && snap.contactMask != 0 && inFlight)
            Land(snap);
        else if (inFlight && snap.contactMask == 0 && snap.contactClock > flight.takeoffTick) {
            // The game processed a touch between two frames: land, then take
            // off again unless this landing is being rated.
            Land(snap);
            if (!pendingLanding) StartFlight(snap);
        }
        PublishAirEvents(snap);
        if (pendingLanding) UpdateLandingCheck(snap);
        @previous = snap;
        return true;
    }
}
