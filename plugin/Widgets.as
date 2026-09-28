int g_hudFont = -1;
string g_resultLabel = "";
string g_resultReason = "";
int g_resultShownAt = -1;
int g_statChangedAt = -1;
int g_statScoreBefore = 0;
int g_statComboBefore = 0;
int g_statBestBefore = 0;
int g_statEarned = 0;

void InitWidgets() {
    g_hudFont = nvg::LoadFont("DroidSans-Bold.ttf");
}

void ShowResult(JumpVerdict@ verdict, int raceTime) {
    if (verdict is null) return;
    StopPopupPreview();
    g_resultLabel = verdict.label;
    g_resultReason = verdict.reason;
    g_resultShownAt = raceTime;
}

void ClearResult() {
    g_resultLabel = "";
    g_resultReason = "";
    g_resultShownAt = -1;
}

void ShowStatChange(JumpVerdict@ verdict, int raceTime,
    int scoreBefore, int comboBefore, int bestBefore) {
    if (verdict is null || !verdict.exact) return;
    g_statChangedAt = raceTime;
    g_statScoreBefore = scoreBefore;
    g_statComboBefore = comboBefore;
    g_statBestBefore = bestBefore;
    g_statEarned = verdict.points;
}

void ClearStatChange() {
    g_statChangedAt = -1;
    g_statEarned = 0;
}

float StatPulse(int age) {
    if (age < 0 || age >= 500) return 0.0f;
    return Math::Sin(Math::PI * float(age) / 500.0f);
}

float StatBadgeFade(int age) {
    if (age < 0 || age >= 900) return 0.0f;
    return 1.0f - Math::Clamp(float(age - 550) / 350.0f, 0.0f, 1.0f);
}

vec4 HudColor(float r, float g, float b, float a = 1.0f) {
    return vec4(r, g, b, a);
}

vec4 GradeColor(const string &in label, float alpha = 1.0f) {
    if (label == "S+") return HudColor(1.0f, 0.94f, 0.55f, alpha);
    if (label == "S") return HudColor(1.0f, 0.84f, 0.28f, alpha);
    if (label == "A") return HudColor(0.04f, 0.98f, 0.78f, alpha);
    if (label == "B") return HudColor(0.38f, 0.78f, 1.0f, alpha);
    if (label == "C") return HudColor(0.63f, 0.66f, 1.0f, alpha);
    if (label == "D") return HudColor(1.0f, 0.55f, 0.22f, alpha);
    if (label == "UNRATED" || label.Contains("/"))
        return HudColor(0.67f, 0.78f, 0.90f, alpha);
    return HudColor(1.0f, 0.34f, 0.53f, alpha);
}

void HudBox(float x, float y, float w, float h, float radius,
    const vec4 &in color) {
    nvg::BeginPath();
    nvg::RoundedRect(x, y, w, h, radius);
    nvg::FillColor(color);
    nvg::Fill();
}

void HudText(float x, float y, const string &in value, float size,
    const vec4 &in color, int align) {
    nvg::FontSize(size);
    nvg::TextAlign(align);
    nvg::FillColor(color);
    nvg::Text(x, y, value);
}

void HudCardBase(const vec4 &in r, const vec4 &in accent) {
    HudBox(r.x + 3, r.y + 4, r.z, r.w, 13, HudColor(0, 0, 0, 0.28f));
    HudBox(r.x, r.y, r.z, r.w, 13, HudColor(0.025f, 0.039f, 0.09f, 0.90f));
    HudBox(r.x, r.y, 4, r.w, 2, accent);
}

string ModeName(int mode) {
    if (mode == 1) return "LEFT";
    if (mode == 2) return "RIGHT";
    return "NEUTRAL";
}

