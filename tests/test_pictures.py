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
