"""Guard the local-only audio boundary and the default sound names."""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "plugin" / "AudioDirector.as"
assert SOURCE.is_file(), "Audio director is missing"
text = SOURCE.read_text(encoding="utf-8")
settings = (ROOT / "plugin" / "Settings.as").read_text(encoding="utf-8")
voice_pools = (ROOT / "plugin" / "VoicePools.as").read_text(encoding="utf-8")
landing = {"Sample_0064.wav", "Sample_0065.wav", "Sample_0063.wav",
           "Sample_0058.wav", "Sample_0053.wav"}
for filename in landing | {
    "SP2_SND_GROUP_00000006.wav", "SP2_SND_GROUP_00000002.wav",
    "WSR_Wakeboarding_Results.mp3"
}:
    assert filename in voice_pools, filename
for grade in "SABCD":
    assert f"S_Grade{grade}List" in settings + voice_pools
assert "RenderSettingsSounds" in settings
assert "S_ImpactFile" not in settings
assert "S_SoundImpact" not in settings + text
assert not (ROOT / "plugin" / "assets" / "impact.wav").exists()
assert 'filename.Contains("..")' in text
ignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
for pattern in ("SP2_*.wav", "Sample_*.wav", "WSR_*.mp3", "LocalSounds/"):
    assert pattern in ignore, pattern
print("Default sound names and local-only media boundary: PASS")
