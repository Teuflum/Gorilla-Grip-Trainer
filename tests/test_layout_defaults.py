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
    "diagnostics", "grade", "combo", "score", "best", "last", "finish"
}
assert 'S_ShowWhenGameHudOff' in (Path(__file__).resolve().parents[1] / "plugin" / "Settings.as").read_text()
widgets_source = (Path(__file__).resolve().parents[1] / "plugin" / "Widgets.as").read_text()
assert 'S_EnableWidgets' in widgets_source
assert 'S_ShowWhenGameHudOff' in widgets_source
assert 'UI::CollapsingHeader(widget.title)' in SOURCE
assert 'UI::SameLine();\n        if (UI::Button("Reset widget"))' in SOURCE
for width, height in ((2048, 1151), (1280, 720)):
    for widget_id, (x, y, w, h) in widgets.items():
        assert 0 <= x <= 1 and 0 <= y <= 1, (widget_id, x, y)
        assert 0.08 <= w <= 0.9 and 0.045 <= h <= 0.8, (widget_id, w, h)
        assert x + w <= 1 and y + h <= 1, (widget_id, x, y, w, h)
        assert w * width >= 100 and h * height >= 30, (widget_id, width, height)
print("Seven HUD default rectangles fit at 2048x1151 and 1280x720: PASS")
