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

// A landing's change to the Stats widget, for its count-up, pulse and badges.
class StatChange {
    int at;
    int earned;
    bool comboGained;
    bool comboBroken;
    bool newBest;
}

ShownResult@ g_result;
StatChange@ g_statChange;

void InitWidgets() {
    g_hudFont = nvg::LoadFont("DroidSans-Bold.ttf");
}

void ShowResult(JumpVerdict@ verdict) {
    if (verdict is null) return;
    @g_result = ShownResult();
    g_result.grade = verdict.grade;
    g_result.caption = verdict.caption.Length > 0 ? verdict.caption : GradeCaption(verdict.grade);
}

void ClearResult() {
    @g_result = null;
}

// Called after the session applied the verdict.
void ShowStatChange(JumpVerdict@ verdict, int raceTime, int comboBefore, int bestBefore) {
    if (verdict is null || !verdict.exact) return;
    @g_statChange = StatChange();
    g_statChange.at = raceTime;
    g_statChange.earned = verdict.points;
    g_statChange.comboGained = g_session.combo > comboBefore;
    g_statChange.comboBroken = comboBefore > 0 && g_session.combo == 0;
    g_statChange.newBest = g_session.bestCombo > bestBefore;
}

void ClearStatChange() {
    @g_statChange = null;
}

float StatPulse(int age) {
    if (age < 0 || age >= 500) return 0.0f;
    return Math::Sin(Math::PI * float(age) / 500.0f);
}

float StatBadgeFade(int age) {
    if (age < 0 || age >= 900) return 0.0f;
    return 1.0f - Math::Clamp(float(age - 550) / 350.0f, 0.0f, 1.0f);
}

string ModeName(SlideMode mode) {
    if (mode == SlideMode::Left) return "LEFT";
    if (mode == SlideMode::Right) return "RIGHT";
    return "NONE";
}

vec4 ModeColor(SlideMode mode) {
    if (mode == SlideMode::Left) return Hud::Magenta;
    if (mode == SlideMode::Right) return Hud::Teal;
    return Hud::Label;
}

