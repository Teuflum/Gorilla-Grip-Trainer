int g_hudFont = -1;
// The landing result on the Grade widget, or a Popup-tab preview of one.
class ShownResult {
    Grade grade;
    string caption;
    uint64 shownAt = Time::Now;
    // A preview plays even with widgets off or outside a run.
    bool preview = false;

    int Age() { return int(Time::Now - shownAt); }
}

// A landing's change to the Stats widget; the changed values show in colour briefly.
class StatChange {
    int at;
    bool earned;
    bool comboGained;
    bool comboBroken;
    bool newBest;
}

ShownResult@ g_result;
StatChange@ g_statChange;

void InitWidgets() {
    g_hudFont = nvg::LoadFont("DroidSans-Bold.ttf");
}

// A landing result, or a Popup-tab preview of one.
void ShowResult(Grade grade, const string &in caption, bool preview = false) {
    @g_result = ShownResult();
    g_result.grade = grade;
    g_result.caption = caption;
    g_result.preview = preview;
}

// Called after the session applied the verdict.
void ShowStatChange(JumpVerdict@ verdict, int raceTime, int comboBefore, int bestBefore) {
    if (verdict.grade == Grade::Unrated) return;
    @g_statChange = StatChange();
    g_statChange.at = raceTime;
    g_statChange.earned = verdict.points > 0;
    g_statChange.comboGained = g_session.combo > comboBefore;
    g_statChange.comboBroken = comboBefore > 0 && g_session.combo == 0;
    g_statChange.newBest = g_session.bestCombo > bestBefore;
}

string ModeName(SlideMode mode) {
    if (mode == SlideMode::Left) return "LEFT";
    if (mode == SlideMode::Right) return "RIGHT";
    return "NONE";
}

vec4 ModeColor(SlideMode mode) {
    if (mode == SlideMode::Left) return Hud::Magenta;
    if (mode == SlideMode::Right) return Hud::Teal;
    return Hud::Muted();
}

// One wheel of the contact grid, outlined gold for a front wheel on the ground
// (only those raise tire force), blue for a rear wheel on the ground, and dim
// in the air, with the tire's icing.
void RenderWheelTile(float x, float y, float w, float h, float s,
    const string &in name, bool front, bool contact, float icing, bool exact) {
    vec4 color = !contact ? Hud::Muted() : (front ? Hud::Gold : Hud::Ice);
    Hud::Outline(x, y, w, h, 5*s, color, contact ? 2*s : 1*s);
    Hud::Text(x + 8*s, y + 11*s, name, 10*s, color, Hud::Left);
    Hud::Text(x + w - 8*s, y + h - 12*s,
        exact ? Text::Format("%.0f%%", icing * 100.0f) : "--", 16*s,
        color, Hud::Right);
}

string ForceText(PhysicsSnapshot@ snap, bool held, bool rearOnly, int modeAge) {
    if (!snap.exact) return "FORCE --";
    if (!g_tracker.inFlight) {
        if (held) return "FORCE LOCKED " + Text::Format("%.2fx", snap.force);
        if (rearOnly) return "REAR WHEELS ONLY";
        return "FORCE " + Text::Format("%.2fx", snap.force);
    }
    if (held) return "FORCE LOCKED";
    if (modeAge < 0) return "NO DIRECTION";
    if (modeAge < snap.recoveryDelayMs) return "FORCE DELAYED";
    if (modeAge < 2 * snap.recoveryDelayMs) return "FORCE COMING BACK";
    return "FULL FORCE READY";
}

string ForceExplanation(PhysicsSnapshot@ snap, bool held, bool rearOnly,
    int modeAge, bool readFailing) {
    if (readFailing) return "JUMPS NOT RATED | PLUGIN NEEDS UPDATE";
    if (!snap.exact) return "";
    if (held) return "GAS OFF GOING BACKWARDS | PRESS GAS";
    if (!g_tracker.inFlight && rearOnly) return "FORCE ONLY CHANGES ON THE FRONT WHEELS";
    if (modeAge < 0) return "STEER ON THE GROUND TO SET A DIRECTION";
    if (g_tracker.inFlight)
        return "FORCE BACK " + snap.recoveryDelayMs + "-" +
            (2 * snap.recoveryDelayMs) + " ms AFTER A SWITCH";
    return "FRONT WHEELS ON THE GROUND ADD FORCE";
}

