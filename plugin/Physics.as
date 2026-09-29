// Read-only snapshots of the active physics car.
class PhysicsSnapshot {
    bool exact = false;
    // The check that rejected the read, when it is not exact.
    string failure = "";
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

// Where the physics fields live. Every offset is read at load time from the
// game code that uses it, so an update that moves a field moves the offset
// with it. The checks in ReadPhysics still reject a read that looks wrong.
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
    uint vehicle = 0;        // on CSmPlayer
    uint position = 0;
    uint physicsClock = 0;
    uint wheelChangedAt = 0; // from a wheel's contact flag
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

// The byte offset stored at byte `at` of a code match.
uint CodeByte(uint64 code, uint at) {
    return Dev::ReadUint8(code + at);
}

// Where the call or jump whose 32-bit displacement is at byte `at` goes.
uint64 CodeTarget(uint64 code, uint at) {
    return uint64(int64(code) + int64(at) + 4 + int64(Dev::ReadInt32(code + at)));
}

bool PlausibleOffset(uint offset) {
    return offset >= 0x40 && offset < 0x4000;
}

// Locates the physics fields in the running game. The patterns wildcard every
// field offset, call target, jump and stack slot, so they survive a rebuild that
// only moves those. Fields that appear more than once in a match must agree.
// Every pattern ends on a fixed byte: Dev::FindPattern misses a pattern that
// ends in a wildcard.
bool LocatePhysics() {
    // Steering rate limiter: model and wheel count.
    uint64 wheelLoop = FindPhysicsCode("wheel loop",
        "48 8B 82 ?? ?? ?? ?? 8B 52 10 48 89 84 24 ?? ?? ?? ?? E8 ?? ?? ?? ?? "
        "44 8B BB ?? ?? ?? ?? 4C 8D A3 ?? ?? ?? ?? F3 0F 10 35");
    // Same function: reverse gate, raw steer, smoothed steer.
    uint64 steerInput = FindPhysicsCode("steering input",
        "83 BB ?? ?? ?? ?? 00 74 ?? F3 0F 10 8B ?? ?? ?? ?? EB ?? F3 0F 10 8B ?? ?? ?? ?? "
        "41 0F 28 D1 48 8B CB E8 ?? ?? ?? ?? 48 8D 8B ?? ?? ?? ?? E8 ?? ?? ?? ?? "
        "48 8B BC 24 ?? ?? ?? ?? 85 C0 74 ?? 41 0F 28 C8 EB ?? F3 0F 10 8B ?? ?? ?? ?? "
        "48 8B 84 24 ?? ?? ?? ?? F3 0F 59 B8 ?? ?? ?? ?? 44 0F 2F C7 73 ?? F3 0F 10 93 ?? ?? ?? ?? 0F 28 C2");
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
        "41 8B 40 08 89 83 ?? ?? ?? ?? 44 89 B3 ?? ?? ?? ?? E9");
    // Model defaults: 400 ms force recovery delay, 300 ms neutral timeout.
    uint64 modelDefaults = FindPhysicsCode("model defaults",
        "41 C7 84 24 ?? ?? ?? ?? 90 01 00 00 0F 28 45 ?? 41 C7 84 24 ?? ?? ?? ?? 2C 01 00 00");
    // The player holds its car as a handle {id, ?, pointer}; both paths here
    // resolve the same handle with the car-class resolver.
    uint64 vehicleHandle = FindPhysicsCode("vehicle handle",
        "41 0F 10 86 ?? ?? ?? ?? 48 8D 4C 24 ?? 0F 29 44 24 ?? E8 ?? ?? ?? ?? 48 85 C0 0F 84 ?? ?? ?? ?? "
        "41 8B 8E ?? ?? ?? ?? 4C 8B 7C 24 ?? 89 88 ?? ?? ?? ?? 41 8B 8E ?? ?? ?? ?? 89 88 ?? ?? ?? ?? "
        "48 83 C4 ?? 41 5E C3 41 0F 10 86 ?? ?? ?? ?? 48 89 5C 24");
    // The resolver checks the id against class 0x0A020000 and returns the
    // pointer, shifted out of the handle's upper bytes.
    uint64 vehicleResolver = FindPhysicsCode("vehicle resolver",
        "48 83 EC ?? 0F 28 01 BA 00 00 02 0A 0F 11 44 24 ?? 8B 4C 24 ?? 0F 11 44 24 ?? E8 ?? ?? ?? ?? "
        "0F 10 44 24 ?? 8B C8 33 D2 85 C9 66 0F 73 D8 ?? 66 48 0F 7E C0");
    // Per-wheel contact update: reads the contact flag, sets the state (1 on
    // the ground, 2 in the air) and times the change against the clock stamp.
    uint64 wheelState = FindPhysicsCode("wheel state",
        "44 8B 41 ?? 45 85 C0 74 ?? 0F B6 41 ?? 3C ?? 74 ?? 3C ?? 74 ?? 3C ?? 75 ?? 41 83 B9 ?? ?? ?? ?? 00 74 ?? "
        "B8 01 00 00 00 EB ?? 33 C0 41 83 FA 01 75 ?? 85 D2 75 ?? 89 91 ?? ?? ?? ?? EB ?? 45 85 C0 74 ?? "
        "0F B6 41 ?? 3C ?? 74 ?? 3C ?? 74 ?? 3C ?? 74 ?? C7 81 ?? ?? ?? ?? 02 00 00 00 EB ?? 41 83 FA 02 75 ?? "
        "85 D2 75 ?? 89 91 ?? ?? ?? ?? EB ?? 85 C0 74 ?? C7 81 ?? ?? ?? ?? 01 00 00 00 EB ?? 85 D2 74 ?? "
        "F7 D8 1B C0 83 C0 02 89 81 ?? ?? ?? ?? 8B 91 ?? ?? ?? ?? 44 3B D2 75 ?? 44 3B 41 ?? 0F 84 ?? ?? ?? ?? "
        "41 83 FA 01 75 ?? 41 8B C3 0F 57 C9 2B 81 ?? ?? ?? ?? 0F 57 C0");
    // The car's per-tick state: a caller passes its place in the car to the
    // fill, which passes it and the clock on to the writer.
    uint64 stateCaller = FindPhysicsCode("state caller",
        "49 8B 86 ?? ?? ?? ?? 49 8B CE 49 8B 3C 07 48 8B D7 4C 8D 87 ?? ?? ?? ?? E8 ?? ?? ?? ?? "
        "8B 87 ?? ?? ?? ?? 83 F8 FF");
    uint64 stateFill = FindPhysicsCode("state fill",
        "48 89 5C 24 ?? 48 89 6C 24 ?? 48 89 74 24 ?? 48 89 7C 24 ?? 41 56 48 83 EC ?? 48 8B DA "
        "0F 29 74 24 ?? 48 8B 11 4C 8B F1 48 8D 4C 24 ?? 49 8B F8 E8 ?? ?? ?? ?? 8B 53 ?? 4C 8D 93 ?? ?? ?? ?? "
        "48 8B AB ?? ?? ?? ?? 0F 57 F6 8B 30 83 FA FF 74 ?? 49 8B 8E ?? ?? ?? ?? 4C 8D 44 24 ?? E8 ?? ?? ?? ?? EB ?? "
        "48 C7 44 24 ?? 00 00 00 00 C7 44 24 ?? 00 00 00 00 4C 8B 03 4C 8D 8B ?? ?? ?? ?? 48 89 7C 24 ?? "
        "48 8D 54 24 ?? 8B CE 4C 89 54 24 ?? E8");
    // The writer stores the clock in the state first...
    uint64 stateWriter = FindPhysicsCode("state writer",
        "4C 8B DC 55 57 41 54 49 8D 6B ?? 48 81 EC ?? ?? ?? ?? 48 8B 05 ?? ?? ?? ?? 48 33 C4 48 89 45 ?? "
        "48 8B 7D ?? 4D 8B D0 49 89 5B ?? 49 8B D9 49 89 73 ?? 48 8B 75 ?? 4D 89 6B ?? 4D 89 73 ?? 44 8B F1 "
        "4D 89 7B ?? 4C 8B FA 41 0F 29 73 ?? 41 0F 29 7B ?? 45 0F 29 43 ?? 45 0F 29 4B ?? 45 0F 29 93 ?? ?? ?? ?? "
        "89 4C 24 ?? 49 8B 48 ?? 45 0F 29 9B ?? ?? ?? ?? 45 0F 29 A3 ?? ?? ?? ?? 48 89 7C 24 ?? E8 ?? ?? ?? ?? "
        "4C 8B E8 48 8D 4C 24 ?? 41 8B 40 ?? 45 8B CE 48 89 4C 24 ?? 4D 8B C5 48 8B CE 89 44 24 ?? 49 8B D2 "
        "E8 ?? ?? ?? ?? F3 44 0F 10 25 ?? ?? ?? ?? 44 89 77 ?? 41 0F 28 D4");
    // ...and later the rotation, then the position copied from the physics body.
    uint64 stateLocation = FindPhysicsCode("state location",
        "48 8D 54 24 ?? 48 8D 4F ?? 66 0F 7F 44 24 ?? E8 ?? ?? ?? ?? 41 0F 28 D4 48 8D 56 ?? 48 8D 4F ?? "
        "E8 ?? ?? ?? ?? F3 0F 10 46 ?? 48 8D 4F ?? F3 0F 58 86");
    if (wheelLoop == 0 || steerInput == 0 || contactFlags == 0 || steerMode == 0 ||
        contactClock == 0 || modelDefaults == 0 || vehicleHandle == 0 ||
        vehicleResolver == 0 || wheelState == 0 || stateCaller == 0 || stateFill == 0 ||
        stateWriter == 0 || stateLocation == 0) return false;

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
    uint pointerAt = CodeByte(vehicleResolver, 46);
    l.vehicle = CodeOffset(vehicleHandle, 4) + pointerAt;
    uint flagAt = CodeByte(wheelState, 3);
    uint stampAt = CodeOffset(wheelState, 181);
    l.wheelChangedAt = stampAt - flagAt;
    uint stateAt = CodeOffset(stateCaller, 20);
    l.physicsClock = stateAt + CodeByte(stateWriter, 184);
    l.position = stateAt + CodeByte(stateLocation, 31);

