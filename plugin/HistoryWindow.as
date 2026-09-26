bool g_showHistory = false;
bool g_historyShowFinished = true;
bool g_historyShowResets = true;
bool g_historyClearArmed = false;
string g_historyMapFilter = "";
string g_historySelectedId = "";

bool HistoryMatches(RunRecord@ run) {
    if (run is null) return false;
    if (run.status == "FINISHED" && !g_historyShowFinished) return false;
    if (run.status == "RESET" && !g_historyShowResets) return false;
    if (g_historyMapFilter.Length > 0 &&
        !run.mapName.Contains(g_historyMapFilter) &&
        !run.mapUid.Contains(g_historyMapFilter)) return false;
    return true;
}

RunRecord@ SelectedHistoryRun() {
    if (g_history is null) return null;
    for (uint i = 0; i < g_history.runs.Length; i++)
        if (g_history.runs[i].id == g_historySelectedId)
            return g_history.runs[i];
    return null;
}

void RenderHistoryWindow() {
    if (!g_showHistory) return;
    if (!UI::Begin("Gorilla Grip Trainer - Run History", g_showHistory)) {
        UI::End();
        return;
    }
    if (g_history is null) {
        UI::Text("History is not ready.");
        UI::End();
        return;
    }
    g_historyMapFilter = UI::InputText("Map name or UID", g_historyMapFilter);
    g_historyShowFinished = UI::Checkbox("Finished", g_historyShowFinished);
    UI::SameLine();
    g_historyShowResets = UI::Checkbox("Resets", g_historyShowResets);
    UI::Text("Attempts: " + g_history.runs.Length);
    UI::BeginChild("attempts", vec2(0, 240), true);
    for (int i = int(g_history.runs.Length) - 1; i >= 0; i--) {
        RunRecord@ run = g_history.runs[uint(i)];
        if (!HistoryMatches(run)) continue;
        string row = run.status + "  " + run.mapName + "  " +
            Time::FormatString("%Y-%m-%d %H:%M", run.startedAt / 1000) +
            "  " + run.score + " pts##" + run.id;
        if (UI::Selectable(row, g_historySelectedId == run.id))
            g_historySelectedId = run.id;
    }
    UI::EndChild();
    RunRecord@ selected = SelectedHistoryRun();
    if (selected !is null) {
        UI::SeparatorText("Selected attempt");
        UI::Text(selected.mapName + "  |  " + selected.status);
        if (selected.status == "FINISHED")
            UI::Text("Finish: " + Time::Format(uint64(selected.finishMs)));
        UI::Text("Score " + selected.score + "  Best combo x" +
            DisplayComboMultiplier(selected.bestCombo) +
            "  Hits " + selected.hits + "  Misses " + selected.misses);
        UI::SeparatorText("Jumps");
        for (uint j = 0; j < selected.jumps.Length; j++) {
            HistoryJump@ jump = selected.jumps[j];
            bool uncertainGrade = jump.timingEstimated && GradeBasePoints(jump.label) > 0;
            string lead = jump.leadMinMs < 0 ? "no preview" :
                jump.leadMinMs + "-" + jump.leadMaxMs + " ms before takeoff";
            UI::Text("#" + (j + 1) + "  " + jump.label +
                (uncertainGrade ? "+" : "") + "  " +
                Time::Format(uint64(jump.landingMs)) + "  " + lead);
            if (jump.preview.Length > 0)
                UI::Text("Takeoff preview: " + jump.preview +
                    (jump.timingEstimated ? "+" : ""));
            UI::Text("Streak " + jump.combo + "  Next x" +
                DisplayComboMultiplier(jump.combo) + "  +" + jump.points +
                " pts  Spins " + jump.spins);
            if (jump.scoreAfter >= 0)
                UI::Text("Score after landing: " + jump.scoreAfter);
            UI::TextWrapped(jump.reason);
        }
    }
    UI::Separator();
    if (!g_historyClearArmed) {
        if (UI::Button("Clear local history...")) g_historyClearArmed = true;
    } else {
        UI::Text("This removes saved attempts from this computer.");
        if (UI::Button("Confirm clear all attempts")) {
            g_history.Clear();
            g_historySelectedId = "";
            g_historyClearArmed = false;
        }
        UI::SameLine();
        if (UI::Button("Cancel")) g_historyClearArmed = false;
    }
    UI::End();
}
