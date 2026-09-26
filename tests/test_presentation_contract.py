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
assert 'nvg::LoadTexture("assets/gorilla-emoji.png")' in widgets
assert (ROOT / "assets" / "gorilla-emoji.png").is_file()

# Layout stays flat; Sounds uses compact collapsible sections.
assert 'UI::TreeNode(' not in layout
assert 'UI::SeparatorText(' in layout
assert 'UI::CollapsingHeader(' in settings
assert '&inout' not in '\n'.join(line.split('//')[0] for line in settings.splitlines())

# The announcer belongs to the confirmed landing only.
assert 'S_UseAirAnnouncer' not in settings + audio
assert 'OnAirCall' not in audio

print("Combined grade, compact sound settings, and voice timing contract: PASS")
