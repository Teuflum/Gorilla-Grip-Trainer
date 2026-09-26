"""Routine log lines are opt-in; problem reports always reach Openplanet.log."""

import re
from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
settings = (root / "Settings.as").read_text(encoding="utf-8")
sources = {path.name: path.read_text(encoding="utf-8") for path in root.glob("*.as")}

assert '[Setting category="Debug" name="Log trainer events"' in settings
assert "bool S_DebugLogging = false;" in settings
helper = settings.split("void DebugLog(const string &in message) {", 1)[1].split("\n}", 1)[0]
assert "if (S_DebugLogging) print(message);" in helper

# Problem reports, plus the one-line marker when event logging changes state.
PROBLEMS = (
    "Gorilla Grip Trainer event logging",
    "Gorilla Grip Trainer: unsupported executable signature",
    "Gorilla Grip Trainer audio file name rejected",
    "Gorilla Grip Trainer audio missing",
    "Gorilla Grip Trainer audio could not load",
    "Gorilla Grip Trainer audio: results loop could not restart",
    "Gorilla Grip Trainer audio: results sound unavailable",
    "Gorilla Grip Trainer audio: results voice could not start",
    "Gorilla Grip Trainer history: primary file invalid",
    "Gorilla Grip Trainer history: recovered from backup",
    "Gorilla Grip Trainer history: backup invalid",
    "Gorilla Grip Trainer history: preserved corrupt file",
    "Gorilla Grip Trainer: gorilla emoji texture could not load",
)

calls = []
for name, text in sources.items():
    for call, message in re.findall(r'\b(print|DebugLog)\("(Gorilla Grip Trainer[^"]*)"', text):
        calls.append((name, call, message))
assert len(calls) == 30, len(calls)  # 17 routine events, 12 problems, 1 state marker

for name, call, message in calls:
    problem = message.startswith(PROBLEMS)
    expected = "print" if problem else "DebugLog"
    assert call == expected, f"{name}: {call}(\"{message}...\") should use {expected}"
for prefix in PROBLEMS:
    assert any(message.startswith(prefix) for _, _, message in calls), prefix

# In-game tests look for the marker to know event logging is on.
update = sources["Main.as"].split("void Update(float dt) {", 1)[1].split("\n}", 1)[0]
assert "S_DebugLogging != g_eventLoggingOn" in update
assert 'print("Gorilla Grip Trainer event logging " + (S_DebugLogging ? "on" : "off"))' in update

# The in-game tests read the marker since the latest plugin load.
from trainer_log import event_logging_enabled

LOADED = "[ TRAC] Loaded plugin 'GorillaGripTrainer' (version 0.1.0)\n"
ON = "[GorillaGripTrainer]  Gorilla Grip Trainer event logging on\n"
OFF = "[GorillaGripTrainer]  Gorilla Grip Trainer event logging off\n"
assert not event_logging_enabled("")
assert not event_logging_enabled(LOADED)
assert event_logging_enabled(LOADED + ON)
assert not event_logging_enabled(LOADED + ON + OFF)
assert event_logging_enabled(LOADED + OFF + ON)
assert not event_logging_enabled(ON + LOADED), "a marker before the reload is stale"

# The force trace extends the snapshot log, so it needs event logging on.
main = sources["Main.as"]
assert 'DebugLog("Gorilla Grip Trainer snapshot at' in main
print("Routine trainer logging is behind the Debug switch: PASS")
