"""The physics offsets come from code patterns, not from one pinned game build.

Without a game binary this checks the plugin source only. With one (set
TRACKMANIA_EXE, or have the default Ubisoft install), it also checks that every
pattern matches exactly once and that repeated fields agree. On the build the
research measured, the offsets must equal the measured ones.
"""

import os
import re
import struct
from pathlib import Path


root = Path(__file__).resolve().parents[1]
physics = (root / "plugin" / "Physics.as").read_text(encoding="utf-8")
main = (root / "plugin" / "Main.as").read_text(encoding="utf-8")
readme = (root / "README.md").read_text(encoding="utf-8")

# No build pin is left.
assert "IsSupportedBuild" not in physics + main
assert "0x6980d607" not in physics and "0x2cba000" not in physics
assert "g_supportedBuild = LocatePhysics();" in main
assert "Meta::UnloadPlugin" in main.split("g_supportedBuild = LocatePhysics();", 1)[1].split("return;", 1)[0]
assert "tied to one Trackmania build" not in readme

locate = physics.split("bool LocatePhysics() {", 1)[1].split("\n}\n", 1)[0]
patterns = {}
for var, name, literals in re.findall(
        r'uint64 (\w+) = FindPhysicsCode\("([^"]+)",\s*((?:"[^"]*"\s*)+)\);', locate):
    patterns[var] = (name, "".join(re.findall(r'"([^"]*)"', literals)).split())
assert len(patterns) == 6, sorted(patterns)
# Dev::FindPattern misses a pattern that ends in a wildcard (seen in game).
for name, toks in patterns.values():
    assert toks[0] != "??" and toks[-1] != "??", f"{name} must start and end on a fixed byte"
for var in patterns:
    assert f"{var} == 0" in locate, f"missing-pattern check for {var}"

fields = {f: (var, int(at)) for f, var, at in
          re.findall(r"l\.(\w+) = CodeOffset\((\w+), (\d+)\);", locate)}
repeats = [(var, int(at), f) for var, at, f in
           re.findall(r"CodeOffset\((\w+), (\d+)\) == l\.(\w+)", locate)]
assert len(fields) == 14 and len(repeats) == 8, (len(fields), len(repeats))
for var, at in list(fields.values()) + [(v, a) for v, a, _ in repeats]:
    toks = patterns[var][1]
    assert toks[at:at + 4] == ["??"] * 4, f"{var} @{at} is not a wildcarded offset"

# Every physics read goes through the layout.
read = physics.split("PhysicsSnapshot@ ReadPhysics(", 1)[1]
read = read.split("if (!g_supportedBuild) return snap;", 1)[1]
assert not re.search(r"\+ 0x[0-9a-f]+\)", read), "hard-coded offset in ReadPhysics"
assert "GetOffsetUint64(player, l.vehicle)" in read
# The existing sanity checks stay, plus a loose clock check for the fixed offsets.
for check in ("Dev::SafeReadUint32(vehicle + l.wheelCount) != 4",
              "(pos - vis.Position).Length() > 4.0f",
              "Math::Abs(raw - vis.InputSteer) > 0.25f",
              "force < 0.95f || force > 2.1f || mode > 2",
              "delay < 100 || delay > 1000",
              "Math::Abs(physicsClock - snap.gameTime) > 1000"):
    assert check in read, check

# Offsets measured on the build the research used (PE timestamp 0x6980d607).
MEASURED = {
    "model": 0x88, "wheelCount": 0x380, "rawSteer": 0xa0, "smoothedSteer": 0x1430,
    "forceGate": 0x1600, "modeAt": 0x14d8, "force": 0x14dc, "neutralAt": 0x14e0,
    "mode": 0x14e5, "contactClock": 0x1414, "wheels": 0x17b4, "wheelStride": 0xb8,
    "recoveryDelay": 0x1194, "neutralTimeout": 0x1198,
}
assert set(MEASURED) == set(fields)
defaults = dict(re.findall(r"uint (\w+) = (0x[0-9a-f]+);", physics.split("class PhysicsLayout {", 1)[1].split("\n}", 1)[0]))
assert defaults == {"vehicle": "0x1118", "position": "0x538", "physicsClock": "0x4f4",
                    "wheelChangedAt": "0x6c"}, defaults


def load_image(path):
    raw = path.read_bytes()
    pe = struct.unpack_from("<I", raw, 0x3C)[0]
    stamp = struct.unpack_from("<I", raw, pe + 8)[0]
    sections = struct.unpack_from("<H", raw, pe + 6)[0]
    optional = struct.unpack_from("<H", raw, pe + 20)[0]
    size = struct.unpack_from("<I", raw, pe + 24 + 56)[0]
    image = bytearray(size)
    for i in range(sections):
        header = pe + 24 + optional + 40 * i
        vsize, va, rsize, rptr = struct.unpack_from("<IIII", raw, header + 8)
        n = min(vsize, rsize)
        image[va:va + n] = raw[rptr:rptr + n]
    return bytes(image), stamp


exe = Path(os.environ.get("TRACKMANIA_EXE", r"C:\Program Files (x86)\Ubisoft\Ubisoft Game Launcher\games\Trackmania\Trackmania.exe"))
if not exe.is_file():
    print(f"Physics patterns: source checks PASS (no game binary at {exe})")
    raise SystemExit(0)

image, stamp = load_image(exe)
matches = {}
for var, (name, toks) in patterns.items():
    rx = re.compile(b"".join(b"." if t == "??" else re.escape(bytes([int(t, 16)])) for t in toks), re.S)
    found = [m.start() for m in rx.finditer(image)]
    assert len(found) == 1, f"{name}: {len(found)} matches"
    matches[var] = found[0]


def offset(var, at):
    return struct.unpack_from("<i", image, matches[var] + at)[0]


layout = {f: offset(var, at) for f, (var, at) in fields.items()}
for var, at, f in repeats:
    assert offset(var, at) == layout[f], f"{f} disagrees at {var} @{at}"
print("  " + ", ".join(f"{f} {v:#x}" for f, v in layout.items()))
if stamp == 0x6980D607:
    assert layout == MEASURED, layout
    print("Physics patterns: PASS on the measured build")
else:
    print(f"Physics patterns: PASS on build {stamp:#x} (offsets not compared)")
