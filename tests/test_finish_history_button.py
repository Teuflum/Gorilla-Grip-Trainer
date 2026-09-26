"""VIEW HISTORY works with the Openplanet overlay open and centres its caps."""

from pathlib import Path


root = Path(__file__).resolve().parents[1] / "plugin"
finish = (root / "Finish.as").read_text(encoding="utf-8")
button = finish.split("void RenderFinishHistoryButton(", 1)[1].split("\n}", 1)[0]

# Clicks count whether or not the overlay is open, except when an overlay
# window (any plugin's, or Openplanet's own) lies under the mouse.
assert "!UI::IsOverlayShown() && UI::IsMouseClicked()" not in button
assert "IsWindowHovered" not in finish
assert "bool overWindow = UI::IsOverlayShown() && UI::WantCaptureMouse();" in button
# A covered button neither highlights nor clicks.
assert "bool active = hovered && !overWindow;" in button
assert button.index("bool active") < button.index("HudBox(")
assert "HudBox(x, y, width, height, 7*scale, active ?" in button
assert "if (active && UI::IsMouseClicked()) {" in button
window = (root / "HistoryWindow.as").read_text(encoding="utf-8")
assert "g_historyWindowRect" not in window and "MouseOverHistoryWindow" not in window

# All-caps label sits on its baseline, half a cap height below the centre.
assert "nvg::Align::Center | nvg::Align::Baseline" in button
assert "y + height*0.5f + 0.36f*fontSize" in button
print("VIEW HISTORY button click and alignment: PASS")
