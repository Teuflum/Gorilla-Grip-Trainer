int g_hudFont = -1;
nvg::Texture@ g_gorillaTexture;
string g_resultLabel = "";
string g_resultReason = "";
bool g_resultTimingEstimated = false;
int g_resultShownAt = -1;

void InitWidgets() {
    g_hudFont = nvg::LoadFont("DroidSans-Bold.ttf");
    @g_gorillaTexture = nvg::LoadTexture("assets/gorilla-emoji.png");
    if (g_gorillaTexture is null)
        print("Gorilla Grip Trainer: gorilla emoji texture could not load");
}

void ShowResult(JumpVerdict@ verdict, int raceTime) {
    if (verdict is null) return;
    g_resultLabel = verdict.label;
    g_resultReason = verdict.reason;
    g_resultTimingEstimated = verdict.timingEstimated;
    g_resultShownAt = raceTime;
}

void ClearResult() {
    g_resultLabel = "";
    g_resultReason = "";
    g_resultTimingEstimated = false;
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

void RenderGradePreview(const vec4 &in r, JumpPreview@ preview, bool sample) {
    if (preview is null && !sample) return;
    string label = preview is null ? "S" : preview.label;
    string shownLabel = preview !is null && preview.ambiguous ? label + "+" : label;
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
    HudText(cx, cy - 1*s, shownLabel, 48.0f*s, accent, center);
    string lead = preview is null ? "0-15 ms" :
        preview.leadMinMs + "-" + preview.leadMaxMs + " ms";
    HudText(cx, cy + 31*s, lead + " BEFORE TAKEOFF", 10*s,
        HudColor(0.77f, 0.86f, 0.94f), center);
}

string ResultCaption(const string &in label) {
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

void GorillaDot(float x, float y, float radius, const vec4 &in color) {
    nvg::BeginPath();
    nvg::Circle(vec2(x, y), radius);
    nvg::FillColor(color);
    nvg::Fill();
}

void DrawGorillaEmoji(float x, float y, float size, float alpha) {
    if (g_gorillaTexture is null) return;
    float left = x - size*0.5f;
    float top = y - size*0.5f;
    nvg::BeginPath();
    nvg::Rect(left, top, size, size);
    nvg::FillPaint(nvg::TexturePattern(vec2(left, top),
        vec2(size, size), 0.0f, g_gorillaTexture, alpha));
    nvg::Fill();
}

void DrawFallbackFlame(float x, float baseY, float height, float alpha) {
    nvg::BeginPath();
    nvg::MoveTo(vec2(x-height*0.24f, baseY));
    nvg::BezierTo(vec2(x-height*0.30f, baseY-height*0.35f),
        vec2(x-height*0.10f, baseY-height*0.72f),
        vec2(x, baseY-height));
    nvg::BezierTo(vec2(x+height*0.12f, baseY-height*0.64f),
        vec2(x+height*0.30f, baseY-height*0.32f),
        vec2(x+height*0.24f, baseY));
    nvg::ClosePath();
    nvg::FillColor(HudColor(1.0f, 0.70f, 0.16f, alpha));
    nvg::Fill();
}

void RenderSGorillas(float cx, float cy, float s, int age, float fade) {
    float appear = Math::Clamp(float(age) / 160.0f, 0.0f, 1.0f);
    if (g_gorillaTexture is null) {
        for (int i = 0; i < 5; i++)
            DrawFallbackFlame(cx + (float(i)-2.0f)*29.0f*s,
                cy + 25.0f*s, 43.0f*s, fade*appear);
        return;
    }
    float phase = float(age)*0.020f;
    for (int i = 0; i < 2; i++) {
        float side = i == 0 ? -1.0f : 1.0f;
        float x = cx + side*(150.0f + 18.0f*(1.0f-appear))*s;
        float y = cy - Math::Abs(Math::Sin(phase + float(i)*1.8f))*9.0f*s;
        float size = 72.0f*s*appear;
        GorillaDot(x, y, size*0.46f,
            HudColor(1.0f, 0.77f, 0.22f, 0.15f*fade*appear));
        if (size > 1.0f) DrawGorillaEmoji(x, y, size, fade*appear);
    }
}

void RenderResult(const vec4 &in r, int age, const string &in label,
    bool estimated) {
    if (label.Length == 0) return;
    bool showPlus = estimated && GradeBasePoints(label) > 0;
    string shownLabel = showPlus ? label + "+" : label;
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
    if (label == "S") RenderSGorillas(cx, cy, s, age, fade);
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
    HudText(cx, cy - 8*s + 13*s*remaining, shownLabel, gradeSize*s,
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

bool ShouldRenderWidget(WidgetLayout@ layout) {
    return layout !is null && layout.visible &&
        (UI::IsGameUIVisible() || S_ShowWhenGameHudOff || g_layoutEditing);
}

void RenderWidgets() {
    if (!S_EnableWidgets) return;
    if (g_hudFont >= 0) nvg::FontFace(g_hudFont);
    WidgetLayout@ layout = GetLayout("finish");
    if (g_finish !is null && g_finish.visible &&
        g_finish.summary !is null && ShouldRenderWidget(layout))
        RenderFinishSummary(layout.Pixels(), g_finish.summary);
    if (g_snapshot is null || g_snapshot.raceTime < 0) return;
    @layout = GetLayout("diagnostics");
    if (ShouldRenderWidget(layout))
        RenderDiagnostics(layout.Pixels(), g_snapshot);
    @layout = GetLayout("grade");
    if (ShouldRenderWidget(layout)) {
        JumpPreview@ p = (g_tracker.inFlight || g_tracker.pendingLanding) &&
            g_tracker.previewPublished ? g_tracker.preview : null;
        int age = g_snapshot.raceTime - g_resultShownAt;
        bool active = g_resultShownAt >= 0 && age >= 0 && age < 1000;
        if (p !is null && !g_layoutEditing)
            RenderGradePreview(layout.Pixels(), p, false);
        else if (active || g_layoutEditing)
            RenderResult(layout.Pixels(), active ? age : 240,
                active ? g_resultLabel : "S",
                active && g_resultTimingEstimated);
    }
    @layout = GetLayout("combo");
    if (ShouldRenderWidget(layout))
        RenderStat(layout.Pixels(), "COMBO", "x" + g_session.combo,
            HudColor(1, 0.82f, 0.35f));
    @layout = GetLayout("score");
    if (ShouldRenderWidget(layout))
        RenderStat(layout.Pixels(), "SCORE", "" + g_session.score,
            HudColor(0.90f, 0.98f, 1));
    @layout = GetLayout("best");
    if (ShouldRenderWidget(layout))
        RenderStat(layout.Pixels(), "BEST COMBO", "x" + g_session.bestCombo,
            HudColor(0.46f, 0.79f, 1));
    @layout = GetLayout("last");
    if (ShouldRenderWidget(layout))
        RenderLast(layout.Pixels(), g_lastRun);
}