// One wheel of the contact grid: the border shows ground contact (gold for a
// front wheel, which alone raises tire force; blue for a rear wheel; dim in the
// air) and the fill shows that tire's icing.
void RenderWheelTile(float x, float y, float w, float h, float s,
    const string &in name, bool front, bool contact, float icing, bool exact) {
    vec4 border = !contact ? HudColor(0.18f, 0.25f, 0.34f) :
        (front ? HudColor(1.0f, 0.85f, 0.36f) : HudColor(0.47f, 0.82f, 1.0f));
    float edge = contact ? 2*s : 1*s;
    HudBox(x, y, w, h, 7*s, border);
    HudBox(x + edge, y + edge, w - 2*edge, h - 2*edge, 6*s,
        contact ? HudColor(0.06f, 0.11f, 0.19f) : HudColor(0.04f, 0.07f, 0.13f));
    if (exact && icing > 0.0f)
        HudBox(x + edge, y + edge, (w - 2*edge) * Math::Clamp(icing, 0.0f, 1.0f),
            h - 2*edge, 6*s, HudColor(0.47f, 0.82f, 1.0f, contact ? 0.22f : 0.10f));
    HudText(x + 8*s, y + 11*s, name, 10*s,
        contact ? border : HudColor(0.42f, 0.51f, 0.60f),
        nvg::Align::Left | nvg::Align::Middle);
    HudText(x + w - 8*s, y + h - 12*s,
        exact ? Text::Format("%.0f%%", icing * 100.0f) : "--", 16*s,
        contact ? HudColor(0.91f, 0.96f, 1) : HudColor(0.54f, 0.62f, 0.70f),
        nvg::Align::Right | nvg::Align::Middle);
}

void RenderDiagnostics(const vec4 &in r, PhysicsSnapshot@ snap) {
    float s = Math::Min(r.z / 500.0f, r.w / 215.0f);
    int left = nvg::Align::Left | nvg::Align::Middle;
    int right = nvg::Align::Right | nvg::Align::Middle;
    int center = nvg::Align::Center | nvg::Align::Middle;
    HudCardBase(r, HudColor(0.03f, 0.91f, 0.87f));
    if (snap is null) {
        HudText(r.x + r.z*0.5f, r.y + r.w*0.5f, "NO CAR", 24*s,
            HudColor(0.7f, 0.8f, 0.9f), center);
        return;
    }
    HudText(r.x + 20*s, r.y + 17*s, "SMOOTHED STEER", 10*s,
        HudColor(0.56f, 0.68f, 0.78f), left);
    HudText(r.x + 20*s, r.y + 42*s,
        snap.exact ? Text::Format("%+.1f%%", snap.smoothedSteer * 100.0f) : "--",
        28*s, HudColor(1, 1, 1), left);
    HudText(r.x + r.z - 18*s, r.y + 17*s, "STORED SLIDE MODE", 10*s,
        HudColor(0.56f, 0.68f, 0.78f), right);
    HudText(r.x + r.z - 18*s, r.y + 44*s,
        snap.exact ? ModeName(snap.mode) : "--", 19*s,
        snap.mode == 2 ? HudColor(0.04f, 0.95f, 0.87f) :
        (snap.mode == 1 ? HudColor(1, 0.39f, 0.76f) :
        HudColor(0.6f, 0.7f, 0.8f)), right);
    float bx = r.x + 21*s;
    float by = r.y + 67*s;
    float bw = r.z - 42*s;
    HudBox(bx, by, bw, 15*s, 7*s, HudColor(0.09f, 0.15f, 0.23f));
    HudBox(bx + bw*0.45f, by-3*s, 2*s, 21*s, 0,
        HudColor(1, 0.39f, 0.76f));
    HudBox(bx + bw*0.55f, by-3*s, 2*s, 21*s, 0,
        HudColor(0.04f, 0.95f, 0.87f));
    if (snap.exact)
        HudBox(bx + bw*Math::Clamp((snap.smoothedSteer + 1)*0.5f, 0.0f, 1.0f)-3*s,
            by-5*s, 6*s, 25*s, 3*s, HudColor(1, 1, 1));
    HudText(bx, by + 29*s, "LEFT GATE", 10*s,
        HudColor(1, 0.39f, 0.76f), left);
    HudText(bx + bw, by + 29*s, "RIGHT GATE", 10*s,
        HudColor(0.04f, 0.95f, 0.87f), right);

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
    string phase = g_tracker.inFlight ? "AIR " +
        Math::Max(0, snap.raceTime - g_tracker.takeoffRace) + " ms" : "GROUND";
    HudText(cx, r.y + 124*s, phase, 14*s, HudColor(0.9f, 0.95f, 1), left);
    int modeAge = snap.ModeAgeMs();
    string forceText;
    if (!snap.exact) forceText = "FORCE --";
    else if (!g_tracker.inFlight)
        forceText = "FORCE " + Text::Format("%.2fx", snap.force);
    else if (modeAge < 0) forceText = "NO MODE TIMER";
    else if (modeAge < snap.recoveryDelayMs) forceText = "FORCE DELAY";
    else if (modeAge < 2 * snap.recoveryDelayMs)
        forceText = "RECOVERY WINDOW";
    else forceText = "WINDOW ELAPSED";
    HudText(cr, r.y + 124*s, forceText, 12*s, HudColor(1, 0.85f, 0.43f), right);
    HudText(cx, r.y + 150*s,
        "ICE AVG " + Text::Format("%.0f%%", snap.meanIcing*100.0f), 11*s,
        HudColor(0.47f, 0.82f, 1), left);
    string detail = !snap.exact ? "PHYSICS SAMPLE UNAVAILABLE" :
        modeAge < 0 ? "NO STORED SLIDE MODE" :
        "MODE AGE " + (modeAge < 10000 ? modeAge + " ms" :
            Text::Format("%.1f s", float(modeAge) / 1000.0f));
    bool unverified = snap.exact && g_tracker.inFlight &&
        g_tracker.unratedReason.Length > 0;
    if (unverified) detail = "TIMING UNVERIFIED";
    // Reads have never worked since the plugin loaded: a game update likely
    // moved a fixed offset.
    bool readFailing = !snap.exact && g_readMonitor.ReadFailing();
    if (readFailing) detail = "PHYSICS READ FAILED";
    HudText(cr, r.y + 150*s, detail, 11*s,
        unverified || readFailing ? HudColor(1, 0.58f, 0.36f) :
        HudColor(0.55f, 0.67f, 0.77f), right);
    HudBox(cx, r.y + 168*s, cr - cx, 1*s, 0, HudColor(0.22f, 0.34f, 0.46f));
    string explanation = readFailing ? "JUMPS NOT RATED | PLUGIN NEEDS UPDATE" :
        !snap.exact ? "" : modeAge < 0 ?
        "MODE STARTS ON ELIGIBLE WHEEL CONTACT" : g_tracker.inFlight ?
        snap.recoveryDelayMs + " ms delay | " +
            (2 * snap.recoveryDelayMs) + " ms max | check on landing" :
        "FRONT WHEELS RAISE TIRE FORCE";
    HudText(cx, r.y + 186*s, explanation, 10*s,
        HudColor(0.45f, 0.59f, 0.70f), left);
}

