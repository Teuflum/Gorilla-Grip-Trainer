"""Download the shipped emoji sets and render them as 256x256 PNGs.

Each set comes from a pinned version of its open-source project. Headless
Chrome (or Edge) does the rendering, so no imaging packages are needed.
Run from the Trainer folder: py -3 tools/render_emoji.py [--set NAME ...]
"""

from __future__ import annotations

import argparse
import subprocess
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path


TWEMOJI = "v16.0.1"
FLUENT = "1ffb34c752ecf5d402f04cfb4b392c77f57c54bc"
NOTO = "e20cbc2bbec1926686be9f9bee7d1d2cfa1fea0e"
OPENMOJI = "17.0.0"

EMOJI = {
    "gorilla": "1f98d",
    "oncoming-fist": "1f44a",
    "flexed-biceps": "1f4aa",
    "fire": "1f525",
    "thumbs-up": "1f44d",
    "ok-hand": "1f44c",
    "slightly-smiling-face": "1f642",
    "skull": "1f480",
    "loudly-crying-face": "1f62d",
    "ice": "1f9ca",
    "snowflake": "2744",
    "trophy": "1f3c6",
    "star": "2b50",
}
# Fluent Emoji folder names; True marks emoji with skin-tone variants, whose
# default (yellow) art lives in a Default subfolder.
FLUENT_FOLDERS = {
    "gorilla": ("Gorilla", False),
    "oncoming-fist": ("Oncoming fist", True),
    "flexed-biceps": ("Flexed biceps", True),
    "fire": ("Fire", False),
    "thumbs-up": ("Thumbs up", True),
    "ok-hand": ("Ok hand", True),
    "slightly-smiling-face": ("Slightly smiling face", False),
    "skull": ("Skull", False),
    "loudly-crying-face": ("Loudly crying face", False),
    "ice": ("Ice", False),
    "snowflake": ("Snowflake", False),
    "trophy": ("Trophy", False),
    "star": ("Star", False),
}
SIZE = 256
OUT = Path(__file__).resolve().parents[1] / "plugin" / "assets" / "emoji"
BROWSERS = (
    Path("C:/Program Files/Google/Chrome/Application/chrome.exe"),
    Path("C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"),
)


def fluent_url(name: str, style: str, extension: str) -> str:
    folder, skin_tones = FLUENT_FOLDERS[name]
    snake = folder.lower().replace(" ", "_")
    lower = style.lower()
    base = (f"https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@{FLUENT}/assets/"
            f"{urllib.parse.quote(folder)}/")
    if skin_tones:
        return base + f"Default/{style}/{snake}_{lower}_default.{extension}"
    return base + f"{style}/{snake}_{lower}.{extension}"


SETS = {
    "twemoji": lambda name, code:
        f"https://cdn.jsdelivr.net/gh/jdecked/twemoji@{TWEMOJI}/assets/svg/{code}.svg",
    "fluent-flat": lambda name, code: fluent_url(name, "Flat", "svg"),
    "fluent-3d": lambda name, code: fluent_url(name, "3D", "png"),
    "noto": lambda name, code:
        f"https://raw.githubusercontent.com/googlefonts/noto-emoji/{NOTO}/2D/svg/emoji_u{code}.svg",
    "openmoji": lambda name, code:
        f"https://cdn.jsdelivr.net/gh/hfg-gmuend/openmoji@{OPENMOJI}/color/svg/{code.upper()}.svg",
}


def find_browser(explicit: str | None) -> Path:
    candidates = [Path(explicit)] if explicit else list(BROWSERS)
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise SystemExit("Chrome or Edge not found; pass --browser <path-to-exe>.")


def render(browser: Path, source: Path, png: Path) -> None:
    page = source.with_suffix(".html")
    page.write_text(
        '<html><body style="margin:0;background:transparent">'
        f'<img src="{source.name}" width="{SIZE}" height="{SIZE}" '
        'style="display:block;object-fit:contain">'
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
    parser.add_argument("--set", action="append", choices=sorted(SETS),
                        help="render only this set (repeatable)")
    args = parser.parse_args()
    browser = find_browser(args.browser)
    for set_name in args.set or list(SETS):
        folder = OUT / set_name
        folder.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory() as tmp:
            for name, code in EMOJI.items():
                url = SETS[set_name](name, code)
                source = Path(tmp) / f"{name}{Path(urllib.parse.urlparse(url).path).suffix}"
                with urllib.request.urlopen(url, timeout=30) as response:
                    source.write_bytes(response.read())
                render(browser, source, folder / f"{name}.png")
                print(f"{set_name}/{name}.png <- {url.rsplit('/', 1)[-1]}")


if __name__ == "__main__":
    main()
