// Widget rectangles as screen fractions: x, y, width, height.
[Setting hidden] vec4 S_DiagnosticsRect = vec4(0.030f, 0.029f, 0.258f, 0.181f);
[Setting hidden] [SettingAlias key="S_DiagVisible"] bool S_DiagnosticsVisible = false;
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
    string title;
    string settingPrefix;
    Meta::PluginSetting@ rectSetting;
    Meta::PluginSetting@ visibleSetting;

    WidgetLayout(const string &in widgetTitle, const string &in prefix) {
        title = widgetTitle;
        settingPrefix = prefix;
        auto plugin = Meta::ExecutingPlugin();
        @rectSetting = plugin.GetSetting(prefix + "Rect");
        @visibleSetting = plugin.GetSetting(prefix + "Visible");
    }

    vec4 Rect() { return ClampRect(rectSetting.ReadVec4()); }
    void SetRect(const vec4 &in r) { rectSetting.WriteVec4(ClampRect(r)); }
    bool Visible() { return visibleSetting.ReadBool(); }

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
WidgetLayout@ g_physicsLayout;
WidgetLayout@ g_gradeLayout;
WidgetLayout@ g_statsLayout;
WidgetLayout@ g_lastLayout;
WidgetLayout@ g_finishLayout;
bool g_layoutEditing = false;
bool g_forceLayoutPosition = false;

WidgetLayout@ AddLayout(const string &in title, const string &in settingPrefix) {
    WidgetLayout@ layout = WidgetLayout(title, settingPrefix);
    g_layouts.InsertLast(layout);
    return layout;
}

void InitLayout() {
    @g_physicsLayout = AddLayout("Physics", "S_Diagnostics");
    @g_gradeLayout = AddLayout("Grade", "S_Grade");
    @g_statsLayout = AddLayout("Stats", "S_Stats");
    @g_lastLayout = AddLayout("Last run", "S_Last");
    @g_finishLayout = AddLayout("Finish", "S_Finish");
}

// While this tab is open, RenderLayoutEditor gives every widget a window to
// drag and resize.
[SettingsTab name="Layout" icon="" order="5"]
void RenderSettingsLayout() {
    g_layoutEditing = true;
    UI::TextWrapped("While this tab is open, you can drag the widgets around and resize them.");
    if (UI::Button("Reset to default")) {
        for (uint i = 0; i < g_layouts.Length; i++) g_layouts[i].Reset();
        g_forceLayoutPosition = true;
    }
    if (!UI::BeginTable("widgets", 4)) return;
    UI::TableSetupColumn("Widget", UI::TableColumnFlags::WidthStretch);
    UI::TableSetupColumn("Show", UI::TableColumnFlags::WidthFixed, 40);
    UI::TableSetupColumn("Position (%)", UI::TableColumnFlags::WidthFixed, 130);
    UI::TableSetupColumn("Size (%)", UI::TableColumnFlags::WidthFixed, 130);
    UI::TableHeadersRow();
    for (uint i = 0; i < g_layouts.Length; i++) {
        auto widget = g_layouts[i];
        UI::PushID(widget.settingPrefix);
        UI::TableNextColumn();
        UI::AlignTextToFramePadding();
        UI::Text(widget.title);
        UI::TableNextColumn();
        widget.visibleSetting.WriteBool(UI::Checkbox("##show", widget.Visible()));
        vec4 r = widget.Rect() * 100.0f;
        UI::TableNextColumn();
        UI::SetNextItemWidth(-1);
        vec2 pos = UI::InputFloat2("##position", vec2(r.x, r.y), "%.1f");
        UI::TableNextColumn();
        UI::SetNextItemWidth(-1);
        vec2 size = UI::InputFloat2("##size", vec2(r.z, r.w), "%.1f");
        if (Math::Abs(pos.x - r.x) + Math::Abs(pos.y - r.y) +
            Math::Abs(size.x - r.z) + Math::Abs(size.y - r.w) > 0.001f) {
            widget.SetRect(vec4(pos.x, pos.y, size.x, size.y) * 0.01f);
            g_forceLayoutPosition = true;
        }
        UI::PopID();
    }
    UI::EndTable();
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
        UI::Begin(Icons::ArrowsAlt + " " + widget.title + "##" + widget.settingPrefix,
            UI::WindowFlags::NoCollapse | UI::WindowFlags::NoSavedSettings);
        vec2 pos = UI::GetWindowPos() * scale;
        vec2 size = UI::GetWindowSize() * scale;
        widget.SetRect(vec4(pos.x / screen.x, pos.y / screen.y,
            size.x / screen.x, size.y / screen.y));
        UI::End();
    }
    g_forceLayoutPosition = false;
    g_layoutEditing = false;
}
