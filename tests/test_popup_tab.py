"""The Popup settings tab and its previews."""

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "plugin"
tab = (ROOT / "PopupTab.as").read_text(encoding="utf-8")
widgets = (ROOT / "Widgets.as").read_text(encoding="utf-8")
sources = "".join(p.read_text(encoding="utf-8") for p in ROOT.glob("*.as"))

# Tab order: Rating, Sounds, Popup, Layout, Debug; no tab icons.
tabs = re.findall(r'\[SettingsTab name="(\w+)" icon="" order="(\d+)"\]', sources)
assert sorted(tabs, key=lambda t: int(t[1])) == [
    ("Rating", "1"), ("Sounds", "2"), ("Popup", "3"), ("Layout", "4"), ("Debug", "99")], tabs
assert sources.count("[SettingsTab") == 5

render = tab.split("void RenderSettingsPopup() {", 1)[1].split("\n}", 1)[0]
# One reset covers every popup and picture setting.
reset = render.split('if (UI::Button("Reset to default")) {', 1)[1].split("}", 1)[0]
assert "ResetPopupSettings();" in reset and "ResetPictureSettings();" in reset
assert render.index('UI::SeparatorText("Animation")') < render.index('UI::SeparatorText("Pictures")')
assert 'UI::BeginCombo("Style", PopupStyleLabel())' in render
assert "SelectPopupStyle(g_popupStyles[i]);" in render
assert 'S_PopupIntensity = Math::Clamp(UI::SliderInt("Intensity", S_PopupIntensity, 0, 200, "%d%%"), 0, 200);' in render
for setting, label in (("S_FxShake", "Screen shake"), ("S_FxShockwave", "Shockwave ring"),
                       ("S_FxSparks", "Sparks"), ("S_FxCracks", "Cracks"),
                       ("S_FxShards", "Ice shards"), ("S_FxSnowflakes", "Snowflakes (S, S+)"),
                       ("S_FxRays", "Light rays (S+)"), ("S_FxSheen", "Light sheen"),
                       ("S_FxOutline", "Glowing outline (S+)")):
    assert f'{setting} = UI::Checkbox("{label}", {setting});' in render, setting
assert 'S_ShowPictures = UI::Checkbox("Show pictures", S_ShowPictures);' in render
assert 'UI::Button("Open LocalImages folder")' in render and 'UI::Button("Reload files")' in render
assert "RenderPictureRow(g_pictureResults[i]);" in render

row = tab.split("void RenderPictureRow(const string &in result) {", 1)[1].split("\n}", 1)[0]
assert 'if (UI::Button("Preview")) StartPopupPreview(result);' in row
assert 'if (UI::Selectable("None", source.Length == 0))' in row
assert 'SetPictureSetting(result, "local:" + g_localImages[i]);' in row
assert "UI::Image(picture.thumbnail, vec2(thumb, thumb));" in row

# Previews draw even with widgets off; a real verdict replaces a preview (Review Focus 4).
widgets_render = widgets.split("void RenderWidgets() {", 1)[1].split("\n}", 1)[0]
assert widgets_render.index("int previewAge = PopupPreviewAge();") < widgets_render.index("if (!S_EnableWidgets) return;")
assert "RenderResult(grade.Pixels(), previewAge, g_popupPreviewLabel, false,\n                PopupPreviewSeed(g_popupPreviewLabel));" in widgets_render
assert "if (previewAge < 0 && ShouldRenderWidget(layout)) {" in widgets_render
show = widgets.split("void ShowResult(JumpVerdict@ verdict, int raceTime) {", 1)[1].split("\n}", 1)[0]
assert "StopPopupPreview();" in show
print("Popup tab and previews: PASS")
