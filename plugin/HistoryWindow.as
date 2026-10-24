// What the Run history window shows; it is open while visible is set.
class HistoryView {
    bool visible = false;
    bool showFinished = true;
    bool showResets = true;
    bool clearArmed = false;
    string mapFilter = "";
    string selectedId = "";
}

HistoryView g_historyView;

bool HistoryMatches(RunRecord@ run) {
    if (run.status == RunStatus::Finished && !g_historyView.showFinished) return false;
    if (run.status == RunStatus::Reset && !g_historyView.showResets) return false;
    string query = g_historyView.mapFilter.Trim().ToLower();
    if (query.Length > 0 &&
        !run.mapName.ToLower().Contains(query) &&
        !run.mapUid.ToLower().Contains(query)) return false;
    return true;
}

RunRecord@ SelectedHistoryRun() {
    for (uint i = 0; i < g_history.runs.Length; i++)
        if (g_history.runs[i].id == g_historyView.selectedId &&
            HistoryMatches(g_history.runs[i]))
            return g_history.runs[i];
    return null;
}

string Colored(const vec4 &in color, const string &in text) {
    return Text::FormatOpenplanetColor(vec3(color.x, color.y, color.z)) + text;
}

// How often one run got each grade, in the HUD colours: "S+: 3  S: 2  MISSED: 1".
void RenderGradeTally(RunRecord@ run) {
    bool first = true;
    for (int g = int(Grade::SPlus); g <= int(Grade::Missed); g++) {
        string name = GradeName(Grade(g));
        int count = 0;
        for (uint j = 0; j < run.jumps.Length; j++)
            if (run.jumps[j].label == name) count++;
        if (count == 0) continue;
        if (!first) UI::SameLine(0, 12);
        UI::Text(Colored(GradeColor(Grade(g)), name + ": " + count));
        first = false;
    }
    if (first) UI::TextDisabled("--");
}

void RenderHistoryAttempts() {
    UI::BeginChild("attempts", vec2(0, 220), true);
    if (UI::BeginTable("attemptTable", 5,
        UI::TableFlags::RowBg | UI::TableFlags::SizingStretchProp)) {
        UI::TableSetupColumn("Map", UI::TableColumnFlags::WidthStretch, 2.4f);
        UI::TableSetupColumn("Date", UI::TableColumnFlags::WidthStretch, 1.4f);
        UI::TableSetupColumn("Result", UI::TableColumnFlags::WidthStretch, 1.3f);
        UI::TableSetupColumn("Score", UI::TableColumnFlags::WidthStretch, 0.7f);
        UI::TableSetupColumn("Grades", UI::TableColumnFlags::WidthStretch, 1.8f);
        UI::TableHeadersRow();
        for (int i = int(g_history.runs.Length) - 1; i >= 0; i--) {
            RunRecord@ run = g_history.runs[uint(i)];
            if (!HistoryMatches(run)) continue;
            UI::TableNextRow();
            UI::TableNextColumn();
            if (UI::Selectable(run.mapName + "##" + run.id,
                g_historyView.selectedId == run.id,
                UI::SelectableFlags::SpanAllColumns))
                g_historyView.selectedId = run.id;
            UI::TableNextColumn();
            UI::Text(Time::FormatString("%Y-%m-%d %H:%M", run.startedAt / 1000));
            UI::TableNextColumn();
            if (run.status == RunStatus::Finished)
                UI::Text(Colored(Hud::Gold, "FINISHED " + Time::Format(uint64(run.finishMs))));
            else UI::Text(Colored(GradeColor(Grade::Missed), "RESET"));
            UI::TableNextColumn();
            UI::Text("" + run.score);
            UI::TableNextColumn();
            RenderGradeTally(run);
        }
        UI::EndTable();
    }
    UI::EndChild();
}

