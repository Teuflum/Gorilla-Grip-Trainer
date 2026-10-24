class FinishController {
    RunRecord@ summary;
    bool visible = false;

    void Finish(int raceTime, RunRecord@ active) {
        active.status = RunStatus::Finished;
        active.finishMs = raceTime;
        @summary = active;
        visible = S_AutoFinishSummary;
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
    float s = Math::Min(r.z / 650.0f, r.w / 365.0f);
    float cx = r.x + r.z*0.5f;
    float left = r.x + 25*s;
    float inner = r.z - 50*s;
    Hud::Panel(r);
    Hud::Text(cx, r.y + 40*s, "RUN COMPLETE", 27*s, Hud::TextColor(), Hud::Center);
    nvg::FontSize(17*s);
    Hud::Text(cx, r.y + 75*s, FitText(run.mapName, inner - 20*s), 17*s, Hud::Muted(), Hud::Center);
    array<string> totals = {"FINISH " + Time::Format(uint64(run.finishMs)),
        "SCORE " + run.score, "BEST x" + run.bestCombo};
    Hud::Columns(left, r.y + 125*s, inner, totals, 18*s, Hud::TextColor());

    // One count per grade from S+ to MISSED; anything else counts as unrated.
    array<int> counts(8);
    array<int> leads;
    for (uint i = 0; i < run.jumps.Length; i++) {
        HistoryJump@ jump = run.jumps[i];
        Grade grade = GradeFromName(jump.label);
        counts[uint(Math::Min(int(grade), int(Grade::Unrated)))]++;
        if (IsRated(grade) && jump.leadMs >= 0) leads.InsertLast(jump.leadMs);
    }
    // S+ to D and MISS as columns: the grade in its colour over its count.
    float column = inner / 7.0f;
    for (int g = int(Grade::SPlus); g <= int(Grade::Missed); g++) {
        float x = left + column*(float(g) + 0.5f);
        string name = Grade(g) == Grade::Missed ? "MISS" : GradeName(Grade(g));
        Hud::Text(x, r.y + 195*s, name, 34*s, GradeColor(Grade(g)), Hud::Center);
        Hud::Text(x, r.y + 235*s, "" + counts[uint(g)], 20*s, Hud::TextColor(), Hud::Center);
    }

    string bestLead = "--";
    string medianLead = "--";
    if (leads.Length > 0) {
        leads.SortAsc();
        int median = leads[leads.Length / 2];
        if (leads.Length % 2 == 0)
            median = (leads[leads.Length / 2 - 1] + median) / 2;
        bestLead = leads[0] + " ms";
        medianLead = "~" + median + " ms";
    }
    array<string> details = {"BEST LEAD " + bestLead, "MEDIAN " + medianLead,
        "UNRATED " + counts[uint(Grade::Unrated)]};
    Hud::Columns(left, r.y + 310*s, inner, details, 14*s, Hud::Muted());
}
