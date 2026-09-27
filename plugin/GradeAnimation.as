// The confirmed-landing popup: three styles whose effects can be mixed and
// scaled by one intensity setting. A style sets the base look and switches on
// its own effects; every effect can then be turned on or off with any style.
[Setting hidden] string S_PopupStyle = "ice";
[Setting hidden] int S_PopupIntensity = 100;
[Setting hidden] bool S_FxShake = false;
[Setting hidden] bool S_FxShockwave = false;
[Setting hidden] bool S_FxSparks = false;
[Setting hidden] bool S_FxCracks = true;
[Setting hidden] bool S_FxShards = true;
[Setting hidden] bool S_FxSnowflakes = true;
[Setting hidden] bool S_FxRays = true;
[Setting hidden] bool S_FxSheen = false;
[Setting hidden] bool S_FxOutline = false;

const int FX_SHAKE = 1;
const int FX_SHOCKWAVE = 2;
const int FX_SPARKS = 4;
const int FX_CRACKS = 8;
const int FX_SHARDS = 16;
const int FX_SNOWFLAKES = 32;
const int FX_RAYS = 64;
const int FX_SHEEN = 128;
const int FX_OUTLINE = 256;

array<string> g_popupStyles = {"ice", "arcade", "broadcast"};
array<string> g_popupStyleLabels = {"Ice shatter", "Arcade slam", "Broadcast sheen"};

string PopupStyle() {
    return S_PopupStyle == "arcade" || S_PopupStyle == "broadcast" ? S_PopupStyle : "ice";
}

int StyleEffects(const string &in style) {
    if (style == "arcade") return FX_SHAKE | FX_SHOCKWAVE | FX_SPARKS | FX_RAYS;
    if (style == "broadcast") return FX_SHEEN | FX_OUTLINE;
    return FX_CRACKS | FX_SHARDS | FX_SNOWFLAKES | FX_RAYS;
}

int CurrentEffects() {
    int effects = 0;
    if (S_FxShake) effects |= FX_SHAKE;
    if (S_FxShockwave) effects |= FX_SHOCKWAVE;
    if (S_FxSparks) effects |= FX_SPARKS;
    if (S_FxCracks) effects |= FX_CRACKS;
    if (S_FxShards) effects |= FX_SHARDS;
    if (S_FxSnowflakes) effects |= FX_SNOWFLAKES;
    if (S_FxRays) effects |= FX_RAYS;
    if (S_FxSheen) effects |= FX_SHEEN;
    if (S_FxOutline) effects |= FX_OUTLINE;
    return effects;
}

void ApplyEffects(int effects) {
    S_FxShake = (effects & FX_SHAKE) != 0;
    S_FxShockwave = (effects & FX_SHOCKWAVE) != 0;
    S_FxSparks = (effects & FX_SPARKS) != 0;
    S_FxCracks = (effects & FX_CRACKS) != 0;
    S_FxShards = (effects & FX_SHARDS) != 0;
    S_FxSnowflakes = (effects & FX_SNOWFLAKES) != 0;
    S_FxRays = (effects & FX_RAYS) != 0;
    S_FxSheen = (effects & FX_SHEEN) != 0;
    S_FxOutline = (effects & FX_OUTLINE) != 0;
}

void SelectPopupStyle(const string &in style) {
    S_PopupStyle = style;
    ApplyEffects(StyleEffects(PopupStyle()));
}

string PopupStyleLabel() {
    string style = PopupStyle();
    string name = g_popupStyleLabels[0];
    for (uint i = 0; i < g_popupStyles.Length; i++)
        if (g_popupStyles[i] == style) name = g_popupStyleLabels[i];
    if (CurrentEffects() != StyleEffects(style)) name += " (custom)";
    return name;
}

void ResetPopupSettings() {
    SelectPopupStyle("ice");
    S_PopupIntensity = 100;
}

float PopupIntensity() {
    return float(Math::Clamp(S_PopupIntensity, 0, 200)) / 100.0f;
}

