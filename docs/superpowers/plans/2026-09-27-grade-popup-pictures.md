# Grade Popup Styles, Effects, and Pictures Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the confirmed-landing popup with three selectable, mixable, intensity-scaled animation styles, and show one Twemoji or local picture per result, configured on a new Popup settings tab.

**Architecture:** `Pictures.as` owns picture choices, the shipped Twemoji catalogue, `LocalImages`, and a texture cache. `GradeAnimation.as` owns popup settings, style/effect/intensity rules, a seeded random generator, the preview clock, and the new `RenderResult`. `PopupTab.as` is the settings UI. `Widgets.as` keeps the shared HUD helpers and calls `RenderResult` for real results, the Layout sample, and previews.

**Tech Stack:** Openplanet AngelScript (NanoVG `nvg::`, ImGui `UI::`, `IO::`), Python 3 source-contract tests run directly (`python tests/<name>.py`), headless Chrome for SVG→PNG rendering.

**Spec:** `docs/superpowers/specs/2026-09-27-grade-popup-pictures-design.md`

## Global Constraints

- Work in `Trainer/`. Git needs `git -c safe.directory=*` on this machine (the folder is owned by another Windows user).
- VehicleState stays the only plugin dependency; no new Python packages.
- Twemoji source: `jdecked/twemoji` tag `v16.0.1` via `https://cdn.jsdelivr.net/gh/jdecked/twemoji@v16.0.1/assets/svg/<codepoint>.svg`; shipped PNGs are 256×256 RGBA; licence CC-BY 4.0 with attribution.
- Popup timing envelope: effects in the first ~0.8 s; fade-out 700–1000 ms after the verdict; `s = min(w / 500, h / 125)`; full panel width 480 units, height 105 units.
- Power: S+ 1.0, S 0.8, A 0.55, B 0.4, C 0.3, D 0.2, MISSED 0.5; anything else is calm (power 0).
- Particle count `round((6 + 34 × power) × k)`, particle speed `(120 + 320 × power) × k` units/s, crack count `round((4 + 8 × power) × k)`, snowflakes S+ 10 / S 6 × k.
- Intensity `S_PopupIntensity` int 0–200, default 100, `k = clamp(intensity, 0, 200) / 100`; never changes timing, panel, letter entrance or glow, caption, or pictures. At 0 % no flash or effect.
- Style strings: `ice` (default), `arcade`, `broadcast`; unknown → `ice`.
- Effect defaults: Ice = cracks, shards, snowflakes, rays; Arcade = shake, shockwave, sparks, rays; Broadcast = sheen, outline.
- Picture choice strings: `emoji:<name>`, `local:<file>`, or empty; defaults S+ and S `emoji:gorilla`, A `emoji:flexed-biceps`, B `emoji:thumbs-up`, C `emoji:ok-hand`, D `emoji:slightly-smiling-face`, MISSED `emoji:skull`.
- All new settings are `[Setting hidden]`. Tab order: Rating 1, Sounds 2, Popup 3, Layout 4, Debug 99; every custom tab uses `icon=""`.
- Problems are always logged with `print("Gorilla Grip Trainer ...")`; routine lines use `DebugLog`.
- Do not run live game automation. Installing into `~/OpenplanetNext/Plugins/GorillaGripTrainer/` is allowed; the user reloads the plugin. Never delete or reset `PluginStorage` data; the only PluginStorage write is copying the old gorilla into `LocalImages`.
- `LocalImages/`, `LocalSounds/`, and all local media stay out of Git. Check `git diff --check` and the staged file list before each commit.

## Review Focus