// One wheel of the contact grid: the border shows ground contact (gold for a
// front wheel, which alone raises tire force; blue for a rear wheel; dim in the
// air) and the fill shows that tire's icing.
void RenderWheelTile(float x, float y, float w, float h, float s,
    const string &in name, bool front, bool contact, float icing, bool exact) {
    vec4 border = !contact ? Hud::Line : (front ? Hud::Gold : Hud::Ice);
    float edge = contact ? 2*s : 1*s;
    Hud::Box(x, y, w, h, 7*s, border);
    Hud::Box(x + edge, y + edge, w - 2*edge, h - 2*edge, 6*s,
        contact ? vec4(0.06f, 0.11f, 0.19f, 1.0f) : vec4(0.04f, 0.07f, 0.13f, 1.0f));
    if (exact && icing > 0.0f)
        Hud::Box(x + edge, y + edge, (w - 2*edge) * Math::Clamp(icing, 0.0f, 1.0f),
            h - 2*edge, 6*s, Hud::WithAlpha(Hud::Ice, contact ? 0.22f : 0.10f));
    Hud::Text(x + 8*s, y + 11*s, name, 10*s, contact ? border : Hud::Dim,
        nvg::Align::Left | nvg::Align::Middle);
    Hud::Text(x + w - 8*s, y + h - 12*s,
        exact ? Text::Format("%.0f%%", icing * 100.0f) : "--", 16*s,
        contact ? Hud::Bright : Hud::Dim, nvg::Align::Right | nvg::Align::Middle);
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
    int left = nvg::Align::Left | nvg::Align::Middle;
    int right = nvg::Align::Right | nvg::Align::Middle;
    int center = nvg::Align::Center | nvg::Align::Middle;
    Hud::CardBase(r, Hud::Teal);
    if (snap is null) {
        Hud::Text(r.x + r.z*0.5f, r.y + r.w*0.5f, "NO CAR", 24*s, Hud::Label, center);
        return;
    }
    Hud::Text(r.x + 20*s, r.y + 17*s, "STEERING", 10*s, Hud::Label, left);
    Hud::Text(r.x + 20*s, r.y + 42*s,
        snap.exact ? Text::Format("%+.1f%%", snap.smoothedSteer * 100.0f) : "--",
        28*s, Hud::White, left);
    Hud::Text(r.x + r.z - 18*s, r.y + 17*s, "SLIDE DIRECTION", 10*s, Hud::Label, right);
    Hud::Text(r.x + r.z - 18*s, r.y + 44*s, snap.exact ? ModeName(snap.mode) : "--",
        19*s, ModeColor(snap.mode), right);
    // Steering bar with the two direction gates.
    float bx = r.x + 21*s;
    float by = r.y + 67*s;
    float bw = r.z - 42*s;
    Hud::Box(bx, by, bw, 15*s, 7*s, Hud::Line);
    Hud::Box(bx + bw*0.45f, by - 3*s, 2*s, 21*s, 0, Hud::Magenta);
    Hud::Box(bx + bw*0.55f, by - 3*s, 2*s, 21*s, 0, Hud::Teal);
    if (snap.exact)
        Hud::Box(bx + bw*Math::Clamp((snap.smoothedSteer + 1)*0.5f, 0.0f, 1.0f) - 3*s,
            by - 5*s, 6*s, 25*s, 3*s, Hud::White);
    Hud::Text(bx, by + 29*s, "SETS LEFT", 10*s, Hud::Magenta, left);
    Hud::Text(bx + bw, by + 29*s, "SETS RIGHT", 10*s, Hud::Teal, right);

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
    Hud::Text(cx, r.y + 124*s, phase, 14*s, Hud::Bright, left);
    int modeAge = snap.ModeAgeMs();
    // The backwards-motion hold (gas released while moving backwards) pins
    // the force at 1.0 until gas returns, whatever the timer says.
    bool held = snap.exact && snap.forceGateState != 0;
    // Only a touching front wheel updates the force, so on the rear wheels
    // alone the stored value (often the pre-jump one) is stale.
    bool rearOnly = (snap.contactMask & 3) == 0 && (snap.contactMask & 12) != 0;
    Hud::Text(cr, r.y + 124*s, ForceText(snap, held, rearOnly, modeAge), 12*s, Hud::Gold, right);
    Hud::Text(cx, r.y + 150*s,
        "ICY TIRES " + Text::Format("%.0f%%", snap.meanIcing*100.0f), 11*s, Hud::Ice, left);
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
        unverified || readFailing ? Hud::Orange : Hud::Label, right);
    Hud::Box(cx, r.y + 168*s, cr - cx, 1*s, 0, Hud::Line);
    Hud::Text(cx, r.y + 186*s, ForceExplanation(snap, held, rearOnly, modeAge, readFailing),
        10*s, Hud::Dim, left);
}

void RenderGradePreview(const vec4 &in r, JumpPreview@ preview) {
    vec4 accent = GradeColor(preview.grade);
    float s = Math::Min(r.z / 500.0f, r.w / 125.0f);
    float cx = r.x + r.z*0.5f;
    float cy = r.y + r.w*0.5f;
    float w = 225*s;
    float h = 91*s;
    Hud::Box(cx - w*0.5f + 3*s, cy - h*0.5f + 4*s, w, h, 13*s, Hud::Shadow);
    Hud::Box(cx - w*0.5f, cy - h*0.5f, w, h, 13*s, Hud::Card);
    Hud::Box(cx - w*0.5f, cy - h*0.5f, w, 2*s, 1*s, Hud::WithAlpha(accent, 0.72f));
    int center = nvg::Align::Center | nvg::Align::Middle;
    Hud::Text(cx, cy - 31*s, "TAKEOFF PREVIEW", 10*s, Hud::Label, center);
    Hud::Text(cx, cy - 1*s, GradeName(preview.grade), 48.0f*s, accent, center);
    Hud::Text(cx, cy + 31*s, preview.leadMs + " ms BEFORE TAKEOFF", 10*s, Hud::Bright, center);
}

