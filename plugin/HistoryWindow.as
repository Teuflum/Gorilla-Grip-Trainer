bool g_showHistory = false;
bool g_historyShowFinished = true;
bool g_historyShowResets = true;
bool g_historyClearArmed = false;
string g_historyMapFilter = "";
string g_historySelectedId = "";
int g_historySelectedJump = -1;

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
        if (g_history.runs[i].id == g_historySelectedId &&
            HistoryMatches(g_history.runs[i]))
            return g_history.runs[i];
    return null;
}

string HistoryGrade(HistoryJump@ jump) {
    if (jump is null) return "";
    bool uncertainGrade = jump.label != "S+" && jump.timingEstimated &&
        GradeBasePoints(jump.label) > 0;
    return jump.label + (uncertainGrade ? "+" : "");
}

void RenderHistoryAttempts() {
    UI::SeparatorText("ATTEMPTS");
    UI::BeginChild("attempts", vec2(0, 185), true);
    if (UI::BeginTable("attemptTable", 4,
        UI::TableFlags::RowBg | UI::TableFlags::SizingStretchProp)) {
        UI::TableSetupColumn("Map", UI::TableColumnFlags::WidthStretch, 2.6f);
        UI::TableSetupColumn("Date", UI::TableColumnFlags::WidthStretch, 1.5f);
        UI::TableSetupColumn("Result", UI::TableColumnFlags::WidthStretch, 1.0f);
        UI::TableSetupColumn("Score", UI::TableColumnFlags::WidthStretch, 0.7f);
        UI::TableHeadersRow();
        for (int i = int(g_history.runs.Length) - 1; i >= 0; i--) {
            RunRecord@ run = g_history.runs[uint(i)];
            if (!HistoryMatches(run)) continue;
            UI::TableNextRow();
            UI::TableNextColumn();
            if (UI::Selectable(run.mapName + "##" + run.id,
                g_historySelectedId == run.id,
                UI::SelectableFlags::SpanAllColumns)) {
                g_historySelectedId = run.id;
                g_historySelectedJump = -1;
            }
            UI::TableNextColumn();
            UI::Text(Time::FormatString("%Y-%m-%d %H:%M", run.startedAt / 1000));
            UI::TableNextColumn();
            UI::Text(run.status == "FINISHED" ? "FINISHED" : "RESET");
            UI::TableNextColumn();
            UI::Text("" + run.score);
        }
        UI::EndTable();
    }
    UI::EndChild();
}

void RenderHistoryJumps(RunRecord@ selected) {
    UI::SeparatorText("JUMPS  " + selected.jumps.Length);
    UI::BeginChild("jumps", vec2(0, 220), true);
    if (selected.jumps.Length == 0) UI::Text("No rated jumps in this run.");
    else if (UI::BeginTable("jumpTable", 6,
        UI::TableFlags::RowBg | UI::TableFlags::SizingStretchProp)) {
        UI::TableSetupColumn("#", UI::TableColumnFlags::WidthStretch, 0.4f);
        UI::TableSetupColumn("Grade", UI::TableColumnFlags::WidthStretch, 0.8f);
        UI::TableSetupColumn("Landing", UI::TableColumnFlags::WidthStretch, 1.3f);
        UI::TableSetupColumn("Lead", UI::TableColumnFlags::WidthStretch, 1.3f);
        UI::TableSetupColumn("Points", UI::TableColumnFlags::WidthStretch, 0.8f);
        UI::TableSetupColumn("Next", UI::TableColumnFlags::WidthStretch, 0.7f);
        UI::TableHeadersRow();
        for (uint j = 0; j < selected.jumps.Length; j++) {
            HistoryJump@ jump = selected.jumps[j];
            UI::TableNextRow();
            UI::TableNextColumn();
            if (UI::Selectable("" + (j + 1) + "##jump" + j,
                g_historySelectedJump == int(j),
                UI::SelectableFlags::SpanAllColumns))
                g_historySelectedJump = int(j);
            UI::TableNextColumn();
            UI::PushStyleColor(UI::Col::Text, GradeColor(jump.label));
            UI::Text(HistoryGrade(jump));
            UI::PopStyleColor();
            UI::TableNextColumn();
            UI::Text(Time::Format(uint64(jump.landingMs)));
            UI::TableNextColumn();
            UI::Text(jump.leadMinMs < 0 ? "--" :
                jump.leadMinMs + "-" + jump.leadMaxMs + " ms");
            UI::TableNextColumn();
            UI::Text("+" + jump.points);
            UI::TableNextColumn();
            UI::Text("x" + DisplayComboMultiplier(jump.combo));
        }
        UI::EndTable();
    }
    UI::EndChild();
    if (g_historySelectedJump < 0 ||
        g_historySelectedJump >= int(selected.jumps.Length)) return;
    HistoryJump@ jump = selected.jumps[uint(g_historySelectedJump)];
    UI::SeparatorText("JUMP " + (g_historySelectedJump + 1) + " DETAIL");
    UI::PushStyleColor(UI::Col::Text, GradeColor(jump.label));
    UI::Text(HistoryGrade(jump));
    UI::PopStyleColor();
    UI::SameLine();
    UI::Text("at " + Time::Format(uint64(jump.landingMs)) +
        "  |  +" + jump.points + " pts  |  " + jump.spins + " spins");
    if (jump.preview.Length > 0)
        UI::Text("Takeoff " + jump.preview +
            (jump.timingEstimated && jump.preview != "S+" ? "+" : "") +
            "  |  Lead " + jump.leadMinMs + "-" + jump.leadMaxMs + " ms");
    if (jump.scoreAfter >= 0)
        UI::Text("Score after landing " + jump.scoreAfter);
    UI::TextWrapped(jump.reason);
}

