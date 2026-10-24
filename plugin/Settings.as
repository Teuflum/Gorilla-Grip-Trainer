[Setting hidden name="Enable widgets"]
bool S_EnableWidgets = true;
[Setting hidden name="Show widgets when game HUD is off"]
bool S_ShowWhenGameHudOff = false;
[Setting hidden name="Show finish summary automatically"]
bool S_AutoFinishSummary = true;

// Leads are whole 10 ms physics ticks, so the defaults sit on the tick grid.
[Setting hidden name="S maximum lead (ms)" min=0 max=2000 description="How early the stored steering direction may switch before the last wheel leaves, for each grade. S+ is a 0 ms lead and has no limit of its own. Leads come in whole 10 ms physics ticks, so a limit of 15 grades like 10."]
int S_SMaxLeadMs = 10;
[Setting hidden name="A maximum lead (ms)" min=0 max=2000]
int S_AMaxLeadMs = 30;
[Setting hidden name="B maximum lead (ms)" min=0 max=2000]
int S_BMaxLeadMs = 60;
[Setting hidden name="C maximum lead (ms)" min=0 max=2000]
int S_CMaxLeadMs = 110;
[Setting hidden name="D maximum lead (ms)" min=0 max=2000]
int S_DMaxLeadMs = 250;
[Setting hidden name="Minimum average tire icing" min=0 max=1 description="Checked as the last wheel leaves. Landings only need a fixed 0.34, because tires lose icing in the air."]
float S_MinIcing = 0.65f;
[Setting hidden name="Minimum speed (km/h)" min=0 max=300]
int S_MinSpeed = 50;
[Setting hidden name="Minimum flight (ms)" min=50 max=1000]
int S_MinFlight = 100;

// The tabs are script tabs with a fixed order; category tabs would come in
// whatever order Openplanet puts them. Each draws its hidden settings with
// Openplanet's own controls.
void RenderSettings(const array<string> &in names) {
    auto plugin = Meta::ExecutingPlugin();
    for (uint i = 0; i < names.Length; i++) plugin.GetSetting(names[i]).Render();
}

void ResetSettings(const array<string> &in names) {
    auto plugin = Meta::ExecutingPlugin();
    for (uint i = 0; i < names.Length; i++) plugin.GetSetting(names[i]).Reset();
}

array<string> g_displaySettings = {"S_EnableWidgets", "S_ShowWhenGameHudOff", "S_AutoFinishSummary"};
array<string> g_ratingSettings = {"S_SMaxLeadMs", "S_AMaxLeadMs", "S_BMaxLeadMs", "S_CMaxLeadMs",
    "S_DMaxLeadMs", "S_MinIcing", "S_MinSpeed", "S_MinFlight"};

[SettingsTab name="Display" icon="" order="1"]
void RenderSettingsDisplay() {
    if (UI::Button("Reset to default")) ResetSettings(g_displaySettings);
    RenderSettings(g_displaySettings);
}

[SettingsTab name="Rating" icon="" order="2"]
void RenderSettingsRating() {
    if (UI::Button("Reset to default")) ResetSettings(g_ratingSettings);
    RenderSettings(g_ratingSettings);
    NormalizeGradeThresholds();
}

// Each grade's limit is at least the one before it.
void NormalizeGradeThresholds() {
    S_SMaxLeadMs = Math::Clamp(S_SMaxLeadMs, 0, 2000);
    S_AMaxLeadMs = Math::Clamp(S_AMaxLeadMs, S_SMaxLeadMs, 2000);
    S_BMaxLeadMs = Math::Clamp(S_BMaxLeadMs, S_AMaxLeadMs, 2000);
    S_CMaxLeadMs = Math::Clamp(S_CMaxLeadMs, S_BMaxLeadMs, 2000);
    S_DMaxLeadMs = Math::Clamp(S_DMaxLeadMs, S_CMaxLeadMs, 2000);
}

#if SIG_DEVELOPER
[Setting hidden name="Log trainer events" description="Writes routine trainer events (contact snapshots, previews, verdicts, audio, history saves) to Openplanet.log. Problems are always logged."]
bool S_DebugLogging = false;
[Setting hidden name="Log every tire-force change" description="With trainer events on, also logs a snapshot whenever the tire-force multiplier or force gate changes. Slow the game to capture every physics tick."]
bool S_DebugForceTrace = false;
array<string> g_debugSettings = {"S_DebugLogging", "S_DebugForceTrace"};

[SettingsTab name="Debug" icon="" order="6"]
void RenderSettingsDebug() {
    if (UI::Button("Reset to default")) ResetSettings(g_debugSettings);
    RenderSettings(g_debugSettings);
}
#endif

bool DebugLoggingOn() {
#if SIG_DEVELOPER
    return S_DebugLogging;
#else
    return false;
#endif
}

bool DebugForceTraceOn() {
#if SIG_DEVELOPER
    return S_DebugLogging && S_DebugForceTrace;
#else
    return false;
#endif
}

// Routine events only; problems go to warn() so they are always visible.
void DebugLog(const string &in message) {
    if (DebugLoggingOn()) print(message);
}

// What the debug log last wrote, so it only logs changes.
class TraceLog {
    bool eventLoggingOn = false;
    int contactMask = -1;
    float force = -1.0f;
    int forceGate = -1;

    // Logged whenever the switch changes, so a log shows when tracing starts.
    void UpdateSwitches() {
        if (DebugLoggingOn() == eventLoggingOn) return;
        eventLoggingOn = DebugLoggingOn();
        print("Event logging " + (eventLoggingOn ? "on" : "off"));
    }

    void ForgetSnapshot() {
        contactMask = -1;
    }

    // One line per wheel-contact change, or per tire-force change with the force trace on.
    void Snapshot(PhysicsSnapshot@ next, int t) {
        if (!next.exact) return;
        if (contactMask != int(next.contactMask) || (DebugForceTraceOn() &&
            (force != next.force || forceGate != next.forceGateState))) {
            DebugLog("Snapshot at " + t + "ms: exact true, mode " +
                next.mode + ", steer " + Text::Format("%.6f", next.smoothedSteer) +
                ", contacts " + next.ContactBits() + ", modeAt " + next.modeAt +
                ", clock " + next.tick + ", delay " + next.recoveryDelayMs +
                ", force " + Text::Format("%.3f", next.force) +
                ", gate " + next.forceGateState +
                ", icing " + Text::Format("%.0f", next.icingFL * 100.0f) + "/" +
                Text::Format("%.0f", next.icingFR * 100.0f) + "/" +
                Text::Format("%.0f", next.icingRR * 100.0f) + "/" +
                Text::Format("%.0f", next.icingRL * 100.0f) +
                ", speed " + Text::Format("%.0f", next.speedKmh) +
                ", slip " + Text::Format("%.0f", next.slipDeg));
        }
        contactMask = int(next.contactMask);
        force = next.force;
        forceGate = next.forceGateState;
    }
}

TraceLog g_trace;