// Score leads the card; combo and best combo share the line below it. Each
// value pulses and shows its own badge when a landing changes it.
void RenderStats(const vec4 &in r, StatChange@ change, int statAge) {
    Hud::CardBase(r, Hud::Gold);
    float s = Math::Min(r.z / 320.0f, r.w / 150.0f);
    int left = nvg::Align::Left | nvg::Align::Middle;
    int right = nvg::Align::Right | nvg::Align::Middle;
    float pulse = StatPulse(statAge);
    float fade = StatBadgeFade(statAge);
    bool changed = change !is null && statAge >= 0;

    // The score counts up to its new value.
    bool earned = changed && change.earned > 0;
    float scorePulse = earned ? pulse : 0.0f;
    int shownScore = g_session.score;
    if (earned && statAge < 500)
        shownScore -= change.earned -
            int(float(change.earned)*EaseOutCubic(float(statAge) / 500.0f) + 0.5f);
    Hud::Text(r.x + 18*s, r.y + 22*s, "SCORE", 14*s, Hud::Label, left);
    if (earned && fade > 0.0f)
        Hud::Text(r.x + r.z - 18*s, r.y + 22*s, "+" + change.earned, 13*s,
            Hud::WithAlpha(Hud::Bright, fade), right);
    Hud::Text(r.x + r.z - 18*s, r.y + 62*s, "" + shownScore,
        40*s*(1.0f + 0.12f*scorePulse), Hud::Bright, right);

    Hud::Box(r.x + 18*s, r.y + 96*s, r.z - 36*s, Math::Max(1.0f, s), 0, Hud::Line);

    float rowY = r.y + 123*s;
    bool comboGained = changed && change.comboGained;
    bool comboBroken = changed && change.comboBroken;
    float comboPulse = comboGained || comboBroken ? pulse : 0.0f;
    vec4 comboColor = comboBroken && fade > 0.0f ? Hud::Pink : Hud::Gold;
    Hud::Text(r.x + 18*s, rowY, "COMBO", 13*s, Hud::Label, left);
    string combo = "x" + g_session.combo;
    float comboSize = 22*s*(1.0f + 0.16f*comboPulse);
    float comboX = r.x + 78*s;
    Hud::Text(comboX, rowY, combo, comboSize, comboColor, left);
    if ((comboGained || comboBroken) && fade > 0.0f) {
        nvg::FontSize(comboSize);
        float badgeX = comboX + nvg::TextBounds(combo).x + 8*s;
        Hud::Text(badgeX, rowY, comboBroken ? "BROKEN" : "+1", 12*s,
            Hud::WithAlpha(comboColor, fade), left);
    }

    bool newBest = changed && change.newBest;
    float bestPulse = newBest ? pulse : 0.0f;
    string best = "x" + g_session.bestCombo;
    float bestSize = 22*s*(1.0f + 0.16f*bestPulse);
    float bestX = r.x + r.z - 18*s;
    Hud::Text(bestX, rowY, best, bestSize, Hud::Ice, right);
    nvg::FontSize(bestSize);
    float labelX = bestX - nvg::TextBounds(best).x - 8*s;
    // NEW BEST fades back into the plain BEST label.
    float newBestFade = newBest ? fade : 0.0f;
    if (newBestFade < 1.0f)
        Hud::Text(labelX, rowY, "BEST", 13*s, Hud::WithAlpha(Hud::Label, 1.0f - newBestFade), right);
    if (newBestFade > 0.0f)
        Hud::Text(labelX, rowY, "NEW BEST", 13*s, Hud::WithAlpha(Hud::Ice, newBestFade), right);
}