void RenderHistoryWindow() {
    if (!g_showHistory) return;
    UI::SetNextWindowSize(850, 640, UI::Cond::FirstUseEver);
    UI::PushStyleColor(UI::Col::WindowBg, vec4(0.025f, 0.039f, 0.09f, 0.97f));
    UI::PushStyleColor(UI::Col::ChildBg, vec4(0.035f, 0.065f, 0.13f, 0.88f));
    UI::PushStyleColor(UI::Col::TableHeaderBg, vec4(0.08f, 0.12f, 0.21f, 1.0f));
    if (!UI::Begin("Gorilla Grip Trainer - Run History", g_showHistory)) {
        UI::End();
        UI::PopStyleColor(3);
        return;
    }
    if (g_history is null) {
        UI::Text("History is not ready.");
        UI::End();
        UI::PopStyleColor(3);
        return;
    }
    UI::PushStyleColor(UI::Col::Text, GradeColor("S"));
    UI::SeparatorText("GORILLA GRIP / RUN HISTORY");
    UI::PopStyleColor();
    UI::Text("" + g_history.runs.Length + " saved attempts");
    UI::SetNextItemWidth(250);
    g_historyMapFilter = UI::InputText("Map name or UID", g_historyMapFilter);
    UI::SameLine();
    g_historyShowFinished = UI::Checkbox("Finished", g_historyShowFinished);
    UI::SameLine();
    g_historyShowResets = UI::Checkbox("Resets", g_historyShowResets);
    RenderHistoryAttempts();
    RunRecord@ selected = SelectedHistoryRun();
    if (selected is null) UI::Text("Select an attempt to inspect its jumps.");
    else {
        UI::SeparatorText("SELECTED ATTEMPT");
        UI::TextWrapped(selected.mapName);
        string overview = selected.status == "FINISHED" ?
            "FINISHED  " + Time::Format(uint64(selected.finishMs)) : "RESET";
        UI::Text(overview + "    " + selected.score + " pts    Best x" +
            DisplayComboMultiplier(selected.bestCombo) + "    " +
            selected.hits + " hits    " + selected.misses + " misses");
        RenderHistoryJumps(selected);
    }
    UI::Separator();
    if (!g_historyClearArmed) {
        if (UI::Button("Clear local history...")) g_historyClearArmed = true;
    } else {
        UI::Text("This removes saved attempts from this computer.");
        if (UI::Button("Confirm clear all attempts")) {
            g_history.Clear();
            g_historySelectedId = "";
            g_historySelectedJump = -1;
            g_historyClearArmed = false;
        }
        UI::SameLine();
        if (UI::Button("Cancel")) g_historyClearArmed = false;
    }
    UI::End();
    UI::PopStyleColor(3);
}
