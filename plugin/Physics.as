// Read-only snapshots of the active physics car.
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

// Where the physics fields live. Most offsets are read at load time from the
// game code that uses them, so an update that moves a field moves the offset
// with it. The fixed ones were measured in memory; no instruction names them
// directly, and the checks in ReadPhysics reject a read if they move.
class PhysicsLayout {
    uint model = 0;          // vehicle -> car model
    uint wheelCount = 0;
    uint rawSteer = 0;
    uint smoothedSteer = 0;
    uint forceGate = 0;
    uint modeAt = 0;
    uint force = 0;
    uint neutralAt = 0;
    uint mode = 0;
    uint contactClock = 0;
    uint wheels = 0;         // first wheel's contact flag
    uint wheelStride = 0;
    uint recoveryDelay = 0;  // on the model
    uint neutralTimeout = 0; // on the model
    uint vehicle = 0x1118;   // on CSmPlayer
    uint position = 0x538;
    uint physicsClock = 0x4f4;
    uint wheelChangedAt = 0x6c; // within a wheel
}

PhysicsLayout g_layout;

uint64 FindPhysicsCode(const string &in name, const string &in pattern) {
    uint64 code = Dev::FindPattern(pattern);
    if (code == 0) print("Gorilla Grip Trainer physics: code not found: " + name);
    return code;
}

// The 32-bit field offset stored at byte `at` of a code match.
uint CodeOffset(uint64 code, uint at) {
    return uint(Dev::ReadInt32(code + at));
}

bool PlausibleOffset(uint offset) {
    return offset >= 0x40 && offset < 0x4000;
}

