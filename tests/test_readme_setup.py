"""The README explains the default sound names and where the in-game tests' tools live."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
readme = (ROOT / "README.md").read_text(encoding="utf-8")

# Default sound names, with a hint instead of shipped audio.
for name in ("SP2_SND_GROUP_00000006.wav", "Sample_0064.wav", "Sample_0061.wav",
             "Sample_0065.wav", "Sample_0063.wav", "Sample_0058.wav",
             "Sample_0053.wav", "SP2_SND_GROUP_00000002.wav",
             "WSR_Wakeboarding_Results.mp3"):
    assert f"`{name}`" in readme, name
assert "Wii Sports Resort" in readme
assert "`Sample_0061.wav` (Great Air)" in readme and "`Sample_0064.wav` (Incredible)" in readme
# The most important information comes first; links and credits close it.
sections = [line[3:] for line in readme.splitlines() if line.startswith("## ")]
assert sections[:2] == ["Install", "How a jump is rated"], sections
assert sections[-2:] == ["Development", "More"], sections
assert "The plugin ships no audio" in readme

# The in-game tests need the research repository's tools.
research = "https://github.com/Teuflum/tm-gorilla-grip-reverse-engineering"
assert research in readme
assert "tick_client.py" in readme

# In-game test docstrings say the Logger only drives the test.
for name in ("test_trainer_in_game.py", "test_current_input.py",
             "test_finish_reset_in_game.py"):
    doc = (ROOT / "tests" / name).read_text(encoding="utf-8").split('"""', 2)[1]
    assert "The Trainer itself does not need GorillaGripLogger" in doc, name
    assert research in doc, name
print("README setup notes: PASS")
