"""Grade popup styles, effects, intensity, and rendering contract."""

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "plugin"
anim = (ROOT / "GradeAnimation.as").read_text(encoding="utf-8")


def body(signature: str, text: str = anim) -> str:
    return text.split(signature + " {", 1)[1].split("\n}", 1)[0]


# Settings default to plain Ice shatter at 100 %.
settings = dict(re.findall(r"\[Setting hidden\] \w+ (S_\w+) = ([^;]+);", anim))
assert settings == {
    "S_PopupStyle": '"ice"', "S_PopupIntensity": "100",
    "S_FxShake": "false", "S_FxShockwave": "false", "S_FxSparks": "false",
    "S_FxCracks": "true", "S_FxShards": "true", "S_FxSnowflakes": "true",
    "S_FxRays": "true", "S_FxSheen": "false", "S_FxOutline": "false",
}, settings

# Style effect sets match the spec's effects table.
styles = body("int StyleEffects(const string &in style)")
assert 'if (style == "arcade") return FX_SHAKE | FX_SHOCKWAVE | FX_SPARKS | FX_RAYS;' in styles
assert 'if (style == "broadcast") return FX_SHEEN | FX_OUTLINE;' in styles
assert "return FX_CRACKS | FX_SHARDS | FX_SNOWFLAKES | FX_RAYS;" in styles
flags = dict(re.findall(r"const int (FX_\w+) = (\d+);", anim))
assert flags == {"FX_SHAKE": "1", "FX_SHOCKWAVE": "2", "FX_SPARKS": "4", "FX_CRACKS": "8",
                 "FX_SHARDS": "16", "FX_SNOWFLAKES": "32", "FX_RAYS": "64",
                 "FX_SHEEN": "128", "FX_OUTLINE": "256"}, flags

# Unknown styles fall back to Ice; choosing a style applies its effects;
# a changed effect set shows "(custom)".
assert 'return S_PopupStyle == "arcade" || S_PopupStyle == "broadcast" ? S_PopupStyle : "ice";' in body("string PopupStyle()")
select = body("void SelectPopupStyle(const string &in style)")
assert "ApplyEffects(StyleEffects(PopupStyle()));" in select
label = body("string PopupStyleLabel()")
assert 'if (CurrentEffects() != StyleEffects(style)) name += " (custom)";' in label
reset = body("void ResetPopupSettings()")
assert 'SelectPopupStyle("ice");' in reset and "S_PopupIntensity = 100;" in reset

# Intensity is clamped to 0-200 % (Review Focus 2).
assert "return float(Math::Clamp(S_PopupIntensity, 0, 200)) / 100.0f;" in body("float PopupIntensity()")

# Power table and count formulas; the spec's per-grade numbers follow from them.
power = body("float ResultPower(const string &in label)")
POWER = {"S+": 1.0, "S": 0.8, "A": 0.55, "B": 0.4, "C": 0.3, "D": 0.2, "MISSED": 0.5}
for grade, value in POWER.items():
    literal = f"{value}f"
    assert f'if (label == "{grade}") return {literal};' in power, grade
assert "return 0.0f;" in power
assert "return int((6.0f + 34.0f*power)*k + 0.5f);" in body("int ParticleCount(float power, float k)")
# Cracks truncate: the spec table (D 5) is the approved reference.
assert "return int((4.0f + 8.0f*power)*k);" in body("int CrackCount(float power, float k)")
assert "return (120.0f + 320.0f*power)*k;" in body("float ParticleSpeed(float power, float k)")
snow = body("int SnowflakeCount(const string &in label, float k)")
assert 'label == "S+" ? 10.0f : (label == "S" ? 6.0f : 0.0f)' in snow
particles = {g: int(6 + 34 * p + 0.5) for g, p in POWER.items()}
cracks = {g: int(4 + 8 * p) for g, p in POWER.items()}
assert particles == {"S+": 40, "S": 33, "A": 25, "B": 20, "C": 16, "D": 13, "MISSED": 23}, particles
assert cracks == {"S+": 12, "S": 10, "A": 8, "B": 7, "C": 6, "D": 5, "MISSED": 8}, cracks

# The generator is deterministic for a seed; the preview clock lasts 1 s.
assert "class PopupRandom {" in anim and "float Next() {" in anim
age = body("int PopupPreviewAge()")
assert "if (elapsed >= 1000) {" in age and "StopPopupPreview();" in age
assert "g_popupPreviewStart = Time::Now;" in body("void StartPopupPreview(const string &in label)")
print("Popup styles, effects, and intensity model: PASS")

widgets = (ROOT / "Widgets.as").read_text(encoding="utf-8")

# One RenderResult, in GradeAnimation.as, with a seed.
assert "void RenderResult(const vec4 &in r, int age, const string &in label,\n    uint seed) {" in anim
assert "void RenderResult(" not in widgets
for gone in ("g_gorillaTexture", "RenderSGorillas", "DrawGorillaEmoji", "DrawFallbackFlame", "GorillaDot"):
    assert gone not in widgets, gone
assert "RenderResult(layout.Pixels(), active ? age : 450," in widgets
assert "active ? uint(g_resultShownAt) + 1 : 1" in widgets