    bool agree = CodeOffset(contactFlags, 9) == l.model &&
        CodeOffset(steerMode, 39) == l.mode && CodeOffset(steerMode, 88) == l.mode &&
        CodeOffset(steerMode, 112) == l.mode &&
        CodeOffset(steerMode, 46) == l.neutralAt && CodeOffset(steerMode, 58) == l.neutralAt &&
        CodeOffset(steerMode, 69) == l.neutralAt && CodeOffset(steerMode, 132) == l.modeAt &&
        CodeOffset(vehicleHandle, 74) == CodeOffset(vehicleHandle, 4) &&
        CodeOffset(wheelState, 85) == CodeOffset(wheelState, 56) &&
        CodeOffset(wheelState, 107) == CodeOffset(wheelState, 56) &&
        CodeOffset(wheelState, 119) == CodeOffset(wheelState, 56) &&
        CodeOffset(wheelState, 142) == CodeOffset(wheelState, 56) &&
        CodeOffset(wheelState, 148) == CodeOffset(wheelState, 56) &&
        // The handle goes to this resolver, and the state place to this writer.
        CodeTarget(vehicleHandle, 19) == vehicleResolver &&
        CodeTarget(stateCaller, 25) == stateFill && CodeTarget(stateFill, 144) == stateWriter &&
        stateLocation > stateWriter && stateLocation - stateWriter < 0x1000;
    array<uint> offsets = { l.model, l.wheelCount, l.rawSteer, l.smoothedSteer,
        l.forceGate, l.modeAt, l.force, l.neutralAt, l.mode, l.contactClock, l.wheels,
        l.recoveryDelay, l.neutralTimeout, l.position, l.physicsClock };
    bool plausible = l.wheelStride >= 0x40 && l.wheelStride <= 0x400 &&
        // A pointer inside a 16-byte handle, on a CSmPlayer.
        pointerAt >= 4 && pointerAt < 16 && l.vehicle % 8 == 0 &&
        l.vehicle >= 0x40 && l.vehicle < 0x10000 &&
        // The stamp lies after the contact flag, in the same wheel.
        stampAt > flagAt && stampAt + 4 <= l.wheelStride && flagAt <= l.wheels;
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
        ", delay " + Hex(l.recoveryDelay) + ", timeout " + Hex(l.neutralTimeout) +
        ", vehicle " + Hex(l.vehicle) + ", position " + Hex(l.position) +
        ", physics clock " + Hex(l.physicsClock) + ", wheel stamp " + Hex(l.wheelChangedAt);
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

