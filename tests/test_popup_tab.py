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
reset = render.split('if (ConfirmedResetButton("Reset to default", "popup")) {', 1)[1].split("}", 1)[0]
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
# Thumbnails fit inside a square cell without stretching.
assert "UI::Image(" not in row
assert "vec2 size = aspect >= 1.0f ? vec2(thumb, thumb/aspect) : vec2(thumb*aspect, thumb);" in row
assert "UI::GetWindowDrawList().AddImage(picture.thumbnail, cell + (vec2(thumb, thumb) - size)*0.5f, size);" in row

# Previews draw even with widgets off, on top of the other widgets; a real
# verdict replaces a preview (Review Focus 4).
widgets_render = widgets.split("void RenderWidgets() {", 1)[1].split("\n}", 1)[0]
cards = widgets.split("void RenderWidgetCards(int previewAge) {", 1)[1].split("\n}", 1)[0]
assert widgets_render.index("int previewAge = PopupPreviewAge();") < widgets_render.index("if (S_EnableWidgets) RenderWidgetCards(previewAge);")
assert widgets_render.index("if (S_EnableWidgets) RenderWidgetCards(previewAge);") < widgets_render.index("RenderResult(grade.Pixels(), previewAge,")
assert "RenderResult(grade.Pixels(), previewAge, g_popupPreviewLabel,\n                PopupPreviewSeed(g_popupPreviewLabel));" in widgets_render
assert "return;" not in widgets_render
assert "if (previewAge < 0 && ShouldRenderWidget(layout)) {" in cards
show = widgets.split("void ShowResult(JumpVerdict@ verdict, int raceTime) {", 1)[1].split("\n}", 1)[0]
assert "StopPopupPreview();" in show
print("Popup tab and previews: PASS")

readme = (ROOT.parent / "README.md").read_text(encoding="utf-8")
# The README settings table lists every tab in order.
rows = [line.split("|")[1].strip() for line in readme.split("## Settings", 1)[1].split("\n## ", 1)[0].splitlines()
        if line.startswith("| ") and not line.startswith("| Tab") and not line.startswith("| ---")]
assert rows == ["Display", "Rating", "Sounds", "Popup", "Layout", "Debug"], rows
print("Thumbnails, preview order and README tab list: PASS")
