bool g_showHistory = false;
bool g_historyShowFinished = true;
bool g_historyShowResets = true;
bool g_historyClearArmed = false;
string g_historyMapFilter = "";
string g_historySelectedId = "";
int g_historySelectedJump = -1;
UI::Font@ g_historyTileFont = null;

bool HistoryMatches(RunRecord@ run) {
    if (run is null) return false;
    if (run.status == "FINISHED" && !g_historyShowFinished) return false;
    if (run.status == "RESET" && !g_historyShowResets) return false;
    string query = g_historyMapFilter.Trim().ToLower();
    if (query.Length > 0 &&
        !run.mapName.ToLower().Contains(query) &&
        !run.mapUid.ToLower().Contains(query)) return false;
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

// Older entries may hold a lead range; new ones hold one exact value.
string HistoryLead(HistoryJump@ jump) {
    if (jump.leadMinMs < 0) return "--";
    if (jump.leadMinMs == jump.leadMaxMs) return jump.leadMinMs + " ms";
    return jump.leadMinMs + "-" + jump.leadMaxMs + " ms";
}

UI::Font@ HistoryFont() {
    if (g_historyTileFont is null)
        @g_historyTileFont = UI::LoadFont("DroidSans-Bold.ttf", 22);
    return g_historyTileFont;
}

vec4 HistoryStatusColor(const string &in status) {
    return status == "FINISHED" ? HudColor(1.0f, 0.85f, 0.36f) :
        HudColor(1.0f, 0.48f, 0.58f);
}

// HUD-style section caption: a short gold bar, then the caption in capitals.
void RenderHistoryHeader(const string &in caption,
    const vec4 &in color = vec4(0.60f, 0.73f, 0.84f, 1.0f)) {
    UI::Dummy(vec2(0, 4));
    UI::DrawList@ dl = UI::GetWindowDrawList();
    vec2 pos = UI::GetCursorScreenPos();
    dl.AddRectFilled(vec4(pos.x, pos.y + 1, 3, 16), HudColor(1.0f, 0.85f, 0.36f), 1.0f);
    dl.AddText(vec2(pos.x + 10, pos.y), color, caption, HistoryFont(), 16);
    UI::Dummy(vec2(0, 22));
}

// A row of stat tiles like the finish summary: caption over a large value.
void RenderHistoryTiles(const array<string> &in captions, const array<string> &in values,
    const array<vec4> &in accents, const array<vec4> &in valueColors) {
    UI::DrawList@ dl = UI::GetWindowDrawList();
    vec2 origin = UI::GetCursorScreenPos();
    float gap = 8.0f;
    float height = 58.0f;
    float width = (UI::GetContentRegionAvail().x - gap * float(captions.Length - 1)) /
        float(captions.Length);
    for (uint i = 0; i < captions.Length; i++) {
        float x = origin.x + float(i) * (width + gap);
        dl.AddRectFilled(vec4(x, origin.y, width, height),
            HudColor(0.035f, 0.065f, 0.13f, 0.88f), 4.0f);
        dl.AddRectFilled(vec4(x, origin.y, width, 3.0f), accents[i], 2.0f);
        dl.AddText(vec2(x + 10, origin.y + 9), HudColor(0.60f, 0.73f, 0.84f),
            captions[i]);
        dl.AddText(vec2(x + 10, origin.y + 26), valueColors[i], values[i],
            HistoryFont(), 22);
    }
    UI::Dummy(vec2(0, height + 4));
}

void RenderAttemptTiles(RunRecord@ run) {
    vec4 gold = HudColor(1.0f, 0.85f, 0.36f);
    vec4 cyan = HudColor(0.60f, 0.89f, 1.0f);
    vec4 white = HudColor(1, 1, 1);
    vec4 status = HistoryStatusColor(run.status);
    array<string> captions = {"RESULT", "SCORE", "BEST COMBO", "HITS", "MISSES"};
    array<string> values = {
        run.status == "FINISHED" ? Time::Format(uint64(run.finishMs)) : "RESET",
        "" + run.score, "x" + run.bestCombo, "" + run.hits, "" + run.misses};
    array<vec4> accents = {status, gold, cyan,
        HudColor(0.04f, 0.98f, 0.78f), HudColor(1.0f, 0.48f, 0.58f)};
    array<vec4> valueColors = {status, gold, cyan, white, white};
    RenderHistoryTiles(captions, values, accents, valueColors);
}

void RenderJumpTiles(HistoryJump@ jump) {
    vec4 grade = GradeColor(jump.label);
    vec4 gold = HudColor(1.0f, 0.85f, 0.36f);
    vec4 cyan = HudColor(0.60f, 0.89f, 1.0f);
    vec4 white = HudColor(1, 1, 1);
    vec4 muted = HudColor(0.62f, 0.76f, 0.88f);
    array<string> captions = {"GRADE", "LANDING", "LEAD", "POINTS", "COMBO"};
    array<string> values = {HistoryGrade(jump), Time::Format(uint64(jump.landingMs)),
        HistoryLead(jump),
        "+" + jump.points, "x" + jump.combo};
    array<vec4> accents = {grade, muted, muted, gold, cyan};
    array<vec4> valueColors = {grade, white, white, gold, cyan};
    RenderHistoryTiles(captions, values, accents, valueColors);
}

// Rated grades of one run in their HUD colours, e.g. "S+1 S4 A2  2 missed".
void RenderGradeTally(RunRecord@ run) {
    array<string> labels = {"S+", "S", "A", "B", "C", "D"};
    bool first = true;
    for (uint g = 0; g < labels.Length; g++) {
        int count = 0;
        for (uint j = 0; j < run.jumps.Length; j++)
            if (run.jumps[j].label == labels[g]) count++;
        if (count == 0) continue;
        if (!first) UI::SameLine(0, 6);
        UI::PushStyleColor(UI::Col::Text, GradeColor(labels[g]));
        UI::Text(labels[g] + count);
        UI::PopStyleColor();
        first = false;
    }
    if (run.misses > 0) {
        if (!first) UI::SameLine(0, 10);
        UI::PushStyleColor(UI::Col::Text, GradeColor("MISSED"));
        UI::Text("" + run.misses + " missed");
        UI::PopStyleColor();
        first = false;
    }
    if (first) UI::TextDisabled("--");
}

// Gold selection tint for table rows, matching the HUD accent.
void PushHistorySelectionColors() {
    UI::PushStyleColor(UI::Col::Header, HudColor(1.0f, 0.85f, 0.36f, 0.22f));
    UI::PushStyleColor(UI::Col::HeaderHovered, HudColor(1.0f, 0.85f, 0.36f, 0.12f));
    UI::PushStyleColor(UI::Col::HeaderActive, HudColor(1.0f, 0.85f, 0.36f, 0.30f));
}

void RenderHistoryAttempts() {
    RenderHistoryHeader("ATTEMPTS");
    PushHistorySelectionColors();
    UI::BeginChild("attempts", vec2(0, 185), true);
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
                g_historySelectedId == run.id,
                UI::SelectableFlags::SpanAllColumns)) {
                g_historySelectedId = run.id;
                g_historySelectedJump = -1;
            }
            UI::TableNextColumn();
            UI::Text(Time::FormatString("%Y-%m-%d %H:%M", run.startedAt / 1000));
            UI::TableNextColumn();
            UI::PushStyleColor(UI::Col::Text, HistoryStatusColor(run.status));
            UI::Text(run.status == "FINISHED" ?
                "FINISHED " + Time::Format(uint64(run.finishMs)) : "RESET");
            UI::PopStyleColor();
            UI::TableNextColumn();
            UI::Text("" + run.score);
            UI::TableNextColumn();
            RenderGradeTally(run);
        }
        UI::EndTable();
    }
    UI::EndChild();
    UI::PopStyleColor(3);
}

