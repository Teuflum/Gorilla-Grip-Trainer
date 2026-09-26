[Setting hidden] float S_DiagX = 0.38f;
[Setting hidden] float S_DiagY = 0.67f;
[Setting hidden] float S_DiagW = 0.24f;
[Setting hidden] float S_DiagH = 0.21f;
[Setting hidden] bool S_DiagVisible = true;

// Retain these saved setting keys so existing landing-grade placement carries
// over to the combined grade widget.
[Setting hidden] float S_ResultX = 0.38f;
[Setting hidden] float S_ResultY = 0.48f;
[Setting hidden] float S_ResultW = 0.24f;
[Setting hidden] float S_ResultH = 0.11f;
[Setting hidden] bool S_ResultVisible = true;

[Setting hidden] float S_ComboX = 0.81f;
[Setting hidden] float S_ComboY = 0.62f;
[Setting hidden] float S_ComboW = 0.16f;
[Setting hidden] float S_ComboH = 0.075f;
[Setting hidden] bool S_ComboVisible = true;

[Setting hidden] float S_ScoreX = 0.81f;
[Setting hidden] float S_ScoreY = 0.71f;
[Setting hidden] float S_ScoreW = 0.16f;
[Setting hidden] float S_ScoreH = 0.075f;
[Setting hidden] bool S_ScoreVisible = true;

[Setting hidden] float S_BestX = 0.81f;
[Setting hidden] float S_BestY = 0.80f;
[Setting hidden] float S_BestW = 0.16f;
[Setting hidden] float S_BestH = 0.075f;
[Setting hidden] bool S_BestVisible = true;

[Setting hidden] float S_LastX = 0.03f;
[Setting hidden] float S_LastY = 0.84f;
[Setting hidden] float S_LastW = 0.21f;
[Setting hidden] float S_LastH = 0.095f;
[Setting hidden] bool S_LastVisible = true;

[Setting hidden] float S_FinishX = 0.65f;
[Setting hidden] float S_FinishY = 0.14f;
[Setting hidden] float S_FinishW = 0.31f;
[Setting hidden] float S_FinishH = 0.34f;
[Setting hidden] bool S_FinishVisible = true;

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
    g_layouts.RemoveRange(0, g_layouts.Length);
    g_layouts.InsertLast(WidgetLayout("diagnostics", "Physics", vec4(0.38f, 0.67f, 0.24f, 0.21f), true));
    g_layouts.InsertLast(WidgetLayout("grade", "Grade", vec4(0.38f, 0.48f, 0.24f, 0.11f), true));
    g_layouts.InsertLast(WidgetLayout("combo", "Combo", vec4(0.81f, 0.62f, 0.16f, 0.075f), true));
    g_layouts.InsertLast(WidgetLayout("score", "Score", vec4(0.81f, 0.71f, 0.16f, 0.075f), true));
    g_layouts.InsertLast(WidgetLayout("best", "Best combo", vec4(0.81f, 0.80f, 0.16f, 0.075f), true));
    g_layouts.InsertLast(WidgetLayout("last", "Last run", vec4(0.03f, 0.84f, 0.21f, 0.095f), true));
    g_layouts.InsertLast(WidgetLayout("finish", "Finish summary", vec4(0.65f, 0.14f, 0.31f, 0.34f), true));
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
        vec4(S_ComboX, S_ComboY, S_ComboW, S_ComboH),
        vec4(S_ScoreX, S_ScoreY, S_ScoreW, S_ScoreH),
        vec4(S_BestX, S_BestY, S_BestW, S_BestH),
        vec4(S_LastX, S_LastY, S_LastW, S_LastH),
        vec4(S_FinishX, S_FinishY, S_FinishW, S_FinishH)
    };
    array<bool> shown = {S_DiagVisible, S_ResultVisible,
        S_ComboVisible, S_ScoreVisible, S_BestVisible, S_LastVisible,
        S_FinishVisible};
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
    S_ComboX = a.x; S_ComboY = a.y; S_ComboW = a.z; S_ComboH = a.w;
    S_ComboVisible = g_layouts[2].visible;
    a = g_layouts[3].rect;
    S_ScoreX = a.x; S_ScoreY = a.y; S_ScoreW = a.z; S_ScoreH = a.w;
    S_ScoreVisible = g_layouts[3].visible;
    a = g_layouts[4].rect;
    S_BestX = a.x; S_BestY = a.y; S_BestW = a.z; S_BestH = a.w;
    S_BestVisible = g_layouts[4].visible;
    a = g_layouts[5].rect;
    S_LastX = a.x; S_LastY = a.y; S_LastW = a.z; S_LastH = a.w;
    S_LastVisible = g_layouts[5].visible;
    a = g_layouts[6].rect;
    S_FinishX = a.x; S_FinishY = a.y; S_FinishW = a.z; S_FinishH = a.w;
    S_FinishVisible = g_layouts[6].visible;
}

[SettingsTab name="Layout"]
void RenderSettingsLayout() {
    g_layoutEditing = true;
    UI::TextWrapped("Drag and resize the labeled boxes on the game screen. Their positions and sizes save automatically.");
    for (uint i = 0; i < g_layouts.Length; i++) {
        auto widget = g_layouts[i];
        UI::PushID(widget.id);
        UI::SeparatorText(widget.title);
        widget.visible = UI::Checkbox("Show", widget.visible);
        UI::SameLine();
        if (UI::Button("Reset")) {
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
        vec4 pixels = widget.Pixels();
        UI::Text("Pixels: " + int(pixels.x) + ", " + int(pixels.y) +
            "  /  " + int(pixels.z) + " x " + int(pixels.w));
        UI::PopID();
    }
    if (UI::Button("Reset all positions and sizes")) {
        for (uint i = 0; i < g_layouts.Length; i++) g_layouts[i].Reset();
        g_forceLayoutPosition = true;
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
