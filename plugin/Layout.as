// Widget rectangles as screen fractions: x, y, width, height.
[Setting hidden] vec4 S_DiagnosticsRect = vec4(0.030f, 0.029f, 0.258f, 0.181f);
[Setting hidden] [SettingAlias key="S_DiagVisible"] bool S_DiagnosticsVisible = true;
[Setting hidden] vec4 S_GradeRect = vec4(0.379f, 0.800f, 0.240f, 0.109f);
[Setting hidden] [SettingAlias key="S_ResultVisible"] bool S_GradeVisible = true;
[Setting hidden] vec4 S_StatsRect = vec4(0.030f, 0.701f, 0.160f, 0.130f);
[Setting hidden] bool S_StatsVisible = true;
[Setting hidden] vec4 S_LastRect = vec4(0.030f, 0.839f, 0.210f, 0.094f);
[Setting hidden] bool S_LastVisible = true;
[Setting hidden] vec4 S_FinishRect = vec4(0.670f, 0.029f, 0.330f, 0.329f);
[Setting hidden] bool S_FinishVisible = true;

vec4 ClampRect(const vec4 &in r) {
    float w = Math::Clamp(r.z, 0.08f, 0.90f);
    float h = Math::Clamp(r.w, 0.045f, 0.80f);
    return vec4(Math::Clamp(r.x, 0.0f, 1.0f - w), Math::Clamp(r.y, 0.0f, 1.0f - h), w, h);
}

// A HUD widget's place and visibility, kept in its two settings.
class WidgetLayout {
    string id;
    string title;
    Meta::PluginSetting@ rectSetting;
    Meta::PluginSetting@ visibleSetting;

    WidgetLayout(const string &in widgetId, const string &in widgetTitle,
        const string &in settingPrefix) {
        id = widgetId;
        title = widgetTitle;
        auto plugin = Meta::ExecutingPlugin();
        @rectSetting = plugin.GetSetting(settingPrefix + "Rect");
        @visibleSetting = plugin.GetSetting(settingPrefix + "Visible");
    }

    vec4 Rect() { return ClampRect(rectSetting.ReadVec4()); }
    void SetRect(const vec4 &in r) { rectSetting.WriteVec4(ClampRect(r)); }
    bool Visible() { return visibleSetting.ReadBool(); }
    void SetVisible(bool visible) { visibleSetting.WriteBool(visible); }

    void Reset() {
        rectSetting.Reset();
        visibleSetting.Reset();
    }

    vec4 Pixels() {
        vec4 r = Rect();
        vec2 screen = Display::GetSize();
        return vec4(r.x * screen.x, r.y * screen.y, r.z * screen.x, r.w * screen.y);
    }
}

array<WidgetLayout@> g_layouts;
bool g_layoutEditing = false;
bool g_forceLayoutPosition = false;

void InitLayout() {
    g_layouts.RemoveRange(0, g_layouts.Length);
    g_layouts.InsertLast(WidgetLayout("diagnostics", "Physics", "S_Diagnostics"));
    g_layouts.InsertLast(WidgetLayout("grade", "Grade", "S_Grade"));
    g_layouts.InsertLast(WidgetLayout("stats", "Stats", "S_Stats"));
    g_layouts.InsertLast(WidgetLayout("last", "Last run", "S_Last"));
    g_layouts.InsertLast(WidgetLayout("finish", "Finish summary", "S_Finish"));
}

WidgetLayout@ GetLayout(const string &in id) {
    for (uint i = 0; i < g_layouts.Length; i++)
        if (g_layouts[i].id == id) return g_layouts[i];
    return null;
}

// While this tab is open, RenderLayoutEditor gives every widget a window to
// drag and resize.
[SettingsTab name="Layout" icon="" order="4"]
void RenderSettingsLayout() {
    g_layoutEditing = true;
    UI::TextWrapped("While this tab is open, drag a widget's window by its title to move it, and its corner to resize it.");
    if (UI::Button("Reset all widgets")) {
        for (uint i = 0; i < g_layouts.Length; i++) g_layouts[i].Reset();
        g_forceLayoutPosition = true;
    }
    for (uint i = 0; i < g_layouts.Length; i++) {
        auto widget = g_layouts[i];
        UI::PushID(widget.id);
        if (UI::CollapsingHeader(widget.title)) {
            UI::Indent(12.0f);
            widget.SetVisible(UI::Checkbox("Show", widget.Visible()));
            UI::SameLine();
            if (UI::Button("Reset widget")) {
                widget.Reset();
                g_forceLayoutPosition = true;
            }
            vec4 r = widget.Rect();
            vec2 pos = UI::InputFloat2("Position X/Y (%)", vec2(r.x, r.y) * 100.0f, "%.1f");
            vec2 size = UI::InputFloat2("Width/height (%)", vec2(r.z, r.w) * 100.0f, "%.1f");
            if (Math::Abs(pos.x - r.x*100.0f) > 0.001f || Math::Abs(pos.y - r.y*100.0f) > 0.001f ||
                Math::Abs(size.x - r.z*100.0f) > 0.001f || Math::Abs(size.y - r.w*100.0f) > 0.001f) {
                widget.SetRect(vec4(pos.x, pos.y, size.x, size.y) * 0.01f);
                g_forceLayoutPosition = true;
            }
            UI::Unindent(12.0f);
        }
        UI::PopID();
    }
}

void RenderLayoutEditor() {
    if (!g_layoutEditing) return;
    vec2 screen = Display::GetSize();
    float scale = UI::GetScale();
    UI::Cond condition = g_forceLayoutPosition ? UI::Cond::Always : UI::Cond::Appearing;
    for (uint i = 0; i < g_layouts.Length; i++) {
        auto widget = g_layouts[i];
        if (!widget.Visible()) continue;
        vec4 r = widget.Pixels();
        UI::SetNextWindowPos(int(r.x / scale), int(r.y / scale), condition);
        UI::SetNextWindowSize(int(r.z / scale), int(r.w / scale), condition);
        UI::Begin("Move " + widget.title + "##" + widget.id,
            UI::WindowFlags::NoCollapse | UI::WindowFlags::NoSavedSettings);
        UI::Text("Drag title to move; drag corner to resize");
        vec2 pos = UI::GetWindowPos() * scale;
        vec2 size = UI::GetWindowSize() * scale;
        widget.SetRect(vec4(pos.x / screen.x, pos.y / screen.y,
            size.x / screen.x, size.y / screen.y));
        UI::End();
    }
    g_forceLayoutPosition = false;
    g_layoutEditing = false;
}