    snap.failure = "no player";
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
    snap.failure = "vehicle";
    uint64 vehicle = Dev::GetOffsetUint64(player, l.vehicle);
    if (vehicle < 0x10000 || Dev::SafeReadUint32(vehicle + l.wheelCount) != 4) return snap;
    snap.failure = "car model";
    uint64 model = Dev::SafeReadUint64(vehicle + l.model);
    if (model < 0x10000) return snap;
    snap.failure = "position";
    vec3 pos = Dev::SafeReadVec3(vehicle + l.position);
    if ((pos - vis.Position).Length() > 4.0f) return snap;

    float raw = Dev::SafeReadFloat(vehicle + l.rawSteer);
    float smooth = Dev::SafeReadFloat(vehicle + l.smoothedSteer);
    float force = Dev::SafeReadFloat(vehicle + l.force);
    uint8 mode = Dev::SafeReadUint8(vehicle + l.mode);
    uint delay = Dev::SafeReadUint32(model + l.recoveryDelay);
    int physicsClock = int(Dev::SafeReadUint32(vehicle + l.physicsClock));
    snap.failure = "steering, force or recovery delay";
    if (Math::Abs(raw - vis.InputSteer) > 0.25f ||
        smooth < -1.001f || smooth > 1.001f ||
        force < 0.95f || force > 2.1f || mode > 2 ||
        delay < 100 || delay > 1000) return snap;
    // The physics clock trails the frame clock by under one tick.
    snap.failure = "physics clock";
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
    snap.failure = "";
    snap.exact = true;
    return snap;
}

