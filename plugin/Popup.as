// The landing popup: an ice panel with the grade, cracks, shards and the
// result's pictures. Better grades get bigger effects; UNRATED is calm.
[Setting hidden name="Popup animation"]
bool S_PopupAnimate = true;
[Setting hidden name="Effect intensity (%)" min=0 max=200]
int S_PopupIntensity = 100;
[Setting hidden name="Cracks"]
bool S_FxCracks = true;
[Setting hidden name="Ice shards"]
bool S_FxShards = true;
[Setting hidden name="Snowflakes (S, S+)"]
bool S_FxSnowflakes = true;
[Setting hidden name="Light rays (S+)"]
bool S_FxRays = true;
[Setting hidden name="Flash"]
bool S_FxFlash = true;

array<string> g_effectSettings = {"S_PopupIntensity", "S_FxCracks", "S_FxShards",
    "S_FxSnowflakes", "S_FxRays", "S_FxFlash"};

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
    // The same seed gives the same cracks and shards on every frame.
    uint seed;
    float s;
    float cx;
    float cy;
    float fade;
    float power;
    bool calm;
    bool miss;
    vec4 accent;
    float panelW;
    // How far a MISSED panel has sunk.
    float slump = 0.0f;
}

void RenderResult(const vec4 &in r, int age, Grade grade, const string &in caption,
    uint seed) {
    if (grade == Grade::None) return;
    PopupFrame@ f = PopupFrame();
    f.grade = grade;
    f.caption = caption;
    f.age = S_PopupAnimate ? age : Math::Max(age, SETTLED_AGE);
    f.seed = seed;
    f.s = Math::Min(r.z / 500.0f, r.w / 125.0f);
    f.cx = r.x + r.z*0.5f;
    f.cy = r.y + r.w*0.5f;
    f.fade = 1.0f - Math::Clamp(float(age - 700) / 300.0f, 0.0f, 1.0f);
    f.power = GradePower(grade) * float(Math::Clamp(S_PopupIntensity, 0, 200)) / 100.0f;
    f.calm = !S_PopupAnimate || f.power <= 0.0f;
    f.miss = grade == Grade::Missed;
    f.accent = GradeColor(grade, f.fade);
    f.panelW = (180.0f + 300.0f*EaseOutCubic(float(f.age) / 180.0f))*f.s;
    if (f.miss) f.slump = 10.0f*f.s*EaseOutCubic((float(f.age) - 250.0f) / 350.0f);
    bool top = grade == Grade::SPlus || grade == Grade::S;
    if (!f.calm && S_FxRays && grade == Grade::SPlus) DrawPopupRays(f);
    DrawPopupPanel(f);
    if (!f.calm && S_FxCracks) DrawPopupCracks(f);
    DrawPopupPictures(f);
    if (!f.calm && S_FxShards) DrawPopupShards(f);
    if (!f.calm && S_FxSnowflakes && top) DrawPopupSnowflakes(f);
    DrawPopupLetter(f);
    if (!f.calm && S_FxFlash) DrawPopupFlash(f);
    DrawPopupCaption(f);
}

void DrawPopupPanel(PopupFrame@ f) {
    float s = f.s;
    float x = f.cx - f.panelW*0.5f;
    float y = f.cy + f.slump - 52.0f*s;
    Hud::Box(x, y + 5*s, f.panelW, 105*s, 16*s, vec4(0, 0, 0, 0.35f*f.fade));
    Hud::Box(x, y, f.panelW, 105*s, 16*s, Hud::WithAlpha(Hud::Card, 0.93f*f.fade));
    // A thin grade-coloured border that follows the rounded corners.
    nvg::BeginPath();
    nvg::RoundedRect(x, y, f.panelW, 105*s, 16*s);
    nvg::StrokeWidth(1.5f*s);
    nvg::StrokeColor(Hud::WithAlpha(f.accent, 0.45f*f.fade));
    nvg::Stroke();
}

