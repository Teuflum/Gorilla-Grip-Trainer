"""Routine log lines are opt-in; problem reports always reach Openplanet.log."""

import re
from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
settings = (root / "Settings.as").read_text(encoding="utf-8")
sources = {path.name: path.read_text(encoding="utf-8") for path in root.glob("*.as")}

assert "[Setting hidden] bool S_DebugLogging = false;" in settings
helper = settings.split("void DebugLog(const string &in message) {", 1)[1].split("\n}", 1)[0]
assert "if (DebugLoggingOn()) print(message);" in helper

# Debug options work and appear only in Openplanet's developer mode.
gate = settings.split("bool DebugLoggingOn() {", 1)[1].split("\n}", 1)[0]
assert gate.split() == ["#if", "SIG_DEVELOPER", "return", "S_DebugLogging;",
                        "#else", "return", "false;", "#endif"], gate
before_tab, debug_tab = settings.split('[SettingsTab name="Debug"', 1)
assert before_tab.rstrip().endswith("#if SIG_DEVELOPER")
assert 'order="99"' in debug_tab.split("]", 1)[0]
debug_body, after_tab = debug_tab.split("void RenderSettingsDebug() {", 1)[1].split("\n}", 1)
assert 'UI::Checkbox("Log trainer events", S_DebugLogging)' in debug_body
assert after_tab.lstrip().startswith("#endif")
assert 'category="Debug"' not in settings

# Problem reports, plus the one-line marker when event logging changes state.
PROBLEMS = (
    "Gorilla Grip Trainer event logging",
    "Gorilla Grip Trainer physics:",
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
    "Gorilla Grip Trainer images: could not load",
)

calls = []
for name, text in sources.items():
    for call, message in re.findall(r'\b(print|DebugLog)\("(Gorilla Grip Trainer[^"]*)"', text):
        calls.append((name, call, message))
assert len(calls) == 40, len(calls)  # 22 routine events, 17 problems, 1 state marker

for name, call, message in calls:
    problem = message.startswith(PROBLEMS)
    expected = "print" if problem else "DebugLog"
    assert call == expected, f"{name}: {call}(\"{message}...\") should use {expected}"
for prefix in PROBLEMS:
    assert any(message.startswith(prefix) for _, _, message in calls), prefix

# In-game tests look for the marker to know event logging is on.
update = sources["Main.as"].split("void Update(float dt) {", 1)[1].split("\n}", 1)[0]
assert "DebugLoggingOn() != g_eventLoggingOn" in update
assert 'print("Gorilla Grip Trainer event logging " + (g_eventLoggingOn ? "on" : "off"))' in update
assert not any("S_DebugLogging" in text for name, text in sources.items()
               if name != "Settings.as"), "read the setting through DebugLoggingOn()"

# The in-game tests read the marker since the latest plugin load.
from trainer_log import event_logging_enabled

LOADED = "[ TRAC] Loaded plugin 'GorillaGripTrainer' (version 0.2.0)\n"
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