// Better grades get bigger effects; non-results (UNRATED) are calm.
float ResultPower(const string &in label) {
    if (label == "S+") return 1.0f;
    if (label == "S") return 0.8f;
    if (label == "A") return 0.55f;
    if (label == "B") return 0.4f;
    if (label == "C") return 0.3f;
    if (label == "D") return 0.2f;
    if (label == "MISSED") return 0.5f;
    return 0.0f;
}

int ParticleCount(float power, float k) {
    return int((6.0f + 34.0f*power)*k + 0.5f);
}

int CrackCount(float power, float k) {
    return int((4.0f + 8.0f*power)*k);
}

float ParticleSpeed(float power, float k) {
    return (120.0f + 320.0f*power)*k;
}

int SnowflakeCount(const string &in label, float k) {
    float base = label == "S+" ? 10.0f : (label == "S" ? 6.0f : 0.0f);
    return int(base*k + 0.5f);
}

float Clamp01(float x) {
    return Math::Clamp(x, 0.0f, 1.0f);
}

float EaseOutCubic(float x) {
    float r = 1.0f - Clamp01(x);
    return 1.0f - r*r*r;
}

// Overshoots slightly past 1 before settling; 0 at x <= 0.
float EaseOutBack(float x) {
    float m = Clamp01(x) - 1.0f;
    return 1.0f + 2.9f*m*m*m + 1.9f*m*m;
}

vec4 LerpColor(const vec4 &in a, const vec4 &in b, float t) {
    return a + (b - a)*t;
}

// Xorshift generator: the same seed always gives the same layout, so shards
// and cracks never reshuffle between frames.
class PopupRandom {
    uint state;

    PopupRandom(uint seed) {
        state = seed*uint(1103515245) + uint(12345);
        if (state == 0) state = 1;
    }

    float Next() {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        return float(state % 16777216) / 16777216.0f;
    }
}

// A Popup-tab preview runs on its own clock for one second.
string g_popupPreviewLabel = "";
uint64 g_popupPreviewStart = 0;

void StartPopupPreview(const string &in label) {
    g_popupPreviewLabel = label;
    g_popupPreviewStart = Time::Now;
}

void StopPopupPreview() {
    g_popupPreviewLabel = "";
}

int PopupPreviewAge() {
    if (g_popupPreviewLabel.Length == 0) return -1;
    uint64 elapsed = Time::Now - g_popupPreviewStart;
    if (elapsed >= 1000) {
        StopPopupPreview();
        return -1;
    }
    return int(elapsed);
}

uint PopupPreviewSeed(const string &in label) {
    for (uint i = 0; i < g_pictureResults.Length; i++)
        if (g_pictureResults[i] == label) return uint(7919*(i + 2));
    return 7919;
}

// Everything one popup frame needs; built fresh each frame by RenderResult.
class PopupFrame {
    string label;
    string shown;
    string style;
    int age;
    uint seed;
    float s;
    float cx;
    float cy;
    float fade;
    float power;
    float k;
    int fx;
    bool calm;
    bool miss;
    vec4 accent;
    float panelW;
    // Offsets shared by panel, letter, and pictures (shake, MISSED motion).
    float ox = 0.0f;
    float oy = 0.0f;
    float slump = 0.0f;
    // Where the letter was drawn, for the sheen.
    float letterX;
    float letterY;
    float letterScale = 1.0f;
    float letterRot = 0.0f;
}

bool HasFx(PopupFrame@ f, int effect) {
    return (f.fx & effect) != 0;
}

