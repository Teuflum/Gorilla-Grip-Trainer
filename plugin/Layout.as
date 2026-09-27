[Setting hidden] float S_DiagX = 0.030f;
[Setting hidden] float S_DiagY = 0.029f;
[Setting hidden] float S_DiagW = 0.258f;
[Setting hidden] float S_DiagH = 0.181f;
[Setting hidden] bool S_DiagVisible = true;
[Setting hidden] bool S_DiagWhenHudOff = false;

// Retain these saved setting keys so existing landing-grade placement carries
// over to the combined grade widget.
[Setting hidden] float S_ResultX = 0.379f;
[Setting hidden] float S_ResultY = 0.800f;
[Setting hidden] float S_ResultW = 0.240f;
[Setting hidden] float S_ResultH = 0.109f;
[Setting hidden] bool S_ResultVisible = true;
[Setting hidden] bool S_ResultWhenHudOff = false;

[Setting hidden] float S_StatsX = 0.030f;
[Setting hidden] float S_StatsY = 0.701f;
[Setting hidden] float S_StatsW = 0.160f;
[Setting hidden] float S_StatsH = 0.130f;
[Setting hidden] bool S_StatsVisible = true;
[Setting hidden] bool S_StatsMigrated = false;

// Retain these saved setting keys so the separate Combo, Score and Best combo
// placement carries over to the combined Stats widget.
[Setting hidden] float S_ComboX = 0.030f;
[Setting hidden] float S_ComboY = 0.590f;
[Setting hidden] float S_ComboW = 0.160f;
[Setting hidden] float S_ComboH = 0.075f;
[Setting hidden] bool S_ComboVisible = true;
[Setting hidden] bool S_ComboWhenHudOff = false;

[Setting hidden] float S_ScoreX = 0.030f;
[Setting hidden] float S_ScoreY = 0.673f;
[Setting hidden] float S_ScoreW = 0.160f;
[Setting hidden] float S_ScoreH = 0.075f;
[Setting hidden] bool S_ScoreVisible = true;
[Setting hidden] bool S_ScoreWhenHudOff = false;

[Setting hidden] float S_BestX = 0.030f;
[Setting hidden] float S_BestY = 0.756f;
[Setting hidden] float S_BestW = 0.160f;
[Setting hidden] float S_BestH = 0.075f;
[Setting hidden] bool S_BestVisible = true;
[Setting hidden] bool S_BestWhenHudOff = false;

[Setting hidden] float S_LastX = 0.030f;
[Setting hidden] float S_LastY = 0.839f;
[Setting hidden] float S_LastW = 0.210f;
[Setting hidden] float S_LastH = 0.094f;
[Setting hidden] bool S_LastVisible = true;
[Setting hidden] bool S_LastWhenHudOff = false;

[Setting hidden] float S_FinishX = 0.670f;
[Setting hidden] float S_FinishY = 0.029f;
[Setting hidden] float S_FinishW = 0.330f;
[Setting hidden] float S_FinishH = 0.329f;
[Setting hidden] bool S_FinishVisible = true;
[Setting hidden] bool S_FinishWhenHudOff = false;
[Setting hidden] bool S_HudVisibilityMigrated = false;

class WidgetLayout {
    string id;
    string title;
    vec4 rect;
    vec4 defaultRect;
    bool visible;
    bool defaultVisible;

    WidgetLayout(const string &in widgetId, const string &in widgetTitle,
        const vec4 &in initialRect, bool initialVisible) {
        id = widgetId;
        title = widgetTitle;
        rect = initialRect;
        defaultRect = initialRect;
        visible = initialVisible;
        defaultVisible = initialVisible;
    }

    void Reset() {
        rect = defaultRect;
        visible = defaultVisible;
    }

    void Clamp() {
        rect.z = Math::Clamp(rect.z, 0.08f, 0.90f);
        rect.w = Math::Clamp(rect.w, 0.045f, 0.80f);
        rect.x = Math::Clamp(rect.x, 0.0f, 1.0f - rect.z);
        rect.y = Math::Clamp(rect.y, 0.0f, 1.0f - rect.w);
    }

