bool g_supportedBuild = false;
PhysicsSnapshot@ g_snapshot;
int g_previousContactMask = -1;

void Main() {
    g_supportedBuild = IsSupportedBuild();
    print("Gorilla Grip Trainer build supported: " + g_supportedBuild);
}

void Update(float dt) {
    auto vis = VehicleState::ViewingPlayerState();
    if (vis is null) {
        @g_snapshot = null;
        g_previousContactMask = -1;
        return;
    }
    int t = ReadRaceTime(vis);
    if (t < 0) return;
    PhysicsSnapshot@ next = ReadPhysics(vis, t);
    @g_snapshot = next;
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