void RenderHistoryJumps(RunRecord@ selected) {
    RenderHistoryHeader("JUMPS  " + selected.jumps.Length);
    PushHistorySelectionColors();
    UI::BeginChild("jumps", vec2(0, 220), true);
    if (selected.jumps.Length == 0) UI::Text("No rated jumps in this run.");
    else if (UI::BeginTable("jumpTable", 6,
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
            UI::Text(HistoryLead(jump));
            UI::TableNextColumn();
            UI::Text("+" + jump.points);
            UI::TableNextColumn();
            UI::Text("x" + jump.combo);
        }
        UI::EndTable();
    }
    UI::EndChild();
    UI::PopStyleColor(3);
    if (g_historySelectedJump < 0 ||
        g_historySelectedJump >= int(selected.jumps.Length)) return;
    HistoryJump@ jump = selected.jumps[uint(g_historySelectedJump)];
    RenderHistoryHeader("JUMP " + (g_historySelectedJump + 1));
    RenderJumpTiles(jump);
    string detail = jump.reason;
    // Only mention the takeoff grade when the landing changed it.
    if (jump.preview.Length > 0 && jump.preview != jump.label)
        detail += "  |  Takeoff " + jump.preview +
            (jump.timingEstimated && jump.preview != "S+" ? "+" : "");
    if (jump.scoreAfter >= 0) detail += "  |  Score after landing " + jump.scoreAfter;
    UI::PushStyleColor(UI::Col::Text, HudColor(0.67f, 0.82f, 0.93f));
    UI::TextWrapped(detail);
    UI::PopStyleColor();
}

void RenderHistoryClear() {
    UI::Dummy(vec2(0, 6));
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
    RenderHistoryHeader("GORILLA GRIP  /  RUN HISTORY", HudColor(1.0f, 0.85f, 0.36f));
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
        RenderHistoryHeader("SELECTED ATTEMPT");
        UI::Font@ nameFont = HistoryFont();
        if (nameFont !is null) UI::PushFont(nameFont);
        UI::PushStyleColor(UI::Col::Text, HudColor(1.0f, 0.86f, 0.37f));
        UI::TextWrapped(selected.mapName);
        UI::PopStyleColor();
        if (nameFont !is null) UI::PopFont();
        UI::TextDisabled(Time::FormatString("%Y-%m-%d %H:%M", selected.startedAt / 1000));
        RenderAttemptTiles(selected);
        RenderHistoryJumps(selected);
    }
    RenderHistoryClear();
    UI::End();
    UI::PopStyleColor(3);
}
