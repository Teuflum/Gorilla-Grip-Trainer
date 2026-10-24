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
    Hud::CardBase(r, Hud::Gold);
    Hud::Text(cx, r.y + 36*s, "RUN COMPLETE", 27*s, Hud::Gold, center);
    nvg::FontSize(17*s);
    Hud::Text(cx, r.y + 69*s, FitText(run.mapName, inner - 20*s), 17*s, Hud::Bright, center);

    array<string> statLabels = {"FINISH", "SCORE", "BEST COMBO"};
    array<string> statValues = {Time::Format(uint64(run.finishMs)),
        "" + run.score, "x" + run.bestCombo};
    array<vec4> statColors = {Hud::White, Hud::Gold, Hud::Cyan};
    Hud::TileRow(left, r.y + 91*s, inner, 68*s, 9*s, statLabels, statValues, statColors, false);

    // One count per grade from S+ to MISSED; anything else counts as unrated.
    array<int> counts(8);
    array<int> leads;
    for (uint i = 0; i < run.jumps.Length; i++) {
        HistoryJump@ jump = run.jumps[i];
        Grade grade = GradeFromName(jump.label);
        counts[uint(Math::Min(int(grade), int(Grade::Unrated)))]++;
        if (IsRated(grade) && jump.leadMs >= 0) leads.InsertLast(jump.leadMs);
    }
    array<string> gradeNames;
    array<string> gradeCounts;
    array<vec4> gradeColors;
    for (int g = int(Grade::SPlus); g <= int(Grade::D); g++) {
        gradeNames.InsertLast(GradeName(Grade(g)));
        gradeCounts.InsertLast("" + counts[uint(g)]);
        gradeColors.InsertLast(GradeColor(Grade(g)));
    }
    Hud::TileRow(left, r.y + 177*s, inner, 80*s, 7*s, gradeNames, gradeCounts, gradeColors, true);

    string bestLead = "--";
    string medianLead = "--";
    if (leads.Length > 0) {
        leads.SortAsc();
        int median = leads[leads.Length / 2];
        if (leads.Length % 2 == 0)
            median = (leads[leads.Length / 2 - 1] + median) / 2;
        bestLead = leads[0] + "ms";
        medianLead = "~" + median + "ms";
    }
    array<string> detailLabels = {"MISSED", "UNRATED", "BEST LEAD", "MEDIAN"};
    array<string> detailValues = {"" + counts[uint(Grade::Missed)],
        "" + counts[uint(Grade::Unrated)], bestLead, medianLead};
    array<vec4> detailColors = {Hud::Pink, Hud::Label, Hud::Cyan, Hud::Cyan};
    Hud::TileRow(left, r.y + 271*s, inner, 70*s, 9*s, detailLabels, detailValues, detailColors, true);
}
