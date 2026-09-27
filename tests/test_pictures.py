"""Grade popup pictures: shipped emoji sets and LocalImages choices."""

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
SETS = ["fluent-flat", "fluent-color", "fluent-3d", "twemoji", "noto", "openmoji"]

# Each set ships the same twelve 256x256 RGBA PNGs, and nothing else.
emoji = ASSETS / "emoji"
assert sorted(p.name for p in emoji.iterdir() if p.is_dir()) == sorted(SETS)
for emoji_set in SETS:
    folder = emoji / emoji_set
    assert sorted(p.name for p in folder.glob("*.png")) == sorted(f"{n}.png" for n in EMOJI), emoji_set
    for name in EMOJI:
        png = (folder / f"{name}.png").read_bytes()
        assert png[:8] == b"\x89PNG\r\n\x1a\n", (emoji_set, name)
        width, height, depth, colour = struct.unpack(">IIBB", png[16:26])
        assert (width, height, depth, colour) == (256, 256, 8, 6), (emoji_set, name, width, height, depth, colour)
assert not (ASSETS / "twemoji").exists()

# Every source is credited under its licence; MIT and Apache 2.0 ship their text.
attribution = (emoji / "ATTRIBUTION.md").read_text(encoding="utf-8")
for credit in ("Fluent Emoji by Microsoft Corporation", "MIT",
               "Twemoji by Twitter, Inc. and other contributors",
               "https://creativecommons.org/licenses/by/4.0/",
               "Noto Emoji by Google", "Apache License 2.0",
               "OpenMoji", "https://creativecommons.org/licenses/by-sa/4.0/",
               "microsoft/fluentui-emoji@1ffb34c752ecf5d402f04cfb4b392c77f57c54bc",
               "jdecked/twemoji@v16.0.1",
               "googlefonts/noto-emoji@e20cbc2bbec1926686be9f9bee7d1d2cfa1fea0e",
               "hfg-gmuend/openmoji@17.0.0"):
    assert credit in attribution, credit
for name, code in EMOJI.items():
    assert f"| `{name}.png` |" in attribution and code in attribution, name
assert "Permission is hereby granted, free of charge" in (emoji / "LICENSE-MIT-Fluent.txt").read_text(encoding="utf-8")
assert "Apache License" in (emoji / "LICENSE-Apache-2.0.txt").read_text(encoding="utf-8")
readme = (ROOT / "README.md").read_text(encoding="utf-8")
for link in ("[Fluent Emoji](https://github.com/microsoft/fluentui-emoji)",
             "[Twemoji](https://github.com/jdecked/twemoji)",
             "[Noto Emoji](https://github.com/googlefonts/noto-emoji)",
             "[OpenMoji](https://openmoji.org)"):
    assert link in readme, link
assert "LocalImages/" in (ROOT / ".gitignore").read_text(encoding="utf-8").splitlines()

tool = (ROOT / "tools" / "render_emoji.py").read_text(encoding="utf-8")
assert not (ROOT / "tools" / "render_twemoji.py").exists()
for pin in ('TWEMOJI = "v16.0.1"', 'FLUENT = "1ffb34c752ecf5d402f04cfb4b392c77f57c54bc"',
            'NOTO = "e20cbc2bbec1926686be9f9bee7d1d2cfa1fea0e"', 'OPENMOJI = "17.0.0"'):
    assert pin in tool, pin
for name, code in EMOJI.items():
    assert f'"{name}": "{code}"' in tool, name
print("Shipped emoji sets: PASS")

import re

pictures = (ROOT / "plugin" / "Pictures.as").read_text(encoding="utf-8")
main = (ROOT / "plugin" / "Main.as").read_text(encoding="utf-8")

# Seven hidden picture settings with the agreed defaults, plus the master switch.
defaults = dict(re.findall(r'\[Setting hidden\] string (S_Picture\w+) = "([^"]*)";', pictures))
assert defaults == {
    "S_PictureSPlus": "emoji:noto/gorilla", "S_PictureS": "emoji:noto/gorilla",
    "S_PictureA": "emoji:twemoji/flexed-biceps", "S_PictureB": "emoji:twemoji/thumbs-up",
    "S_PictureC": "emoji:twemoji/ok-hand", "S_PictureD": "emoji:twemoji/slightly-smiling-face",
    "S_PictureMissed": "emoji:twemoji/skull",
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
assert '"assets/emoji/" + parts[0] + "/" + parts[1] + ".png"' in load
# A failed load is logged once: the failed entry is cached, never retried.
assert 'print("Gorilla Grip Trainer images: could not load " + choice);' in load
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

# Review fix: an invalid or unreadable image gives no picture instead of a
# per-frame exception (Openplanet returns a 0x0 texture for bad data, and
# IO::File throws on unreadable files); the failed entry is still cached.
load = pictures.split("PictureTexture@ LoadPicture(const string &in choice) {", 1)[1].split("\n}", 1)[0]
assert "try {" in load and "} catch {" in load
assert "if (!TextureUsable(picture.drawing)) @picture.drawing = null;" in load
assert "if (!TextureUsable(picture.thumbnail)) @picture.thumbnail = null;" in load
for kind in ("nvg::Texture@", "UI::Texture@"):
    usable = pictures.split(f"bool TextureUsable({kind} texture) {{", 1)[1].split("\n}", 1)[0]
    assert "texture !is null && texture.GetSize().x > 0 && texture.GetSize().y > 0" in usable, kind
# Review fix: pictures are drawn much smaller than 256 px, so use mipmaps.
assert "nvg::LoadTexture(asset, nvg::TextureFlags::GenerateMipmaps)" in load
assert "nvg::LoadTexture(ReadLocalImage(path), nvg::TextureFlags::GenerateMipmaps)" in load
print("Invalid pictures fail safely, with mipmaps: PASS")

# Each picture picks its own source: an emoji set, a local file, or none.
# "emoji:<set>/<name>" names the set; the older "emoji:<name>" reads as Twemoji,
# and an unknown set or picture counts as none.
assert "S_EmojiSet" not in pictures and "EmojiSet()" not in pictures
parts = pictures.split("array<string>@ EmojiChoiceParts(const string &in choice) {", 1)[1].split("\n}", 1)[0]
assert 'string emojiSet = slash < 0 ? "twemoji" : rest.SubStr(0, slash);' in parts
assert "if (EmojiSetIndex(emojiSet) < 0 || EmojiIndex(emojiName) < 0) return null;" in parts
source = pictures.split("string PictureSource(const string &in choice) {", 1)[1].split("\n}", 1)[0]
assert 'if (choice.StartsWith("local:")) return "local";' in source
assert "if (parts !is null) return parts[0];" in source
tab = (ROOT / "plugin" / "PopupTab.as").read_text(encoding="utf-8")
assert 'UI::BeginCombo("Emoji set"' not in tab
row = tab.split("void RenderPictureRow(const string &in result) {", 1)[1].split("\n}", 1)[0]
assert 'UI::BeginCombo("##source", PictureSourceLabel(source))' in row
assert 'UI::BeginCombo("##picture", PictureLabel(choice))' in row
# Switching sets keeps the same picture, so sets compare in one click.
assert 'SetPictureSetting(result, "emoji:" + g_emojiSets[i] + "/" + keepName);' in row
assert 'SetPictureSetting(result, "emoji:" + source + "/" + g_emojiNames[i]);' in row
assert 'if (UI::Selectable("Local file", source == "local") && source != "local")' in row
assert 'SetPictureSetting(result, "local:" + g_localImages[i]);' in row
print("Each picture picks its own emoji set or local file: PASS")
