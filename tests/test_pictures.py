"""Grade popup pictures: shipped Twemoji art and LocalImages choices."""

import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "plugin" / "assets"
EMOJI = {
    "gorilla": "1f98d", "oncoming-fist": "1f44a", "flexed-biceps": "1f4aa",
    "fire": "1f525", "thumbs-up": "1f44d", "ok-hand": "1f44c",
    "slightly-smiling-face": "1f642", "skull": "1f480", "ice": "1f9ca",
    "snowflake": "2744", "trophy": "1f3c6", "star": "2b50",
}

# Twelve 256x256 RGBA PNGs, and nothing else, ship in assets/twemoji.
twemoji = ASSETS / "twemoji"
assert sorted(p.name for p in twemoji.glob("*.png")) == sorted(f"{n}.png" for n in EMOJI)
for name in EMOJI:
    png = (twemoji / f"{name}.png").read_bytes()
    assert png[:8] == b"\x89PNG\r\n\x1a\n", name
    width, height, depth, colour = struct.unpack(">IIBB", png[16:26])
    assert (width, height, depth, colour) == (256, 256, 8, 6), (name, width, height, depth, colour)

# CC-BY 4.0 needs a credit that names every shipped file.
attribution = (twemoji / "ATTRIBUTION.md").read_text(encoding="utf-8")
assert "Twemoji by Twitter, Inc. and other contributors" in attribution
assert "https://creativecommons.org/licenses/by/4.0/" in attribution
assert "jdecked/twemoji" in attribution and "v16.0.1" in attribution
for name, code in EMOJI.items():
    assert f"| `{name}.png` |" in attribution and code in attribution, name
readme = (ROOT / "README.md").read_text(encoding="utf-8")
assert "[Twemoji](https://github.com/jdecked/twemoji)" in readme
assert "LocalImages/" in (ROOT / ".gitignore").read_text(encoding="utf-8").splitlines()

tool = (ROOT / "tools" / "render_twemoji.py").read_text(encoding="utf-8")
assert 'VERSION = "v16.0.1"' in tool
for name, code in EMOJI.items():
    assert f'"{name}": "{code}"' in tool, name
print("Shipped Twemoji pictures: PASS")

import re

pictures = (ROOT / "plugin" / "Pictures.as").read_text(encoding="utf-8")
main = (ROOT / "plugin" / "Main.as").read_text(encoding="utf-8")

# Seven hidden picture settings with the agreed defaults, plus the master switch.
defaults = dict(re.findall(r'\[Setting hidden\] string (S_Picture\w+) = "([^"]*)";', pictures))
assert defaults == {
    "S_PictureSPlus": "emoji:gorilla", "S_PictureS": "emoji:gorilla",
    "S_PictureA": "emoji:flexed-biceps", "S_PictureB": "emoji:thumbs-up",
    "S_PictureC": "emoji:ok-hand", "S_PictureD": "emoji:slightly-smiling-face",
    "S_PictureMissed": "emoji:skull",
}, defaults
assert "[Setting hidden] bool S_ShowPictures = true;" in pictures
assert 'array<string> g_pictureResults = {"S+", "S", "A", "B", "C", "D", "MISSED"};' in pictures

# The catalogue lists the Task 1 files in the same order as their labels.
names = re.search(r"array<string> g_emojiNames = \{([^}]*)\};", pictures).group(1)
labels = re.search(r"array<string> g_emojiLabels = \{([^}]*)\};", pictures).group(1)
assert re.findall(r'"([^"]+)"', names) == list(EMOJI)
assert re.findall(r'"([^"]+)"', labels) == [
    "Gorilla", "Oncoming fist", "Flexed biceps", "Fire", "Thumbs up", "OK hand",
    "Slightly smiling face", "Skull", "Ice", "Snowflake", "Trophy", "Star"]
for result, setting in (("S+", "S_PictureSPlus"), ("MISSED", "S_PictureMissed")):
    assert f'if (result == "{result}") return {setting};' in pictures, result

# A local choice can never leave LocalImages.
safe = pictures.split("bool IsSafeLocalName(const string &in name) {", 1)[1].split("\n}", 1)[0]
for part in ('!name.Contains("/")', '!name.Contains("\\\\")', '!name.Contains("..")'):
    assert part in safe, part
load = pictures.split("PictureTexture@ LoadPicture(const string &in choice) {", 1)[1].split("\n}", 1)[0]
assert 'IsSafeLocalName(choice.SubStr(6))' in load
assert 'IO::FromStorageFolder("LocalImages/" + choice.SubStr(6))' in load
assert '"assets/twemoji/" + choice.SubStr(6) + ".png"' in load
# A failed load is logged once: the failed entry is cached, never retried.
assert 'print("Gorilla Grip Trainer images: could not load " + PictureLabel(choice));' in load
get = pictures.split("PictureTexture@ GetPicture(const string &in choice) {", 1)[1].split("\n}", 1)[0]
assert "g_pictureCache.InsertLast(picture);" in get
assert "if (!S_ShowPictures) return null;" in pictures

# LocalImages lists PNG and JPG files and tolerates a missing folder.
scan = pictures.split("void RefreshLocalImages() {", 1)[1].split("\n}", 1)[0]
assert "if (!IO::FolderExists(folder)) return;" in scan
for ext in ('".png"', '".jpg"', '".jpeg"'):
    assert ext in scan, ext
init = main.split("void Main() {", 1)[1].split("\n}", 1)[0]
assert init.index("InitWidgets();") < init.index("InitPictures();")
print("Picture choices and LocalImages: PASS")

# The AI-generated gorilla left the repository.
assert not (ASSETS / "gorilla-emoji.png").exists()
assert not (ASSETS / "GORILLA_ASSET.md").exists()
print("AI gorilla removed from shipped assets: PASS")
