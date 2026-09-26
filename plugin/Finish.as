class FinishController {
    RunRecord@ summary;
    string lastFinishedId = "";
    bool visible = false;

    bool Update(int raceTime, bool finishSequence, RunRecord@ active) {
        if (!finishSequence || active is null || active.id == lastFinishedId)
            return false;
        active.status = "FINISHED";
        active.finishMs = raceTime;
        lastFinishedId = active.id;
        @summary = active;
        visible = S_AutoFinishSummary;
        return true;
    }

    void NewAttempt() {
        @summary = null;
        visible = false;
    }
}

bool IsFinishSequence() {
    auto app = cast<CTrackMania>(GetApp());
    if (app is null || app.CurrentPlayground is null ||
        app.CurrentPlayground.GameTerminals.Length == 0) return false;
    auto terminal = app.CurrentPlayground.GameTerminals[0];
    return terminal !is null &&
        terminal.UISequence_Current == CGamePlaygroundUIConfig::EUISequence::Finish;
}

string g_fitMapSource = "";
string g_fitMapShown = "";
float g_fitMapFontSize = -1.0f;
float g_fitMapMaxWidth = -1.0f;

string FitFinishMapName(const string &in fullName, float fontSize,
    float maxWidth) {
    if (g_fitMapSource == fullName &&
        Math::Abs(g_fitMapFontSize - fontSize) < 0.01f &&
        Math::Abs(g_fitMapMaxWidth - maxWidth) < 0.01f)
        return g_fitMapShown;
    nvg::FontSize(fontSize);
    string shortened = fullName;
    if (nvg::TextBounds(fullName).x > maxWidth) {
        while (shortened.Length > 0) {
            uint cut = shortened.Length;
            do { cut--; }
            while (cut > 0 && (shortened[cut] & 0xC0) == 0x80);
            shortened = shortened.SubStr(0, cut);
            if (nvg::TextBounds(shortened + "…").x <= maxWidth) {
                shortened += "…";
                break;
            }
        }
        if (shortened.Length == 0) shortened = "…";
    }
    g_fitMapSource = fullName;
    g_fitMapShown = shortened;
    g_fitMapFontSize = fontSize;
    g_fitMapMaxWidth = maxWidth;
    return shortened;
}