RunRecord@ g_lastRatedRun = null;
string g_lastRatedMap = "";
int g_lastRatedRevision = -1;

// This map's most recent attempt with at least one rated jump, from the history.
RunRecord@ LastRatedRun() {
    if (g_history is null) return null;
    string mapUid = CurrentMapUid();
    if (mapUid.Length == 0) return g_lastRatedRun;
    if (mapUid == g_lastRatedMap && int(g_history.revision) == g_lastRatedRevision)
        return g_lastRatedRun;
    g_lastRatedMap = mapUid;
    g_lastRatedRevision = int(g_history.revision);
    @g_lastRatedRun = null;
    for (int i = int(g_history.runs.Length) - 1; i >= 0; i--) {
        RunRecord@ run = g_history.runs[uint(i)];
        if (run.mapUid == mapUid && run.hits + run.misses > 0) {
            @g_lastRatedRun = run;
            break;
        }
    }
    return g_lastRatedRun;
}

void RenderLast(const vec4 &in r, RunRecord@ last) {
    Hud::CardBase(r, Hud::Ice);
    float s = Math::Min(r.z / 410.0f, r.w / 105.0f);
    int left = nvg::Align::Left | nvg::Align::Middle;
    int right = nvg::Align::Right | nvg::Align::Middle;
    int center = nvg::Align::Center | nvg::Align::Middle;
    Hud::Text(r.x + 20*s, r.y + 25*s, "LAST RUN", 15*s, Hud::Label, left);
    if (last is null) {
        Hud::Text(r.x + r.z*0.5f, r.y + 70*s, "NO RATED RUN YET", 18*s, Hud::Bright, center);
        return;
    }
    Hud::Text(r.x + r.z - 20*s, r.y + 25*s,
        Time::FormatString("%Y-%m-%d %H:%M", last.startedAt / 1000), 12*s, Hud::Label, right);
    array<string> labels = {"SCORE", "HITS", "MISSES", "BEST"};
    array<string> values = {"" + last.score, "" + last.hits,
        "" + last.misses, "x" + last.bestCombo};
    array<vec4> colors = {Hud::Gold, Hud::Teal, Hud::Pink, Hud::Cyan};
    Hud::TileRow(r.x + 20*s, r.y + 42*s, r.z - 40*s, 52*s, 7*s, labels, values, colors, true);
}

bool ShouldRenderWidget(WidgetLayout@ layout) {
    return layout.Visible() &&
        (UI::IsGameUIVisible() || S_ShowWhenGameHudOff || g_layoutEditing);
}

void RenderShownResult(const vec4 &in r) {
    RenderResult(r, g_result.Age(), g_result.grade, g_result.caption, uint(g_result.shownAt));
}

void RenderWidgets() {
    if (g_hudFont >= 0) nvg::FontFace(g_hudFont);
    bool previewing = g_result !is null && g_result.preview && g_result.Age() < 1000;
    if (S_EnableWidgets) RenderWidgetCards(previewing);
    // A Popup-tab preview plays on top, even with widgets off or outside a run.
    if (previewing) RenderShownResult(g_gradeLayout.Pixels());
}

void RenderWidgetCards(bool previewing) {
    if (g_finish !is null && g_finish.visible &&
        g_finish.summary !is null && ShouldRenderWidget(g_finishLayout))
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
            RenderResult(r, 450, Grade::S, GradeCaption(Grade::S), 1);
    }
    if (ShouldRenderWidget(g_statsLayout)) {
        int statAge = g_statChange is null ? -1 : g_snapshot.raceTime - g_statChange.at;
        RenderStats(g_statsLayout.Pixels(), g_statChange, statAge);
    }
    if (ShouldRenderWidget(g_lastLayout))
        RenderLast(g_lastLayout.Pixels(), LastRatedRun());
}