// The reason, and the takeoff grade when the landing changed it.
string JumpDetail(HistoryJump@ jump) {
    string detail = jump.reason;
    if (jump.preview.Length > 0 && jump.preview != jump.label)
        detail += "\nGrade at takeoff: " + jump.preview;
    if (jump.scoreAfter >= 0) detail += "\nScore after: " + jump.scoreAfter;
    return detail;
}

void RenderHistoryJumps(RunRecord@ selected) {
    UI::SeparatorText(selected.mapName + " - " + selected.jumps.Length + " jumps");
    if (selected.jumps.Length == 0) {
        UI::Text("No rated jumps in this run.");
        return;
    }
    UI::BeginChild("jumps", vec2(0, 260), true);
    if (UI::BeginTable("jumpTable", 6,
        UI::TableFlags::RowBg | UI::TableFlags::SizingStretchProp)) {
        UI::TableSetupColumn("#", UI::TableColumnFlags::WidthStretch, 0.4f);
        UI::TableSetupColumn("Grade", UI::TableColumnFlags::WidthStretch, 0.8f);
        UI::TableSetupColumn("Landing", UI::TableColumnFlags::WidthStretch, 1.3f);
        UI::TableSetupColumn("Lead", UI::TableColumnFlags::WidthStretch, 1.3f);
        UI::TableSetupColumn("Points", UI::TableColumnFlags::WidthStretch, 0.8f);
        UI::TableSetupColumn("Combo", UI::TableColumnFlags::WidthStretch, 0.7f);
        UI::TableHeadersRow();
        for (uint j = 0; j < selected.jumps.Length; j++) {
            HistoryJump@ jump = selected.jumps[j];
            UI::TableNextRow();
            UI::TableNextColumn();
            UI::Selectable("" + (j + 1) + "##jump" + j, false, UI::SelectableFlags::SpanAllColumns);
            if (UI::IsItemHovered()) UI::SetTooltip(JumpDetail(jump));
            UI::TableNextColumn();
            UI::Text(Colored(GradeColor(GradeFromName(jump.label)), jump.label));
            UI::TableNextColumn();
            UI::Text(Time::Format(uint64(jump.landingMs)));
            UI::TableNextColumn();
            UI::Text(jump.leadMs < 0 ? "--" : jump.leadMs + " ms");
            UI::TableNextColumn();
            UI::Text("+" + jump.points);
            UI::TableNextColumn();
            UI::Text("x" + jump.combo);
        }
        UI::EndTable();
    }
    UI::EndChild();
}

void RenderHistoryClear() {
    if (!g_historyView.clearArmed) {
        if (UI::Button("Clear local history...")) g_historyView.clearArmed = true;
        return;
    }
    UI::Text("This removes saved attempts from this computer.");
    if (UI::Button("Confirm clear all attempts")) {
        g_history.Clear();
        g_historyView.selectedId = "";
        g_historyView.clearArmed = false;
    }
    UI::SameLine();
    if (UI::Button("Cancel")) g_historyView.clearArmed = false;
}

void RenderHistoryContents() {
    UI::Text("" + g_history.runs.Length + " saved attempts");
    UI::SetNextItemWidth(250);
    g_historyView.mapFilter = UI::InputText("Map name or UID", g_historyView.mapFilter);
    UI::SameLine();
    g_historyView.showFinished = UI::Checkbox("Finished", g_historyView.showFinished);
    UI::SameLine();
    g_historyView.showResets = UI::Checkbox("Resets", g_historyView.showResets);
    RenderHistoryAttempts();
    RunRecord@ selected = SelectedHistoryRun();
    if (selected is null) UI::Text("Select an attempt to see its jumps.");
    else RenderHistoryJumps(selected);
    UI::Separator();
    RenderHistoryClear();
}

void RenderHistoryWindow() {
    if (!g_historyView.visible) return;
    bool open = true;
    UI::SetNextWindowSize(850, 640, UI::Cond::FirstUseEver);
    if (UI::Begin("Gorilla Grip Trainer - Run History", open)) RenderHistoryContents();
    UI::End();
    g_historyView.visible = open;
}
