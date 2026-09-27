"""Every reset button asks for a second click, like the history window's clear."""

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "plugin"
sources = {path.name: path.read_text(encoding="utf-8") for path in ROOT.glob("*.as")}
settings = sources["Settings.as"]

helper = settings.split(
    "bool ConfirmedResetButton(const string &in label, const string &in id) {", 1
)[1].split("\n}", 1)[0]
assert "if (g_armedReset != id) {" in helper
assert 'if (UI::Button(label + "##" + id)) g_armedReset = id;' in helper
assert 'bool confirmed = UI::Button("Confirm reset##" + id);' in helper
assert 'if (UI::Button("Cancel##" + id)) g_armedReset = "";' in helper
assert 'string g_armedReset = "";' in settings

# No reset button skips the confirmation.
everything = "".join(sources.values())
assert not re.search(r'UI::Button\("Reset', everything)
for call in ('ConfirmedResetButton("Reset to default", "rating")',
             'ConfirmedResetButton("Reset to default", "debug")',
             'ConfirmedResetButton("Reset to default", "sounds")',
             'ConfirmedResetButton("Reset to default", "popup")',
             'ConfirmedResetButton("Reset all widgets", "layout")',
             'ConfirmedResetButton("Reset widget", "widget-" + widget.id)'):
    assert call in everything, call
print("Every reset asks for confirmation: PASS")