render = body("void RenderResult(const vec4 &in r, int age, const string &in label,\n    uint seed)")
# Calm results get no intensity, effects, flash, or picture.
assert "f.calm = f.power <= 0.0f;" in render
assert "f.k = f.calm ? 0.0f : PopupIntensity();" in render
assert "f.fx = f.k > 0.0f ? CurrentEffects() : 0;" in render
assert "if (!f.calm) DrawPopupPictures(f);" in render
assert "if (!f.calm) DrawPopupFlash(f);" in render
assert "f.shown = label;" in render
assert "f.fade = 1.0f - Clamp01(float(age - 700) / 300.0f);" in render
assert "f.s = Math::Min(r.z / 500.0f, r.w / 125.0f);" in render
# Grade-only effects.
assert 'if (HasFx(f, FX_RAYS) && label == "S+") DrawPopupRays(f);' in render
assert 'if (HasFx(f, FX_OUTLINE) && label == "S+") DrawPopupOutline(f);' in render
assert 'if (HasFx(f, FX_SNOWFLAKES) && (label == "S" || label == "S+")) DrawPopupSnowflakes(f);' in render
assert "if (HasFx(f, FX_SHOCKWAVE) && !f.miss) DrawPopupShockwave(f);" in render

# Only S and S+ pictures dance; non-square pictures keep their shape (Review Focus 5).
pics = body("void DrawPopupPictures(PopupFrame@ f)")
assert 'bool dance = f.label == "S" || f.label == "S+";' in pics
draw = body("void DrawPictureTexture(nvg::Texture@ texture, float x, float y, float size,\n    float angle, float alpha)")
assert "vec2 dims = texture.GetSize();" in draw
assert "float w = size*Math::Min(1.0f, aspect);" in draw

# Random layouts are seeded per popup; per-frame jitter adds the frame index.
assert "PopupRandom(f.seed + 7)" in body("void DrawPopupSparks(PopupFrame@ f)")
assert "PopupRandom(f.seed + 13)" in body("void DrawPopupShards(PopupFrame@ f)")
assert "PopupRandom(f.seed + 99)" in body("void DrawPopupCracks(PopupFrame@ f)")
assert "PopupRandom(f.seed + uint(f.age / 16))" in body("void ApplyPopupMotion(PopupFrame@ f)")
# Broadcast's panel never collapses below a sliver on tiny or early frames.
assert "Math::Max(6.0f, 480.0f*EaseOutCubic(float(f.age) / 230.0f))*f.s" in body("float PopupPanelWidth(PopupFrame@ f)")
print("Popup rendering contract: PASS")

# Review fix: a 0x0 texture is never drawn.
assert "if (dims.x <= 0.0f || dims.y <= 0.0f) return;" in draw
# Review fix: intensity multiplies ray, outline and sheen alpha, clamped at 1
# (spec), so 200 % is brighter than 100 %.
rays = body("void DrawPopupRays(PopupFrame@ f)")
outline = body("void DrawPopupOutline(PopupFrame@ f)")
sheen = body("void DrawPopupSheen(PopupFrame@ f)")
assert "float alpha = Math::Min(1.0f, 0.12f*f.k)*f.fade*" in rays
assert "Math::Min(1.0f, alpha*f.k)*f.fade" in outline
assert "Math::Min(1.0f, (0.2f + 0.15f*float(j))*f.k)*f.fade" in sheen
for name, text in (("rays", rays), ("outline", outline), ("sheen", sheen)):
    assert "Math::Min(1.0f, f.k)" not in text, name
print("Intensity brightens rays, outline and sheen: PASS")

# In-game feedback: flat top/bottom bars stuck out past the rounded corners.
# The panel edge is now one thin border in the grade colour that follows the
# corners, and Broadcast's underline is as wide as the caption.
panel = body("void DrawPopupPanel(PopupFrame@ f)")
assert "HudBox(x, y + 2*s" not in panel and "HudBox(x, y + 101*s" not in panel
assert "nvg::RoundedRect(x, y, w, 105*s, 16*s);" in panel
assert "nvg::StrokeWidth(1.5f*s);" in panel
assert "nvg::StrokeColor(HudColor(a.x, a.y, a.z, 0.45f*f.fade));" in panel
assert "float captionW = nvg::TextBounds(ResultCaption(f.label)).x;" in panel
assert "120*s" not in panel
print("Panel border follows the corners; underline fits the caption: PASS")

# In-game feedback: near-white shards at 85 % competed with the ice-white
# letter. They are a lighter-weight ice blue at 55 % so the grade stays readable.
shards = body("void DrawPopupShards(PopupFrame@ f)")
assert "float alpha = 0.55f*(1.0f - t/0.8f)*f.fade;" in shards
assert "HudColor(0.62f, 0.85f, 1.0f, alpha)" in shards
print("Ice shards stay behind the grade visually: PASS")

# In-game feedback: cracks started at the letter's centre and crossed it.
# They start 40 units out (squashed vertically like the cracks themselves).
cracks = body("void DrawPopupCracks(PopupFrame@ f)")
assert "vec2 p = vec2(f.cx + f.ox + Math::Cos(angle)*40.0f*f.s,\n            f.cy + f.oy - 8.0f*f.s + Math::Sin(angle)*40.0f*f.s*0.55f);" in cracks
print("Cracks start outside the grade letter: PASS")

spec = (ROOT.parent / "docs" / "superpowers" / "specs" / "2026-09-27-grade-popup-pictures-design.md").read_text(encoding="utf-8")
assert "- particle and snowflake counts (rounded) and crack counts (rounded down);" in spec
assert "- particle, crack, and snowflake counts (rounded);" not in spec
print("Spec intensity rules match the crack counts: PASS")