void RenderResult(const vec4 &in r, int age, const string &in label,
    uint seed) {
    if (label.Length == 0) return;
    PopupFrame@ f = PopupFrame();
    f.label = label;
    f.shown = label;
    f.style = PopupStyle();
    f.age = age;
    f.seed = seed;
    f.s = Math::Min(r.z / 500.0f, r.w / 125.0f);
    f.cx = r.x + r.z*0.5f;
    f.cy = r.y + r.w*0.5f;
    f.fade = 1.0f - Clamp01(float(age - 700) / 300.0f);
    f.power = ResultPower(label);
    f.calm = f.power <= 0.0f;
    f.miss = label == "MISSED";
    f.k = f.calm ? 0.0f : PopupIntensity();
    f.fx = f.k > 0.0f ? CurrentEffects() : 0;
    f.accent = GradeColor(label, f.fade);
    f.panelW = PopupPanelWidth(f);
    ApplyPopupMotion(f);
    if (HasFx(f, FX_RAYS) && label == "S+") DrawPopupRays(f);
    if (HasFx(f, FX_SHOCKWAVE) && !f.miss) DrawPopupShockwave(f);
    DrawPopupPanel(f);
    if (HasFx(f, FX_OUTLINE) && label == "S+") DrawPopupOutline(f);
    if (HasFx(f, FX_CRACKS)) DrawPopupCracks(f);
    if (!f.calm) DrawPopupPictures(f);
    if (HasFx(f, FX_SPARKS)) DrawPopupSparks(f);
    if (HasFx(f, FX_SHARDS)) DrawPopupShards(f);
    if (HasFx(f, FX_SNOWFLAKES) && (label == "S" || label == "S+")) DrawPopupSnowflakes(f);
    DrawPopupLetter(f);
    if (HasFx(f, FX_SHEEN)) DrawPopupSheen(f);
    if (!f.calm) DrawPopupFlash(f);
    DrawPopupCaption(f);
}

float PopupPanelWidth(PopupFrame@ f) {
    if (f.style == "broadcast")
        return Math::Max(6.0f, 480.0f*EaseOutCubic(float(f.age) / 230.0f))*f.s;
    float duration = f.style == "arcade" ? 170.0f : 180.0f;
    return (180.0f + 300.0f*EaseOutCubic(float(f.age) / duration))*f.s;
}

void ApplyPopupMotion(PopupFrame@ f) {
    float age = float(f.age);
    bool arcadeMiss = f.miss && f.style == "arcade";
    if (arcadeMiss && age < 300.0f)
        f.ox += Math::Sin(age*0.09f)*14.0f*f.s*(1.0f - age/300.0f);
    if (f.miss && f.style == "ice")
        f.slump = 10.0f*f.s*EaseOutCubic((age - 250.0f) / 350.0f);
    if (HasFx(f, FX_SHAKE) && !arcadeMiss && age < 300.0f) {
        PopupRandom@ rng = PopupRandom(f.seed + uint(f.age / 16));
        float decay = 1.0f - age/300.0f;
        f.ox += (rng.Next() - 0.5f)*18.0f*f.power*f.k*decay*f.s;
        f.oy += (rng.Next() - 0.5f)*12.0f*f.power*f.k*decay*f.s;
    }
}

void DrawPopupPanel(PopupFrame@ f) {
    float s = f.s;
    float x = f.cx + f.ox - f.panelW*0.5f;
    float y = f.cy + f.oy + f.slump - 52.0f*s;
    float w = f.panelW;
    vec4 a = f.accent;
    HudBox(x, y + 5*s, w, 105*s, 16*s, HudColor(0, 0, 0, 0.35f*f.fade));
    HudBox(x, y, w, 105*s, 16*s, HudColor(0.025f, 0.035f, 0.09f, 0.93f*f.fade));
    // A thin grade-coloured border that follows the rounded corners; the S+
    // Glowing outline effect brightens it.
    nvg::BeginPath();
    nvg::RoundedRect(x, y, w, 105*s, 16*s);
    nvg::StrokeWidth(1.5f*s);
    nvg::StrokeColor(HudColor(a.x, a.y, a.z, 0.45f*f.fade));
    nvg::Stroke();
    if (f.style != "broadcast") return;
    if (f.age < 260) {
        float edge = 0.9f*(1.0f - float(f.age)/260.0f)*f.fade;
        HudBox(x - 2*s, y, 4*s, 105*s, 1*s, HudColor(1, 1, 1, edge));
        HudBox(x + w - 2*s, y, 4*s, 105*s, 1*s, HudColor(1, 1, 1, edge));
    }
    // The underline grows from the centre to the caption's width.
    float bar = EaseOutCubic(float(f.age - 300) / 300.0f);
    if (bar <= 0.0f) return;
    nvg::FontSize(13.0f*s);
    float captionW = nvg::TextBounds(ResultCaption(f.label)).x;
    HudBox(f.cx + f.ox - captionW*0.5f*bar, f.cy + f.oy + 18*s, captionW*bar, 2*s, 1*s,
        HudColor(a.x, a.y, a.z, 0.9f*f.fade));
}

