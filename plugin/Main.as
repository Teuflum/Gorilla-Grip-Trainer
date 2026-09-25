bool g_supportedBuild = false;
PhysicsSnapshot@ g_snapshot;
int g_previousContactMask = -1;
int g_previousRaceTime = -1;
TransitionTracker@ g_tracker;
SessionState@ g_session;

void Main() {
    g_supportedBuild = IsSupportedBuild();
    @g_tracker = TransitionTracker();
    @g_session = SessionState();
    print("Gorilla Grip Trainer build supported: " + g_supportedBuild);
}

void Update(float dt) {
    auto vis = VehicleState::ViewingPlayerState();
    if (vis is null) {
        @g_snapshot = null;
        g_previousContactMask = -1;
        g_previousRaceTime = -1;
        g_tracker.Reset();
        g_session.Reset();
        return;
    }
    int t = ReadRaceTime(vis);
    if (t < 0) return;
    if (g_previousRaceTime >= 0 && t < g_previousRaceTime - 50) {
        g_tracker.Reset();
        g_session.Reset();
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
    if (UI::MenuItem("Gorilla Grip Trainer diagnostics", "", S_ShowDiagnostics))
        S_ShowDiagnostics = !S_ShowDiagnostics;
}

void RenderInterface() {
    if (!S_ShowDiagnostics) return;
    if (UI::Begin("Gorilla Grip Trainer")) {
        if (g_snapshot is null) UI::Text("NO CAR");
        else if (!g_snapshot.exact) UI::Text("ESTIMATE");
        else {
            UI::Text("EXACT PHYSICS");
            UI::Text("Internal steer: " + Text::Format("%+.1f%%", g_snapshot.smoothedSteer * 100));
            UI::Text("Mode: " + g_snapshot.mode + "  Contact: " + g_snapshot.ContactBits());
            UI::Text("Icing: " + Text::Format("%.0f%%", g_snapshot.meanIcing * 100));
            UI::Text("Force: " + Text::Format("%.2fx", g_snapshot.force));
        }
    }
    UI::End();
}
