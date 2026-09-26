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

void RenderFinishSummary(const vec4 &in r, RunRecord@ run) {
    if (run is null) return;
    float s = Math::Min(r.z / 650.0f, r.w / 365.0f);
    float cx = r.x + r.z*0.5f;
    float left = r.x + 25*s;
    float right = r.x + r.z - 25*s;
    int alignLeft = nvg::Align::Left | nvg::Align::Middle;
    int alignRight = nvg::Align::Right | nvg::Align::Middle;
    int center = nvg::Align::Center | nvg::Align::Middle;
    HudCardBase(r, HudColor(1.0f, 0.80f, 0.28f));
    HudText(cx, r.y + 38*s, "RUN COMPLETE", 26*s,
        HudColor(1.0f, 0.86f, 0.37f), center);
    HudText(cx, r.y + 75*s, run.mapName, 18*s,
        HudColor(0.81f, 0.91f, 1.0f), center);
    HudText(left, r.y + 119*s, "FINISH", 13*s,
        HudColor(0.60f, 0.73f, 0.84f), alignLeft);
    HudText(right, r.y + 119*s, Time::Format(uint64(run.finishMs)), 25*s,
        HudColor(1, 1, 1), alignRight);
    HudText(left, r.y + 157*s, "SCORE", 13*s,
        HudColor(0.60f, 0.73f, 0.84f), alignLeft);
    HudText(right, r.y + 157*s, "" + run.score, 25*s,
        HudColor(1.0f, 0.85f, 0.36f), alignRight);
    HudText(left, r.y + 191*s, "BEST COMBO", 13*s,
        HudColor(0.60f, 0.73f, 0.84f), alignLeft);
    HudText(right, r.y + 191*s, "x" + run.bestCombo, 22*s,
        HudColor(0.60f, 0.89f, 1.0f), alignRight);
    HudBox(left, r.y + 213*s, r.z - 50*s, 1*s, 0,
        HudColor(0.27f, 0.37f, 0.49f));
    array<int> counts(7);
    array<int> leads;
    int bestLo = -1;
    int bestHi = -1;
    for (uint i = 0; i < run.jumps.Length; i++) {
        HistoryJump@ jump = run.jumps[i];
        int index = jump.label == "S" ? 0 : jump.label == "A" ? 1 :
            jump.label == "B" ? 2 : jump.label == "C" ? 3 :
            jump.label == "D" ? 4 : jump.label == "MISSED" ? 5 : 6;
        counts[index]++;
        if (index < 5 && jump.leadMinMs >= 0) {
            int lead = (jump.leadMinMs + jump.leadMaxMs) / 2;
            leads.InsertLast(lead);
            if (bestLo < 0 || lead < (bestLo + bestHi) / 2) {
                bestLo = jump.leadMinMs;
                bestHi = jump.leadMaxMs;
            }
        }
    }
    array<string> grades = {"S", "A", "B", "C", "D"};
    float gradeWidth = (r.z - 50*s) / 5.0f;
    for (uint i = 0; i < grades.Length; i++) {
        float gradeX = left + (float(i) + 0.5f)*gradeWidth;
        HudText(gradeX, r.y + 245*s, grades[i] + " " + counts[i], 19*s,
            GradeColor(grades[i]), center);
    }
    HudText(cx, r.y + 273*s,
        "MISSED " + counts[5] + "   UNRATED " + counts[6], 15*s,
        HudColor(1.0f, 0.45f, 0.56f), center);
    string timing = "BEST LEAD --    MEDIAN --";
    if (leads.Length > 0) {
        leads.SortAsc();
        int median = leads[leads.Length / 2];
        if (leads.Length % 2 == 0)
            median = (leads[leads.Length / 2 - 1] + median) / 2;
        timing = "BEST LEAD " + bestLo + "-" + bestHi + "ms    MEDIAN ~" +
            median + "ms";
    }
    HudText(cx, r.y + 313*s, timing, 14*s,
        HudColor(0.67f, 0.82f, 0.93f), center);
    HudText(cx, r.y + 342*s, "Open the plugin menu to hide this summary", 11*s,
        HudColor(0.49f, 0.64f, 0.76f), center);
}