void DrawPopupFlash(PopupFrame@ f) {
    float duration;
    float strength;
    vec4 colour;
    if (f.style == "ice") {
        duration = 110.0f;
        strength = 0.6f;
        colour = HudColor(0.82f, 0.94f, 1.0f);
    } else if (f.style == "arcade") {
        duration = 90.0f;
        strength = 0.55f*f.power;
        colour = HudColor(1, 1, 1);
    } else {
        return;
    }
    if (float(f.age) >= duration) return;
    float alpha = Math::Min(1.0f, strength*f.k)*(1.0f - float(f.age)/duration)*f.fade;
    HudBox(f.cx + f.ox - f.panelW*0.5f, f.cy + f.oy + f.slump - 52.0f*f.s,
        f.panelW, 105.0f*f.s, 16.0f*f.s, HudColor(colour.x, colour.y, colour.z, alpha));
}

void DrawPopupText(PopupFrame@ f, float x, float y, float scale, float rot,
    const vec4 &in colour, float blur) {
    float size = (f.miss ? 43.0f : 54.0f)*f.s;
    nvg::Save();
    nvg::Translate(x, y);
    nvg::Rotate(rot);
    nvg::Scale(scale, scale);
    nvg::FontBlur(blur);
    HudText(0, 0, f.shown, size, colour, nvg::Align::Center | nvg::Align::Middle);
    nvg::Restore();
}

void DrawPopupLetter(PopupFrame@ f) {
    float age = float(f.age);
    float x = f.cx + f.ox;
    float y = f.cy + f.oy - 8.0f*f.s;
    float scale = 1.0f;
    float rot = 0.0f;
    vec4 colour = f.accent;
    if (f.style == "broadcast") {
        float wipe = EaseOutCubic((age - 120.0f) / 260.0f);
        if (wipe <= 0.0f) return;
        nvg::Scissor(x - 120.0f*f.s, y - 60.0f*f.s, 240.0f*f.s*wipe, 120.0f*f.s);
        if (f.miss && age > 150.0f && age < 450.0f) {
            PopupRandom@ rng = PopupRandom(f.seed + uint(f.age / 40));
            if ((f.age / 40) % 2 == 0) x += (rng.Next() - 0.5f)*10.0f*f.s;
            DrawPopupText(f, x + 3.0f*f.s, y, 1.0f, 0.0f,
                HudColor(0.31f, 0.86f, 1.0f, 0.6f*f.fade), 0.0f);
        }
        f.letterX = x; f.letterY = y; f.letterScale = 1.0f; f.letterRot = 0.0f;
        DrawPopupText(f, x, y, 1.0f, 0.0f, colour, 0.0f);
        nvg::ResetScissor();
        return;
    }
    if (f.style == "arcade") {
        if (f.miss) {
            scale = 1.0f + 0.6f*(1.0f - EaseOutCubic(age / 220.0f));
            y += 6.0f*f.s*EaseOutCubic((age - 200.0f) / 300.0f);
        } else {
            scale = 3.2f - 2.2f*EaseOutBack(age / 240.0f);
            rot = -0.2f*(1.0f - EaseOutCubic(age / 240.0f));
        }
        if (!f.calm)
            DrawPopupText(f, x, y, scale, rot, HudColor(f.accent.x, f.accent.y,
                f.accent.z, 0.7f*f.fade*f.power), 18.0f*f.power*f.s);
    } else {
        scale = 1.0f + 0.9f*(1.0f - EaseOutBack(age / 260.0f));
        if (f.miss) {
            float slump = EaseOutCubic((age - 250.0f) / 350.0f);
            y += 14.0f*f.s*slump;
            rot = 0.12f*slump;
        } else {
            float warm = Clamp01((age - 120.0f) / 300.0f);
            colour = LerpColor(HudColor(0.84f, 0.95f, 1.0f, f.fade), f.accent, warm);
            DrawPopupText(f, x, y, scale, rot,
                HudColor(0.78f, 0.93f, 1.0f, 0.8f*(1.0f - warm)*f.fade), 12.0f*f.s);
        }
    }
    f.letterX = x; f.letterY = y; f.letterScale = scale; f.letterRot = rot;
    DrawPopupText(f, x, y, scale, rot, colour, 0.0f);
}