void RenderDiagnostics(const vec4 &in r, PhysicsSnapshot@ snap) {
    float s = Math::Min(r.z / 500.0f, r.w / 215.0f);
    Hud::Panel(r);
    if (snap is null) {
        Hud::Text(r.x + r.z*0.5f, r.y + r.w*0.5f, "NO CAR", 24*s, Hud::TextColor(), Hud::Center);
        return;
    }
    Hud::Text(r.x + 20*s, r.y + 17*s, "STEERING", 10*s, Hud::Muted(), Hud::Left);
    Hud::Text(r.x + 20*s, r.y + 42*s,
        snap.exact ? Text::Format("%+.1f%%", snap.smoothedSteer * 100.0f) : "--",
        28*s, Hud::TextColor(), Hud::Left);
    Hud::Text(r.x + r.z - 18*s, r.y + 17*s, "SLIDE DIRECTION", 10*s, Hud::Muted(), Hud::Right);
    Hud::Text(r.x + r.z - 18*s, r.y + 44*s, snap.exact ? ModeName(snap.mode) : "--",
        19*s, ModeColor(snap.mode), Hud::Right);
    // Steering bar with the two direction gates.
    float bx = r.x + 21*s;
    float by = r.y + 67*s;
    float bw = r.z - 42*s;
    Hud::Outline(bx, by, bw, 15*s, 7*s, Hud::Muted(), 1*s);
    Hud::Box(bx + bw*0.45f, by - 3*s, 2*s, 21*s, 0, Hud::Magenta);
    Hud::Box(bx + bw*0.55f, by - 3*s, 2*s, 21*s, 0, Hud::Teal);
    if (snap.exact)
        Hud::Box(bx + bw*Math::Clamp((snap.smoothedSteer + 1)*0.5f, 0.0f, 1.0f) - 3*s,
            by - 5*s, 6*s, 25*s, 3*s, Hud::TextColor());
    Hud::Text(bx, by + 29*s, "SETS LEFT", 10*s, Hud::Magenta, Hud::Left);
    Hud::Text(bx + bw, by + 29*s, "SETS RIGHT", 10*s, Hud::Teal, Hud::Right);

    // Wheel grid in the car's layout; indices are the game's wheel order.
    array<string> names = {"FL", "FR", "RL", "RR"};
    array<uint> wheels = {0, 1, 3, 2};
    float tileW = 100*s;
    float tileH = 40*s;
    float gridX = r.x + 20*s;
    float gridY = r.y + 112*s;
    for (uint i = 0; i < 4; i++) {
        uint wheel = wheels[i];
        RenderWheelTile(gridX + float(i % 2) * (tileW + 10*s),
            gridY + float(i / 2) * (tileH + 6*s), tileW, tileH, s,
            names[i], wheel < 2, (snap.contactMask & (1 << wheel)) != 0,
            snap.WheelIcing(wheel), snap.exact);
    }

    float cx = gridX + 2*tileW + 32*s;
    float cr = r.x + r.z - 18*s;
    string phase = g_tracker.inFlight ? "IN AIR " +
        Math::Max(0, snap.raceTime - g_tracker.flight.takeoffRace) + " ms" : "ON GROUND";
    Hud::Text(cx, r.y + 124*s, phase, 14*s, Hud::TextColor(), Hud::Left);
    int modeAge = snap.ModeAgeMs();
    // The backwards-motion hold (gas released while moving backwards) pins
    // the force at 1.0 until gas returns, whatever the timer says.
    bool held = snap.exact && snap.forceGateState != 0;
    // Only a touching front wheel updates the force, so on the rear wheels
    // alone the stored value (often the pre-jump one) is stale.
    bool rearOnly = (snap.contactMask & FRONT_WHEELS) == 0 && snap.contactMask != 0;
    Hud::Text(cr, r.y + 124*s, ForceText(snap, held, rearOnly, modeAge), 12*s, Hud::Gold, Hud::Right);
    Hud::Text(cx, r.y + 150*s,
        "ICY TIRES " + Text::Format("%.0f%%", snap.meanIcing*100.0f), 11*s, Hud::Ice, Hud::Left);
    string detail;
    if (!snap.exact) detail = "NO PHYSICS READ";
    else if (modeAge < 0) detail = "NO DIRECTION SET";
    else if (modeAge < 10000) detail = "SET " + modeAge + " ms AGO";
    else detail = "SET " + Text::Format("%.1f s AGO", float(modeAge) / 1000.0f);
    bool unverified = snap.exact && g_tracker.inFlight &&
        g_tracker.flight.unratedReason.Length > 0;
    if (unverified) detail = "TIMING NOT EXACT";
    // Reads have never worked since the plugin loaded: a game update likely
    // changed a field the code checks missed.
    bool readFailing = !snap.exact && g_readMonitor.ReadFailing();
    if (readFailing) detail = "PHYSICS READ FAILED";
    Hud::Text(cr, r.y + 150*s, detail, 11*s,
        unverified || readFailing ? Hud::Orange : Hud::Muted(), Hud::Right);
    Hud::Box(cx, r.y + 168*s, cr - cx, 1*s, 0, Hud::Muted());
    Hud::Text(cx, r.y + 186*s, ForceExplanation(snap, held, rearOnly, modeAge, readFailing),
        10*s, Hud::Muted(), Hud::Left);
}