void RenderGradePreview(const vec4 &in r, JumpPreview@ preview, bool sample) {
    if (preview is null && !sample) return;
    string label = preview is null ? "S" : preview.label;
    vec4 accent = GradeColor(label);
    float s = Math::Min(r.z / 500.0f, r.w / 125.0f);
    float cx = r.x + r.z*0.5f;
    float cy = r.y + r.w*0.5f;
    float w = 225*s;
    float h = 91*s;
    HudBox(cx - w*0.5f + 3*s, cy - h*0.5f + 4*s, w, h, 13*s,
        HudColor(0, 0, 0, 0.25f));
    HudBox(cx - w*0.5f, cy - h*0.5f, w, h, 13*s,
        HudColor(0.025f, 0.039f, 0.09f, 0.87f));
    HudBox(cx - w*0.5f, cy - h*0.5f, w, 2*s, 1*s,
        HudColor(accent.x, accent.y, accent.z, 0.72f));
    int center = nvg::Align::Center | nvg::Align::Middle;
    HudText(cx, cy - 31*s, "TAKEOFF PREVIEW", 10*s,
        HudColor(0.68f, 0.78f, 0.88f), center);
    HudText(cx, cy - 1*s, label, 48.0f*s, accent, center);
    string lead = preview is null ? "12 ms" : preview.leadMs + " ms";
    HudText(cx, cy + 31*s, lead + " BEFORE TAKEOFF", 10*s,
        HudColor(0.77f, 0.86f, 0.94f), center);
}

string ResultCaption(const string &in label) {
    if (label == "S+") return "PERFECT GORILLA GRIP";
    if (label == "S") return "GORILLA GRIP";
    if (label == "A") return "CLEAN TIMING";
    if (label == "B") return "SOLID TIMING";
    if (label == "C") return "GOOD SETUP";
    if (label == "D") return "EARLY SETUP";
    if (label == "UNRATED") {
        if (g_resultReason.Contains("physics read"))
            return "PHYSICS READ LOST";
        if (g_resultReason.Contains("contact timing"))
            return "CONTACT TIMING LOST";
        if (g_resultReason.Contains("force contact"))
            return "FORCE CHECK UNAVAILABLE";
        return "TIMING UNVERIFIED";
    }
    return "GRIP MISSED";
}

