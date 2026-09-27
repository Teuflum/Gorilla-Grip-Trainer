// Yaw rate on this build (stage 0 of the tick-exact timing spec: slope
// +1.005, r2 0.997 against the frame-to-frame yaw change); -1 when unknown.
const int YAW_RATE_OFFSET = 0x554;
// Converts the stored value to rad/s with the sign of the yaw change.
const float YAW_RATE_SCALE = 1.0f;

// Read-only snapshots of the active physics car on the validated game build.
class PhysicsSnapshot {
    bool exact = false;
    int raceTime = -1;
    int gameTime = -1;
    float rawSteer = 0.0f;
    float smoothedSteer = 0.0f;
    int mode = 0;
    uint modeAt = 0;
    float force = 1.0f;
    // Nonzero selects the game's baseline-force branch (observed during bounces).
    int forceGateState = 0;
    int recoveryDelayMs = 400;
    uint contactMask = 0;
    float meanIcing = 0.0f;
    float icingFL = 0.0f;
    float icingFR = 0.0f;
    float icingRR = 0.0f;
    float icingRL = 0.0f;
    // Ground material under each wheel in the game's wheel order (FL FR RR RL).
    string materials = "";
    float speedKmh = 0.0f;
    // Angle between the car's heading and its horizontal velocity.
    float slipDeg = 0.0f;
    float yaw = 0.0f;
    // Yaw rate in rad/s, from the physics state; false when unknown.
    bool hasYawRate = false;
    float yawRate = 0.0f;
    // Game clock of each wheel's last contact change (touchdown or lift-off),
    // in the contact-bit order. The physics step writes it, so it dates a
    // change that happened between two rendered frames.
    array<uint> wheelChangedAt = array<uint>(4);
    // The physics step's own clock (vehicle+0x4f4).
    int physicsClock = -1;
    // Start of the current neutral-steering spell (vehicle+0x14e0), or -1.
    int neutralAt = -1;
    // Neutral time after which the game lets the stored direction lapse.
    int neutralTimeoutMs = -1;
    // The car's last tick with ground contact (vehicle+0x1414). It stays at the
    // takeoff tick through the flight; sub-tick wheel grazes do not move it.
    int contactClock = -1;
    // The frame clock (PlaygroundClientScriptAPI.GameTime); it runs ahead of
    // the physics tick but advances with race time.
    int frameClock = -1;

    int ModeAgeMs() const {
        int changedAt = int(modeAt);
        if (!exact || mode == 0 || gameTime < 0 || changedAt < 0 ||
            changedAt > gameTime) return -1;
        return gameTime - changedAt;
    }

    // Icing of one wheel in the game's wheel order, matching the contact bits.
    float WheelIcing(uint wheel) const {
        if (wheel == 0) return icingFL;
        if (wheel == 1) return icingFR;
        if (wheel == 2) return icingRR;
        return icingRL;
    }

    string ContactBits() const {
        string bits = "";
        for (uint i = 0; i < 4; i++)
            bits += (contactMask & (1 << i)) != 0 ? "1" : "0";
        return bits;
    }

    // Race time of a physics tick; race time and the frame clock advance together.
    int RaceAt(int tick) const { return tick + raceTime - frameClock; }
}

bool IsSupportedBuild() {
    uint64 base = Dev::BaseAddress();
    uint peOffset = Dev::SafeReadUint32(base + 0x3c);
    return peOffset > 0x40 && peOffset < 0x1000 &&
        Dev::SafeReadUint32(base + peOffset + 8) == 0x6980d607 &&
        Dev::SafeReadUint32(base + peOffset + 24 + 56) == 0x2cba000;
}

int ReadRaceTime(CSceneVehicleVisState@ vis) {
    auto app = GetApp();
    int t = -1;
    int start = int(vis.RaceStartTime);
    if (app !is null && app.CurrentPlayground !is null &&
        app.CurrentPlayground.GameTerminals.Length > 0) {
        CSmPlayer@ player = cast<CSmPlayer>(app.CurrentPlayground.GameTerminals[0].GUIPlayer);
        if (player !is null) {
            CSmScriptPlayer@ script = cast<CSmScriptPlayer>(player.ScriptAPI);
            if (script !is null) {
                t = script.CurrentRaceTime;
                start = script.StartTime;
            }
        }
    }
    if (t <= 0 && app !is null && app.Network !is null &&
        app.Network.PlaygroundClientScriptAPI !is null) {
        auto api = cast<CGamePlaygroundClientScriptAPI>(app.Network.PlaygroundClientScriptAPI);
        if (api !is null) t = api.GameTime - start;
    }
    return t;
}

