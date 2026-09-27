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
