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