// Score leads the card; combo and best combo share the line below it. Each
// value pulses and shows its own badge when a landing changes it.
void RenderStats(const vec4 &in r, int statAge) {
    vec4 gold = HudColor(1, 0.82f, 0.35f);
    vec4 white = HudColor(0.90f, 0.98f, 1);
    vec4 blue = HudColor(0.46f, 0.79f, 1);
    vec4 pink = HudColor(1.0f, 0.43f, 0.57f);
    vec4 label = HudColor(0.60f, 0.73f, 0.84f);
    HudCardBase(r, gold);
    float s = Math::Min(r.z / 320.0f, r.w / 150.0f);
    int left = nvg::Align::Left | nvg::Align::Middle;
    int right = nvg::Align::Right | nvg::Align::Middle;
    float pulse = StatPulse(statAge);
    float fade = StatBadgeFade(statAge);
    bool changed = statAge >= 0;

    bool earned = changed && g_statEarned > 0;
    float scorePulse = earned ? pulse : 0.0f;
    int shownScore = g_session.score;
    if (earned && statAge < 500) {
        float remaining = 1.0f - float(statAge) / 500.0f;
        float eased = 1.0f - remaining*remaining*remaining;
        shownScore = g_statScoreBefore + int(float(g_statEarned)*eased + 0.5f);
    }
    HudText(r.x + 18*s, r.y + 22*s, "SCORE", 14*s, label, left);
    if (earned && fade > 0.0f)
        HudText(r.x + r.z - 18*s, r.y + 22*s, "+" + g_statEarned, 13*s,
            HudColor(white.x, white.y, white.z, fade), right);
    HudText(r.x + r.z - 18*s, r.y + 62*s, "" + shownScore,
        40*s*(1.0f + 0.12f*scorePulse), white, right);

    HudBox(r.x + 18*s, r.y + 96*s, r.z - 36*s, Math::Max(1.0f, s),
        0, HudColor(0.11f, 0.16f, 0.24f));

    float rowY = r.y + 123*s;
    bool comboGained = changed && g_session.combo > g_statComboBefore;
    bool comboBroken = changed && g_statComboBefore > 0 && g_session.combo == 0;
    float comboPulse = comboGained || comboBroken ? pulse : 0.0f;
    vec4 comboColor = comboBroken && fade > 0.0f ? pink : gold;
    HudText(r.x + 18*s, rowY, "COMBO", 13*s, label, left);
    string combo = "x" + g_session.combo;
    float comboSize = 22*s*(1.0f + 0.16f*comboPulse);
    float comboX = r.x + 78*s;
    HudText(comboX, rowY, combo, comboSize, comboColor, left);
    if ((comboGained || comboBroken) && fade > 0.0f) {
        nvg::FontSize(comboSize);
        float badgeX = comboX + nvg::TextBounds(combo).x + 8*s;
        HudText(badgeX, rowY, comboBroken ? "BROKEN" : "+1", 12*s,
            HudColor(comboColor.x, comboColor.y, comboColor.z, fade), left);
    }

    bool newBest = changed && g_session.bestCombo > g_statBestBefore;
    float bestPulse = newBest ? pulse : 0.0f;
    string best = "x" + g_session.bestCombo;
    float bestSize = 22*s*(1.0f + 0.16f*bestPulse);
    float bestX = r.x + r.z - 18*s;
    HudText(bestX, rowY, best, bestSize, blue, right);
    nvg::FontSize(bestSize);
    float labelX = bestX - nvg::TextBounds(best).x - 8*s;
    // NEW BEST fades back into the plain BEST label.
    float newBestFade = newBest ? fade : 0.0f;
    if (newBestFade < 1.0f)
        HudText(labelX, rowY, "BEST", 13*s,
            HudColor(label.x, label.y, label.z, 1.0f - newBestFade), right);
    if (newBestFade > 0.0f)
        HudText(labelX, rowY, "NEW BEST", 13*s,
            HudColor(blue.x, blue.y, blue.z, newBestFade), right);
}

RunRecord@ g_lastRatedRun = null;
string g_lastRatedKey = "";