    vec4 Pixels() {
        Clamp();
        vec2 screen = Display::GetSize();
        return vec4(rect.x * screen.x, rect.y * screen.y,
            rect.z * screen.x, rect.w * screen.y);
    }
}

array<WidgetLayout@> g_layouts;
bool g_layoutEditing = false;
bool g_forceLayoutPosition = false;

void InitLayout() {
    if (!S_HudVisibilityMigrated) {
        bool show = !S_HideWithUI;
        S_DiagWhenHudOff = show; S_ResultWhenHudOff = show;
        S_ComboWhenHudOff = show; S_ScoreWhenHudOff = show;
        S_BestWhenHudOff = show; S_LastWhenHudOff = show;
        S_FinishWhenHudOff = show;
        S_HudVisibilityMigrated = true;
    }
    if (!S_GlobalHudVisibilityMigrated) {
        S_ShowWhenGameHudOff = S_DiagWhenHudOff || S_ResultWhenHudOff ||
            S_ComboWhenHudOff || S_ScoreWhenHudOff || S_BestWhenHudOff ||
            S_LastWhenHudOff || S_FinishWhenHudOff;
        S_GlobalHudVisibilityMigrated = true;
    }
    if (!S_StatsMigrated) {
        // Keep the old stat column's left edge and width, and end where it
        // ended, so the Stats card still sits above Last run.
        float left = Math::Min(S_ComboX, Math::Min(S_ScoreX, S_BestX));
        float width = Math::Max(S_ComboW, Math::Max(S_ScoreW, S_BestW));
        float bottom = Math::Max(S_ComboY + S_ComboH,
            Math::Max(S_ScoreY + S_ScoreH, S_BestY + S_BestH));
        S_StatsX = left; S_StatsW = width;
        S_StatsY = Math::Max(0.0f, bottom - S_StatsH);
        S_StatsVisible = S_ComboVisible || S_ScoreVisible || S_BestVisible;
        S_StatsMigrated = true;
    }
    g_layouts.RemoveRange(0, g_layouts.Length);
    g_layouts.InsertLast(WidgetLayout("diagnostics", "Physics", vec4(0.030f, 0.029f, 0.258f, 0.181f), true));
    g_layouts.InsertLast(WidgetLayout("grade", "Grade", vec4(0.379f, 0.800f, 0.240f, 0.109f), true));
    g_layouts.InsertLast(WidgetLayout("stats", "Stats", vec4(0.030f, 0.701f, 0.160f, 0.130f), true));
    g_layouts.InsertLast(WidgetLayout("last", "Last run", vec4(0.030f, 0.839f, 0.210f, 0.094f), true));
    g_layouts.InsertLast(WidgetLayout("finish", "Finish summary", vec4(0.670f, 0.029f, 0.330f, 0.329f), true));
    LoadLayoutSettings();
}

WidgetLayout@ GetLayout(const string &in id) {
    for (uint i = 0; i < g_layouts.Length; i++)
        if (g_layouts[i].id == id) return g_layouts[i];
    return null;
}

void LoadLayoutSettings() {
    array<vec4> saved = {
        vec4(S_DiagX, S_DiagY, S_DiagW, S_DiagH),
        vec4(S_ResultX, S_ResultY, S_ResultW, S_ResultH),
        vec4(S_StatsX, S_StatsY, S_StatsW, S_StatsH),
        vec4(S_LastX, S_LastY, S_LastW, S_LastH),
        vec4(S_FinishX, S_FinishY, S_FinishW, S_FinishH)
    };
    array<bool> shown = {S_DiagVisible, S_ResultVisible, S_StatsVisible,
        S_LastVisible, S_FinishVisible};
    for (uint i = 0; i < g_layouts.Length; i++) {
        g_layouts[i].rect = saved[i];
        g_layouts[i].visible = shown[i];
        g_layouts[i].Clamp();
    }
}

