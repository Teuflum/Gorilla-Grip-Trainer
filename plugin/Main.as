bool g_supportedBuild = false;
PhysicsSnapshot@ g_snapshot;
int g_previousContactMask = -1;
float g_previousForce = -1.0f;
int g_previousForceGate = -1;
int g_previousRaceTime = -1;
bool g_eventLoggingOn = false;
int g_loggedFrameSkip = -1;
TransitionTracker@ g_tracker;
SessionState@ g_session;
AudioDirector@ g_audio;
HistoryStore@ g_history;
RunRecord@ g_activeRun;
FinishController@ g_finish;
uint g_runSequence = 0;
// Whether the last processed frame was in the Stadium car; the tracker resets
// when the car changes.
bool g_stadiumCar = true;

// Only the Stadium car ice slides, so only its jumps can have a gorilla grip.
// VehicleState reports CarSport when it cannot tell the car.
bool IsStadiumCar(CSceneVehicleVisState@ vis) {
    return VehicleState::GetVehicleType(vis) == VehicleState::VehicleType::CarSport;
}

string CurrentMapUid() {
    auto app = cast<CTrackMania>(GetApp());
    if (app is null || app.RootMap is null || app.RootMap.MapInfo is null)
        return "";
    return app.RootMap.MapInfo.MapUid;
}

string CurrentMapName() {
    auto app = cast<CTrackMania>(GetApp());
    if (app is null || app.RootMap is null) return "Unknown map";
    return Text::StripFormatCodes(string(app.RootMap.MapName));
}

void StartActiveRun() {
    if (g_finish !is null && g_finish.summary !is null) {
        // A race-time rewind already reset the session earlier in Update().
        if (g_previousRaceTime < 0) ResetAttemptState();
        g_finish.NewAttempt();
    }
    @g_activeRun = RunRecord();
    g_activeRun.mapUid = CurrentMapUid();
    g_activeRun.mapName = CurrentMapName();
    g_activeRun.startedAt = Time::MilliStamp;
    g_runSequence++;
    g_activeRun.id = g_activeRun.mapUid + ":" +
        Text::Format("%lld", g_activeRun.startedAt) + ":" +
        Text::Format("%u", g_runSequence);
}

void EndActiveRun(const string &in status, int finishMs = -1) {
    if (g_activeRun is null) return;
    g_activeRun.status = status;
    g_activeRun.finishMs = finishMs;
    g_history.Append(g_activeRun);
    @g_activeRun = null;
}

void ResetAttemptState() {
    EndActiveRun("RESET");
    g_tracker.Reset();
    g_session.Reset();
    ClearResult();
    ClearStatChange();
    g_audio.OnReset();
}

void Main() {
    g_supportedBuild = LocatePhysics();
    if (!g_supportedBuild) {
        UI::ShowNotification("Gorilla Grip Trainer",
            "Could not find the car physics in this Trackmania build. The trainer needs an update before it can work.",
            vec4(0.72f, 0.36f, 0.07f, 1.0f),
            12000);
        print("Gorilla Grip Trainer physics: not found in this game build; unloading");
        Meta::UnloadPlugin(Meta::ExecutingPlugin());
        return;
    }
    @g_tracker = TransitionTracker();
    @g_session = SessionState();
    @g_history = HistoryStore();
    g_history.Load();
    @g_finish = FinishController();
    InitVoicePools();
    @g_audio = AudioDirector();
    g_audio.Load();
    InitLayout();
    InitWidgets();
    InitPictures();
    DebugLog("Gorilla Grip Trainer physics offsets: " + DescribeLayout());
}