void RenderGradePreview(const vec4 &in r, JumpPreview@ preview) {
    float s = Math::Min(r.z / 500.0f, r.w / 125.0f);
    float cx = r.x + r.z*0.5f;
    float cy = r.y + r.w*0.5f;
    float w = 225*s;
    float h = 91*s;
    Hud::Panel(vec4(cx - w*0.5f, cy - h*0.5f, w, h));
    Hud::Text(cx, cy - 31*s, "TAKEOFF PREVIEW", 10*s, Hud::Muted(), Hud::Center);
    Hud::Text(cx, cy - 1*s, GradeName(preview.grade), 48.0f*s, GradeColor(preview.grade), Hud::Center);
    Hud::Text(cx, cy + 31*s, preview.leadMs + " ms BEFORE TAKEOFF", 10*s, Hud::TextColor(), Hud::Center);
}

// Score on the first line, combo and best combo on the second, each value in
// its own colour. For half a second after a landing, the values it changed
// turn white; a broken combo shows in the MISSED colour.
void RenderStats(const vec4 &in r, StatChange@ change, int statAge) {
    Hud::Panel(r);
    float s = Math::Min(r.z / 320.0f, r.w / 150.0f);
    float x0 = r.x + 18*s;
    float x1 = r.x + r.z - 18*s;
    bool cue = change !is null && statAge >= 0 && statAge < 500;
    Hud::Text(x0, r.y + 40*s, "SCORE", 14*s, Hud::Muted(), Hud::Left);
    Hud::Text(x1, r.y + 40*s, "" + g_session.score, 34*s,
        cue && change.earned ? Hud::TextColor() : Hud::Gold, Hud::Right);
    vec4 comboColor = Hud::Gold;
    if (cue && change.comboGained) comboColor = Hud::TextColor();
    if (cue && change.comboBroken) comboColor = GradeColor(Grade::Missed);
    Hud::LabelValue(x0, r.y + 105*s, "COMBO", "x" + g_session.combo, 22*s, comboColor, false);
    Hud::LabelValue(x1, r.y + 105*s, "BEST", "x" + g_session.bestCombo, 22*s,
        cue && change.newBest ? Hud::TextColor() : Hud::Ice, true);
}