// Locates the physics fields in the running game. The patterns wildcard every
// field offset, call target, jump and stack slot, so they survive a rebuild that
// only moves those. Fields that appear more than once in a match must agree.
bool LocatePhysics() {
    // Steering rate limiter: model and wheel count.
    uint64 wheelLoop = FindPhysicsCode("wheel loop",
        "48 8B 82 ?? ?? ?? ?? 8B 52 10 48 89 84 24 ?? ?? ?? ?? E8 ?? ?? ?? ?? "
        "44 8B BB ?? ?? ?? ?? 4C 8D A3 ?? ?? ?? ??");
    // Same function: reverse gate, raw steer, smoothed steer.
    uint64 steerInput = FindPhysicsCode("steering input",
        "83 BB ?? ?? ?? ?? 00 74 ?? F3 0F 10 8B ?? ?? ?? ?? EB ?? F3 0F 10 8B ?? ?? ?? ?? "
        "41 0F 28 D1 48 8B CB E8 ?? ?? ?? ?? 48 8D 8B ?? ?? ?? ?? E8 ?? ?? ?? ?? "
        "48 8B BC 24 ?? ?? ?? ?? 85 C0 74 ?? 41 0F 28 C8 EB ?? F3 0F 10 8B ?? ?? ?? ?? "
        "48 8B 84 24 ?? ?? ?? ?? F3 0F 59 B8 ?? ?? ?? ?? 44 0F 2F C7 73 ?? F3 0F 10 93 ?? ?? ?? ??");
    // Per-wheel contact test: model, wheel stride, first contact flag.
    uint64 contactFlags = FindPhysicsCode("contact flags",
        "40 53 48 83 EC ?? 48 8B 99 ?? ?? ?? ?? 4C 8B C1 44 8B D2 48 81 C1 ?? ?? ?? ?? "
        "44 0F 29 54 24 ?? 0F 28 EA 49 69 D2 ?? ?? ?? ?? 44 0F 28 D3 E8 ?? ?? ?? ?? "
        "42 83 BC 02 ?? ?? ?? ?? 00");
    // The +-0.1 steering comparison that stores the slide direction.
    uint64 steerMode = FindPhysicsCode("steering mode",
        "F3 0F 10 05 ?? ?? ?? ?? 0F 2F C1 76 ?? C6 87 ?? ?? ?? ?? 01 C7 87 ?? ?? ?? ?? FF FF FF FF "
        "EB ?? 0F 2F CA 76 ?? C6 87 ?? ?? ?? ?? 02 C7 87 ?? ?? ?? ?? FF FF FF FF EB ?? "
        "8B 8F ?? ?? ?? ?? 83 F9 FF 75 ?? 89 97 ?? ?? ?? ?? 8B CA 41 03 8F ?? ?? ?? ?? "
        "3B CA 73 ?? C6 87 ?? ?? ?? ?? 00 C7 87 ?? ?? ?? ?? FF FF FF FF "
        "0F B6 87 ?? ?? ?? ?? 38 87 ?? ?? ?? ?? 75 ?? F7 87 ?? ?? ?? ?? 00 00 02 00 74 ?? "
        "89 97 ?? ?? ?? ?? C7 87 ?? ?? ?? ?? 00 00 80 3F");
    // Contact processing stamps the car's last grounded tick.
    uint64 contactClock = FindPhysicsCode("contact clock",
        "44 89 A3 ?? ?? ?? ?? 41 8B 00 89 83 ?? ?? ?? ?? 41 8B 40 04 89 83 ?? ?? ?? ?? "
        "41 8B 40 08 89 83 ?? ?? ?? ?? 44 89 B3 ?? ?? ?? ?? E9 ?? ?? ?? ??");
    // Model defaults: 400 ms force recovery delay, 300 ms neutral timeout.
    uint64 modelDefaults = FindPhysicsCode("model defaults",
        "41 C7 84 24 ?? ?? ?? ?? 90 01 00 00 0F 28 45 ?? 41 C7 84 24 ?? ?? ?? ?? 2C 01 00 00");
    if (wheelLoop == 0 || steerInput == 0 || contactFlags == 0 || steerMode == 0 ||
        contactClock == 0 || modelDefaults == 0) return false;

    PhysicsLayout l;
    l.model = CodeOffset(wheelLoop, 3);
    l.wheelCount = CodeOffset(wheelLoop, 26);
    l.forceGate = CodeOffset(steerInput, 2);
    l.rawSteer = CodeOffset(steerInput, 73);
    l.smoothedSteer = CodeOffset(steerInput, 103);
    l.wheelStride = CodeOffset(contactFlags, 38);
    l.wheels = CodeOffset(contactFlags, 55);
    l.mode = CodeOffset(steerMode, 15);
    l.neutralAt = CodeOffset(steerMode, 22);
    l.modeAt = CodeOffset(steerMode, 95);
    l.force = CodeOffset(steerMode, 138);
    l.contactClock = CodeOffset(contactClock, 3);
    l.recoveryDelay = CodeOffset(modelDefaults, 4);
    l.neutralTimeout = CodeOffset(modelDefaults, 20);

    bool agree = CodeOffset(contactFlags, 9) == l.model &&
        CodeOffset(steerMode, 39) == l.mode && CodeOffset(steerMode, 88) == l.mode &&
        CodeOffset(steerMode, 112) == l.mode &&
        CodeOffset(steerMode, 46) == l.neutralAt && CodeOffset(steerMode, 58) == l.neutralAt &&
        CodeOffset(steerMode, 69) == l.neutralAt && CodeOffset(steerMode, 132) == l.modeAt;
    array<uint> offsets = { l.model, l.wheelCount, l.rawSteer, l.smoothedSteer,
        l.forceGate, l.modeAt, l.force, l.neutralAt, l.mode, l.contactClock, l.wheels,
        l.recoveryDelay, l.neutralTimeout };
    bool plausible = l.wheelStride >= 0x40 && l.wheelStride <= 0x400;
    for (uint i = 0; i < offsets.Length; i++)
        plausible = plausible && PlausibleOffset(offsets[i]);
    if (!agree || !plausible) {
        print("Gorilla Grip Trainer physics: code check failed (" +
            (agree ? "implausible offset" : "offsets disagree") + ")");
        return false;
    }
    g_layout = l;
    return true;
}

