"""Only jumps in the Stadium car are rated.

The Snow, Rally and Desert cars don't ice slide, so they have no gorilla grip.
Their frames never reach the transition tracker, and a car change resets it so
a jump that started in one car is not graded in another.
"""

from pathlib import Path


root = Path(__file__).resolve().parents[1]
main = (root / "plugin" / "Main.as").read_text(encoding="utf-8")
readme = (root / "README.md").read_text(encoding="utf-8")
update_body = main.split("void Update(float dt) {", 1)[1].split("\n}\n", 1)[0]

helper = main.split("bool IsStadiumCar(CSceneVehicleVisState@ vis) {", 1)[1].split("\n}\n", 1)[0]
assert "VehicleState::GetVehicleType(vis) == VehicleState::VehicleType::CarSport" in helper

gate = update_body.split("bool stadiumCar = IsStadiumCar(vis);", 1)[1]
before_tracker = gate.split("g_tracker.Update(next);", 1)[0]
# The car check runs before every tracker update.
assert update_body.count("g_tracker.Update(") == 1
assert "if (!stadiumCar) {" in before_tracker
assert "return;" in before_tracker.split("if (!stadiumCar) {", 1)[1].split("}", 1)[0]
# A car change drops the jump in progress.
change = before_tracker.split("if (stadiumCar != g_stadiumCar) {", 1)[1].split("}", 1)[0]
assert "g_stadiumCar = stadiumCar;" in change and "g_tracker.Reset();" in change
# The widgets keep showing the current car's physics.
assert update_body.index("@g_snapshot = next;") < update_body.index("IsStadiumCar(vis)")

assert "Only the Stadium car is rated" in readme
print("Only Stadium-car jumps are rated: PASS")