PhysicsSnapshot@ ReadPhysics(CSceneVehicleVisState@ vis, int raceTime) {
    PhysicsSnapshot@ snap = PhysicsSnapshot();
    snap.raceTime = raceTime;
    snap.icingFL = vis.FLIcing01;
    snap.icingFR = vis.FRIcing01;
    snap.icingRR = vis.RRIcing01;
    snap.icingRL = vis.RLIcing01;
    snap.meanIcing = (snap.icingFL + snap.icingFR + snap.icingRR + snap.icingRL) * 0.25f;
    snap.materials = tostring(vis.FLGroundContactMaterial) + "/" +
        tostring(vis.FRGroundContactMaterial) + "/" +
        tostring(vis.RRGroundContactMaterial) + "/" +
        tostring(vis.RLGroundContactMaterial);
    snap.speedKmh = vis.WorldVel.Length() * 3.6f;
    snap.yaw = Math::Atan2(vis.Dir.x, vis.Dir.z);
    float forward = vis.WorldVel.x * vis.Dir.x + vis.WorldVel.z * vis.Dir.z;
    float side = vis.WorldVel.x * vis.Dir.z - vis.WorldVel.z * vis.Dir.x;
    snap.slipDeg = Math::ToDeg(Math::Atan2(Math::Abs(side), forward));
    if (!g_supportedBuild) return snap;

    auto app = GetApp();
    if (app is null || app.CurrentPlayground is null ||
        app.CurrentPlayground.GameTerminals.Length == 0) return snap;
    if (app.Network !is null && app.Network.PlaygroundClientScriptAPI !is null) {
        auto api = cast<CGamePlaygroundClientScriptAPI>(app.Network.PlaygroundClientScriptAPI);
        if (api !is null) snap.gameTime = api.GameTime;
    }
    CSmPlayer@ player = cast<CSmPlayer>(app.CurrentPlayground.GameTerminals[0].GUIPlayer);
    if (player is null) return snap;
    uint64 vehicle = Dev::GetOffsetUint64(player, 0x1118);
    if (vehicle < 0x10000 || Dev::SafeReadUint32(vehicle + 0x380) != 4) return snap;
    uint64 model = Dev::SafeReadUint64(vehicle + 0x88);
    if (model < 0x10000) return snap;
    vec3 pos = Dev::SafeReadVec3(vehicle + 0x538);
    if ((pos - vis.Position).Length() > 4.0f) return snap;

    float raw = Dev::SafeReadFloat(vehicle + 0xa0);
    float smooth = Dev::SafeReadFloat(vehicle + 0x1430);
    float force = Dev::SafeReadFloat(vehicle + 0x14dc);
    uint8 mode = Dev::SafeReadUint8(vehicle + 0x14e5);
    uint delay = Dev::SafeReadUint32(model + 0x1194);
    if (Math::Abs(raw - vis.InputSteer) > 0.25f ||
        smooth < -1.001f || smooth > 1.001f ||
        force < 0.95f || force > 2.1f || mode > 2 ||
        delay < 100 || delay > 1000) return snap;

    snap.rawSteer = raw;
    snap.smoothedSteer = smooth;
    snap.mode = int(mode);
    snap.modeAt = Dev::SafeReadUint32(vehicle + 0x14d8);
    snap.force = force;
    snap.forceGateState = int(Dev::SafeReadUint32(vehicle + 0x1600));
    snap.recoveryDelayMs = int(delay);
    for (uint i = 0; i < 4; i++) {
        uint64 wheel = vehicle + 0x17b4 + 0xb8 * i;
        if (Dev::SafeReadUint32(wheel) != 0)
            snap.contactMask |= (1 << i);
        snap.wheelChangedAt[i] = Dev::SafeReadUint32(wheel + 0x6c);
    }
    snap.physicsClock = int(Dev::SafeReadUint32(vehicle + 0x4f4));
    snap.contactClock = int(Dev::SafeReadUint32(vehicle + 0x1414));
    // Stage 0: time everything on the physics clock.
    snap.frameClock = snap.gameTime;
    snap.gameTime = snap.physicsClock;
    if (YAW_RATE_OFFSET >= 0) {
        snap.yawRate = YAW_RATE_SCALE * Dev::SafeReadFloat(vehicle + uint64(YAW_RATE_OFFSET));
        snap.hasYawRate = Math::Abs(snap.yawRate) < 100.0f;
    }
    snap.neutralAt = int(Dev::SafeReadUint32(vehicle + 0x14e0));
    uint neutralTimeout = Dev::SafeReadUint32(model + 0x1198);
    snap.neutralTimeoutMs = neutralTimeout >= 50 && neutralTimeout <= 5000 ?
        int(neutralTimeout) : -1;
    snap.exact = true;
    return snap;
}