// This map's most recent attempt with at least one rated jump, from the history.
RunRecord@ LastRatedRun() {
    if (g_history is null) return null;
    string mapUid = CurrentMapUid();
    if (mapUid.Length == 0) return g_lastRatedRun;
    uint count = g_history.runs.Length;
    string key = mapUid + "|" + count + "|" +
        (count == 0 ? "" : g_history.runs[g_history.runs.Length - 1].id);
    if (key == g_lastRatedKey) return g_lastRatedRun;
    g_lastRatedKey = key;
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
    HudCardBase(r, HudColor(0.39f, 0.67f, 0.98f));
    float s = Math::Min(r.z / 410.0f, r.w / 105.0f);
    int left = nvg::Align::Left | nvg::Align::Middle;
    int right = nvg::Align::Right | nvg::Align::Middle;
    int center = nvg::Align::Center | nvg::Align::Middle;
    HudText(r.x + 20*s, r.y + 25*s, "LAST RUN", 15*s,
        HudColor(0.65f, 0.77f, 0.88f), left);
    if (last !is null)
        HudText(r.x + r.z - 20*s, r.y + 25*s,
            Time::FormatString("%Y-%m-%d %H:%M", last.startedAt / 1000), 12*s,
            HudColor(0.62f, 0.76f, 0.88f), right);
    if (last is null) {
        HudText(r.x + r.z*0.5f, r.y + 70*s, "NO RATED RUN YET", 18*s,
            HudColor(0.84f, 0.93f, 1), center);
        return;
    }
    array<string> labels = {"SCORE", "HITS", "MISSES", "BEST"};
    array<string> values = {"" + last.score, "" + last.hits,
        "" + last.misses, "x" + last.bestCombo};
    float gap = 7*s;
    float width = (r.z - 40*s - 3*gap) / 4.0f;
    for (uint i = 0; i < labels.Length; i++) {
        float x = r.x + 20*s + float(i)*(width + gap);
        vec4 color = i == 0 ? HudColor(1.0f, 0.85f, 0.36f) :
            (i == 1 ? HudColor(0.13f, 0.93f, 0.78f) :
            (i == 2 ? HudColor(1.0f, 0.48f, 0.58f) :
            HudColor(0.60f, 0.89f, 1.0f)));
        HudBox(x, r.y + 42*s, width, 52*s, 8*s,
            HudColor(0.035f, 0.065f, 0.13f, 0.88f));
        HudBox(x + 8*s, r.y + 43*s, width - 16*s, 2*s, 1*s,
            HudColor(color.x, color.y, color.z, 0.75f));
        HudText(x + width*0.5f, r.y + 60*s, labels[i], 10*s,
            HudColor(0.62f, 0.76f, 0.88f), center);
        HudText(x + width*0.5f, r.y + 79*s, values[i], 20*s,
            color, center);
    }
}

bool ShouldRenderWidget(WidgetLayout@ layout) {
    return layout !is null && layout.visible &&
        (UI::IsGameUIVisible() || S_ShowWhenGameHudOff || g_layoutEditing);
}

void RenderWidgets() {
    if (g_hudFont >= 0) nvg::FontFace(g_hudFont);
    int previewAge = PopupPreviewAge();
    if (S_EnableWidgets) RenderWidgetCards(previewAge);
    // A Popup-tab preview plays on top, even with widgets off or outside a run.
    if (previewAge >= 0) {
        WidgetLayout@ grade = GetLayout("grade");
        if (grade !is null)
            RenderResult(grade.Pixels(), previewAge, g_popupPreviewLabel,
                PopupPreviewSeed(g_popupPreviewLabel));
    }
}

void RenderWidgetCards(int previewAge) {
    WidgetLayout@ layout = GetLayout("finish");
    if (g_finish !is null && g_finish.visible &&
        g_finish.summary !is null && ShouldRenderWidget(layout))
        RenderFinishSummary(layout.Pixels(), g_finish.summary);
    if (g_snapshot is null) return;
    @layout = GetLayout("diagnostics");
    if (ShouldRenderWidget(layout))
        RenderDiagnostics(layout.Pixels(), g_snapshot);
    @layout = GetLayout("grade");
    if (previewAge < 0 && ShouldRenderWidget(layout)) {
        JumpPreview@ p = (g_tracker.inFlight || g_tracker.pendingLanding) &&
            g_tracker.previewPublished ? g_tracker.preview : null;
        int age = g_snapshot.raceTime - g_resultShownAt;
        bool active = g_resultShownAt >= 0 && age >= 0 && age < 1000;
        if (p !is null && !g_layoutEditing)
            RenderGradePreview(layout.Pixels(), p, false);
        else if (active || g_layoutEditing)
            RenderResult(layout.Pixels(), active ? age : 450,
                active ? g_resultLabel : "S",
                active ? uint(g_resultShownAt) + 1 : 1);
    }
    @layout = GetLayout("stats");
    if (ShouldRenderWidget(layout)) {
        int statAge = g_statChangedAt < 0 ? -1 :
            g_snapshot.raceTime - g_statChangedAt;
        RenderStats(layout.Pixels(), statAge);
    }
    @layout = GetLayout("last");
    if (ShouldRenderWidget(layout))
        RenderLast(layout.Pixels(), LastRatedRun());
}
