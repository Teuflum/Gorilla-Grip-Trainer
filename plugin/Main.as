bool g_supportedBuild = false;
PhysicsSnapshot@ g_snapshot;
int g_previousContactMask = -1;
int g_previousRaceTime = -1;
TransitionTracker@ g_tracker;
SessionState@ g_session;
LastRunSummary@ g_lastRun;

void Main() {
    g_supportedBuild = IsSupportedBuild();
    @g_tracker = TransitionTracker();
    @g_session = SessionState();
    @g_lastRun = LastRunSummary();
    InitLayout();
    InitWidgets();
    print("Gorilla Grip Trainer build supported: " + g_supportedBuild);
}

void Update(float dt) {
    auto vis = VehicleState::ViewingPlayerState();
    if (vis is null) {
        g_lastRun.Capture(g_session);
        @g_snapshot = null;
        g_previousContactMask = -1;
        g_previousRaceTime = -1;
        g_tracker.Reset();
        g_session.Reset();
        ClearResult();
        return;
    }
    int t = ReadRaceTime(vis);
    if (t < 0) return;
    if (g_previousRaceTime >= 0 && t < g_previousRaceTime - 50) {
        g_lastRun.Capture(g_session);
        g_tracker.Reset();
        g_session.Reset();
        ClearResult();
    }
    g_previousRaceTime = t;
    PhysicsSnapshot@ next = ReadPhysics(vis, t);
    @g_snapshot = next;
    g_tracker.Update(next);
    if (g_tracker.landingEvent) {
        print("Gorilla Grip Trainer landing at " + g_tracker.landingRace +
            "ms: takeoff mode " + g_tracker.takeoffMode +
            ", landing steer " + g_tracker.landingDirection);
    }
    if (g_tracker.unratedEvent)
        print("Gorilla Grip Trainer timing unrated at " + t + "ms: " +
            g_tracker.unratedReason);
    if (g_tracker.previewEvent) {
        JumpPreview@ p = g_tracker.preview;
        print("Gorilla Grip Trainer preview at " + t + "ms: " + p.label +
            " lead " + p.leadMinMs + "-" + p.leadMaxMs + "ms");
    }
    if (g_tracker.takeoffCueEvent)
        print("Gorilla Grip Trainer takeoff cue at " + t + "ms");
    if (g_tracker.verdictEvent) {
        JumpVerdict@ v = g_tracker.verdict;
        g_session.Apply(v);
        ShowResult(v, t);
        print("Gorilla Grip Trainer verdict at " + t + "ms: " + v.label +
            " | " + v.reason + " | force " + next.force +
            " | spins " + v.spinCount + " | combo " + g_session.combo +
            " | score " + g_session.score);
    }
    if (!next.exact) return;
    if (g_previousContactMask != int(next.contactMask)) {
        print("Gorilla Grip Trainer snapshot at " + t + "ms: exact true, mode " +
            next.mode + ", steer " + Text::Format("%.6f", next.smoothedSteer) +
            ", contacts " + next.ContactBits() + ", modeAt " + next.modeAt +
            ", clock " + next.gameTime + ", delay " + next.recoveryDelayMs);
    }
    g_previousContactMask = int(next.contactMask);
}

void RenderMenu() {
    if (UI::MenuItem("Gorilla Grip Trainer physics panel", "", S_DiagVisible)) {
        S_DiagVisible = !S_DiagVisible;
        WidgetLayout@ widget = GetLayout("diagnostics");
        if (widget !is null) widget.visible = S_DiagVisible;
    }
}

void RenderInterface() {
    RenderLayoutEditor();
}

void Render() {
    RenderWidgets();
}
