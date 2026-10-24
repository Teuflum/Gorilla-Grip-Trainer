class FinishController {
    RunRecord@ summary;
    string lastFinishedId = "";
    bool visible = false;

    // True once per run, when it first reaches the finish.
    bool Update(int raceTime, RunRecord@ active) {
        if (active is null || active.id == lastFinishedId) return false;
        active.status = RunStatus::Finished;
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

// Back in the map editor after a test or validation run: the editor keeps the
// same map loaded, but the drive is over.
bool IsEditingMap() {
    auto app = cast<CTrackMania>(GetApp());
    return app !is null && app.Editor !is null && app.CurrentPlayground is null;
}

// Cuts text to maxWidth at the current font size, ending it with an ellipsis.
string FitText(const string &in text, float maxWidth) {
    if (nvg::TextBounds(text).x <= maxWidth) return text;
    string cut = text;
    while (cut.Length > 0 && nvg::TextBounds(cut + "…").x > maxWidth) {
        uint end = cut.Length - 1;
        // Keep multi-byte UTF-8 characters whole.
        while (end > 0 && (cut[end] & 0xC0) == 0x80) end--;
        cut = cut.SubStr(0, end);
    }
    return cut + "…";
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
    Hud::CardBase(r, Hud::Gold);
    Hud::Text(cx, r.y + 36*s, "RUN COMPLETE", 27*s, Hud::Gold, center);

    // Long map names shrink to 12 px, then get cut.
    float nameSize = 17*s;
    float nameWidth = inner - 20*s;
    nvg::FontSize(nameSize);
    float measuredWidth = nvg::TextBounds(run.mapName).x;
    if (measuredWidth > nameWidth)
        nameSize = Math::Max(12*s, nameSize * nameWidth / measuredWidth);
    nvg::FontSize(nameSize);
    Hud::Text(cx, r.y + 69*s, FitText(run.mapName, nameWidth), nameSize, Hud::Bright, center);

    array<string> statLabels = {"FINISH", "SCORE", "BEST COMBO"};
    array<string> statValues = {Time::Format(uint64(run.finishMs)),
        "" + run.score, "x" + run.bestCombo};
    array<vec4> statColors = {Hud::White, Hud::Gold, Hud::Cyan};
    Hud::TileRow(left, r.y + 91*s, inner, 68*s, 9*s, statLabels, statValues, statColors, false);

    // One count per grade from S+ to MISSED; anything else counts as unrated.
    array<int> counts(8);
    array<int> leads;
    int bestLo = -1;
    int bestHi = -1;
    for (uint i = 0; i < run.jumps.Length; i++) {
        HistoryJump@ jump = run.jumps[i];
        Grade grade = GradeFromName(jump.label);
        counts[uint(Math::Min(int(grade), int(Grade::Unrated)))]++;
        if (IsRated(grade) && jump.leadMinMs >= 0) {
            int lead = (jump.leadMinMs + jump.leadMaxMs) / 2;
            leads.InsertLast(lead);
            if (bestLo < 0 || lead < (bestLo + bestHi) / 2) {
                bestLo = jump.leadMinMs;
                bestHi = jump.leadMaxMs;
            }
        }
    }
    float gradeGap = 7*s;
    float gradeWidth = (inner - 5*gradeGap) / 6.0f;
    for (int g = int(Grade::SPlus); g <= int(Grade::D); g++) {
        float tileX = left + float(g)*(gradeWidth + gradeGap);
        float gradeX = tileX + gradeWidth*0.5f;
        vec4 color = GradeColor(Grade(g));
        Hud::Box(tileX, r.y + 181*s, gradeWidth, 88*s, 10*s, Hud::Tile);
        Hud::Box(tileX + 9*s, r.y + 182*s, gradeWidth - 18*s, 2*s, 1*s,
            Hud::WithAlpha(color, 0.75f));
        Hud::Text(gradeX, r.y + 223*s, GradeName(Grade(g)), 40*s, color, center);
        Hud::Text(gradeX, r.y + 257*s, "" + counts[uint(g)], 21*s, Hud::Bright, center);
    }

    string bestLead = "--";
    string medianLead = "--";
    if (leads.Length > 0) {
        leads.SortAsc();
        int median = leads[leads.Length / 2];
        if (leads.Length % 2 == 0)
            median = (leads[leads.Length / 2 - 1] + median) / 2;
        // Older entries may hold a lead range; new ones hold one exact value.
        bestLead = bestLo == bestHi ? bestLo + "ms" : bestLo + "-" + bestHi + "ms";
        medianLead = "~" + median + "ms";
    }
    array<string> detailLabels = {"MISSED", "UNRATED", "BEST LEAD", "MEDIAN"};
    array<string> detailValues = {"" + counts[uint(Grade::Missed)],
        "" + counts[uint(Grade::Unrated)], bestLead, medianLead};
    array<vec4> detailColors = {Hud::Pink, Hud::Label, Hud::Cyan, Hud::Cyan};
    float detailGap = 9*s;
    float detailWidth = (inner - detailGap) / 2.0f;
    for (uint i = 0; i < detailLabels.Length; i++) {
        float x = left + float(i % 2)*(detailWidth + detailGap);
        float y = r.y + (i < 2 ? 280*s : 322*s);
        Hud::Box(x, y, detailWidth, 34*s, 8*s, Hud::Tile);
        Hud::Box(x, y + 5*s, 2*s, 24*s, 1*s, detailColors[i]);
        Hud::Text(x + 13*s, y + 17*s, detailLabels[i], 11*s, Hud::Label, alignLeft);
        Hud::Text(x + detailWidth - 13*s, y + 17*s, detailValues[i], 16*s,
            detailColors[i], alignRight);
    }
}