void SaveLayoutSettings() {
    for (uint i = 0; i < g_layouts.Length; i++) g_layouts[i].Clamp();
    vec4 a = g_layouts[0].rect;
    S_DiagX = a.x; S_DiagY = a.y; S_DiagW = a.z; S_DiagH = a.w;
    S_DiagVisible = g_layouts[0].visible;
    a = g_layouts[1].rect;
    S_ResultX = a.x; S_ResultY = a.y; S_ResultW = a.z; S_ResultH = a.w;
    S_ResultVisible = g_layouts[1].visible;
    a = g_layouts[2].rect;
    S_StatsX = a.x; S_StatsY = a.y; S_StatsW = a.z; S_StatsH = a.w;
    S_StatsVisible = g_layouts[2].visible;
    a = g_layouts[3].rect;
    S_LastX = a.x; S_LastY = a.y; S_LastW = a.z; S_LastH = a.w;
    S_LastVisible = g_layouts[3].visible;
    a = g_layouts[4].rect;
    S_FinishX = a.x; S_FinishY = a.y; S_FinishW = a.z; S_FinishH = a.w;
    S_FinishVisible = g_layouts[4].visible;
}

[SettingsTab name="Layout" icon="" order="4"]
void RenderSettingsLayout() {
    g_layoutEditing = true;
    if (UI::Button("Reset all widgets")) {
        for (uint i = 0; i < g_layouts.Length; i++) g_layouts[i].Reset();
        g_forceLayoutPosition = true;
    }
    for (uint i = 0; i < g_layouts.Length; i++) {
        auto widget = g_layouts[i];
        UI::PushID(widget.id);
        if (!UI::CollapsingHeader(widget.title)) {
            UI::PopID();
            continue;
        }
        UI::Indent(12.0f);
        widget.visible = UI::Checkbox("Show", widget.visible);
        UI::SameLine();
        if (UI::Button("Reset widget")) {
            widget.Reset();
            g_forceLayoutPosition = true;
        }
        vec2 pos = UI::InputFloat2("Position X/Y (%)",
            vec2(widget.rect.x * 100.0f, widget.rect.y * 100.0f), "%.1f");
        vec2 size = UI::InputFloat2("Width/height (%)",
            vec2(widget.rect.z * 100.0f, widget.rect.w * 100.0f), "%.1f");
        if (Math::Abs(pos.x - widget.rect.x*100.0f) > 0.001f ||
            Math::Abs(pos.y - widget.rect.y*100.0f) > 0.001f ||
            Math::Abs(size.x - widget.rect.z*100.0f) > 0.001f ||
            Math::Abs(size.y - widget.rect.w*100.0f) > 0.001f) {
            widget.rect = vec4(pos.x/100.0f, pos.y/100.0f,
                size.x/100.0f, size.y/100.0f);
            widget.Clamp();
            g_forceLayoutPosition = true;
        }
        UI::Unindent(12.0f);
        UI::PopID();
    }
    SaveLayoutSettings();
}

void RenderLayoutEditor() {
    if (!g_layoutEditing) return;
    vec2 screen = Display::GetSize();
    float scale = UI::GetScale();
    for (uint i = 0; i < g_layouts.Length; i++) {
        auto widget = g_layouts[i];
        if (!widget.visible) continue;
        vec4 r = widget.Pixels();
        UI::Cond condition = g_forceLayoutPosition ? UI::Cond::Always : UI::Cond::Appearing;
        UI::SetNextWindowPos(int(r.x / scale), int(r.y / scale), condition);
        UI::SetNextWindowSize(int(r.z / scale), int(r.w / scale), condition);
        UI::Begin("Move " + widget.title + "##" + widget.id,
            UI::WindowFlags::NoCollapse | UI::WindowFlags::NoSavedSettings);
        UI::Text("Drag title to move; drag corner to resize");
        vec2 pos = UI::GetWindowPos() * scale;
        vec2 size = UI::GetWindowSize() * scale;
        widget.rect = vec4(pos.x / screen.x, pos.y / screen.y,
            size.x / screen.x, size.y / screen.y);
        widget.Clamp();
        UI::End();
    }
    SaveLayoutSettings();
    g_forceLayoutPosition = false;
    g_layoutEditing = false;
}