void RenderFinishSummary(const vec4 &in r, RunRecord@ run) {
    if (run is null) return;
    float s = Math::Min(r.z / 650.0f, r.w / 365.0f);
    float cx = r.x + r.z*0.5f;
    float left = r.x + 25*s;
    float inner = r.z - 50*s;
    int center = nvg::Align::Center | nvg::Align::Middle;
    int alignLeft = nvg::Align::Left | nvg::Align::Middle;
    int alignRight = nvg::Align::Right | nvg::Align::Middle;
    HudCardBase(r, HudColor(1.0f, 0.80f, 0.28f));
    HudText(cx, r.y + 36*s, "RUN COMPLETE", 27*s,
        HudColor(1.0f, 0.86f, 0.37f), center);
    float nameSize = 17*s;
    float nameWidth = inner - 20*s;
    nvg::FontSize(nameSize);
    float measuredWidth = nvg::TextBounds(run.mapName).x;
    if (measuredWidth > nameWidth)
        nameSize = Math::Max(12*s, nameSize * nameWidth / measuredWidth);
    string shownName = FitFinishMapName(run.mapName, nameSize, nameWidth);
    HudText(cx, r.y + 69*s, shownName, nameSize,
        HudColor(0.81f, 0.91f, 1.0f), center);
    array<string> statLabels = {"FINISH", "SCORE", "BEST COMBO"};
    array<string> statValues = {Time::Format(uint64(run.finishMs)),
        "" + run.score, "x" + run.bestCombo};
    float gap = 9*s;
    float statWidth = (inner - 2*gap) / 3.0f;
    for (uint i = 0; i < statLabels.Length; i++) {
        float x = left + float(i)*(statWidth + gap);
        HudBox(x, r.y + 91*s, statWidth, 68*s, 10*s,
            HudColor(0.035f, 0.065f, 0.13f, 0.88f));
        HudText(x + statWidth*0.5f, r.y + 111*s, statLabels[i], 11*s,
            HudColor(0.60f, 0.73f, 0.84f), center);
        vec4 valueColor = i == 1 ? HudColor(1.0f, 0.85f, 0.36f) :
            (i == 2 ? HudColor(0.60f, 0.89f, 1.0f) : HudColor(1, 1, 1));
        HudText(x + statWidth*0.5f, r.y + 138*s, statValues[i], 24*s,
            valueColor, center);
    }
    array<int> counts(8);
    array<int> leads;
    int bestLo = -1;
    int bestHi = -1;
    for (uint i = 0; i < run.jumps.Length; i++) {
        HistoryJump@ jump = run.jumps[i];
        int index = jump.label == "S+" ? 0 : jump.label == "S" ? 1 :
            jump.label == "A" ? 2 : jump.label == "B" ? 3 :
            jump.label == "C" ? 4 : jump.label == "D" ? 5 :
            jump.label == "MISSED" ? 6 : 7;
        counts[index]++;
        if (index < 6 && jump.leadMinMs >= 0) {
            int lead = (jump.leadMinMs + jump.leadMaxMs) / 2;
            leads.InsertLast(lead);
            if (bestLo < 0 || lead < (bestLo + bestHi) / 2) {
                bestLo = jump.leadMinMs;
                bestHi = jump.leadMaxMs;
            }
        }
    }
    array<string> grades = {"S+", "S", "A", "B", "C", "D"};
    float gradeGap = 7*s;
    float gradeWidth = (inner - 5*gradeGap) / 6.0f;
    for (uint i = 0; i < grades.Length; i++) {
        float tileX = left + float(i)*(gradeWidth + gradeGap);
        float gradeX = tileX + gradeWidth*0.5f;
        vec4 color = GradeColor(grades[i]);
        HudBox(tileX, r.y + 181*s, gradeWidth, 88*s, 10*s,
            HudColor(0.035f, 0.065f, 0.13f, 0.92f));
        HudBox(tileX + 9*s, r.y + 182*s, gradeWidth - 18*s, 2*s, 1*s,
            HudColor(color.x, color.y, color.z, 0.75f));
        HudText(gradeX, r.y + 223*s, grades[i], 40*s, color, center);
        HudText(gradeX, r.y + 257*s, "" + counts[i], 21*s,
            HudColor(0.90f, 0.95f, 1.0f), center);
    }
    string bestLead = "--";
    string medianLead = "--";
    if (leads.Length > 0) {
        leads.SortAsc();
        int median = leads[leads.Length / 2];
        if (leads.Length % 2 == 0)
            median = (leads[leads.Length / 2 - 1] + median) / 2;
        bestLead = bestLo + "-" + bestHi + "ms";
        medianLead = "~" + median + "ms";
    }
    array<string> detailLabels = {"MISSED", "UNRATED", "BEST LEAD", "MEDIAN"};
    array<string> detailValues = {"" + counts[6], "" + counts[7],
        bestLead, medianLead};
    float detailGap = 9*s;
    float detailWidth = (inner - detailGap) / 2.0f;
    for (uint i = 0; i < detailLabels.Length; i++) {
        float x = left + float(i % 2)*(detailWidth + detailGap);
        float y = r.y + (i < 2 ? 280*s : 322*s);
        vec4 accent = i == 0 ? HudColor(1.0f, 0.48f, 0.58f) :
            (i == 1 ? HudColor(0.62f, 0.76f, 0.88f) :
            HudColor(0.60f, 0.89f, 1.0f));
        HudBox(x, y, detailWidth, 34*s, 8*s,
            HudColor(0.035f, 0.065f, 0.13f, 0.88f));
        HudBox(x, y + 5*s, 2*s, 24*s, 1*s, accent);
        HudText(x + 13*s, y + 17*s, detailLabels[i], 11*s,
            HudColor(0.67f, 0.82f, 0.93f), alignLeft);
        HudText(x + detailWidth - 13*s, y + 17*s, detailValues[i], 16*s,
            accent, alignRight);
    }
    RenderFinishHistoryButton(r, s, run);
}

void RenderFinishHistoryButton(const vec4 &in panel, float scale,
    RunRecord@ run) {
    float width = 128*scale;
    float height = 29*scale;
    float x = panel.x + panel.z - 25*scale - width;
    float y = panel.y + 18*scale;
    vec2 mouse = UI::GetMousePos() * UI::GetScale();
    bool hovered = mouse.x >= x && mouse.x < x + width &&
        mouse.y >= y && mouse.y < y + height;
    // With the overlay open, an overlay window above the button takes the mouse.
    bool overWindow = UI::IsOverlayShown() && UI::WantCaptureMouse();
    bool active = hovered && !overWindow;
    HudBox(x, y, width, height, 7*scale, active ?
        HudColor(0.26f, 0.21f, 0.11f, 0.98f) :
        HudColor(0.10f, 0.15f, 0.25f, 0.94f));
    // Capitals have no descenders, so centre them by cap height on the baseline.
    float fontSize = 11*scale;
    HudText(x + width*0.5f, y + height*0.5f + 0.36f*fontSize, "VIEW HISTORY",
        fontSize, HudColor(1.0f, 0.85f, 0.36f),
        nvg::Align::Center | nvg::Align::Baseline);
    if (active && UI::IsMouseClicked()) {
        g_historySelectedId = run.id;
        g_historySelectedJump = -1;
        g_historyShowFinished = true;
        g_historyMapFilter = "";
        g_showHistory = true;
        UI::ShowOverlay();
    }
}