// How long reads must fail in the Stadium car during a run before the trainer
// says it cannot read the physics.
const int READ_FAILURE_WARN_MS = 3000;
// Contact changes in a row whose wheel timestamp never dated them before the
// trainer says the timestamps look wrong.
const int UNSTAMPED_CHANGES_WARN = 12;
// Ticks after the frame that shows a contact change by which the wheel's
// timestamp must date it.
const int STAMP_WAIT_TICKS = 2;

void WarnPhysics(const string &in message) {
    UI::ShowNotification("Gorilla Grip Trainer", message,
        vec4(0.72f, 0.36f, 0.07f, 1.0f), 12000);
}

// Watches for an update that the code checks in LocatePhysics missed: code
// that still matches but no longer names the field the trainer reads. That
// shows up only as reads that never pass the checks in ReadPhysics, or as
// wheel timestamps that never date a contact change.
class PhysicsReadMonitor {
    // An exact read since the plugin loaded. A game update needs a restart,
    // so once a read worked, later failures are loading or spectating.
    bool everExact = false;
    int failingSince = -1;
    string failure = "";
    bool readWarned = false;

    PhysicsSnapshot@ previous;
    // Per wheel: the physics clock before a contact change that its timestamp
    // has not dated yet, or -1, and the clock by which it must.
    array<int> changeAfter = array<int>(4, -1);
    array<int> stampDeadline = array<int>(4);
    int unstampedRun = 0;
    bool stampWarned = false;

    bool ReadFailing() const { return readWarned && !everExact; }

    // A frame in the Stadium car during a run.
    void Observe(PhysicsSnapshot@ snap) {
        if (!snap.exact) {
            ForgetStamps();
            if (everExact || readWarned) return;
            if (failingSince < 0 || snap.raceTime < failingSince)
                failingSince = snap.raceTime;
            failure = snap.failure;
            if (snap.raceTime - failingSince < READ_FAILURE_WARN_MS) return;
            readWarned = true;
            print("Gorilla Grip Trainer physics: no exact read in " +
                READ_FAILURE_WARN_MS + " ms of driving the Stadium car (failed check: " +
                failure + "); jumps are not rated");
            WarnPhysics("Can't read the car physics in this Trackmania build, so jumps aren't rated. The trainer needs an update.");
            return;
        }
        if (readWarned && !everExact)
            print("Gorilla Grip Trainer physics: exact reads working again");
        everExact = true;
        failingSince = -1;
        ObserveStamps(snap);
    }

    // Another car: its reads fail by design, so a failure spell ends.
    void Pause() {
        failingSince = -1;
        ForgetStamps();
    }

    void ForgetStamps() {
        @previous = null;
        for (uint i = 0; i < 4; i++) changeAfter[i] = -1;
    }

    // The physics step stamps a wheel when its contact changes, on that tick
    // or the next one, so the stamp lands after the frame before the change.
    // A moved offset reads a value unrelated to the clock.
    void ObserveStamps(PhysicsSnapshot@ snap) {
        if (previous is null || snap.physicsClock < previous.physicsClock) {
            ForgetStamps();
            @previous = snap;
            return;
        }
        for (uint i = 0; i < 4; i++) {
            int at = int(snap.wheelChangedAt[i]);
            bool changed = ((previous.contactMask ^ snap.contactMask) & (1 << i)) != 0;
            if (changed && changeAfter[i] < 0) {
                changeAfter[i] = previous.physicsClock;
                stampDeadline[i] = snap.physicsClock + STAMP_WAIT_TICKS * PHYSICS_TICK_MS;
            }
            if (changeAfter[i] < 0) continue;
            // A tick of slack either side: the stamp only has to name this change.
            if (at >= changeAfter[i] && at <= snap.physicsClock + PHYSICS_TICK_MS) {
                changeAfter[i] = -1;
                unstampedRun = 0;
            } else if (snap.physicsClock > stampDeadline[i]) {
                changeAfter[i] = -1;
                unstampedRun++;
            }
        }
        @previous = snap;
        if (stampWarned || unstampedRun < UNSTAMPED_CHANGES_WARN) return;
        stampWarned = true;
        print("Gorilla Grip Trainer physics: the last " + unstampedRun +
            " wheel contact changes had no matching wheel timestamp; landings are dated by frame");
        WarnPhysics("Wheel contact times look wrong in this Trackmania build, so landings are timed less exactly. The trainer needs an update.");
    }
}

PhysicsReadMonitor g_readMonitor;