void Update(float dt) {
    if (!g_supportedBuild) return;
    // One line per change, so the in-game tests can tell event logging is on.
    if (DebugLoggingOn() != g_eventLoggingOn) {
        g_eventLoggingOn = DebugLoggingOn();
        print("Gorilla Grip Trainer event logging " + (g_eventLoggingOn ? "on" : "off"));
    }
    // The frame-skip value is logged whenever it or event logging changes.
    int frameSkip = DebugLoggingOn() ? DebugFrameSkip() : -1;
    if (frameSkip != g_loggedFrameSkip) {
        g_loggedFrameSkip = frameSkip;
        if (frameSkip > 0) DebugLog("Gorilla Grip Trainer frame skip " + frameSkip);
    }
    g_audio.UpdateSettings();
    auto vis = VehicleState::ViewingPlayerState();
    bool finishSequence = IsFinishSequence();
    if (finishSequence) {
        int finishTime = vis is null ? g_previousRaceTime : ReadRaceTime(vis);
        if (finishTime < 0) finishTime = g_previousRaceTime;
        string mapUid = CurrentMapUid();
        if (finishTime >= 0 && g_activeRun !is null &&
            (mapUid.Length == 0 || mapUid == g_activeRun.mapUid) &&
            g_finish.Update(finishTime, true, g_activeRun)) {
            g_history.Append(g_activeRun);
            @g_activeRun = null;
            g_audio.OnFinish();
            DebugLog("Gorilla Grip Trainer finish summary: " + finishTime +
                "ms, score " + g_session.score);
        }
        return;
    }
    if (vis is null) {
        if (g_finish.summary !is null &&
            CurrentMapUid() == g_finish.summary.mapUid) {
            @g_snapshot = null;
            g_previousContactMask = -1;
            g_previousRaceTime = -1;
            return;
        }
        if (g_finish.summary !is null) g_finish.NewAttempt();
        ResetAttemptState();
        @g_snapshot = null;
        g_previousContactMask = -1;
        g_previousRaceTime = -1;
        return;
    }
    int t = ReadRaceTime(vis);
    if (t < 0) {
        // The start countdown (a failed read gives -1) already begins the next
        // attempt: stop the finish music and clear the old run's stats now,
        // not when the timer reaches zero.
        if (t < -1 && (g_activeRun !is null || g_finish.summary !is null)) {
            ResetAttemptState();
            if (g_finish.summary !is null) g_finish.NewAttempt();
            g_previousRaceTime = -1;
        }
        // Keep the widgets up during the countdown, without timing anything.
        if (g_activeRun is null) @g_snapshot = ReadPhysics(vis, t);
        return;
    }
    if (g_activeRun is null && g_finish.summary !is null &&
        t > 500 && t >= g_finish.summary.finishMs - 50) return;
    string mapUid = CurrentMapUid();
    if (g_activeRun !is null && mapUid.Length > 0 &&
        g_activeRun.mapUid.Length > 0 && mapUid != g_activeRun.mapUid)
        ResetAttemptState();
    if (g_previousRaceTime >= 0 && t < g_previousRaceTime - 50)
        ResetAttemptState();
    if (g_activeRun is null) StartActiveRun();
    else if (g_activeRun.mapUid.Length == 0 && mapUid.Length > 0) {
        g_activeRun.mapUid = mapUid;
        g_activeRun.mapName = CurrentMapName();
    }
    g_previousRaceTime = t;
    // Developer frame skipping simulates a low frame rate for timing tests.
    if (!ProcessThisFrame()) return;
    PhysicsSnapshot@ next = ReadPhysics(vis, t);
    @g_snapshot = next;
    // Snow, Rally and Desert jumps are not rated; a jump in progress when the
    // car changes is dropped.
    bool stadiumCar = IsStadiumCar(vis);
    if (stadiumCar != g_stadiumCar) {
        g_stadiumCar = stadiumCar;
        g_tracker.Reset();
        DebugLog("Gorilla Grip Trainer car " + tostring(VehicleState::GetVehicleType(vis)) +
            (stadiumCar ? ": rating jumps" : ": jumps are not rated outside the Stadium car"));
    }
    if (!stadiumCar) {
        g_readMonitor.Pause();
        return;
    }
    g_readMonitor.Observe(next);
    g_tracker.Update(next);
    if (g_tracker.landingEvent) {
        DebugLog("Gorilla Grip Trainer landing at " + g_tracker.landingRace +
            "ms: takeoff mode " + g_tracker.takeoffMode +
            ", stored mode " + next.mode);
    }
    if (g_tracker.silentLandingEvent)
        DebugLog("Gorilla Grip Trainer landing resolved without verdict at " + t +
            "ms: takeoff mode " + g_tracker.takeoffMode + ", stored mode " + next.mode +
            ", force " + Text::Format("%.3f", next.force) +
            ", gate " + next.forceGateState);
    if (g_tracker.forceDisagreedEvent)
        DebugLog("Gorilla Grip Trainer force did not rise although the direction held at " + t +
            "ms: force " + Text::Format("%.3f", next.force) + ", gate " + next.forceGateState +
            ", steer " + Text::Format("%.3f", next.smoothedSteer));
    if (g_tracker.unratedEvent)
        DebugLog("Gorilla Grip Trainer timing unrated at " + t + "ms: " +
            g_tracker.unratedReason);
    if (g_tracker.skippedEvent)
        DebugLog("Gorilla Grip Trainer jump skipped by the rating filters: " +
            g_tracker.skippedReason);
    if (g_tracker.previewEvent) {
        JumpPreview@ p = g_tracker.preview;
        DebugLog("Gorilla Grip Trainer preview at " + t + "ms: " + p.label +
            " lead " + p.leadMs + "ms");
    }
    if (g_tracker.takeoffCueEvent)
        g_audio.OnTakeoffCue();
    if (g_tracker.takeoffCueEvent)
        DebugLog("Gorilla Grip Trainer takeoff cue at " + t + "ms");
    if (g_tracker.verdictEvent) {
        JumpVerdict@ v = g_tracker.verdict;
        int scoreBefore = g_session.score;
        int comboBefore = g_session.combo;
        int bestBefore = g_session.bestCombo;
        g_session.Apply(v);
        ShowStatChange(v, t, scoreBefore, comboBefore, bestBefore);
        g_activeRun.Record(v, g_session, g_tracker.preview);
        ShowResult(v, t);
        g_audio.OnVerdict(v);
        DebugLog("Gorilla Grip Trainer verdict at " + t + "ms: " + v.label +
            " | " + v.reason + " | force " + next.force +
            " | force gate " + next.forceGateState +
            " | eligible at " + g_tracker.forceEligibleClock +
            " | combo " + g_session.combo +
            " | score " + g_session.score +
            " | takeoff " + v.takeoffTime + "ms | landing " + v.landingTime +
            "ms | lead " + v.leadMs + "ms");
    }
    if (!next.exact) return;
    if (g_previousContactMask != int(next.contactMask) || (DebugForceTraceOn() &&
        (g_previousForce != next.force || g_previousForceGate != next.forceGateState))) {
        DebugLog("Gorilla Grip Trainer snapshot at " + t + "ms: exact true, mode " +
            next.mode + ", steer " + Text::Format("%.6f", next.smoothedSteer) +
            ", contacts " + next.ContactBits() + ", modeAt " + next.modeAt +
            ", clock " + next.gameTime + ", delay " + next.recoveryDelayMs +
            ", force " + Text::Format("%.3f", next.force) +
            ", gate " + next.forceGateState +
            ", materials " + next.materials +
            ", icing " + Text::Format("%.0f", next.icingFL * 100.0f) + "/" +
            Text::Format("%.0f", next.icingFR * 100.0f) + "/" +
            Text::Format("%.0f", next.icingRR * 100.0f) + "/" +
            Text::Format("%.0f", next.icingRL * 100.0f) +
            ", speed " + Text::Format("%.0f", next.speedKmh) +
            ", slip " + Text::Format("%.0f", next.slipDeg));
    }
    g_previousContactMask = int(next.contactMask);
    g_previousForce = next.force;
    g_previousForceGate = next.forceGateState;
}

void RenderMenu() {
    if (!g_supportedBuild || !UI::BeginMenu(Icons::SnowflakeO + " Gorilla Grip Trainer"))
        return;
    if (g_finish !is null && g_finish.summary !is null &&
        UI::MenuItem("Finish summary", "", g_finish.visible))
        g_finish.visible = !g_finish.visible;
    if (UI::MenuItem("Run history", "", g_showHistory))
        g_showHistory = !g_showHistory;
    if (UI::MenuItem("Enable widgets", "", S_EnableWidgets))
        S_EnableWidgets = !S_EnableWidgets;
    UI::EndMenu();
}

void RenderInterface() {
    if (!g_supportedBuild) return;
    RenderLayoutEditor();
    RenderHistoryWindow();
}

void Render() {
    if (!g_supportedBuild) return;
    RenderWidgets();
}
