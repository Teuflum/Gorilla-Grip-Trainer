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
