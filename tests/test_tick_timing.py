"""Tick-exact timing: the Trainer dates contact changes with the game's own clocks."""

from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
physics = (root / "Physics.as").read_text(encoding="utf-8")
settings = (root / "Settings.as").read_text(encoding="utf-8")
main = (root / "Main.as").read_text(encoding="utf-8")
transitions = (root / "Transitions.as").read_text(encoding="utf-8")
read = physics.split("PhysicsSnapshot@ ReadPhysics(", 1)[1].split("\n}", 1)[0]
update = main.split("void Update(float dt) {", 1)[1].split("\n}", 1)[0]

# Each wheel's block stores the game clock of its last contact change at +0x6c.
assert "array<uint> wheelChangedAt = array<uint>(4);" in physics
assert "uint64 wheel = vehicle + 0x17b4 + 0xb8 * i;" in read
assert "snap.wheelChangedAt[i] = Dev::SafeReadUint32(wheel + 0x6c);" in read
assert "snap.physicsClock = int(Dev::SafeReadUint32(vehicle + 0x4f4));" in read

# Frame skipping simulates a low frame rate, only in developer mode.
assert "[Setting hidden] int S_DebugFrameSkip = 1;" in settings
skip = settings.split("int DebugFrameSkip() {", 1)[1].split("\n}", 1)[0]
assert skip.split() == ["#if", "SIG_DEVELOPER", "return", "Math::Clamp(S_DebugFrameSkip,",
                        "1,", "10);", "#else", "return", "1;", "#endif"], skip
debug_tab = settings.split("void RenderSettingsDebug() {", 1)[1].split("\n}", 1)[0]
assert 'UI::SliderInt("Process every Nth frame", S_DebugFrameSkip, 1, 10)' in debug_tab
assert "S_DebugFrameSkip = 1;" in debug_tab
assert update.index("if (!ProcessThisFrame()) return;") < \
    update.index("PhysicsSnapshot@ next = ReadPhysics(vis, t);")
assert 'DebugLog("Gorilla Grip Trainer frame skip " + frameSkip);' in update
print("Wheel timestamps and frame skip: PASS")

# Stage 0 probe (removed again in Task 5).
assert 'DebugLog("Gorilla Grip Trainer stamp probe at " + t +' in update
assert "vehicle + 0x538 + 4 * i" in read
print("Stage 0 probe line: PASS")
