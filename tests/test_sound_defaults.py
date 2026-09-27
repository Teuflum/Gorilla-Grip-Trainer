"""Sound defaults follow the author's setup; a fresh install keeps only files it has."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
settings = (ROOT / "plugin" / "Settings.as").read_text(encoding="utf-8")
pools = (ROOT / "plugin" / "VoicePools.as").read_text(encoding="utf-8")


def body(signature: str, text: str) -> str:
    return text.split(signature + " {", 1)[1].split("\n}", 1)[0]


assert "[Setting hidden] float S_MasterVolume = 0.5f;" in settings

# The shipped lists, as "<file>|<gain>" rows.
DEFAULTS = {
    "jump": "SP2_SND_GROUP_00000006.wav|0.35",
    "S": "Sample_0064.wav|0.40\\nSample_0061.wav|0.40",
    "A": "Sample_0065.wav|0.40",
    "B": "Sample_0063.wav|0.40",
    "C": "Sample_0058.wav|0.40",
    "D": "Sample_0053.wav|0.40",
    "failure": "SP2_SND_GROUP_00000002.wav|0.35",
    "results": "WSR_Wakeboarding_Results.mp3|0.25",
}
defaults = body("string DefaultVoiceList(const string &in grade)", pools)
for grade, value in DEFAULTS.items():
    assert f'if (grade == "{grade}") return "{value}";' in defaults, grade

# The pre-list single-file settings and their migration are gone.
for gone in ("S_LandSFile", "S_LandSVolume", "S_JumpFile", "S_JumpVolume",
             "S_FailureFile", "S_FailureVolume", "S_ResultsFile",
             "S_ResultsVolume", "S_FixedPoolsMigrated"):
    assert gone not in settings + pools, gone

# A fresh install gets the defaults whose files are in LocalSounds; an
# install that already has its lists is left alone.
init = body("void InitVoicePools()", pools)
assert "if (!S_GradePoolsMigrated) {" in init
assert "ApplyDefaultSounds(true);" in init
assert "S_GradePoolsMigrated = true;" in init
existing = body("string ExistingSoundsOnly(const string &in encoded)", pools)
assert 'IO::FileExists(IO::FromStorageFolder("LocalSounds/" + name))' in existing
apply = body("void ApplyDefaultSounds(bool onlyExisting)", pools)
for setting, grade in (("S_JumpList", "jump"), ("S_GradeSList", "S"),
                       ("S_GradeAList", "A"), ("S_GradeBList", "B"),
                       ("S_GradeCList", "C"), ("S_GradeDList", "D"),
                       ("S_FailureList", "failure"), ("S_ResultsList", "results")):
    assert f'{setting} = DefaultSoundsFor("{grade}", onlyExisting);' in apply, setting
chosen = body("string DefaultSoundsFor(const string &in grade, bool onlyExisting)", pools)
assert "return onlyExisting ? ExistingSoundsOnly(DefaultVoiceList(grade)) : DefaultVoiceList(grade);" in chosen

# Reset to default on the Sounds tab restores every default, even for files
# that are not there yet, then rebuilds the lists and reloads the audio.
reset = body("void ResetSoundSettings()", settings)
for line in ("S_EnableAudio = true;", "S_MasterVolume = 0.5f;",
             "S_SoundTakeoff = true;", "S_SoundFailure = true;",
             "S_SoundVoices = true;", "S_SoundResults = true;",
             "S_GradeSEnabled = true;", "S_GradeDEnabled = true;",
             "ApplyDefaultSounds(false);", "ReloadVoicePools();",
             "if (g_audio !is null) g_audio.Load();"):
    assert line in reset, line
reload = body("void ReloadVoicePools()", pools)
assert "g_voicePools.RemoveRange(0, g_voicePools.Length);" in reload
assert "BuildVoicePools();" in reload
sounds = body("void RenderSettingsSounds()", settings)
assert 'if (ConfirmedResetButton("Reset to default", "sounds")) ResetSoundSettings();' in sounds
assert sounds.index("InitVoicePools();") < sounds.index('ConfirmedResetButton("Reset to default", "sounds")')
print("Sound defaults and fresh-install seeding: PASS")