void DrawPopupFlash(PopupFrame@ f) {
    const float duration = 110.0f;
    if (float(f.age) >= duration) return;
    float alpha = 0.6f*(1.0f - float(f.age)/duration)*f.fade;
    Hud::Box(f.cx - f.panelW*0.5f, f.cy + f.slump - 52.0f*f.s,
        f.panelW, 105.0f*f.s, 16.0f*f.s, vec4(0.82f, 0.94f, 1.0f, alpha));
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

void DrawPopupRays(PopupFrame@ f) {
    float alpha = 0.12f*f.fade*EaseOutCubic(float(f.age - 150) / 300.0f);
    if (alpha <= 0.0f) return;
    nvg::Save();
    nvg::Translate(f.cx, f.cy);
    nvg::Rotate(float(f.age)*0.0012f);
    nvg::FillColor(Hud::WithAlpha(Hud::Gold, alpha));
    for (int i = 0; i < 12; i++) {
        nvg::Rotate(Math::PI*2.0f/12.0f);
        nvg::BeginPath();
        nvg::MoveTo(vec2(0, 0));
        nvg::LineTo(vec2(320.0f*f.s, -18.0f*f.s));
        nvg::LineTo(vec2(320.0f*f.s, 18.0f*f.s));
        nvg::ClosePath();
        nvg::Fill();
    }
    nvg::Restore();
}

void DrawPopupCracks(PopupFrame@ f) {
    float alpha = 0.7f*f.fade*(1.0f - Math::Clamp(float(f.age - 350) / 400.0f, 0.0f, 1.0f));
    if (alpha <= 0.0f) return;
    float grow = EaseOutCubic(float(f.age) / 220.0f);
    Math::Randomizer rng(uint64(f.seed) + 99);
    int count = int(4.0f + 8.0f*f.power);
    nvg::StrokeWidth(1.4f*f.s);
    nvg::StrokeColor(vec4(0.82f, 0.94f, 1.0f, alpha));
    for (int i = 0; i < count; i++) {
        float angle = rng.Float()*Math::PI*2.0f;
        float step = grow*(60.0f + 90.0f*rng.Float())*f.s/4.0f;
        // Start outside the letter so the grade stays readable.
        vec2 p = vec2(f.cx + Math::Cos(angle)*40.0f*f.s,
            f.cy - 8.0f*f.s + Math::Sin(angle)*40.0f*f.s*0.55f);
        nvg::BeginPath();
        nvg::MoveTo(p);
        for (int j = 0; j < 4; j++) {
            angle += (rng.Float() - 0.5f)*0.9f;
            p += vec2(Math::Cos(angle)*step, Math::Sin(angle)*step*0.55f);
            nvg::LineTo(p);
        }
        nvg::Stroke();
    }
}

void DrawPopupShards(PopupFrame@ f) {
    float t = float(f.age) / 1000.0f;
    if (t >= 0.8f) return;
    float alpha = 0.55f*(1.0f - t/0.8f)*f.fade;
    float gravity = f.miss ? 300.0f : 120.0f;
    vec4 colour = f.miss ? vec4(0.55f, 0.6f, 0.66f, alpha) : vec4(0.62f, 0.85f, 1.0f, alpha);
    Math::Randomizer rng(uint64(f.seed) + 13);
    int count = int(6.0f + 34.0f*f.power + 0.5f);
    for (int i = 0; i < count; i++) {
        float angle = rng.Float()*Math::PI*2.0f;
        float distance = (120.0f + 320.0f*f.power*rng.Float())*t*1.1f*f.s;
        float size = (6.0f + 6.0f*rng.Float())*f.s;
        float rot = rng.Float()*6.0f;
        float spin = (rng.Float() - 0.5f)*12.0f;
        vec2 p = vec2(f.cx + Math::Cos(angle)*distance*1.3f,
            f.cy + Math::Sin(angle)*distance*0.6f + gravity*t*t*f.s);
        nvg::Save();
        nvg::Translate(p);
        nvg::Rotate(rot + spin*t);
        nvg::BeginPath();
        nvg::MoveTo(vec2(0, -size));
        nvg::LineTo(vec2(size*0.6f, size*0.7f));
        nvg::LineTo(vec2(-size*0.5f, size*0.5f));
        nvg::ClosePath();
        nvg::FillColor(colour);
        nvg::Fill();
        nvg::Restore();
    }
}

void DrawSnowflake(const vec2 &in c, float r) {
    nvg::BeginPath();
    for (int arm = 0; arm < 6; arm++) {
        float a = float(arm)*Math::PI/3.0f;
        vec2 d = vec2(Math::Cos(a), Math::Sin(a));
        vec2 branch = c + d*(r*0.6f);
        vec2 n = vec2(-d.y, d.x)*(r*0.25f);
        nvg::MoveTo(c);
        nvg::LineTo(c + d*r);
        nvg::MoveTo(branch + n - d*(r*0.2f));
        nvg::LineTo(branch);
        nvg::LineTo(branch - n - d*(r*0.2f));
    }
    nvg::Stroke();
}

void DrawPopupSnowflakes(PopupFrame@ f) {
    float alpha = f.fade*(1.0f - Math::Clamp(float(f.age - 400) / 400.0f, 0.0f, 1.0f));
    float travel = EaseOutCubic(float(f.age - 80) / 600.0f);
    if (alpha <= 0.0f || travel <= 0.0f) return;
    int count = f.grade == Grade::SPlus ? 10 : 6;
    nvg::StrokeWidth(1.5f*f.s);
    nvg::StrokeColor(vec4(0.9f, 0.97f, 1.0f, alpha));
    for (int i = 0; i < count; i++) {
        float angle = float(i)/float(count)*Math::PI*2.0f + float(f.age)*0.001f;
        float distance = (40.0f + 200.0f*travel)*f.s;
        DrawSnowflake(vec2(f.cx + Math::Cos(angle)*distance*1.4f,
            f.cy + Math::Sin(angle)*distance*0.6f), 7.0f*f.s);
    }
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
    Hud::Text(f.cx, f.cy + f.slump + 28.0f*f.s, f.caption, 13.0f*f.s,
        vec4(0.88f, 0.96f, 1.0f, alpha), nvg::Align::Center | nvg::Align::Middle);
}
