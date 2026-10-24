[Setting category="Display" name="Enable widgets"]
bool S_EnableWidgets = true;
[Setting category="Display" name="Show widgets when game HUD is off"]
bool S_ShowWhenGameHudOff = false;
[Setting category="Display" name="Show finish summary automatically"]
bool S_AutoFinishSummary = true;

// Leads are whole 10 ms physics ticks, so the defaults sit on the tick grid.
[Setting category="Rating" name="S maximum lead (ms)" min=0 max=2000 description="How early the stored steering direction may switch before the last wheel leaves, for each grade. S+ is a 0 ms lead and has no limit of its own. Leads come in whole 10 ms physics ticks, so a limit of 15 grades like 10."]
int S_SMaxLeadMs = 10;
[Setting category="Rating" name="A maximum lead (ms)" min=0 max=2000]
int S_AMaxLeadMs = 30;
[Setting category="Rating" name="B maximum lead (ms)" min=0 max=2000]
int S_BMaxLeadMs = 60;
[Setting category="Rating" name="C maximum lead (ms)" min=0 max=2000]
int S_CMaxLeadMs = 110;
[Setting category="Rating" name="D maximum lead (ms)" min=0 max=2000]
int S_DMaxLeadMs = 250;
[Setting category="Rating" name="Minimum average tire icing" min=0 max=1 description="Checked as the last wheel leaves. Landings only need a fixed 0.34, because tires lose icing in the air."]
float S_MinIcing = 0.65f;
[Setting category="Rating" name="Minimum speed (km/h)" min=0 max=300]
int S_MinSpeed = 50;
[Setting category="Rating" name="Minimum flight (ms)" min=50 max=1000]
int S_MinFlight = 100;

// Each grade's limit is at least the one before it.
void NormalizeGradeThresholds() {
    S_SMaxLeadMs = Math::Clamp(S_SMaxLeadMs, 0, 2000);
    S_AMaxLeadMs = Math::Clamp(S_AMaxLeadMs, S_SMaxLeadMs, 2000);
    S_BMaxLeadMs = Math::Clamp(S_BMaxLeadMs, S_AMaxLeadMs, 2000);
    S_CMaxLeadMs = Math::Clamp(S_CMaxLeadMs, S_BMaxLeadMs, 2000);
    S_DMaxLeadMs = Math::Clamp(S_DMaxLeadMs, S_CMaxLeadMs, 2000);
}

#if SIG_DEVELOPER
[Setting category="Debug" name="Log trainer events" description="Writes routine trainer events (contact snapshots, previews, verdicts, audio, history saves) to Openplanet.log. Problems are always logged."]
bool S_DebugLogging = false;
[Setting category="Debug" name="Log every tire-force change" description="With trainer events on, also logs a snapshot whenever the tire-force multiplier or force gate changes. Slow the game to capture every physics tick."]
bool S_DebugForceTrace = false;
[Setting category="Debug" name="Process every Nth frame" min=1 max=10 description="Skips frames so the rating sees a lower frame rate, for timing tests."]
int S_DebugFrameSkip = 1;
#endif

int g_frameSkipCounter = 0;

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

int DebugFrameSkip() {
#if SIG_DEVELOPER
    return Math::Clamp(S_DebugFrameSkip, 1, 10);
#else
    return 1;
#endif
}

bool ProcessThisFrame() {
    int n = DebugFrameSkip();
    if (n <= 1) return true;
    g_frameSkipCounter = (g_frameSkipCounter + 1) % n;
    return g_frameSkipCounter == 0;
}

// Routine events only; problems go to warn() so they are always visible.
void DebugLog(const string &in message) {
    if (DebugLoggingOn()) print(message);
}