string Hex(uint value) { return Text::Format("0x%x", value); }

string DescribeLayout() {
    PhysicsLayout@ l = g_layout;
    return "model " + Hex(l.model) + ", wheel count " + Hex(l.wheelCount) +
        ", raw " + Hex(l.rawSteer) + ", smoothed " + Hex(l.smoothedSteer) +
        ", gate " + Hex(l.forceGate) + ", modeAt " + Hex(l.modeAt) +
        ", force " + Hex(l.force) + ", neutralAt " + Hex(l.neutralAt) +
        ", mode " + Hex(l.mode) + ", contact clock " + Hex(l.contactClock) +
        ", wheels " + Hex(l.wheels) + " + " + Hex(l.wheelStride) + " * i" +
        ", delay " + Hex(l.recoveryDelay) + ", timeout " + Hex(l.neutralTimeout);
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
    PhysicsLayout@ l = g_layout;
    uint64 vehicle = Dev::GetOffsetUint64(player, l.vehicle);
    if (vehicle < 0x10000 || Dev::SafeReadUint32(vehicle + l.wheelCount) != 4) return snap;
    uint64 model = Dev::SafeReadUint64(vehicle + l.model);
    if (model < 0x10000) return snap;
    vec3 pos = Dev::SafeReadVec3(vehicle + l.position);
    if ((pos - vis.Position).Length() > 4.0f) return snap;

    float raw = Dev::SafeReadFloat(vehicle + l.rawSteer);
    float smooth = Dev::SafeReadFloat(vehicle + l.smoothedSteer);
    float force = Dev::SafeReadFloat(vehicle + l.force);
    uint8 mode = Dev::SafeReadUint8(vehicle + l.mode);
    uint delay = Dev::SafeReadUint32(model + l.recoveryDelay);
    int physicsClock = int(Dev::SafeReadUint32(vehicle + l.physicsClock));
    if (Math::Abs(raw - vis.InputSteer) > 0.25f ||
        smooth < -1.001f || smooth > 1.001f ||
        force < 0.95f || force > 2.1f || mode > 2 ||
        delay < 100 || delay > 1000) return snap;
    // The physics clock trails the frame clock by under one tick.
    if (snap.gameTime >= 0 && Math::Abs(physicsClock - snap.gameTime) > 1000) return snap;

    snap.rawSteer = raw;
    snap.smoothedSteer = smooth;
    snap.mode = int(mode);
    snap.modeAt = Dev::SafeReadUint32(vehicle + l.modeAt);
    snap.force = force;
    snap.forceGateState = int(Dev::SafeReadUint32(vehicle + l.forceGate));
    snap.recoveryDelayMs = int(delay);
    for (uint i = 0; i < 4; i++) {
        uint64 wheel = vehicle + l.wheels + l.wheelStride * i;
        if (Dev::SafeReadUint32(wheel) != 0)
            snap.contactMask |= (1 << i);
        snap.wheelChangedAt[i] = Dev::SafeReadUint32(wheel + l.wheelChangedAt);
    }
    snap.physicsClock = physicsClock;
    snap.contactClock = int(Dev::SafeReadUint32(vehicle + l.contactClock));
    // Stage 0: time everything on the physics clock.
    snap.frameClock = snap.gameTime;
    snap.gameTime = snap.physicsClock;
    snap.neutralAt = int(Dev::SafeReadUint32(vehicle + l.neutralAt));
    uint neutralTimeout = Dev::SafeReadUint32(model + l.neutralTimeout);
    snap.neutralTimeoutMs = neutralTimeout >= 50 && neutralTimeout <= 5000 ?
        int(neutralTimeout) : -1;
    snap.exact = true;
    return snap;
}
