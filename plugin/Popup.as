// The landing popup: the grade on a panel in the widget box colours, with the
// result's pictures. The grade drops in, a miss sinks and tips over, and S and
// S+ pictures bounce.
[Setting hidden name="Popup animation"]
bool S_PopupAnimate = true;

// Without animation the popup shows from the start as it looks at this age.
const int SETTLED_AGE = 600;

float EaseOutCubic(float x) {
    float r = 1.0f - Math::Clamp(x, 0.0f, 1.0f);
    return 1.0f - r*r*r;
}

// Overshoots slightly past 1 before settling; 0 at x <= 0.
float EaseOutBack(float x) {
    float m = Math::Clamp(x, 0.0f, 1.0f) - 1.0f;
    return 1.0f + 2.9f*m*m*m + 1.9f*m*m;
}

void StartPopupPreview(Grade grade) {
    @g_result = ShownResult();
    g_result.grade = grade;
    g_result.caption = GradeCaption(grade);
    g_result.preview = true;
}

class PopupFrame {
    Grade grade;
    string caption;
    int age;
    float s;
    float cx;
    float cy;
    float fade;
    bool miss;
    vec4 accent;
    float panelW;
    // How far a MISSED panel has sunk.
    float slump = 0.0f;
}

void RenderResult(const vec4 &in r, int age, Grade grade, const string &in caption) {
    if (grade == Grade::None) return;
    PopupFrame@ f = PopupFrame();
    f.grade = grade;
    f.caption = caption;
    f.age = S_PopupAnimate ? age : Math::Max(age, SETTLED_AGE);
    f.s = Math::Min(r.z / 500.0f, r.w / 125.0f);
    f.cx = r.x + r.z*0.5f;
    f.cy = r.y + r.w*0.5f;
    f.fade = 1.0f - Math::Clamp(float(age - 700) / 300.0f, 0.0f, 1.0f);
    f.miss = grade == Grade::Missed;
    f.accent = GradeColor(grade, f.fade);
    f.panelW = (180.0f + 300.0f*EaseOutCubic(float(f.age) / 180.0f))*f.s;
    if (f.miss) f.slump = 10.0f*f.s*EaseOutCubic((float(f.age) - 250.0f) / 350.0f);
    DrawPopupPanel(f);
    DrawPopupPictures(f);
    DrawPopupLetter(f);
    DrawPopupCaption(f);
}

void DrawPopupPanel(PopupFrame@ f) {
    nvg::Save();
    nvg::GlobalAlpha(f.fade);
    Hud::Panel(vec4(f.cx - f.panelW*0.5f, f.cy + f.slump - 52.0f*f.s, f.panelW, 105.0f*f.s));
    nvg::Restore();
}

void DrawPopupText(PopupFrame@ f, float x, float y, float scale, float rot,
    const vec4 &in colour, float blur) {
    float size = (f.miss ? 43.0f : 54.0f)*f.s;
    nvg::Save();
    nvg::Translate(x, y);
    nvg::Rotate(rot);
    nvg::Scale(scale, scale);
    nvg::FontBlur(blur);
    Hud::Text(0, 0, GradeName(f.grade), size, colour, nvg::Align::Center | nvg::Align::Middle);
    nvg::Restore();
}

// The grade drops in from a larger size; a hit warms from ice white to its
// colour, a miss tips over.
void DrawPopupLetter(PopupFrame@ f) {
    float age = float(f.age);
    float x = f.cx;
    float y = f.cy - 8.0f*f.s;
    float scale = 1.0f + 0.9f*(1.0f - EaseOutBack(age / 260.0f));
    float rot = 0.0f;
    vec4 colour = f.accent;
    if (f.miss) {
        float slump = EaseOutCubic((age - 250.0f) / 350.0f);
        y += 14.0f*f.s*slump;
        rot = 0.12f*slump;
    } else {
        float warm = Math::Clamp((age - 120.0f) / 300.0f, 0.0f, 1.0f);
        colour = Math::Lerp(vec4(0.84f, 0.95f, 1.0f, f.fade), f.accent, warm);
        DrawPopupText(f, x, y, scale, rot,
            vec4(0.78f, 0.93f, 1.0f, 0.8f*(1.0f - warm)*f.fade), 12.0f*f.s);
    }
    DrawPopupText(f, x, y, scale, rot, colour, 0.0f);
}

// Keeps the picture's aspect ratio inside a size-by-size square.
void DrawPictureTexture(nvg::Texture@ texture, float x, float y, float size,
    float angle, float alpha) {
    vec2 dims = texture.GetSize();
    if (!HasArea(dims)) return;
    float aspect = dims.x / dims.y;
    float w = size*Math::Min(1.0f, aspect);
    float h = size*Math::Min(1.0f, 1.0f / aspect);
    nvg::Save();
    nvg::Translate(x, y);
    nvg::Rotate(angle);
    nvg::BeginPath();
    nvg::Rect(-w*0.5f, -h*0.5f, w, h);
    nvg::FillPaint(nvg::TexturePattern(vec2(-w*0.5f, -h*0.5f), vec2(w, h),
        0.0f, texture, alpha));
    nvg::Fill();
    nvg::Restore();
}

// The result's picture on both sides of the panel; S and S+ pictures bounce.
void DrawPopupPictures(PopupFrame@ f) {
    nvg::Texture@ picture = PictureForResult(f.grade);
    if (picture is null) return;
    bool dance = S_PopupAnimate && (f.grade == Grade::S || f.grade == Grade::SPlus);
    float age = float(f.age);
    for (int i = 0; i < 2; i++) {
        float side = i == 0 ? -1.0f : 1.0f;
        float delay = 60.0f + 40.0f*float(i);
        float size = 72.0f*f.s*EaseOutBack((age - delay) / 300.0f);
        float alpha = f.fade*Math::Clamp((age - delay) / 100.0f, 0.0f, 1.0f);
        float x = f.cx + side*150.0f*f.s;
        float y = f.cy + f.slump;
        float tilt = 0.0f;
        if (dance) {
            float wave = Math::Sin(age*0.012f + float(i)*1.8f);
            y -= Math::Abs(wave)*12.0f*f.s;
            tilt = wave*0.18f*side;
        }
        if (size > 1.0f && alpha > 0.0f)
            DrawPictureTexture(picture, x, y, size, tilt, alpha);
    }
}

void DrawPopupCaption(PopupFrame@ f) {
    float alpha = f.fade*Math::Clamp(float(f.age - 120) / 200.0f, 0.0f, 1.0f);
    if (alpha <= 0.0f) return;
    vec4 text = Hud::TextColor();
    Hud::Text(f.cx, f.cy + f.slump + 28.0f*f.s, f.caption, 13.0f*f.s,
        Hud::WithAlpha(text, text.w*alpha), nvg::Align::Center | nvg::Align::Middle);
}
