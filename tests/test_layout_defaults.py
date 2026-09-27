"""Check the shipped HUD rectangles at desktop and smaller game resolutions."""

from __future__ import annotations

import re
from pathlib import Path


SOURCE = (Path(__file__).resolve().parents[1] / "plugin" / "Layout.as").read_text()
RECT = re.compile(
    r'WidgetLayout\("([a-z]+)",\s*"[^"]+",\s*vec4\('
    r'([0-9.]+)f,\s*([0-9.]+)f,\s*([0-9.]+)f,\s*([0-9.]+)f\)'
)
widgets = {
    match.group(1): tuple(float(match.group(i)) for i in range(2, 6))
    for match in RECT.finditer(SOURCE)
}
assert set(widgets) == {
    "diagnostics", "grade", "stats", "last", "finish"
}
# The shipped layout (set from the author's in-game arrangement, 2026-09-27).
assert widgets == {
    "diagnostics": (0.030, 0.029, 0.258, 0.181),
    "grade": (0.379, 0.800, 0.240, 0.109),
    "stats": (0.030, 0.701, 0.160, 0.130),
    "last": (0.030, 0.839, 0.210, 0.094),
    "finish": (0.670, 0.029, 0.330, 0.329),
}, widgets
# The [Setting] defaults match the reset rectangles.
prefixes = {"diagnostics": "Diag", "grade": "Result", "stats": "Stats",
            "last": "Last", "finish": "Finish"}
settings = dict(re.findall(r"\[Setting hidden\] float (S_\w+) = ([0-9.]+)f;", SOURCE))
for widget_id, rect in widgets.items():
    saved = tuple(float(settings[f"S_{prefixes[widget_id]}{k}"]) for k in "XYWH")
    assert saved == rect, (widget_id, saved, rect)
assert 'S_ShowWhenGameHudOff' in (Path(__file__).resolve().parents[1] / "plugin" / "Settings.as").read_text()
widgets_source = (Path(__file__).resolve().parents[1] / "plugin" / "Widgets.as").read_text()
assert 'S_EnableWidgets' in widgets_source
assert 'S_ShowWhenGameHudOff' in widgets_source
assert 'UI::CollapsingHeader(widget.title)' in SOURCE
assert 'UI::SameLine();\n        if (ConfirmedResetButton("Reset widget", "widget-" + widget.id))' in SOURCE
layout_body = SOURCE.split('void RenderSettingsLayout() {', 1)[1]
assert layout_body.index('ConfirmedResetButton("Reset all widgets", "layout")') < layout_body.index('UI::CollapsingHeader(')
# The on-screen move boxes explain themselves; the tab has no drag hint.
assert 'Drag the boxes' not in SOURCE
for width, height in ((2048, 1151), (1280, 720)):
    for widget_id, (x, y, w, h) in widgets.items():
        assert 0 <= x <= 1 and 0 <= y <= 1, (widget_id, x, y)
        assert 0.08 <= w <= 0.9 and 0.045 <= h <= 0.8, (widget_id, w, h)
        assert x + w <= 1 and y + h <= 1, (widget_id, x, y, w, h)
        assert w * width >= 100 and h * height >= 30, (widget_id, width, height)
print("Five HUD default rectangles fit at 2048x1151 and 1280x720: PASS")