// This map's most recent attempt with at least one rated jump.
RunRecord@ LastRatedRun() {
    string mapUid = CurrentMapUid();
    for (int i = int(g_history.runs.Length) - 1; i >= 0; i--) {
        RunRecord@ run = g_history.runs[uint(i)];
        if (run.mapUid == mapUid && run.hits + run.misses > 0) return run;
    }
    return null;
}

void RenderLast(const vec4 &in r, RunRecord@ last) {
    Hud::Panel(r);
    float s = Math::Min(r.z / 410.0f, r.w / 105.0f);
    Hud::Text(r.x + 20*s, r.y + 30*s, "LAST RUN", 15*s, Hud::Muted(), Hud::Left);
    if (last is null) {
        Hud::Text(r.x + r.z*0.5f, r.y + 70*s, "NO RATED RUN YET", 18*s, Hud::TextColor(), Hud::Center);
        return;
    }
    Hud::Text(r.x + r.z - 20*s, r.y + 30*s,
        Time::FormatString("%Y-%m-%d %H:%M", last.startedAt / 1000), 12*s, Hud::Muted(), Hud::Right);
    array<string> labels = {"SCORE", "HITS", "MISSES", "BEST"};
    array<string> values = {"" + last.score, "" + last.hits, "" + last.misses,
        "x" + last.bestCombo};
    array<vec4> colors = {Hud::Gold, Hud::Teal, GradeColor(Grade::Missed), Hud::Ice};
    Hud::Columns(r.x + 20*s, r.y + 60*s, r.z - 40*s, labels, 11*s, Hud::Muted());
    Hud::Columns(r.x + 20*s, r.y + 83*s, r.z - 40*s, values, 18*s, colors);
}

bool ShouldRenderWidget(WidgetLayout@ layout) {
    return layout.Visible() &&
        (UI::IsGameUIVisible() || S_ShowWhenGameHudOff || g_layoutEditing);
}

void RenderShownResult(const vec4 &in r) {
    RenderResult(r, g_result.Age(), g_result.grade, g_result.caption);
}

void RenderWidgets() {
    if (g_hudFont >= 0) nvg::FontFace(g_hudFont);
    bool previewing = g_result !is null && g_result.preview && g_result.Age() < 1000;
    if (S_EnableWidgets) RenderWidgetCards(previewing);
    // A Popup-tab preview plays on top, even with widgets off or outside a run.
    if (previewing) RenderShownResult(g_gradeLayout.Pixels());
}

void RenderWidgetCards(bool previewing) {
    if (g_finish.visible && g_finish.summary !is null && ShouldRenderWidget(g_finishLayout))
        RenderFinishSummary(g_finishLayout.Pixels(), g_finish.summary);
    if (g_snapshot is null) return;
    if (ShouldRenderWidget(g_physicsLayout))
        RenderDiagnostics(g_physicsLayout.Pixels(), g_snapshot);
    if (!previewing && ShouldRenderWidget(g_gradeLayout)) {
        vec4 r = g_gradeLayout.Pixels();
        JumpPreview@ p = (g_tracker.inFlight || g_tracker.pendingLanding) &&
            g_tracker.flight.previewPublished ? g_tracker.flight.preview : null;
        if (p !is null && !g_layoutEditing)
            RenderGradePreview(r, p);
        else if (g_result !is null && g_result.Age() < 1000)
            RenderShownResult(r);
        else if (g_layoutEditing)
            RenderResult(r, 450, Grade::S, GradeCaption(Grade::S));
    }
    if (ShouldRenderWidget(g_statsLayout)) {
        int statAge = g_statChange is null ? -1 : g_snapshot.raceTime - g_statChange.at;
        RenderStats(g_statsLayout.Pixels(), g_statChange, statAge);
    }
    if (ShouldRenderWidget(g_lastLayout))
        RenderLast(g_lastLayout.Pixels(), LastRatedRun());
}
