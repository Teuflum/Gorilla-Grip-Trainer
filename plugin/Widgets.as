int g_hudFont = -1;
string g_resultLabel = "";
string g_resultReason = "";
int g_resultShownAt = -1;

void InitWidgets() {
    g_hudFont = nvg::LoadFont("DroidSans-Bold.ttf");
}

void ShowResult(JumpVerdict@ verdict, int raceTime) {
    if (verdict is null) return;
    g_resultLabel = verdict.label;
    g_resultReason = verdict.reason;
    g_resultShownAt = raceTime;
}

void ClearResult() {
    g_resultLabel = "";
    g_resultReason = "";
    g_resultShownAt = -1;
}

vec4 HudColor(float r, float g, float b, float a = 1.0f) {
    return vec4(r, g, b, a);
}

vec4 GradeColor(const string &in label, float alpha = 1.0f) {
    if (label == "S") return HudColor(1.0f, 0.84f, 0.28f, alpha);
    if (label == "A") return HudColor(0.04f, 0.98f, 0.78f, alpha);
    if (label == "B") return HudColor(0.38f, 0.78f, 1.0f, alpha);
    if (label == "C") return HudColor(0.63f, 0.66f, 1.0f, alpha);
    if (label == "D") return HudColor(1.0f, 0.55f, 0.22f, alpha);
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

void RenderDiagnostics(const vec4 &in r, PhysicsSnapshot@ snap) {
    float s = Math::Min(r.z / 500.0f, r.w / 215.0f);
    int left = nvg::Align::Left | nvg::Align::Middle;
    int right = nvg::Align::Right | nvg::Align::Middle;
    int center = nvg::Align::Center | nvg::Align::Middle;
    HudCardBase(r, HudColor(0.03f, 0.91f, 0.87f));
    HudText(r.x + 19*s, r.y + 21*s, "GORILLA GRIP", 16*s,
        HudColor(0.91f, 0.98f, 1), left);
    HudText(r.x + r.z - 17*s, r.y + 21*s,
        snap !is null && snap.exact ? "EXACT PHYSICS" : "UNRATED",
        10*s, snap !is null && snap.exact ? HudColor(0.10f, 1, 0.75f) :
        HudColor(1, 0.64f, 0.35f), right);
    if (snap is null) {
        HudText(r.x + r.z*0.5f, r.y + r.w*0.5f, "NO CAR", 24*s,
            HudColor(0.7f, 0.8f, 0.9f), center);
        return;
    }
    HudText(r.x + 20*s, r.y + 66*s,
        Text::Format("%+.1f%%", snap.smoothedSteer * 100.0f), 37*s,
        HudColor(1, 1, 1), left);
    HudText(r.x + 205*s, r.y + 65*s, "INTERNAL STEER", 11*s,
        HudColor(0.56f, 0.68f, 0.78f), left);
    HudText(r.x + r.z - 18*s, r.y + 65*s, ModeName(snap.mode), 19*s,
        snap.mode == 2 ? HudColor(0.04f, 0.95f, 0.87f) :
        (snap.mode == 1 ? HudColor(1, 0.39f, 0.76f) :
        HudColor(0.6f, 0.7f, 0.8f)), right);
    float bx = r.x + 21*s;
    float by = r.y + 94*s;
    float bw = r.z - 42*s;
    HudBox(bx, by, bw, 15*s, 7*s, HudColor(0.09f, 0.15f, 0.23f));
    HudBox(bx + bw*0.45f, by-3*s, 2*s, 21*s, 0,
        HudColor(1, 0.39f, 0.76f));
    HudBox(bx + bw*0.55f, by-3*s, 2*s, 21*s, 0,
        HudColor(0.04f, 0.95f, 0.87f));
    HudBox(bx + bw*Math::Clamp((snap.smoothedSteer + 1)*0.5f, 0.0f, 1.0f)-3*s,
        by-5*s, 6*s, 25*s, 3*s, HudColor(1, 1, 1));
    HudText(bx, by + 29*s, "LEFT GATE", 10*s,
        HudColor(1, 0.39f, 0.76f), left);
    HudText(bx + bw, by + 29*s, "RIGHT GATE", 10*s,
        HudColor(0.04f, 0.95f, 0.87f), right);

    string phase = g_tracker.inFlight ? "AIR " +
        Math::Max(0, snap.raceTime - g_tracker.takeoffRace) + "ms" : "GROUND";
    HudText(r.x + 20*s, r.y + 157*s, phase, 14*s,
        HudColor(0.9f, 0.95f, 1), left);
    HudText(r.x + r.z*0.5f, r.y + 157*s,
        "ICE " + Text::Format("%.0f%%", snap.meanIcing*100.0f), 13*s,
        HudColor(0.47f, 0.82f, 1), center);
    string forceText;
    if (!snap.exact) forceText = "FORCE --";
    else if (!g_tracker.inFlight)
        forceText = "FORCE " + Text::Format("%.2fx", snap.force);
    else {
        int age = snap.gameTime - int(snap.modeAt);
        forceText = age < snap.recoveryDelayMs ? "WAITING" :
            (age < 2 * snap.recoveryDelayMs ? "RECOVERING" : "READY ON CONTACT");
    }
    HudText(r.x + r.z - 18*s, r.y + 157*s, forceText, 12*s,
        HudColor(1, 0.85f, 0.43f), right);
    HudBox(r.x + 18*s, r.y + 176*s, r.z - 36*s, 1*s, 0,
        HudColor(0.22f, 0.34f, 0.46f));
    string detail = snap.exact ? "STORED DIRECTION: " + ModeName(snap.mode) :
        "Exact physics unavailable on this build";
    if (snap.exact && g_tracker.inFlight) {
        detail = g_tracker.unratedReason.Length > 0 ? "TIMING UNVERIFIED" :
            "MODE AGE " + Math::Max(0, snap.gameTime - int(snap.modeAt)) + " ms";
    }
    HudText(r.x + r.z*0.5f, r.y + 195*s, detail, 11*s,
        g_tracker.inFlight && g_tracker.unratedReason.Length > 0 ?
        HudColor(1, 0.58f, 0.36f) : HudColor(0.55f, 0.67f, 0.77f), center);
}

void RenderTiming(const vec4 &in r, JumpPreview@ preview, bool sample) {
    if (preview is null && !sample) return;
    string label = preview is null ? "S" : preview.label;
    vec4 accent = GradeColor(label);
    HudCardBase(r, accent);
    float s = Math::Min(r.z / 390.0f, r.w / 75.0f);
    int left = nvg::Align::Left | nvg::Align::Middle;
    int right = nvg::Align::Right | nvg::Align::Middle;
    HudText(r.x + 16*s, r.y + r.w*0.50f, label, 38*s, accent, left);
    HudText(r.x + 71*s, r.y + r.w*0.36f, "TAKEOFF TIMING", 13*s,
        HudColor(0.88f, 0.97f, 1), left);
    string lead = preview is null ? "0-15 ms" :
        preview.leadMinMs + "-" + preview.leadMaxMs + " ms";
    HudText(r.x + r.z - 17*s, r.y + r.w*0.66f, lead, 13*s,
        HudColor(0.67f, 0.78f, 0.88f), right);
}

string ResultCaption(const string &in label) {
    if (label == "S") return "GORILLA GRIP";
    if (label == "A") return "CLEAN TIMING";
    if (label == "B") return "SOLID TIMING";
    if (label == "C") return "GOOD SETUP";
    if (label == "D") return "EARLY SETUP";
    return "GRIP MISSED";
}

void RenderResult(const vec4 &in r, int age, const string &in label) {
    if (label.Length == 0) return;
    float s = Math::Min(r.z / 500.0f, r.w / 125.0f);
    float fade = 1.0f - Math::Clamp(float(age - 700) / 300.0f, 0.0f, 1.0f);
    float p = Math::Clamp(float(age) / 190.0f, 0.0f, 1.0f);
    float remaining = 1.0f - p;
    float reveal = 1.0f - remaining * remaining * remaining;
    float impact = 1.0f - Math::Clamp(float(age) / 280.0f, 0.0f, 1.0f);
    vec4 accent = GradeColor(label, fade);
    float cx = r.x + r.z*0.5f;
    float cy = r.y + r.w*0.5f;
    float panelW = (170.0f + 290.0f*reveal)*s;
    HudBox(cx - panelW*0.5f, cy - 52*s + 5*s, panelW, 105*s,
        16*s, HudColor(0, 0, 0, 0.35f*fade));
    HudBox(cx - panelW*0.5f, cy - 52*s, panelW, 105*s,
        16*s, HudColor(0.025f, 0.035f, 0.09f, 0.93f*fade));
    HudBox(cx - panelW*0.5f, cy - 50*s, panelW, 3*s, 1*s,
        HudColor(accent.x, accent.y, accent.z, 0.75f*fade));
    HudBox(cx - panelW*0.5f, cy + 49*s, panelW, 2*s, 1*s,
        HudColor(accent.x, accent.y, accent.z, 0.28f*fade));
    HudBox(cx - 74*s, cy - 30*s, 148*s, 58*s, 24*s,
        HudColor(accent.x, accent.y, accent.z, 0.13f*impact*fade));
    for (int i = 0; i < 5; i++) {
        float distance = (54.0f + float(i)*27.0f + (1.0f-impact)*43.0f)*s;
        float sy = cy - 26*s + float(i%3)*20*s;
        float sw = (12.0f - float(i))*s;
        vec4 shard = HudColor(accent.x, accent.y, accent.z,
            impact*fade*(0.8f - float(i)*0.08f));
        HudBox(cx - distance - sw, sy, sw, 3*s, 1*s, shard);
        HudBox(cx + distance, sy, sw, 3*s, 1*s, shard);
    }
    int centered = nvg::Align::Center | nvg::Align::Middle;
    float gradeSize = (label == "MISSED" ? 43.0f : 54.0f) +
        28.0f*remaining*remaining;
    HudText(cx, cy - 8*s + 13*s*remaining, label, gradeSize*s,
        accent, centered);
    HudText(cx, cy + 28*s, ResultCaption(label), 13*s,
        HudColor(0.88f, 0.96f, 1, fade *
            Math::Clamp(float(age - 75) / 150.0f, 0.0f, 1.0f)), centered);
}

void RenderStat(const vec4 &in r, const string &in title,
    const string &in value, const vec4 &in accent) {
    HudCardBase(r, accent);
    float s = Math::Min(r.z / 320.0f, r.w / 85.0f);
    int left = nvg::Align::Left | nvg::Align::Middle;
    int right = nvg::Align::Right | nvg::Align::Middle;
    HudText(r.x + 18*s, r.y + 23*s, title, 14*s,
        HudColor(0.60f, 0.73f, 0.84f), left);
    HudText(r.x + r.z - 18*s, r.y + r.w - 29*s, value, 30*s,
        accent, right);
}

void RenderLast(const vec4 &in r, LastRunSummary@ last) {
    HudCardBase(r, HudColor(0.39f, 0.67f, 0.98f));
    float s = Math::Min(r.z / 410.0f, r.w / 105.0f);
    int left = nvg::Align::Left | nvg::Align::Middle;
    HudText(r.x + 20*s, r.y + 25*s, "LAST RUN", 15*s,
        HudColor(0.65f, 0.77f, 0.88f), left);
    if (last is null || !last.hasRun) {
        HudText(r.x + 20*s, r.y + 70*s, "NO RATED RUN YET", 18*s,
            HudColor(0.84f, 0.93f, 1), left);
        return;
    }
    HudText(r.x + 20*s, r.y + 69*s,
        last.score + " PTS   " + last.hits + " HITS   " +
        last.misses + " MISSES   BEST x" + last.bestCombo, 15*s,
        HudColor(0.87f, 0.95f, 1), left);
}

void RenderWidgets() {
    if (g_snapshot is null || g_snapshot.raceTime < 0) return;
    if (S_HideWithUI && !UI::IsGameUIVisible()) return;
    if (g_hudFont >= 0) nvg::FontFace(g_hudFont);
    WidgetLayout@ layout = GetLayout("diagnostics");
    if (layout !is null && layout.visible)
        RenderDiagnostics(layout.Pixels(), g_snapshot);
    @layout = GetLayout("timing");
    if (layout !is null && layout.visible) {
        JumpPreview@ p = g_tracker.inFlight && g_tracker.previewPublished ?
            g_tracker.preview : null;
        RenderTiming(layout.Pixels(), p, g_layoutEditing);
    }
    @layout = GetLayout("result");
    if (layout !is null && layout.visible) {
        int age = g_snapshot.raceTime - g_resultShownAt;
        bool active = g_resultShownAt >= 0 && age >= 0 && age < 1000;
        RenderResult(layout.Pixels(), active ? age : 240,
            active ? g_resultLabel : (g_layoutEditing ? "S" : ""));
    }
    @layout = GetLayout("combo");
    if (layout !is null && layout.visible)
        RenderStat(layout.Pixels(), "COMBO", "x" + g_session.combo,
            HudColor(1, 0.82f, 0.35f));
    @layout = GetLayout("score");
    if (layout !is null && layout.visible)
        RenderStat(layout.Pixels(), "SCORE", "" + g_session.score,
            HudColor(0.90f, 0.98f, 1));
    @layout = GetLayout("best");
    if (layout !is null && layout.visible)
        RenderStat(layout.Pixels(), "BEST COMBO", "x" + g_session.bestCombo,
            HudColor(0.46f, 0.79f, 1));
    @layout = GetLayout("last");
    if (layout !is null && layout.visible)
        RenderLast(layout.Pixels(), g_lastRun);
}