1. A local file that is not a valid image (for example a renamed text file) → no picture for that result, one log line, no script exception. Pinned in Task 2 (load path returns a cached entry with a null texture and logs once) and checked live in Task 6.
2. Hand-edited settings out of range (`S_PopupIntensity = 999`, `S_PopupStyle = "foo"`) → intensity clamps to 200 %, style falls back to Ice shatter. Pinned in Task 3.
3. A `local:` choice containing `/`, `\`, or `..` → treated as None and never read. Pinned in Task 2.
4. A real landing while a Preview is running → the real result replaces the preview. Pinned in Task 5.
5. A non-square local picture → drawn inside the 72-unit square without stretching. Pinned in Task 4.

---

## File Structure

| File | Responsibility |
| --- | --- |
| Create `tools/render_twemoji.py` | Download the twelve pinned Twemoji SVGs and render 256×256 PNGs with headless Chrome. |
| Create `plugin/assets/twemoji/*.png` (12) | Shipped pictures. |
| Create `plugin/assets/twemoji/ATTRIBUTION.md` | CC-BY 4.0 credit and file list. |
| Create `plugin/Pictures.as` | Picture settings, catalogue, choice parsing, `LocalImages` scan, texture cache. |
| Create `plugin/GradeAnimation.as` | Popup settings, styles, effects, intensity, random generator, preview clock, `RenderResult`. |
| Create `plugin/PopupTab.as` | Popup settings tab. |
| Modify `plugin/Widgets.as` | Remove old gorilla code and old `RenderResult`; stop previews on real results; draw previews. |
| Modify `plugin/Main.as` | Call `InitPictures()`. |
| Modify `plugin/Layout.as` | Layout tab order 3 → 4. |
| Delete `plugin/assets/gorilla-emoji.png`, `plugin/assets/GORILLA_ASSET.md` | AI-generated art leaves the repo. |
| Modify `.gitignore`, `README.md`, `AGENTS.md`, `docs/superpowers/specs/2026-09-25-gorilla-grip-trainer.md` | Ignore `LocalImages/`, credit Twemoji, describe the Popup tab. |
| Create `tests/test_pictures.py`, `tests/test_grade_animation.py`, `tests/test_popup_tab.py` | Source-contract tests. |
| Modify `tests/test_debug_logging.py`, `tests/test_presentation_contract.py` | Logging list/count, gorilla asset checks, tab order. |

---

### Task 1: Shipped Twemoji pictures

**Files:**
- Create: `tools/render_twemoji.py`
- Create: `plugin/assets/twemoji/<name>.png` (12 files, generated)
- Create: `plugin/assets/twemoji/ATTRIBUTION.md`
- Modify: `.gitignore`, `README.md`
- Test: `tests/test_pictures.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `plugin/assets/twemoji/<name>.png` for the names `gorilla`, `oncoming-fist`, `flexed-biceps`, `fire`, `thumbs-up`, `ok-hand`, `slightly-smiling-face`, `skull`, `ice`, `snowflake`, `trophy`, `star` (Task 2 loads `assets/twemoji/<name>.png`).

- [ ] **Step 1: Write the failing test**

Create `tests/test_pictures.py`:

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python tests/test_pictures.py`
Expected: FAIL with `AssertionError` on the first `sorted(...)` assertion (no PNGs yet).

- [ ] **Step 3: Write the render tool**

Create `tools/render_twemoji.py`:

```python
"""Download the shipped Twemoji SVGs and render them as 256x256 PNGs.

Headless Chrome (or Edge) does the rendering, so no imaging packages are
needed. Run from the Trainer folder: py -3 tools/render_twemoji.py
"""

from __future__ import annotations

import argparse
import subprocess
import tempfile
import urllib.request
from pathlib import Path


VERSION = "v16.0.1"
BASE = f"https://cdn.jsdelivr.net/gh/jdecked/twemoji@{VERSION}/assets/svg/"
EMOJI = {
    "gorilla": "1f98d",
    "oncoming-fist": "1f44a",
    "flexed-biceps": "1f4aa",
    "fire": "1f525",
    "thumbs-up": "1f44d",
    "ok-hand": "1f44c",
    "slightly-smiling-face": "1f642",
    "skull": "1f480",
    "ice": "1f9ca",
    "snowflake": "2744",
    "trophy": "1f3c6",
    "star": "2b50",
}
SIZE = 256
OUT = Path(__file__).resolve().parents[1] / "plugin" / "assets" / "twemoji"
BROWSERS = (
    Path("C:/Program Files/Google/Chrome/Application/chrome.exe"),
    Path("C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"),
)


def find_browser(explicit: str | None) -> Path:
    candidates = [Path(explicit)] if explicit else list(BROWSERS)
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise SystemExit("Chrome or Edge not found; pass --browser <path-to-exe>.")


def render(browser: Path, svg: Path, png: Path) -> None:
    page = svg.with_suffix(".html")
    page.write_text(
        '<html><body style="margin:0;background:transparent">'
        f'<img src="{svg.name}" width="{SIZE}" height="{SIZE}" style="display:block">'
        "</body></html>",
        encoding="utf-8",
    )
    subprocess.run(
        [str(browser), "--headless=new", "--disable-gpu", "--hide-scrollbars",
         "--default-background-color=00000000", f"--window-size={SIZE},{SIZE}",
         f"--screenshot={png}", page.as_uri()],
        check=True, capture_output=True, timeout=60,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--browser", help="path to chrome.exe or msedge.exe")
    args = parser.parse_args()
    browser = find_browser(args.browser)
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for name, code in EMOJI.items():
            svg = Path(tmp) / f"{name}.svg"
            with urllib.request.urlopen(BASE + code + ".svg", timeout=30) as response:
                svg.write_bytes(response.read())
            render(browser, svg, OUT / f"{name}.png")
            print(f"{name}.png <- {code}.svg")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Render the PNGs**

Run: `py -3 tools/render_twemoji.py`
Expected: twelve lines such as `gorilla.png <- 1f98d.svg`, and twelve PNGs in `plugin/assets/twemoji/`. Open `gorilla.png` and `skull.png` in an image viewer to confirm a transparent background.

- [ ] **Step 5: Write the attribution, README credit, and ignore rule**

Create `plugin/assets/twemoji/ATTRIBUTION.md`:

```markdown
# Twemoji pictures

The PNG files in this folder are Twemoji by Twitter, Inc. and other contributors,
licensed under CC-BY 4.0 (https://creativecommons.org/licenses/by/4.0/).
They were rendered at 256×256 from the SVGs of the maintained Twemoji project,
https://github.com/jdecked/twemoji, tag v16.0.1, by `tools/render_twemoji.py`.
The pictures are unchanged apart from rasterization.

| File | Emoji | Codepoint |
| --- | --- | --- |
| `gorilla.png` | 🦍 | 1f98d |
| `oncoming-fist.png` | 👊 | 1f44a |
| `flexed-biceps.png` | 💪 | 1f4aa |
| `fire.png` | 🔥 | 1f525 |
| `thumbs-up.png` | 👍 | 1f44d |
| `ok-hand.png` | 👌 | 1f44c |
| `slightly-smiling-face.png` | 🙂 | 1f642 |
| `skull.png` | 💀 | 1f480 |
| `ice.png` | 🧊 | 1f9ca |
| `snowflake.png` | ❄️ | 2744 |
| `trophy.png` | 🏆 | 1f3c6 |
| `star.png` | ⭐ | 2b50 |
```

Append to the end of `README.md`:

```markdown

Emoji pictures: [Twemoji](https://github.com/jdecked/twemoji) by Twitter, Inc. and other contributors, licensed under [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/); see `plugin/assets/twemoji/ATTRIBUTION.md`.
```

In `.gitignore`, add a line `LocalImages/` directly after `LocalSounds/`.

- [ ] **Step 6: Run test to verify it passes**

Run: `python tests/test_pictures.py`
Expected: `Shipped Twemoji pictures: PASS`

- [ ] **Step 7: Commit**

```bash
git -c safe.directory=* add tools/render_twemoji.py plugin/assets/twemoji tests/test_pictures.py README.md .gitignore
git -c safe.directory=* diff --cached --check
git -c safe.directory=* diff --cached --stat
git -c safe.directory=* commit -m "Ship twelve Twemoji pictures for the grade popup"
```

End the commit message with the `Co-Authored-By` line from the session instructions. The staged list must show exactly 12 PNGs, `ATTRIBUTION.md`, the tool, the test, `README.md`, and `.gitignore`.

---

### Task 2: Picture choices, LocalImages, and texture cache

**Files:**
- Create: `plugin/Pictures.as`
- Modify: `plugin/Main.as` (in `Main()`, after `InitWidgets();`)
- Modify: `tests/test_debug_logging.py`
- Test: `tests/test_pictures.py` (append)

**Interfaces:**
- Consumes: Task 1 PNG names.
- Produces (used by Tasks 3–5):
  - `array<string> g_pictureResults` = `{"S+", "S", "A", "B", "C", "D", "MISSED"}`
  - `array<string> g_emojiNames`, `array<string> g_emojiLabels` (same order as Task 1)
  - `array<string> g_localImages`, `bool g_localImagesScanned`
  - `string DefaultPicture(const string &in result)`
  - `string PictureSetting(const string &in result)`
  - `void SetPictureSetting(const string &in result, const string &in choice)`
  - `void ResetPictureSettings()`
  - `string PictureLabel(const string &in choice)` → `"None"`, an emoji label, or the local file name
  - `class PictureTexture { string choice; nvg::Texture@ drawing; UI::Texture@ thumbnail; }`
  - `PictureTexture@ GetPicture(const string &in choice)` (null for None/invalid)
  - `nvg::Texture@ PictureForResult(const string &in result)` (null when pictures are off, None, or failed)
  - `void RefreshLocalImages()`, `void ClearPictureCache()`, `void InitPictures()`

- [ ] **Step 1: Write the failing test**

Append to `tests/test_pictures.py` (after the existing `print`):

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python tests/test_pictures.py`
Expected: first line PASS, then `FileNotFoundError` for `plugin/Pictures.as`.

- [ ] **Step 3: Write `plugin/Pictures.as`**

```angelscript
// Pictures beside the grade popup: shipped Twemoji art or the user's own PNG
// and JPG files in LocalImages. Each result stores one choice string:
// "emoji:<name>", "local:<file>", or "" for no picture.
[Setting hidden] bool S_ShowPictures = true;
[Setting hidden] string S_PictureSPlus = "emoji:gorilla";
[Setting hidden] string S_PictureS = "emoji:gorilla";
[Setting hidden] string S_PictureA = "emoji:flexed-biceps";
[Setting hidden] string S_PictureB = "emoji:thumbs-up";
[Setting hidden] string S_PictureC = "emoji:ok-hand";
[Setting hidden] string S_PictureD = "emoji:slightly-smiling-face";
[Setting hidden] string S_PictureMissed = "emoji:skull";

array<string> g_pictureResults = {"S+", "S", "A", "B", "C", "D", "MISSED"};
array<string> g_emojiNames = {"gorilla", "oncoming-fist", "flexed-biceps",
    "fire", "thumbs-up", "ok-hand", "slightly-smiling-face", "skull", "ice",
    "snowflake", "trophy", "star"};
array<string> g_emojiLabels = {"Gorilla", "Oncoming fist", "Flexed biceps",
    "Fire", "Thumbs up", "OK hand", "Slightly smiling face", "Skull", "Ice",
    "Snowflake", "Trophy", "Star"};

string DefaultPicture(const string &in result) {
    if (result == "S+" || result == "S") return "emoji:gorilla";
    if (result == "A") return "emoji:flexed-biceps";
    if (result == "B") return "emoji:thumbs-up";
    if (result == "C") return "emoji:ok-hand";
    if (result == "D") return "emoji:slightly-smiling-face";
    if (result == "MISSED") return "emoji:skull";
    return "";
}

string PictureSetting(const string &in result) {
    if (result == "S+") return S_PictureSPlus;
    if (result == "S") return S_PictureS;
    if (result == "A") return S_PictureA;
    if (result == "B") return S_PictureB;
    if (result == "C") return S_PictureC;
    if (result == "D") return S_PictureD;
    if (result == "MISSED") return S_PictureMissed;
    return "";
}

void SetPictureSetting(const string &in result, const string &in choice) {
    if (result == "S+") S_PictureSPlus = choice;
    else if (result == "S") S_PictureS = choice;
    else if (result == "A") S_PictureA = choice;
    else if (result == "B") S_PictureB = choice;
    else if (result == "C") S_PictureC = choice;
    else if (result == "D") S_PictureD = choice;
    else if (result == "MISSED") S_PictureMissed = choice;
}

void ResetPictureSettings() {
    S_ShowPictures = true;
    for (uint i = 0; i < g_pictureResults.Length; i++)
        SetPictureSetting(g_pictureResults[i], DefaultPicture(g_pictureResults[i]));
}

int EmojiIndex(const string &in name) {
    for (uint i = 0; i < g_emojiNames.Length; i++)
        if (g_emojiNames[i] == name) return int(i);
    return -1;
}

// A local choice names one file directly inside LocalImages.
bool IsSafeLocalName(const string &in name) {
    return name.Length > 0 && !name.Contains("/") && !name.Contains("\\") &&
        !name.Contains("..");
}

string PictureLabel(const string &in choice) {
    if (choice.StartsWith("emoji:")) {
        int i = EmojiIndex(choice.SubStr(6));
        if (i >= 0) return g_emojiLabels[i];
    }
    if (choice.StartsWith("local:") && IsSafeLocalName(choice.SubStr(6)))
        return choice.SubStr(6);
    return "None";
}

class PictureTexture {
    string choice;
    nvg::Texture@ drawing;
    UI::Texture@ thumbnail;
}

array<PictureTexture@> g_pictureCache;
array<string> g_localImages;
bool g_localImagesScanned = false;

MemoryBuffer@ ReadLocalImage(const string &in path) {
    IO::File file(path, IO::FileMode::Read);
    MemoryBuffer@ buffer = file.Read(file.Size());
    file.Close();
    return buffer;
}

PictureTexture@ LoadPicture(const string &in choice) {
    PictureTexture@ picture = PictureTexture();
    picture.choice = choice;
    if (choice.StartsWith("emoji:") && EmojiIndex(choice.SubStr(6)) >= 0) {
        string asset = "assets/twemoji/" + choice.SubStr(6) + ".png";
        @picture.drawing = nvg::LoadTexture(asset);
        @picture.thumbnail = UI::LoadTexture(asset);
    } else if (choice.StartsWith("local:") && IsSafeLocalName(choice.SubStr(6))) {
        string path = IO::FromStorageFolder("LocalImages/" + choice.SubStr(6));
        if (IO::FileExists(path)) {
            @picture.drawing = nvg::LoadTexture(ReadLocalImage(path));
            @picture.thumbnail = UI::LoadTexture(ReadLocalImage(path));
        }
    } else {
        return null;
    }
    if (picture.drawing is null)
        print("Gorilla Grip Trainer images: could not load " + PictureLabel(choice));
    return picture;
}

// Loads each choice once; a failed load stays cached so it is logged once.
PictureTexture@ GetPicture(const string &in choice) {
    if (choice.Length == 0) return null;
    for (uint i = 0; i < g_pictureCache.Length; i++)
        if (g_pictureCache[i].choice == choice) return g_pictureCache[i];
    PictureTexture@ picture = LoadPicture(choice);
    if (picture !is null) g_pictureCache.InsertLast(picture);
    return picture;
}

void ClearPictureCache() {
    g_pictureCache.RemoveRange(0, g_pictureCache.Length);
}

nvg::Texture@ PictureForResult(const string &in result) {
    if (!S_ShowPictures) return null;
    PictureTexture@ picture = GetPicture(PictureSetting(result));
    if (picture is null) return null;
    return picture.drawing;
}

void RefreshLocalImages() {
    g_localImages.RemoveRange(0, g_localImages.Length);
    g_localImagesScanned = true;
    string folder = IO::FromStorageFolder("LocalImages");
    if (!IO::FolderExists(folder)) return;
    array<string>@ files = IO::IndexFolder(folder, false);
    if (files is null) return;
    for (uint i = 0; i < files.Length; i++) {
        string name = Path::GetFileName(files[i]);
        // Path::GetExtension may or may not include the dot, as in
        // RefreshSoundFiles, so accept both forms.
        string extension = Path::GetExtension(name).ToLower();
        if (extension != ".png" && extension != ".jpg" && extension != ".jpeg" &&
            extension != "png" && extension != "jpg" && extension != "jpeg") continue;
        if (IsSafeLocalName(name)) g_localImages.InsertLast(name);
    }
    g_localImages.SortAsc();
}

// Scan LocalImages and load the chosen pictures so the first popup does not
// stall on a texture load.
void InitPictures() {
    RefreshLocalImages();
    for (uint i = 0; i < g_pictureResults.Length; i++)
        PictureForResult(g_pictureResults[i]);
}
```

- [ ] **Step 4: Call `InitPictures()` from `Main()`**

In `plugin/Main.as`, change:

```angelscript
    InitLayout();
    InitWidgets();
```

to:

```angelscript
    InitLayout();
    InitWidgets();
    InitPictures();
```

- [ ] **Step 5: Update the logging test**

In `tests/test_debug_logging.py`, add `"Gorilla Grip Trainer images: could not load",` to the `PROBLEMS` tuple (after the `history: preserved corrupt file` entry) and change the count line to:

```python
assert len(calls) == 31, len(calls)  # 17 routine events, 13 problems, 1 state marker
```

- [ ] **Step 6: Run the tests**

Run: `python tests/test_pictures.py` then `python tests/test_debug_logging.py`
Expected: `Shipped Twemoji pictures: PASS`, `Picture choices and LocalImages: PASS`, `Routine trainer logging is behind the Debug switch: PASS`.

- [ ] **Step 7: Commit**

```bash
git -c safe.directory=* add plugin/Pictures.as plugin/Main.as tests/test_pictures.py tests/test_debug_logging.py
git -c safe.directory=* diff --cached --check
git -c safe.directory=* commit -m "Add per-result picture choices with LocalImages support"
```

---

### Task 3: Popup settings, styles, effects, intensity, and preview clock

**Files:**
- Create: `plugin/GradeAnimation.as` (model half; Task 4 appends rendering)
- Test: `tests/test_grade_animation.py`

**Interfaces:**
- Consumes: `g_pictureResults` (Task 2).
- Produces (used by Tasks 4–5):
  - settings `S_PopupStyle`, `S_PopupIntensity`, `S_FxShake`, `S_FxShockwave`, `S_FxSparks`, `S_FxCracks`, `S_FxShards`, `S_FxSnowflakes`, `S_FxRays`, `S_FxSheen`, `S_FxOutline`
  - `const int FX_SHAKE = 1, FX_SHOCKWAVE = 2, FX_SPARKS = 4, FX_CRACKS = 8, FX_SHARDS = 16, FX_SNOWFLAKES = 32, FX_RAYS = 64, FX_SHEEN = 128, FX_OUTLINE = 256`
  - `array<string> g_popupStyles` = `{"ice", "arcade", "broadcast"}`, `array<string> g_popupStyleLabels` = `{"Ice shatter", "Arcade slam", "Broadcast sheen"}`
  - `string PopupStyle()`, `int StyleEffects(const string &in style)`, `int CurrentEffects()`, `void ApplyEffects(int effects)`, `void SelectPopupStyle(const string &in style)`, `string PopupStyleLabel()`, `void ResetPopupSettings()`, `float PopupIntensity()`
  - `float ResultPower(const string &in label)`, `int ParticleCount(float power, float k)`, `int CrackCount(float power, float k)`, `float ParticleSpeed(float power, float k)`, `int SnowflakeCount(const string &in label, float k)`
  - `float Clamp01(float x)`, `float EaseOutCubic(float x)`, `float EaseOutBack(float x)`, `vec4 LerpColor(const vec4 &in a, const vec4 &in b, float t)`
  - `class PopupRandom { PopupRandom(uint seed); float Next(); }`
  - `string g_popupPreviewLabel`, `void StartPopupPreview(const string &in label)`, `void StopPopupPreview()`, `int PopupPreviewAge()`, `uint PopupPreviewSeed(const string &in label)`

- [ ] **Step 1: Write the failing test**

Create `tests/test_grade_animation.py`:

```python
"""Grade popup styles, effects, intensity, and rendering contract."""

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "plugin"
anim = (ROOT / "GradeAnimation.as").read_text(encoding="utf-8")


def body(signature: str, text: str = anim) -> str:
    return text.split(signature + " {", 1)[1].split("\n}", 1)[0]


# Settings default to plain Ice shatter at 100 %.
settings = dict(re.findall(r"\[Setting hidden\] \w+ (S_\w+) = ([^;]+);", anim))
assert settings == {
    "S_PopupStyle": '"ice"', "S_PopupIntensity": "100",
    "S_FxShake": "false", "S_FxShockwave": "false", "S_FxSparks": "false",
    "S_FxCracks": "true", "S_FxShards": "true", "S_FxSnowflakes": "true",
    "S_FxRays": "true", "S_FxSheen": "false", "S_FxOutline": "false",
}, settings

# Style effect sets match the spec's effects table.
styles = body("int StyleEffects(const string &in style)")
assert 'if (style == "arcade") return FX_SHAKE | FX_SHOCKWAVE | FX_SPARKS | FX_RAYS;' in styles
assert 'if (style == "broadcast") return FX_SHEEN | FX_OUTLINE;' in styles
assert "return FX_CRACKS | FX_SHARDS | FX_SNOWFLAKES | FX_RAYS;" in styles
flags = dict(re.findall(r"const int (FX_\w+) = (\d+);", anim))
assert flags == {"FX_SHAKE": "1", "FX_SHOCKWAVE": "2", "FX_SPARKS": "4", "FX_CRACKS": "8",
                 "FX_SHARDS": "16", "FX_SNOWFLAKES": "32", "FX_RAYS": "64",
                 "FX_SHEEN": "128", "FX_OUTLINE": "256"}, flags

# Unknown styles fall back to Ice; choosing a style applies its effects;
# a changed effect set shows "(custom)".
assert 'return S_PopupStyle == "arcade" || S_PopupStyle == "broadcast" ? S_PopupStyle : "ice";' in body("string PopupStyle()")
select = body("void SelectPopupStyle(const string &in style)")
assert "ApplyEffects(StyleEffects(PopupStyle()));" in select
label = body("string PopupStyleLabel()")
assert 'if (CurrentEffects() != StyleEffects(style)) name += " (custom)";' in label
reset = body("void ResetPopupSettings()")
assert 'SelectPopupStyle("ice");' in reset and "S_PopupIntensity = 100;" in reset

# Intensity is clamped to 0-200 % (Review Focus 2).
assert "return float(Math::Clamp(S_PopupIntensity, 0, 200)) / 100.0f;" in body("float PopupIntensity()")

# Power table and count formulas; the spec's per-grade numbers follow from them.
power = body("float ResultPower(const string &in label)")
POWER = {"S+": 1.0, "S": 0.8, "A": 0.55, "B": 0.4, "C": 0.3, "D": 0.2, "MISSED": 0.5}
for grade, value in POWER.items():
    literal = f"{value}f"
    assert f'if (label == "{grade}") return {literal};' in power, grade
assert "return 0.0f;" in power
assert "return int((6.0f + 34.0f*power)*k + 0.5f);" in body("int ParticleCount(float power, float k)")
assert "return int((4.0f + 8.0f*power)*k + 0.5f);" in body("int CrackCount(float power, float k)")
assert "return (120.0f + 320.0f*power)*k;" in body("float ParticleSpeed(float power, float k)")
snow = body("int SnowflakeCount(const string &in label, float k)")
assert 'label == "S+" ? 10.0f : (label == "S" ? 6.0f : 0.0f)' in snow
particles = {g: int(6 + 34 * p + 0.5) for g, p in POWER.items()}
cracks = {g: int(4 + 8 * p + 0.5) for g, p in POWER.items()}
assert particles == {"S+": 40, "S": 33, "A": 25, "B": 20, "C": 16, "D": 13, "MISSED": 23}, particles
assert cracks == {"S+": 12, "S": 10, "A": 8, "B": 7, "C": 6, "D": 5, "MISSED": 8}, cracks

# The generator is deterministic for a seed; the preview clock lasts 1 s.
assert "class PopupRandom {" in anim and "float Next() {" in anim
age = body("int PopupPreviewAge()")
assert "if (elapsed >= 1000) {" in age and "StopPopupPreview();" in age
assert "g_popupPreviewStart = Time::Now;" in body("void StartPopupPreview(const string &in label)")
print("Popup styles, effects, and intensity model: PASS")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python tests/test_grade_animation.py`
Expected: FAIL with `FileNotFoundError` for `plugin/GradeAnimation.as`.

- [ ] **Step 3: Write the model half of `plugin/GradeAnimation.as`**

```angelscript
// The confirmed-landing popup: three styles whose effects can be mixed and
// scaled by one intensity setting. A style sets the base look and switches on
// its own effects; every effect can then be turned on or off with any style.
[Setting hidden] string S_PopupStyle = "ice";
[Setting hidden] int S_PopupIntensity = 100;
[Setting hidden] bool S_FxShake = false;
[Setting hidden] bool S_FxShockwave = false;
[Setting hidden] bool S_FxSparks = false;
[Setting hidden] bool S_FxCracks = true;
[Setting hidden] bool S_FxShards = true;
[Setting hidden] bool S_FxSnowflakes = true;
[Setting hidden] bool S_FxRays = true;
[Setting hidden] bool S_FxSheen = false;
[Setting hidden] bool S_FxOutline = false;

const int FX_SHAKE = 1;
const int FX_SHOCKWAVE = 2;
const int FX_SPARKS = 4;
const int FX_CRACKS = 8;
const int FX_SHARDS = 16;
const int FX_SNOWFLAKES = 32;
const int FX_RAYS = 64;
const int FX_SHEEN = 128;
const int FX_OUTLINE = 256;

array<string> g_popupStyles = {"ice", "arcade", "broadcast"};
array<string> g_popupStyleLabels = {"Ice shatter", "Arcade slam", "Broadcast sheen"};

string PopupStyle() {
    return S_PopupStyle == "arcade" || S_PopupStyle == "broadcast" ? S_PopupStyle : "ice";
}

int StyleEffects(const string &in style) {
    if (style == "arcade") return FX_SHAKE | FX_SHOCKWAVE | FX_SPARKS | FX_RAYS;
    if (style == "broadcast") return FX_SHEEN | FX_OUTLINE;
    return FX_CRACKS | FX_SHARDS | FX_SNOWFLAKES | FX_RAYS;
}

int CurrentEffects() {
    int effects = 0;
    if (S_FxShake) effects |= FX_SHAKE;
    if (S_FxShockwave) effects |= FX_SHOCKWAVE;
    if (S_FxSparks) effects |= FX_SPARKS;
    if (S_FxCracks) effects |= FX_CRACKS;
    if (S_FxShards) effects |= FX_SHARDS;
    if (S_FxSnowflakes) effects |= FX_SNOWFLAKES;
    if (S_FxRays) effects |= FX_RAYS;
    if (S_FxSheen) effects |= FX_SHEEN;
    if (S_FxOutline) effects |= FX_OUTLINE;
    return effects;
}

void ApplyEffects(int effects) {
    S_FxShake = (effects & FX_SHAKE) != 0;
    S_FxShockwave = (effects & FX_SHOCKWAVE) != 0;
    S_FxSparks = (effects & FX_SPARKS) != 0;
    S_FxCracks = (effects & FX_CRACKS) != 0;
    S_FxShards = (effects & FX_SHARDS) != 0;
    S_FxSnowflakes = (effects & FX_SNOWFLAKES) != 0;
    S_FxRays = (effects & FX_RAYS) != 0;
    S_FxSheen = (effects & FX_SHEEN) != 0;
    S_FxOutline = (effects & FX_OUTLINE) != 0;
}

void SelectPopupStyle(const string &in style) {
    S_PopupStyle = style;
    ApplyEffects(StyleEffects(PopupStyle()));
}

string PopupStyleLabel() {
    string style = PopupStyle();
    string name = g_popupStyleLabels[0];
    for (uint i = 0; i < g_popupStyles.Length; i++)
        if (g_popupStyles[i] == style) name = g_popupStyleLabels[i];
    if (CurrentEffects() != StyleEffects(style)) name += " (custom)";
    return name;
}

void ResetPopupSettings() {
    SelectPopupStyle("ice");
    S_PopupIntensity = 100;
}

float PopupIntensity() {
    return float(Math::Clamp(S_PopupIntensity, 0, 200)) / 100.0f;
}

// Better grades get bigger effects; non-results (UNRATED) are calm.
float ResultPower(const string &in label) {
    if (label == "S+") return 1.0f;
    if (label == "S") return 0.8f;
    if (label == "A") return 0.55f;
    if (label == "B") return 0.4f;
    if (label == "C") return 0.3f;
    if (label == "D") return 0.2f;
    if (label == "MISSED") return 0.5f;
    return 0.0f;
}

int ParticleCount(float power, float k) {
    return int((6.0f + 34.0f*power)*k + 0.5f);
}

int CrackCount(float power, float k) {
    return int((4.0f + 8.0f*power)*k + 0.5f);
}

float ParticleSpeed(float power, float k) {
    return (120.0f + 320.0f*power)*k;
}

int SnowflakeCount(const string &in label, float k) {
    float base = label == "S+" ? 10.0f : (label == "S" ? 6.0f : 0.0f);
    return int(base*k + 0.5f);
}

float Clamp01(float x) {
    return Math::Clamp(x, 0.0f, 1.0f);
}

float EaseOutCubic(float x) {
    float r = 1.0f - Clamp01(x);
    return 1.0f - r*r*r;
}

// Overshoots slightly past 1 before settling; 0 at x <= 0.
float EaseOutBack(float x) {
    float m = Clamp01(x) - 1.0f;
    return 1.0f + 2.9f*m*m*m + 1.9f*m*m;
}

vec4 LerpColor(const vec4 &in a, const vec4 &in b, float t) {
    return a + (b - a)*t;
}

// Xorshift generator: the same seed always gives the same layout, so shards
// and cracks never reshuffle between frames.
class PopupRandom {
    uint state;

    PopupRandom(uint seed) {
        state = seed*uint(1103515245) + uint(12345);
        if (state == 0) state = 1;
    }

    float Next() {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        return float(state % 16777216) / 16777216.0f;
    }
}

// A Popup-tab preview runs on its own clock for one second.
string g_popupPreviewLabel = "";
uint64 g_popupPreviewStart = 0;

void StartPopupPreview(const string &in label) {
    g_popupPreviewLabel = label;
    g_popupPreviewStart = Time::Now;
}

void StopPopupPreview() {
    g_popupPreviewLabel = "";
}

int PopupPreviewAge() {
    if (g_popupPreviewLabel.Length == 0) return -1;
    uint64 elapsed = Time::Now - g_popupPreviewStart;
    if (elapsed >= 1000) {
        StopPopupPreview();
        return -1;
    }
    return int(elapsed);
}

uint PopupPreviewSeed(const string &in label) {
    for (uint i = 0; i < g_pictureResults.Length; i++)
        if (g_pictureResults[i] == label) return uint(7919*(i + 2));
    return 7919;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python tests/test_grade_animation.py`
Expected: `Popup styles, effects, and intensity model: PASS`

- [ ] **Step 5: Commit**

```bash
git -c safe.directory=* add plugin/GradeAnimation.as tests/test_grade_animation.py
git -c safe.directory=* diff --cached --check
git -c safe.directory=* commit -m "Add popup style, effect, and intensity settings"
```

---

### Task 4: Render the popup styles and effects; retire the AI gorilla

**Files:**
- Modify: `plugin/GradeAnimation.as` (append rendering)
- Modify: `plugin/Widgets.as` (delete lines for `g_gorillaTexture`, its load in `InitWidgets`, `GorillaDot`, `DrawGorillaEmoji`, `DrawFallbackFlame`, `RenderSGorillas`, and the old `RenderResult`; update the one `RenderResult` call)
- Delete: `plugin/assets/gorilla-emoji.png`, `plugin/assets/GORILLA_ASSET.md`
- Modify: `tests/test_presentation_contract.py`, `tests/test_debug_logging.py`
- Test: `tests/test_grade_animation.py` (append), `tests/test_pictures.py` (append)

**Interfaces:**
- Consumes: everything Task 3 produces; `PictureForResult` (Task 2); `GradeColor`, `GradeBasePoints`, `ResultCaption`, `HudBox`, `HudText`, `HudColor` (existing).
- Produces: `void RenderResult(const vec4 &in r, int age, const string &in label, bool estimated, uint seed)` (Task 5 calls it for previews).

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_grade_animation.py`:

```python
widgets = (ROOT / "Widgets.as").read_text(encoding="utf-8")

# One RenderResult, in GradeAnimation.as, with a seed.
assert "void RenderResult(const vec4 &in r, int age, const string &in label,\n    bool estimated, uint seed) {" in anim
assert "void RenderResult(" not in widgets
for gone in ("g_gorillaTexture", "RenderSGorillas", "DrawGorillaEmoji", "DrawFallbackFlame", "GorillaDot"):
    assert gone not in widgets, gone
assert "RenderResult(layout.Pixels(), active ? age : 450," in widgets
assert "active ? uint(g_resultShownAt) + 1 : 1" in widgets

render = body("void RenderResult(const vec4 &in r, int age, const string &in label,\n    bool estimated, uint seed)")
# Calm results get no intensity, effects, flash, or picture.
assert "f.calm = f.power <= 0.0f;" in render
assert "f.k = f.calm ? 0.0f : PopupIntensity();" in render
assert "f.fx = f.k > 0.0f ? CurrentEffects() : 0;" in render
assert "if (!f.calm) DrawPopupPictures(f);" in render
assert "if (!f.calm) DrawPopupFlash(f);" in render
assert 'f.shown = estimated && GradeBasePoints(label) > 0 ? label + "+" : label;' in render
assert "f.fade = 1.0f - Clamp01(float(age - 700) / 300.0f);" in render
assert "f.s = Math::Min(r.z / 500.0f, r.w / 125.0f);" in render
# Grade-only effects.
assert 'if (HasFx(f, FX_RAYS) && label == "S+") DrawPopupRays(f);' in render
assert 'if (HasFx(f, FX_OUTLINE) && label == "S+") DrawPopupOutline(f);' in render
assert 'if (HasFx(f, FX_SNOWFLAKES) && (label == "S" || label == "S+")) DrawPopupSnowflakes(f);' in render
assert "if (HasFx(f, FX_SHOCKWAVE) && !f.miss) DrawPopupShockwave(f);" in render

# Only S and S+ pictures dance; non-square pictures keep their shape (Review Focus 5).
pics = body("void DrawPopupPictures(PopupFrame@ f)")
assert 'bool dance = f.label == "S" || f.label == "S+";' in pics
draw = body("void DrawPictureTexture(nvg::Texture@ texture, float x, float y, float size,\n    float angle, float alpha)")
assert "vec2 dims = texture.GetSize();" in draw
assert "float w = size*Math::Min(1.0f, aspect);" in draw

# Random layouts are seeded per popup; per-frame jitter adds the frame index.
assert "PopupRandom(f.seed + 7)" in body("void DrawPopupSparks(PopupFrame@ f)")
assert "PopupRandom(f.seed + 13)" in body("void DrawPopupShards(PopupFrame@ f)")
assert "PopupRandom(f.seed + 99)" in body("void DrawPopupCracks(PopupFrame@ f)")
assert "PopupRandom(f.seed + uint(f.age / 16))" in body("void ApplyPopupMotion(PopupFrame@ f)")
# Broadcast's panel never collapses below a sliver on tiny or early frames.
assert "Math::Max(6.0f, 480.0f*EaseOutCubic(float(f.age) / 230.0f))*f.s" in body("float PopupPanelWidth(PopupFrame@ f)")
print("Popup rendering contract: PASS")
```

Append to `tests/test_pictures.py`:

```python
# The AI-generated gorilla left the repository.
assert not (ASSETS / "gorilla-emoji.png").exists()
assert not (ASSETS / "GORILLA_ASSET.md").exists()
print("AI gorilla removed from shipped assets: PASS")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python tests/test_grade_animation.py`
Expected: model PASS line, then `AssertionError` at the first new `RenderResult` assertion.

- [ ] **Step 3: Append the renderer to `plugin/GradeAnimation.as`**

```angelscript
// Everything one popup frame needs; built fresh each frame by RenderResult.
class PopupFrame {
    string label;
    string shown;
    string style;
    int age;
    uint seed;
    float s;
    float cx;
    float cy;
    float fade;
    float power;
    float k;
    int fx;
    bool calm;
    bool miss;
    vec4 accent;
    float panelW;
    // Offsets shared by panel, letter, and pictures (shake, MISSED motion).
    float ox = 0.0f;
    float oy = 0.0f;
    float slump = 0.0f;
    // Where the letter was drawn, for the sheen.
    float letterX;
    float letterY;
    float letterScale = 1.0f;
    float letterRot = 0.0f;
}

bool HasFx(PopupFrame@ f, int effect) {
    return (f.fx & effect) != 0;
}

void RenderResult(const vec4 &in r, int age, const string &in label,
    bool estimated, uint seed) {
    if (label.Length == 0) return;
    PopupFrame@ f = PopupFrame();
    f.label = label;
    f.shown = estimated && GradeBasePoints(label) > 0 ? label + "+" : label;
    f.style = PopupStyle();
    f.age = age;
    f.seed = seed;
    f.s = Math::Min(r.z / 500.0f, r.w / 125.0f);
    f.cx = r.x + r.z*0.5f;
    f.cy = r.y + r.w*0.5f;
    f.fade = 1.0f - Clamp01(float(age - 700) / 300.0f);
    f.power = ResultPower(label);
    f.calm = f.power <= 0.0f;
    f.miss = label == "MISSED";
    f.k = f.calm ? 0.0f : PopupIntensity();
    f.fx = f.k > 0.0f ? CurrentEffects() : 0;
    f.accent = GradeColor(label, f.fade);
    f.panelW = PopupPanelWidth(f);
    ApplyPopupMotion(f);
    if (HasFx(f, FX_RAYS) && label == "S+") DrawPopupRays(f);
    if (HasFx(f, FX_SHOCKWAVE) && !f.miss) DrawPopupShockwave(f);
    DrawPopupPanel(f);
    if (HasFx(f, FX_OUTLINE) && label == "S+") DrawPopupOutline(f);
    if (HasFx(f, FX_CRACKS)) DrawPopupCracks(f);
    if (!f.calm) DrawPopupPictures(f);
    if (HasFx(f, FX_SPARKS)) DrawPopupSparks(f);
    if (HasFx(f, FX_SHARDS)) DrawPopupShards(f);
    if (HasFx(f, FX_SNOWFLAKES) && (label == "S" || label == "S+")) DrawPopupSnowflakes(f);
    DrawPopupLetter(f);
    if (HasFx(f, FX_SHEEN)) DrawPopupSheen(f);
    if (!f.calm) DrawPopupFlash(f);
    DrawPopupCaption(f);
}

float PopupPanelWidth(PopupFrame@ f) {
    if (f.style == "broadcast")
        return Math::Max(6.0f, 480.0f*EaseOutCubic(float(f.age) / 230.0f))*f.s;
    float duration = f.style == "arcade" ? 170.0f : 180.0f;
    return (180.0f + 300.0f*EaseOutCubic(float(f.age) / duration))*f.s;
}

void ApplyPopupMotion(PopupFrame@ f) {
    float age = float(f.age);
    bool arcadeMiss = f.miss && f.style == "arcade";
    if (arcadeMiss && age < 300.0f)
        f.ox += Math::Sin(age*0.09f)*14.0f*f.s*(1.0f - age/300.0f);
    if (f.miss && f.style == "ice")
        f.slump = 10.0f*f.s*EaseOutCubic((age - 250.0f) / 350.0f);
    if (HasFx(f, FX_SHAKE) && !arcadeMiss && age < 300.0f) {
        PopupRandom@ rng = PopupRandom(f.seed + uint(f.age / 16));
        float decay = 1.0f - age/300.0f;
        f.ox += (rng.Next() - 0.5f)*18.0f*f.power*f.k*decay*f.s;
        f.oy += (rng.Next() - 0.5f)*12.0f*f.power*f.k*decay*f.s;
    }
}

void DrawPopupPanel(PopupFrame@ f) {
    float s = f.s;
    float x = f.cx + f.ox - f.panelW*0.5f;
    float y = f.cy + f.oy + f.slump - 52.0f*s;
    float w = f.panelW;
    vec4 a = f.accent;
    HudBox(x, y + 5*s, w, 105*s, 16*s, HudColor(0, 0, 0, 0.35f*f.fade));
    HudBox(x, y, w, 105*s, 16*s, HudColor(0.025f, 0.035f, 0.09f, 0.93f*f.fade));
    HudBox(x, y + 2*s, w, 3*s, 1*s, HudColor(a.x, a.y, a.z, 0.75f*f.fade));
    HudBox(x, y + 101*s, w, 2*s, 1*s, HudColor(a.x, a.y, a.z, 0.28f*f.fade));
    if (f.style != "broadcast") return;
    if (f.age < 260) {
        float edge = 0.9f*(1.0f - float(f.age)/260.0f)*f.fade;
        HudBox(x - 2*s, y, 4*s, 105*s, 1*s, HudColor(1, 1, 1, edge));
        HudBox(x + w - 2*s, y, 4*s, 105*s, 1*s, HudColor(1, 1, 1, edge));
    }
    float bar = EaseOutCubic(float(f.age - 300) / 300.0f);
    if (bar > 0.0f)
        HudBox(f.cx + f.ox - 60*s*bar, f.cy + f.oy + 18*s, 120*s*bar, 2*s, 1*s,
            HudColor(a.x, a.y, a.z, 0.9f*f.fade));
}

void DrawPopupFlash(PopupFrame@ f) {
    float duration;
    float strength;
    vec4 colour;
    if (f.style == "ice") {
        duration = 110.0f;
        strength = 0.6f;
        colour = HudColor(0.82f, 0.94f, 1.0f);
    } else if (f.style == "arcade") {
        duration = 90.0f;
        strength = 0.55f*f.power;
        colour = HudColor(1, 1, 1);
    } else {
        return;
    }
    if (float(f.age) >= duration) return;
    float alpha = Math::Min(1.0f, strength*f.k)*(1.0f - float(f.age)/duration)*f.fade;
    HudBox(f.cx + f.ox - f.panelW*0.5f, f.cy + f.oy + f.slump - 52.0f*f.s,
        f.panelW, 105.0f*f.s, 16.0f*f.s, HudColor(colour.x, colour.y, colour.z, alpha));
}

void DrawPopupText(PopupFrame@ f, float x, float y, float scale, float rot,
    const vec4 &in colour, float blur) {
    float size = (f.miss ? 43.0f : 54.0f)*f.s;
    nvg::Save();
    nvg::Translate(x, y);
    nvg::Rotate(rot);
    nvg::Scale(scale, scale);
    nvg::FontBlur(blur);
    HudText(0, 0, f.shown, size, colour, nvg::Align::Center | nvg::Align::Middle);
    nvg::Restore();
}

void DrawPopupLetter(PopupFrame@ f) {
    float age = float(f.age);
    float x = f.cx + f.ox;
    float y = f.cy + f.oy - 8.0f*f.s;
    float scale = 1.0f;
    float rot = 0.0f;
    vec4 colour = f.accent;
    if (f.style == "broadcast") {
        float wipe = EaseOutCubic((age - 120.0f) / 260.0f);
        if (wipe <= 0.0f) return;
        nvg::Scissor(x - 120.0f*f.s, y - 60.0f*f.s, 240.0f*f.s*wipe, 120.0f*f.s);
        if (f.miss && age > 150.0f && age < 450.0f) {
            PopupRandom@ rng = PopupRandom(f.seed + uint(f.age / 40));
            if ((f.age / 40) % 2 == 0) x += (rng.Next() - 0.5f)*10.0f*f.s;
            DrawPopupText(f, x + 3.0f*f.s, y, 1.0f, 0.0f,
                HudColor(0.31f, 0.86f, 1.0f, 0.6f*f.fade), 0.0f);
        }
        f.letterX = x; f.letterY = y; f.letterScale = 1.0f; f.letterRot = 0.0f;
        DrawPopupText(f, x, y, 1.0f, 0.0f, colour, 0.0f);
        nvg::ResetScissor();
        return;
    }
    if (f.style == "arcade") {
        if (f.miss) {
            scale = 1.0f + 0.6f*(1.0f - EaseOutCubic(age / 220.0f));
            y += 6.0f*f.s*EaseOutCubic((age - 200.0f) / 300.0f);
        } else {
            scale = 3.2f - 2.2f*EaseOutBack(age / 240.0f);
            rot = -0.2f*(1.0f - EaseOutCubic(age / 240.0f));
        }
        if (!f.calm)
            DrawPopupText(f, x, y, scale, rot, HudColor(f.accent.x, f.accent.y,
                f.accent.z, 0.7f*f.fade*f.power), 18.0f*f.power*f.s);
    } else {
        scale = 1.0f + 0.9f*(1.0f - EaseOutBack(age / 260.0f));
        if (f.miss) {
            float slump = EaseOutCubic((age - 250.0f) / 350.0f);
            y += 14.0f*f.s*slump;
            rot = 0.12f*slump;
        } else {
            float warm = Clamp01((age - 120.0f) / 300.0f);
            colour = LerpColor(HudColor(0.84f, 0.95f, 1.0f, f.fade), f.accent, warm);
            DrawPopupText(f, x, y, scale, rot,
                HudColor(0.78f, 0.93f, 1.0f, 0.8f*(1.0f - warm)*f.fade), 12.0f*f.s);
        }
    }
    f.letterX = x; f.letterY = y; f.letterScale = scale; f.letterRot = rot;
    DrawPopupText(f, x, y, scale, rot, colour, 0.0f);
}

// The letter redrawn in white inside a moving clip band; three nested bands
// with rising alpha give soft edges.
void DrawPopupSheen(PopupFrame@ f) {
    array<int> starts;
    if (f.label == "S+") { starts.InsertLast(260); starts.InsertLast(520); }
    else if (f.label == "S" || f.label == "A" || f.label == "B") starts.InsertLast(300);
    float strength = Math::Min(1.0f, f.k)*f.fade;
    for (uint i = 0; i < starts.Length; i++) {
        float t = float(f.age - starts[i]) / 340.0f;
        if (t <= 0.0f || t >= 1.0f) continue;
        float bandX = f.letterX - 150.0f*f.s + 300.0f*f.s*t;
        for (int j = 0; j < 3; j++) {
            float half = (40.0f - 12.0f*float(j))*f.s;
            nvg::Scissor(bandX - half, f.letterY - 60.0f*f.s, half*2.0f, 120.0f*f.s);
            DrawPopupText(f, f.letterX, f.letterY, f.letterScale, f.letterRot,
                HudColor(1, 1, 1, (0.2f + 0.15f*float(j))*strength), 0.0f);
        }
        nvg::ResetScissor();
    }
}

void DrawPopupRays(PopupFrame@ f) {
    float alpha = 0.12f*Math::Min(1.0f, f.k)*f.fade*
        EaseOutCubic(float(f.age - 150) / 300.0f);
    if (alpha <= 0.0f) return;
    nvg::Save();
    nvg::Translate(f.cx + f.ox, f.cy + f.oy);
    nvg::Rotate(float(f.age)*0.0012f);
    nvg::FillColor(HudColor(1.0f, 0.84f, 0.35f, alpha));
    for (int i = 0; i < 12; i++) {
        nvg::Rotate(Math::PI*2.0f/12.0f);
        nvg::BeginPath();
        nvg::MoveTo(vec2(0, 0));
        nvg::LineTo(vec2(320.0f*f.s, -18.0f*f.s));
        nvg::LineTo(vec2(320.0f*f.s, 18.0f*f.s));
        nvg::ClosePath();
        nvg::Fill();
    }
    nvg::Restore();
}

void DrawPopupShockwave(PopupFrame@ f) {
    if (f.age >= 480) return;
    float t = float(f.age) / 480.0f;
    float radius = (30.0f + 260.0f*f.k*EaseOutCubic(t))*f.s;
    nvg::BeginPath();
    nvg::Ellipse(vec2(f.cx + f.ox, f.cy + f.oy), radius, radius*0.42f);
    nvg::StrokeWidth((2.0f + 7.0f*f.power*(1.0f - t))*f.s);
    nvg::StrokeColor(HudColor(f.accent.x, f.accent.y, f.accent.z, 0.8f*(1.0f - t)*f.fade));
    nvg::Stroke();
}

void DrawPopupOutline(PopupFrame@ f) {
    float glow = 0.5f + 0.5f*Math::Sin(float(f.age)*0.02f);
    float strength = Math::Min(1.0f, f.k)*f.fade;
    float x = f.cx + f.ox - f.panelW*0.5f;
    float y = f.cy + f.oy - 52.0f*f.s;
    for (int pass = 0; pass < 2; pass++) {
        nvg::BeginPath();
        nvg::RoundedRect(x, y, f.panelW, 105.0f*f.s, 16.0f*f.s);
        nvg::StrokeWidth((pass == 0 ? 6.0f : 2.0f)*f.s);
        float alpha = pass == 0 ? 0.25f*glow : 0.35f + 0.4f*glow;
        nvg::StrokeColor(HudColor(f.accent.x, f.accent.y, f.accent.z, alpha*strength));
        nvg::Stroke();
    }
}

void DrawPopupCracks(PopupFrame@ f) {
    float alpha = 0.7f*f.fade*(1.0f - Clamp01(float(f.age - 350) / 400.0f));
    if (alpha <= 0.0f) return;
    float grow = EaseOutCubic(float(f.age) / 220.0f);
    PopupRandom@ rng = PopupRandom(f.seed + 99);
    int count = CrackCount(f.power, f.k);
    nvg::StrokeWidth(1.4f*f.s);
    nvg::StrokeColor(HudColor(0.82f, 0.94f, 1.0f, alpha));
    for (int i = 0; i < count; i++) {
        float angle = rng.Next()*Math::PI*2.0f;
        float step = grow*(60.0f + 90.0f*rng.Next())*f.s/4.0f;
        vec2 p = vec2(f.cx + f.ox, f.cy + f.oy - 8.0f*f.s);
        nvg::BeginPath();
        nvg::MoveTo(p);
        for (int j = 0; j < 4; j++) {
            angle += (rng.Next() - 0.5f)*0.9f;
            p += vec2(Math::Cos(angle)*step, Math::Sin(angle)*step*0.55f);
            nvg::LineTo(p);
        }
        nvg::Stroke();
    }
}

void DrawPopupSparks(PopupFrame@ f) {
    float t = float(f.age) / 1000.0f;
    if (t >= 0.75f) return;
    float alpha = (1.0f - t/0.75f)*f.fade;
    float gravity = f.miss ? 260.0f : 156.0f;
    array<vec4> confetti = {HudColor(1, 0.84f, 0.28f), HudColor(0.35f, 0.85f, 1),
        HudColor(1, 0.43f, 0.57f), HudColor(0.45f, 0.9f, 0.45f)};
    PopupRandom@ rng = PopupRandom(f.seed + 7);
    int count = ParticleCount(f.power, f.k);
    for (int i = 0; i < count; i++) {
        float angle = rng.Next()*Math::PI*2.0f;
        float distance = ParticleSpeed(f.power*rng.Next(), f.k)*t*f.s;
        float radius = (1.5f + 3.0f*rng.Next())*f.s*(f.miss ? 1.3f : 1.0f);
        float rot = rng.Next()*6.0f;
        float spin = (rng.Next() - 0.5f)*12.0f;
        float pick = rng.Next();
        vec2 p = vec2(f.cx + f.ox + Math::Cos(angle)*distance*1.3f,
            f.cy + f.oy + Math::Sin(angle)*distance*0.7f + gravity*t*t*f.s);
        if (f.label == "S+" && pick > 0.5f) {
            vec4 c = confetti[int(pick*8.0f) % 4];
            nvg::Save();
            nvg::Translate(p);
            nvg::Rotate(rot + spin*t);
            HudBox(-4*f.s, -2*f.s, 8*f.s, 4*f.s, 0, HudColor(c.x, c.y, c.z, alpha));
            nvg::Restore();
        } else {
            vec4 c = f.miss ? HudColor(0.55f, 0.59f, 0.65f) : f.accent;
            nvg::BeginPath();
            nvg::Circle(p, radius);
            nvg::FillColor(HudColor(c.x, c.y, c.z, alpha));
            nvg::Fill();
        }
    }
}

void DrawPopupShards(PopupFrame@ f) {
    float t = float(f.age) / 1000.0f;
    if (t >= 0.8f) return;
    float alpha = 0.85f*(1.0f - t/0.8f)*f.fade;
    float gravity = f.miss ? 300.0f : 120.0f;
    vec4 colour = f.miss ? HudColor(0.55f, 0.6f, 0.66f, alpha) :
        HudColor(0.86f, 0.96f, 1.0f, alpha);
    PopupRandom@ rng = PopupRandom(f.seed + 13);
    int count = ParticleCount(f.power, f.k);
    for (int i = 0; i < count; i++) {
        float angle = rng.Next()*Math::PI*2.0f;
        float distance = ParticleSpeed(f.power*rng.Next(), f.k)*t*1.1f*f.s;
        float size = (6.0f + 6.0f*rng.Next())*f.s;
        float rot = rng.Next()*6.0f;
        float spin = (rng.Next() - 0.5f)*12.0f;
        vec2 p = vec2(f.cx + f.ox + Math::Cos(angle)*distance*1.3f,
            f.cy + f.oy + Math::Sin(angle)*distance*0.6f + gravity*t*t*f.s);
        nvg::Save();
        nvg::Translate(p);
        nvg::Rotate(rot + spin*t);
        nvg::BeginPath();
        nvg::MoveTo(vec2(0, -size));
        nvg::LineTo(vec2(size*0.6f, size*0.7f));
        nvg::LineTo(vec2(-size*0.5f, size*0.5f));
        nvg::ClosePath();
        nvg::FillColor(colour);
        nvg::Fill();
        nvg::Restore();
    }
}

void DrawSnowflake(const vec2 &in c, float r) {
    nvg::BeginPath();
    for (int arm = 0; arm < 6; arm++) {
        float a = float(arm)*Math::PI/3.0f;
        vec2 d = vec2(Math::Cos(a), Math::Sin(a));
        vec2 branch = c + d*(r*0.6f);
        vec2 n = vec2(-d.y, d.x)*(r*0.25f);
        nvg::MoveTo(c);
        nvg::LineTo(c + d*r);
        nvg::MoveTo(branch + n - d*(r*0.2f));
        nvg::LineTo(branch);
        nvg::LineTo(branch - n - d*(r*0.2f));
    }
    nvg::Stroke();
}

void DrawPopupSnowflakes(PopupFrame@ f) {
    float alpha = f.fade*(1.0f - Clamp01(float(f.age - 400) / 400.0f));
    float travel = EaseOutCubic(float(f.age - 80) / 600.0f);
    if (alpha <= 0.0f || travel <= 0.0f) return;
    int count = SnowflakeCount(f.label, f.k);
    nvg::StrokeWidth(1.5f*f.s);
    nvg::StrokeColor(HudColor(0.9f, 0.97f, 1.0f, alpha));
    for (int i = 0; i < count; i++) {
        float angle = float(i)/float(count)*Math::PI*2.0f + float(f.age)*0.001f;
        float distance = (40.0f + 200.0f*f.k*travel)*f.s;
        DrawSnowflake(vec2(f.cx + f.ox + Math::Cos(angle)*distance*1.4f,
            f.cy + f.oy + Math::Sin(angle)*distance*0.6f), 7.0f*f.s);
    }
}

// Keeps the picture's aspect ratio inside a size-by-size square.
void DrawPictureTexture(nvg::Texture@ texture, float x, float y, float size,
    float angle, float alpha) {
    vec2 dims = texture.GetSize();
    float aspect = dims.y > 0.0f ? dims.x / dims.y : 1.0f;
    float w = size*Math::Min(1.0f, aspect);
    float h = size*Math::Min(1.0f, 1.0f / Math::Max(aspect, 0.001f));
    nvg::Save();
    nvg::Translate(x, y);
    nvg::Rotate(angle);
    nvg::BeginPath();
    nvg::Rect(-w*0.5f, -h*0.5f, w, h);
    nvg::FillPaint(nvg::TexturePattern(vec2(-w*0.5f, -h*0.5f), vec2(w, h),
        0.0f, texture, alpha));
    nvg::Fill();
    nvg::Restore();
}

void DrawPopupPictures(PopupFrame@ f) {
    nvg::Texture@ picture = PictureForResult(f.label);
    if (picture is null) return;
    bool dance = f.label == "S" || f.label == "S+";
    float age = float(f.age);
    for (int i = 0; i < 2; i++) {
        float side = i == 0 ? -1.0f : 1.0f;
        float size = 72.0f*f.s;
        float alpha = f.fade;
        float x = f.cx + f.ox + side*150.0f*f.s;
        float y = f.cy + f.oy + f.slump;
        if (f.style == "broadcast") {
            float enter = EaseOutCubic((age - 60.0f) / 300.0f);
            x += side*30.0f*f.s*(1.0f - enter);
            alpha *= enter;
        } else {
            float delay = f.style == "ice" ? 60.0f + 40.0f*float(i) : 60.0f;
            float duration = f.style == "ice" ? 300.0f : 260.0f;
            size *= EaseOutBack((age - delay) / duration);
            alpha *= Clamp01((age - delay) / 100.0f);
        }
        float tilt = 0.0f;
        if (dance) {
            float wave = Math::Sin(age*0.012f + float(i)*1.8f);
            y -= Math::Abs(wave)*12.0f*f.s;
            tilt = wave*0.18f*side;
        }
        if (size > 1.0f && alpha > 0.0f)
            DrawPictureTexture(picture, x, y, size, tilt, alpha);
    }
}

void DrawPopupCaption(PopupFrame@ f) {
    float alpha = f.fade*Clamp01(float(f.age - 120) / 200.0f);
    if (alpha <= 0.0f) return;
    HudText(f.cx + f.ox, f.cy + f.oy + f.slump + 28.0f*f.s, ResultCaption(f.label),
        13.0f*f.s, HudColor(0.88f, 0.96f, 1, alpha),
        nvg::Align::Center | nvg::Align::Middle);
}
```

- [ ] **Step 4: Remove the old gorilla code from `plugin/Widgets.as`**

Delete line 2 (`nvg::Texture@ g_gorillaTexture;`). In `InitWidgets()`, delete these three lines:

```angelscript
    @g_gorillaTexture = nvg::LoadTexture("assets/gorilla-emoji.png");
    if (g_gorillaTexture is null)
        print("Gorilla Grip Trainer: gorilla emoji texture could not load");
```

Delete the whole functions `GorillaDot`, `DrawGorillaEmoji`, `DrawFallbackFlame`, `RenderSGorillas`, and the old `RenderResult(const vec4 &in r, int age, const string &in label, bool estimated)` (currently lines 264–359, from `void GorillaDot(` through the closing brace of `RenderResult`). Keep `ResultCaption`, `GradeColor`, `HudBox`, `HudText`, and `HudColor`.

In `RenderWidgets()`, replace:

```angelscript
        else if (active || g_layoutEditing)
            RenderResult(layout.Pixels(), active ? age : 240,
                active ? g_resultLabel : "S",
                active && g_resultTimingEstimated);
```

with:

```angelscript
        else if (active || g_layoutEditing)
            RenderResult(layout.Pixels(), active ? age : 450,
                active ? g_resultLabel : "S",
                active && g_resultTimingEstimated,
                active ? uint(g_resultShownAt) + 1 : 1);
```

- [ ] **Step 5: Move the AI gorilla out of the repository**

Look at the installed storage folder first, then copy and remove:

```bash
ls ~/OpenplanetNext/PluginStorage/GorillaGripTrainer
mkdir -p LocalImages ~/OpenplanetNext/PluginStorage/GorillaGripTrainer/LocalImages
cp plugin/assets/gorilla-emoji.png LocalImages/gorilla-emoji.png
cp plugin/assets/gorilla-emoji.png ~/OpenplanetNext/PluginStorage/GorillaGripTrainer/LocalImages/gorilla-emoji.png
git -c safe.directory=* rm plugin/assets/gorilla-emoji.png plugin/assets/GORILLA_ASSET.md
```

Expected: `LocalImages/gorilla-emoji.png` exists but `git status --short` does not list it (ignored since Task 1).

- [ ] **Step 6: Update the presentation and logging tests**

In `tests/test_presentation_contract.py`, replace:

```python
assert 'nvg::LoadTexture("assets/gorilla-emoji.png")' in widgets
assert (ROOT / "assets" / "gorilla-emoji.png").is_file()
```

with:

```python
assert "gorilla-emoji" not in widgets
assert (ROOT / "assets" / "twemoji" / "gorilla.png").is_file()
```

In `tests/test_debug_logging.py`, remove `"Gorilla Grip Trainer: gorilla emoji texture could not load",` from `PROBLEMS` and change the count line to:

```python
assert len(calls) == 30, len(calls)  # 17 routine events, 12 problems, 1 state marker
```

- [ ] **Step 7: Run the tests**

Run each: `python tests/test_grade_animation.py`, `python tests/test_pictures.py`, `python tests/test_presentation_contract.py`, `python tests/test_debug_logging.py`, `python tests/test_layout_defaults.py`, `python tests/test_stats_widget.py`
Expected: every script ends in `PASS`, including `Popup rendering contract: PASS` and `AI gorilla removed from shipped assets: PASS`.

- [ ] **Step 8: Commit**

```bash
git -c safe.directory=* add plugin/GradeAnimation.as plugin/Widgets.as tests/test_grade_animation.py tests/test_pictures.py tests/test_presentation_contract.py tests/test_debug_logging.py
git -c safe.directory=* status --short
git -c safe.directory=* diff --cached --check
git -c safe.directory=* commit -m "Draw the grade popup in three mixable styles with pictures"
```

The status must show the two deleted assets as staged deletions and no `LocalImages/` entry.

---

### Task 5: Popup tab and previews

**Files:**
- Create: `plugin/PopupTab.as`
- Modify: `plugin/Widgets.as` (`ShowResult`, start of `RenderWidgets`, grade block)
- Modify: `plugin/Layout.as` (tab attribute)
- Modify: `tests/test_presentation_contract.py`
- Test: `tests/test_popup_tab.py`

**Interfaces:**
- Consumes: Task 2 (`g_pictureResults`, `g_emojiNames`, `g_emojiLabels`, `g_localImages`, `g_localImagesScanned`, `PictureSetting`, `SetPictureSetting`, `PictureLabel`, `GetPicture`, `PictureTexture`, `RefreshLocalImages`, `ClearPictureCache`, `ResetPictureSettings`); Task 3 (`g_popupStyles`, `g_popupStyleLabels`, `PopupStyle`, `PopupStyleLabel`, `SelectPopupStyle`, `ResetPopupSettings`, `StartPopupPreview`, `StopPopupPreview`, `PopupPreviewAge`, `PopupPreviewSeed`, `g_popupPreviewLabel`, the `S_Fx*` settings); Task 4 (`RenderResult` with seed).
- Produces: `[SettingsTab name="Popup" icon="" order="3"] void RenderSettingsPopup()`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_popup_tab.py`:

```python
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
reset = render.split('if (UI::Button("Reset to default")) {', 1)[1].split("}", 1)[0]
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
assert 'UI::Selectable("None", choice.Length == 0)' in row
assert 'SetPictureSetting(result, "emoji:" + g_emojiNames[i]);' in row
assert 'SetPictureSetting(result, "local:" + g_localImages[i]);' in row
assert "UI::Image(picture.thumbnail, vec2(thumb, thumb));" in row

# Previews draw even with widgets off; a real verdict replaces a preview (Review Focus 4).
widgets_render = widgets.split("void RenderWidgets() {", 1)[1].split("\n}", 1)[0]
assert widgets_render.index("int previewAge = PopupPreviewAge();") < widgets_render.index("if (!S_EnableWidgets) return;")
assert "RenderResult(grade.Pixels(), previewAge, g_popupPreviewLabel, false,\n                PopupPreviewSeed(g_popupPreviewLabel));" in widgets_render
assert "if (previewAge < 0 && ShouldRenderWidget(layout)) {" in widgets_render
show = widgets.split("void ShowResult(JumpVerdict@ verdict, int raceTime) {", 1)[1].split("\n}", 1)[0]
assert "StopPopupPreview();" in show
print("Popup tab and previews: PASS")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python tests/test_popup_tab.py`
Expected: FAIL with `FileNotFoundError` for `plugin/PopupTab.as`.

- [ ] **Step 3: Write `plugin/PopupTab.as`**

```angelscript
[SettingsTab name="Popup" icon="" order="3"]
void RenderSettingsPopup() {
    if (!g_localImagesScanned) RefreshLocalImages();
    if (UI::Button("Reset to default")) {
        ResetPopupSettings();
        ResetPictureSettings();
    }

    UI::SeparatorText("Animation");
    UI::SetNextItemWidth(260.0f);
    if (UI::BeginCombo("Style", PopupStyleLabel())) {
        for (uint i = 0; i < g_popupStyles.Length; i++)
            if (UI::Selectable(g_popupStyleLabels[i], g_popupStyles[i] == PopupStyle()))
                SelectPopupStyle(g_popupStyles[i]);
        UI::EndCombo();
    }
    UI::SetNextItemWidth(260.0f);
    S_PopupIntensity = Math::Clamp(UI::SliderInt("Intensity", S_PopupIntensity, 0, 200, "%d%%"), 0, 200);
    S_FxShake = UI::Checkbox("Screen shake", S_FxShake);
    S_FxShockwave = UI::Checkbox("Shockwave ring", S_FxShockwave);
    S_FxSparks = UI::Checkbox("Sparks", S_FxSparks);
    S_FxCracks = UI::Checkbox("Cracks", S_FxCracks);
    S_FxShards = UI::Checkbox("Ice shards", S_FxShards);
    S_FxSnowflakes = UI::Checkbox("Snowflakes (S, S+)", S_FxSnowflakes);
    S_FxRays = UI::Checkbox("Light rays (S+)", S_FxRays);
    S_FxSheen = UI::Checkbox("Light sheen", S_FxSheen);
    S_FxOutline = UI::Checkbox("Glowing outline (S+)", S_FxOutline);

    UI::SeparatorText("Pictures");
    S_ShowPictures = UI::Checkbox("Show pictures", S_ShowPictures);
    if (UI::Button("Open LocalImages folder")) {
        string folder = IO::FromStorageFolder("LocalImages");
        if (!IO::FolderExists(folder)) IO::CreateFolder(folder, true);
        OpenExplorerPath(folder);
    }
    UI::SameLine();
    if (UI::Button("Reload files")) {
        RefreshLocalImages();
        ClearPictureCache();
    }
    for (uint i = 0; i < g_pictureResults.Length; i++)
        RenderPictureRow(g_pictureResults[i]);
}

void RenderPictureRow(const string &in result) {
    UI::PushID(result);
    string choice = PictureSetting(result);
    float thumb = 28.0f*UI::GetScale();
    PictureTexture@ picture = GetPicture(choice);
    if (picture !is null && picture.thumbnail !is null)
        UI::Image(picture.thumbnail, vec2(thumb, thumb));
    else
        UI::Dummy(vec2(thumb, thumb));
    UI::SameLine();
    UI::AlignTextToFramePadding();
    UI::Text(result == "MISSED" ? "Missed" : result);
    UI::SameLine(110.0f*UI::GetScale());
    UI::SetNextItemWidth(240.0f);
    if (UI::BeginCombo("##picture", PictureLabel(choice))) {
        if (UI::Selectable("None", choice.Length == 0))
            SetPictureSetting(result, "");
        for (uint i = 0; i < g_emojiNames.Length; i++)
            if (UI::Selectable(g_emojiLabels[i], choice == "emoji:" + g_emojiNames[i]))
                SetPictureSetting(result, "emoji:" + g_emojiNames[i]);
        if (g_localImages.Length > 0) UI::Separator();
        for (uint i = 0; i < g_localImages.Length; i++)
            if (UI::Selectable(g_localImages[i], choice == "local:" + g_localImages[i]))
                SetPictureSetting(result, "local:" + g_localImages[i]);
        UI::EndCombo();
    }
    UI::SameLine();
    if (UI::Button("Preview")) StartPopupPreview(result);
    UI::PopID();
}
```

- [ ] **Step 4: Wire previews into `plugin/Widgets.as`**

In `ShowResult`, add `StopPopupPreview();` as the first line after `if (verdict is null) return;`.

Replace the start of `RenderWidgets()`:

```angelscript
void RenderWidgets() {
    if (!S_EnableWidgets) return;
    if (g_hudFont >= 0) nvg::FontFace(g_hudFont);
```

with:

```angelscript
void RenderWidgets() {
    if (g_hudFont >= 0) nvg::FontFace(g_hudFont);
    // A Popup-tab preview plays even with widgets off or outside a run.
    int previewAge = PopupPreviewAge();
    if (previewAge >= 0) {
        WidgetLayout@ grade = GetLayout("grade");
        if (grade !is null)
            RenderResult(grade.Pixels(), previewAge, g_popupPreviewLabel, false,
                PopupPreviewSeed(g_popupPreviewLabel));
    }
    if (!S_EnableWidgets) return;
```

and in the grade block replace `if (ShouldRenderWidget(layout)) {` (the one directly after `@layout = GetLayout("grade");`) with:

```angelscript
    if (previewAge < 0 && ShouldRenderWidget(layout)) {
```

- [ ] **Step 5: Move the Layout tab to order 4**

In `plugin/Layout.as` change `[SettingsTab name="Layout" icon="" order="3"]` to `[SettingsTab name="Layout" icon="" order="4"]`.

In `tests/test_presentation_contract.py`, replace the tab-order block:

```python
tabs = re.findall(r'\[SettingsTab name="(\w+)" icon="" order="(\d+)"\]', layout + settings)
assert sorted(tabs, key=lambda tab: int(tab[1])) == [
    ("Rating", "1"), ("Sounds", "2"), ("Layout", "3"), ("Debug", "99")], tabs
assert (layout + settings).count("[SettingsTab") == 4
```

with:

```python
popup = (ROOT / "PopupTab.as").read_text(encoding="utf-8")
tabs = re.findall(r'\[SettingsTab name="(\w+)" icon="" order="(\d+)"\]', layout + settings + popup)
assert sorted(tabs, key=lambda tab: int(tab[1])) == [
    ("Rating", "1"), ("Sounds", "2"), ("Popup", "3"), ("Layout", "4"), ("Debug", "99")], tabs
assert (layout + settings + popup).count("[SettingsTab") == 5
```

- [ ] **Step 6: Run the tests**

Run each: `python tests/test_popup_tab.py`, `python tests/test_presentation_contract.py`, `python tests/test_grade_animation.py`, `python tests/test_improve_countdown.py`
Expected: every script ends in `PASS`.

- [ ] **Step 7: Commit**

```bash
git -c safe.directory=* add plugin/PopupTab.as plugin/Widgets.as plugin/Layout.as tests/test_popup_tab.py tests/test_presentation_contract.py
git -c safe.directory=* diff --cached --check
git -c safe.directory=* commit -m "Add the Popup settings tab with live previews"
```

---

### Task 6: Documentation, install, and in-game check

**Files:**
- Modify: `README.md`, `AGENTS.md`, `docs/superpowers/specs/2026-09-25-gorilla-grip-trainer.md`

**Interfaces:**
- Consumes: all earlier tasks.
- Produces: an installed build for the user to reload.

- [ ] **Step 1: Update the docs**

In `README.md`, in the Grade-widget paragraph, replace `S and S+ use the [original gorilla image](plugin/assets/GORILLA_ASSET.md).` with:

```markdown
The landing popup has three styles on the **Popup** tab: Ice shatter (default), Arcade slam, and Broadcast sheen. A style switches on its own effects (screen shake, shockwave ring, sparks, cracks, ice shards, snowflakes, light rays, light sheen, glowing outline), and each effect can be turned on or off with any style; **Intensity** (0–200 %) scales them, and better grades get bigger effects. Each result can show one picture on both sides of the panel: shipped Twemoji art or your own PNG/JPG files in `LocalImages` (use **Open LocalImages folder**). Only S and S+ pictures bounce. **Preview** plays any result's popup with the current settings.
```

In `AGENTS.md`, change `` `LocalSounds/`, local audio, `` to `` `LocalSounds/`, `LocalImages/`, local audio, ``.

In `docs/superpowers/specs/2026-09-25-gorilla-grip-trainer.md`, in the player-experience table row that contains `S and S+ have bouncing gorilla images`, replace that phrase with `the popup uses the selected style (see 2026-09-27-grade-popup-pictures-design.md), with an optional picture per result; only S and S+ pictures bounce`.

- [ ] **Step 2: Run every offline test**

Run from `Trainer/`:

```bash
for t in test_pictures test_grade_animation test_popup_tab test_stats_widget test_layout_defaults test_combo_display test_presentation_contract test_last_run_widget test_physics_widget test_finish_history_button test_improve_countdown test_debug_logging test_debug_trace test_rating_settings test_audio_pools test_audio_manifest test_slide_check test_timing_display test_landing_confirmation test_touch_switch_reason test_history_design test_history_schema test_history_search test_audio_installer; do printf "%-28s " $t; python tests/$t.py 2>&1 | tail -1; done
```

Expected: every line ends in `PASS`. Do not run `test_trainer_in_game.py`, `test_current_input.py`, or the finish/reset in-game tests.

- [ ] **Step 3: Install into Openplanet**

```bash
I=~/OpenplanetNext/Plugins/GorillaGripTrainer
ls "$I" "$I/assets"
cp plugin/*.as plugin/info.toml "$I/"
mkdir -p "$I/assets/twemoji"
cp plugin/assets/twemoji/*.png "$I/assets/twemoji/"
rm -f "$I/assets/gorilla-emoji.png" "$I/assets/GORILLA_ASSET.md"
for f in plugin/*.as; do diff -q "$f" "$I/$(basename "$f")"; done
```

Expected: no `diff` output. The `rm` only removes the installed copies of the two files deleted from the repository.

- [ ] **Step 4: Ask the user to reload and check**

Ask the user to reload Gorilla Grip Trainer in Openplanet, then read the log:

```bash
grep -n "GorillaGripTrainer\|Gorilla Grip Trainer images" ~/OpenplanetNext/Openplanet.log | tail -20
```

Expected: a fresh `Loaded plugin 'GorillaGripTrainer' (version 0.2.0)` line and no `ERROR` or `could not load` line. If there is a compile error, fix it before anything else. The Trainer unloads on compile errors.

Ask the user to:
1. Open the **Popup** tab and press **Preview** for every result with each style.
2. Try a mix, e.g. Ice shatter with Shockwave ring turned on and Ice shards off, and check that the dropdown shows "Ice shatter (custom)".
3. Preview S+ at 0 %, 100 %, and 200 % intensity.
4. Pick `gorilla-emoji.png` from LocalImages for one result, and set another to None.
5. Land real jumps: at least an S, a lower grade, and a miss.
6. Report anything that looks off, or any frame drop during the S+ popup at 200 %.

- [ ] **Step 5: Commit and push after the user confirms**

```bash
git -c safe.directory=* add README.md AGENTS.md docs/superpowers/specs/2026-09-25-gorilla-grip-trainer.md
git -c safe.directory=* diff --cached --check
git -c safe.directory=* commit -m "Document the Popup tab, styles, and pictures"
git -c safe.directory=* status --short
git -c safe.directory=* push origin main
```

Push only after the user confirms the in-game check. `status --short` must be empty before pushing.
