"""Check the configurable landing-only sound model in Openplanet source."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "plugin"
settings = (ROOT / "Settings.as").read_text(encoding="utf-8")
audio = (ROOT / "AudioDirector.as").read_text(encoding="utf-8")
main = (ROOT / "Main.as").read_text(encoding="utf-8")

assert '[Setting category="Audio"' not in settings
assert '[SettingsTab name="Sounds"]' in settings
assert 'S_UseAirAnnouncer' not in settings + audio
assert 'OnAirCall' not in audio
assert 'g_audio.Update(' not in main

for grade in "SABCD":
    assert f'"{grade}"' in settings
    assert f'S_Grade{grade}Enabled' in settings
    assert f'S_Grade{grade}List' in settings

for category in ("Takeoff", "Failure", "Voices", "Results"):
    assert f'S_Sound{category}' in settings
    assert f'S_Sound{category}' in audio

assert 'Math::Rand(' in audio
assert 'lastPick' in audio
assert 'RenderVoicePool' in settings
assert 'UI::CollapsingHeader(' in settings
assert 'OpenExplorerPath(' in settings
assert 'PreviewFile(' in settings + audio

print("Editable grade pools and landing-only sound contract: PASS")
