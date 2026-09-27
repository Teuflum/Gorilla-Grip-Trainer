"""Guard the combined grade flow and settings UI against regressions."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "plugin"
layout = (ROOT / "Layout.as").read_text(encoding="utf-8")
widgets = (ROOT / "Widgets.as").read_text(encoding="utf-8")
settings = (ROOT / "Settings.as").read_text(encoding="utf-8")
audio = (ROOT / "AudioDirector.as").read_text(encoding="utf-8")

# Exactly one movable grade anchor must serve takeoff and touchdown.
assert 'WidgetLayout("grade", "Grade"' in layout
assert 'WidgetLayout("timing"' not in layout
assert 'WidgetLayout("result"' not in layout
assert 'GetLayout("grade")' in widgets
assert 'GetLayout("timing")' not in widgets
assert 'GetLayout("result")' not in widgets
assert "gorilla-emoji" not in widgets
assert (ROOT / "assets" / "emoji" / "fluent-flat" / "gorilla.png").is_file()

# Layout and Sounds use compact collapsible sections.
assert 'UI::CollapsingHeader(widget.title)' in layout
assert 'UI::CollapsingHeader(' in settings
assert '&inout' not in '\n'.join(line.split('//')[0] for line in settings.splitlines())

# The announcer belongs to the confirmed landing only.
assert 'S_UseAirAnnouncer' not in settings + audio
assert 'OnAirCall' not in audio

# Custom settings tabs carry no icon; Debug stays last.
import re
popup = (ROOT / "PopupTab.as").read_text(encoding="utf-8")
tabs = re.findall(r'\[SettingsTab name="(\w+)" icon="" order="(\d+)"\]', layout + settings + popup)
assert sorted(tabs, key=lambda tab: int(tab[1])) == [
    ("Rating", "1"), ("Sounds", "2"), ("Popup", "3"), ("Layout", "4"), ("Debug", "99")], tabs
assert (layout + settings + popup).count("[SettingsTab") == 5

# Only the top-level plugin menu entry has an icon.
main = (ROOT / "Main.as").read_text(encoding="utf-8")
menu = main.split("void RenderMenu() {", 1)[1].split("\n}", 1)[0]
assert menu.count("Icons::") == 1 and "UI::BeginMenu(Icons::" in menu
assert "UI::MenuItem(Icons::" not in menu

print("Combined grade, compact sound settings, and voice timing contract: PASS")