// The letter redrawn in white inside a moving clip band; three nested bands
// with rising alpha give soft edges.
void DrawPopupSheen(PopupFrame@ f) {
    array<int> starts;
    if (f.label == "S+") { starts.InsertLast(260); starts.InsertLast(520); }
    else if (f.label == "S" || f.label == "A" || f.label == "B") starts.InsertLast(300);
    for (uint i = 0; i < starts.Length; i++) {
        float t = float(f.age - starts[i]) / 340.0f;
        if (t <= 0.0f || t >= 1.0f) continue;
        float bandX = f.letterX - 150.0f*f.s + 300.0f*f.s*t;
        for (int j = 0; j < 3; j++) {
            float half = (40.0f - 12.0f*float(j))*f.s;
            nvg::Scissor(bandX - half, f.letterY - 60.0f*f.s, half*2.0f, 120.0f*f.s);
            DrawPopupText(f, f.letterX, f.letterY, f.letterScale, f.letterRot,
                HudColor(1, 1, 1, Math::Min(1.0f, (0.2f + 0.15f*float(j))*f.k)*f.fade), 0.0f);
        }
        nvg::ResetScissor();
    }
}

void DrawPopupRays(PopupFrame@ f) {
    float alpha = Math::Min(1.0f, 0.12f*f.k)*f.fade*
        EaseOutCubic(float(f.age - 150) / 300.0f);
    if (alpha <= 0.0f) return;
    nvg::Save();
    nvg::Translate(f.cx + f.ox, f.cy + f.oy);
    nvg::Rotate(float(f.age)*0.0012f);
    nvg::FillColor(HudColor(1.0f, 0.84f, 0.35f, alpha));
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

void DrawPopupShockwave(PopupFrame@ f) {
    if (f.age >= 480) return;
    float t = float(f.age) / 480.0f;
    float radius = (30.0f + 260.0f*f.k*EaseOutCubic(t))*f.s;
    nvg::BeginPath();
    nvg::Ellipse(vec2(f.cx + f.ox, f.cy + f.oy), radius, radius*0.42f);
    nvg::StrokeWidth((2.0f + 7.0f*f.power*(1.0f - t))*f.s);
    nvg::StrokeColor(HudColor(f.accent.x, f.accent.y, f.accent.z, 0.8f*(1.0f - t)*f.fade));
    nvg::Stroke();
}

void DrawPopupOutline(PopupFrame@ f) {
    float glow = 0.5f + 0.5f*Math::Sin(float(f.age)*0.02f);
    float x = f.cx + f.ox - f.panelW*0.5f;
    float y = f.cy + f.oy - 52.0f*f.s;
    for (int pass = 0; pass < 2; pass++) {
        nvg::BeginPath();
        nvg::RoundedRect(x, y, f.panelW, 105.0f*f.s, 16.0f*f.s);
        nvg::StrokeWidth((pass == 0 ? 6.0f : 2.0f)*f.s);
        float alpha = pass == 0 ? 0.25f*glow : 0.35f + 0.4f*glow;
        nvg::StrokeColor(HudColor(f.accent.x, f.accent.y, f.accent.z, Math::Min(1.0f, alpha*f.k)*f.fade));
        nvg::Stroke();
    }
}

void DrawPopupCracks(PopupFrame@ f) {
    float alpha = 0.7f*f.fade*(1.0f - Clamp01(float(f.age - 350) / 400.0f));
    if (alpha <= 0.0f) return;
    float grow = EaseOutCubic(float(f.age) / 220.0f);
    PopupRandom@ rng = PopupRandom(f.seed + 99);
    int count = CrackCount(f.power, f.k);
    nvg::StrokeWidth(1.4f*f.s);
    nvg::StrokeColor(HudColor(0.82f, 0.94f, 1.0f, alpha));
    for (int i = 0; i < count; i++) {
        float angle = rng.Next()*Math::PI*2.0f;
        float step = grow*(60.0f + 90.0f*rng.Next())*f.s/4.0f;
        // Start outside the letter so the grade stays readable.
        vec2 p = vec2(f.cx + f.ox + Math::Cos(angle)*40.0f*f.s,
            f.cy + f.oy - 8.0f*f.s + Math::Sin(angle)*40.0f*f.s*0.55f);
        nvg::BeginPath();
        nvg::MoveTo(p);
        for (int j = 0; j < 4; j++) {
            angle += (rng.Next() - 0.5f)*0.9f;
            p += vec2(Math::Cos(angle)*step, Math::Sin(angle)*step*0.55f);
            nvg::LineTo(p);
        }
        nvg::Stroke();
    }
}

void DrawPopupSparks(PopupFrame@ f) {
    float t = float(f.age) / 1000.0f;
    if (t >= 0.75f) return;
    float alpha = (1.0f - t/0.75f)*f.fade;
    float gravity = f.miss ? 260.0f : 156.0f;
    array<vec4> confetti = {HudColor(1, 0.84f, 0.28f), HudColor(0.35f, 0.85f, 1),
        HudColor(1, 0.43f, 0.57f), HudColor(0.45f, 0.9f, 0.45f)};
    PopupRandom@ rng = PopupRandom(f.seed + 7);
    int count = ParticleCount(f.power, f.k);
    for (int i = 0; i < count; i++) {
        float angle = rng.Next()*Math::PI*2.0f;
        float distance = ParticleSpeed(f.power*rng.Next(), f.k)*t*f.s;
        float radius = (1.5f + 3.0f*rng.Next())*f.s*(f.miss ? 1.3f : 1.0f);
        float rot = rng.Next()*6.0f;
        float spin = (rng.Next() - 0.5f)*12.0f;
        float pick = rng.Next();
        vec2 p = vec2(f.cx + f.ox + Math::Cos(angle)*distance*1.3f,
            f.cy + f.oy + Math::Sin(angle)*distance*0.7f + gravity*t*t*f.s);
        if (f.label == "S+" && pick > 0.5f) {
            vec4 c = confetti[int(pick*8.0f) % 4];
            nvg::Save();
            nvg::Translate(p);
            nvg::Rotate(rot + spin*t);
            HudBox(-4*f.s, -2*f.s, 8*f.s, 4*f.s, 0, HudColor(c.x, c.y, c.z, alpha));
            nvg::Restore();
        } else {
            vec4 c = f.miss ? HudColor(0.55f, 0.59f, 0.65f) : f.accent;
            nvg::BeginPath();
            nvg::Circle(p, radius);
            nvg::FillColor(HudColor(c.x, c.y, c.z, alpha));
            nvg::Fill();
        }
    }
}

void DrawPopupShards(PopupFrame@ f) {
    float t = float(f.age) / 1000.0f;
    if (t >= 0.8f) return;
    float alpha = 0.55f*(1.0f - t/0.8f)*f.fade;
    float gravity = f.miss ? 300.0f : 120.0f;
    vec4 colour = f.miss ? HudColor(0.55f, 0.6f, 0.66f, alpha) :
        HudColor(0.62f, 0.85f, 1.0f, alpha);
    PopupRandom@ rng = PopupRandom(f.seed + 13);
    int count = ParticleCount(f.power, f.k);
    for (int i = 0; i < count; i++) {
        float angle = rng.Next()*Math::PI*2.0f;
        float distance = ParticleSpeed(f.power*rng.Next(), f.k)*t*1.1f*f.s;
        float size = (6.0f + 6.0f*rng.Next())*f.s;
        float rot = rng.Next()*6.0f;
        float spin = (rng.Next() - 0.5f)*12.0f;
        vec2 p = vec2(f.cx + f.ox + Math::Cos(angle)*distance*1.3f,
            f.cy + f.oy + Math::Sin(angle)*distance*0.6f + gravity*t*t*f.s);
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
    float alpha = f.fade*(1.0f - Clamp01(float(f.age - 400) / 400.0f));
    float travel = EaseOutCubic(float(f.age - 80) / 600.0f);
    if (alpha <= 0.0f || travel <= 0.0f) return;
    int count = SnowflakeCount(f.label, f.k);
    nvg::StrokeWidth(1.5f*f.s);
    nvg::StrokeColor(HudColor(0.9f, 0.97f, 1.0f, alpha));
    for (int i = 0; i < count; i++) {
        float angle = float(i)/float(count)*Math::PI*2.0f + float(f.age)*0.001f;
        float distance = (40.0f + 200.0f*f.k*travel)*f.s;
        DrawSnowflake(vec2(f.cx + f.ox + Math::Cos(angle)*distance*1.4f,
            f.cy + f.oy + Math::Sin(angle)*distance*0.6f), 7.0f*f.s);
    }
}

// Keeps the picture's aspect ratio inside a size-by-size square.
void DrawPictureTexture(nvg::Texture@ texture, float x, float y, float size,
    float angle, float alpha) {
    vec2 dims = texture.GetSize();
    if (dims.x <= 0.0f || dims.y <= 0.0f) return;
    float aspect = dims.y > 0.0f ? dims.x / dims.y : 1.0f;
    float w = size*Math::Min(1.0f, aspect);
    float h = size*Math::Min(1.0f, 1.0f / Math::Max(aspect, 0.001f));
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

void DrawPopupPictures(PopupFrame@ f) {
    nvg::Texture@ picture = PictureForResult(f.label);
    if (picture is null) return;
    bool dance = f.label == "S" || f.label == "S+";
    float age = float(f.age);
    for (int i = 0; i < 2; i++) {
        float side = i == 0 ? -1.0f : 1.0f;
        float size = 72.0f*f.s;
        float alpha = f.fade;
        float x = f.cx + f.ox + side*150.0f*f.s;
        float y = f.cy + f.oy + f.slump;
        if (f.style == "broadcast") {
            float enter = EaseOutCubic((age - 60.0f) / 300.0f);
            x += side*30.0f*f.s*(1.0f - enter);
            alpha *= enter;
        } else {
            float delay = f.style == "ice" ? 60.0f + 40.0f*float(i) : 60.0f;
            float duration = f.style == "ice" ? 300.0f : 260.0f;
            size *= EaseOutBack((age - delay) / duration);
            alpha *= Clamp01((age - delay) / 100.0f);
        }
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
    float alpha = f.fade*Clamp01(float(f.age - 120) / 200.0f);
    if (alpha <= 0.0f) return;
    HudText(f.cx + f.ox, f.cy + f.oy + f.slump + 28.0f*f.s, ResultCaption(f.label),
        13.0f*f.s, HudColor(0.88f, 0.96f, 1, alpha),
        nvg::Align::Center | nvg::Align::Middle);
}
