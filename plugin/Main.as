bool g_supportedBuild = false;
PhysicsSnapshot@ g_snapshot;
int g_previousRaceTime = -1;
JumpTracker@ g_tracker;
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
    if (g_finish.summary !is null) {
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

void EndActiveRun(RunStatus status, int finishMs = -1) {
    if (g_activeRun is null) return;
    g_activeRun.status = status;
    g_activeRun.finishMs = finishMs;
    g_history.Append(g_activeRun);
    @g_activeRun = null;
}

void ResetAttemptState() {
    EndActiveRun(RunStatus::Reset);
    @g_tracker = JumpTracker();
    @g_session = SessionState();
    ClearResult();
    ClearStatChange();
    g_audio.OnReset();
}

void Main() {
    g_supportedBuild = Physics::Locate();
    if (!g_supportedBuild) {
        UI::ShowNotification("Gorilla Grip Trainer",
            "Could not find the car physics in this Trackmania build. The trainer needs an update before it can work.",
            vec4(0.72f, 0.36f, 0.07f, 1.0f),
            12000);
        warn("Car physics not found in this game build; unloading");
        Meta::UnloadPlugin(Meta::ExecutingPlugin());
        return;
    }
    NormalizeGradeThresholds();
    @g_tracker = JumpTracker();
    @g_session = SessionState();
    @g_history = HistoryStore();
    g_history.Load();
    @g_finish = FinishController();
    @g_audio = AudioDirector();
    g_audio.Load();
    InitLayout();
    InitWidgets();
    InitPictures();
    DebugLog("Physics offsets: " + Physics::Describe());
}

void OnSettingsChanged() {
    NormalizeGradeThresholds();
}

void OnDisabled() {
    if (g_audio is null) return;
    g_audio.OnReset();
    g_audio.StopPreview();
}

void Update(float dt) {
    if (!g_supportedBuild) return;
    g_trace.UpdateSwitches();
    g_audio.UpdateSettings();
    auto vis = VehicleState::ViewingPlayerState();
    if (IsFinishSequence()) {
        UpdateFinish(vis);
        return;
    }
    if (vis is null) {
        LeaveDrive();
        return;
    }
    int t = Physics::RaceTime(vis);
    if (t < 0) {
        UpdateCountdown(vis, t);
        return;
    }
    // Until the restart, the race clock keeps running past the finished time.
    if (g_activeRun is null && g_finish.summary !is null &&
        t > 500 && t >= g_finish.summary.finishMs - 50) return;
    FollowRun(t);
    RateFrame(vis, t);
}

void UpdateFinish(CSceneVehicleVisState@ vis) {
    int finishTime = vis is null ? g_previousRaceTime : Physics::RaceTime(vis);
    if (finishTime < 0) finishTime = g_previousRaceTime;
    if (finishTime < 0 || g_activeRun is null) return;
    string mapUid = CurrentMapUid();
    if (mapUid.Length > 0 && mapUid != g_activeRun.mapUid) return;
    if (!g_finish.Update(finishTime, g_activeRun)) return;
    g_history.Append(g_activeRun);
    @g_activeRun = null;
    g_audio.OnFinish();
    DebugLog("Finish summary: " + finishTime + "ms, score " + g_session.score);
}

// No car to follow: a menu, the editor, or a map change.
void LeaveDrive() {
    // Already cleared on an earlier frame.
    if (g_snapshot is null && g_activeRun is null && g_finish.summary is null) return;
    // The editor keeps the map loaded, so returning to it would otherwise
    // keep the finish summary and its music until the editor closes.
    bool keepSummary = g_finish.summary !is null && !IsEditingMap() &&
        CurrentMapUid() == g_finish.summary.mapUid;
    if (!keepSummary) {
        g_finish.NewAttempt();
        ResetAttemptState();
    }
    @g_snapshot = null;
    g_trace.ForgetSnapshot();
    g_previousRaceTime = -1;
}

void UpdateCountdown(CSceneVehicleVisState@ vis, int t) {
    // The start countdown (a failed read gives -1) already begins the next
    // attempt: stop the finish music and clear the old run's stats now,
    // not when the timer reaches zero.
    if (t < -1 && (g_activeRun !is null || g_finish.summary !is null)) {
        ResetAttemptState();
        g_finish.NewAttempt();
        g_previousRaceTime = -1;
    }
    // Keep the widgets up during the countdown, without timing anything.
    if (g_activeRun is null) @g_snapshot = Physics::Read(vis, t);
}

// Starts a run, or ends it on a map change or a rewind of the race clock.
void FollowRun(int t) {
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
}

void RateFrame(CSceneVehicleVisState@ vis, int t) {
    PhysicsSnapshot@ next = Physics::Read(vis, t);
    @g_snapshot = next;
    // Snow, Rally and Desert jumps are not rated; a jump in progress when the
    // car changes is dropped.
    bool stadiumCar = IsStadiumCar(vis);
    if (stadiumCar != g_stadiumCar) {
        g_stadiumCar = stadiumCar;
        @g_tracker = JumpTracker();
        DebugLog("Car " + tostring(VehicleState::GetVehicleType(vis)) +
            (stadiumCar ? ": rating jumps" : ": jumps are not rated outside the Stadium car"));
    }
    if (!stadiumCar) {
        g_readMonitor.Pause();
        return;
    }
    g_readMonitor.Observe(next);
    if (!g_tracker.Update(next)) {
        @g_tracker = JumpTracker();
        g_tracker.Update(next);
    }
    if (g_tracker.takeoffCueEvent) {
        g_audio.OnTakeoffCue();
        DebugLog("Takeoff cue at " + t + "ms");
    }
    if (g_tracker.verdictEvent) ApplyVerdict(g_tracker.verdict, next, t);
    g_trace.Snapshot(next, t);
}

void ApplyVerdict(JumpVerdict@ v, PhysicsSnapshot@ next, int t) {
    int scoreBefore = g_session.score;
    int comboBefore = g_session.combo;
    int bestBefore = g_session.bestCombo;
    g_session.Apply(v);
    ShowStatChange(v, t, scoreBefore, comboBefore, bestBefore);
    g_activeRun.Record(v, g_session, g_tracker.flight.preview);
    ShowResult(v, t);
    g_audio.OnVerdict(v);
    DebugLog("Verdict at " + t + "ms: " + GradeName(v.grade) +
        " | " + v.reason + " | force " + next.force +
        " | force gate " + next.forceGateState +
        " | eligible at " + g_tracker.landing.forceEligibleTick +
        " | combo " + g_session.combo +
        " | score " + g_session.score +
        " | takeoff " + v.takeoffTime + "ms | landing " + v.landingTime +
        "ms | lead " + v.leadMs + "ms");
}

void RenderMenu() {
    if (!g_supportedBuild || !UI::BeginMenu(Icons::SnowflakeO + " Gorilla Grip Trainer"))
        return;
    if (g_finish !is null && g_finish.summary !is null &&
        UI::MenuItem("Finish summary", "", g_finish.visible))
        g_finish.visible = !g_finish.visible;
    if (UI::MenuItem("Run history", "", g_historyView.visible))
        g_historyView.visible = !g_historyView.visible;
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
