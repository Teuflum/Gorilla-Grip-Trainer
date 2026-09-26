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

for cue in ("Jump", "Failure", "Results"):
    assert f'S_{cue}List' in settings
    assert f'VoicePoolFor("{cue.lower()}")' in audio

for category in ("Takeoff", "Failure", "Voices", "Results"):
    assert f'S_Sound{category}' in settings
    assert f'S_Sound{category}' in audio

assert 'Math::Rand(' in audio
assert 'lastPick' in audio
assert 'RenderVoicePool' in settings
assert 'UI::CollapsingHeader(' in settings
assert 'UI::CollapsingHeader("Grades")' in settings
assert 'UI::Button("+")' in settings
assert 'UI::Button("-")' in settings
assert 'available - 155.0f' in settings
assert 'float field = row * 0.325f;' in settings
assert 'float picker = row * 0.325f;' in settings
assert 'UI::Button("Add clip")' not in settings
assert '@pool.entries[i].sample = g_audio.LoadLocal(choice.file)' in settings
assert 'if (S_SoundFailure)' in audio
assert 'if (S_SoundVoices && S_SoundFailure)' not in audio
assert 'OpenExplorerPath(' in settings
assert 'PreviewFile(' in settings + audio
sounds_body = settings.split('void RenderSettingsSounds() {', 1)[1]
assert sounds_body.index('UI::Button("Open LocalSounds folder")') < sounds_body.index('UI::Checkbox("Enable all sounds"')

print("Editable grade pools and landing-only sound contract: PASS")
