[Setting hidden] // Legacy preference, copied to each widget once.
bool S_HideWithUI = true;
[Setting category="Display" name="Enable widgets"]
bool S_EnableWidgets = true;
[Setting category="Display" name="Show widgets when game HUD is off"]
bool S_ShowWhenGameHudOff = false;
[Setting hidden] bool S_GlobalHudVisibilityMigrated = false;
[Setting category="Display" name="Show finish summary automatically"]
bool S_AutoFinishSummary = true;
[Setting category="Debug" name="Log every tire-force change" description="Also writes a snapshot line to Openplanet.log whenever the tire-force multiplier or force gate changes, not only on wheel-contact changes. For research traces; slow the game to capture every physics tick."]
bool S_DebugForceTrace = false;

[Setting hidden]
float S_MinIcing = 0.65f;
[Setting hidden]
int S_MinSpeed = 50;
[Setting hidden]
int S_MinFlight = 100;
[Setting hidden] int S_SMaxLeadMs = 15;
[Setting hidden] int S_AMaxLeadMs = 35;
[Setting hidden] int S_BMaxLeadMs = 65;
[Setting hidden] int S_CMaxLeadMs = 110;
[Setting hidden] int S_DMaxLeadMs = 250;

void NormalizeGradeThresholds() {
    S_SMaxLeadMs = Math::Clamp(S_SMaxLeadMs, 0, 2000);
    S_AMaxLeadMs = Math::Clamp(S_AMaxLeadMs, S_SMaxLeadMs, 2000);
    S_BMaxLeadMs = Math::Clamp(S_BMaxLeadMs, S_AMaxLeadMs, 2000);
    S_CMaxLeadMs = Math::Clamp(S_CMaxLeadMs, S_BMaxLeadMs, 2000);
    S_DMaxLeadMs = Math::Clamp(S_DMaxLeadMs, S_CMaxLeadMs, 2000);
}

[SettingsTab name="Rating"]
void RenderSettingsRating() {
    if (UI::Button("Reset rating defaults")) {
        S_SMaxLeadMs = 15; S_AMaxLeadMs = 35; S_BMaxLeadMs = 65;
        S_CMaxLeadMs = 110; S_DMaxLeadMs = 250;
        S_MinIcing = 0.65f; S_MinSpeed = 50; S_MinFlight = 100;
    }
    UI::TextWrapped("How early the physics steering direction may switch before the last wheel leaves. Each value is the latest grade's upper limit in milliseconds.");
    UI::TextWrapped("S+ is awarded only for a confirmed 0-0 ms switch lead, with no separate threshold. It uses S points and sounds.");
    UI::TextWrapped("The + marker on A-D means takeoff happened between sampled frames that cross a grade limit. A+ still scores A; the true timing may qualify for a higher rank.");
    S_SMaxLeadMs = UI::InputInt("S maximum lead (ms)", S_SMaxLeadMs);
    S_AMaxLeadMs = UI::InputInt("A maximum lead (ms)", S_AMaxLeadMs);
    S_BMaxLeadMs = UI::InputInt("B maximum lead (ms)", S_BMaxLeadMs);
    S_CMaxLeadMs = UI::InputInt("C maximum lead (ms)", S_CMaxLeadMs);
    S_DMaxLeadMs = UI::InputInt("D maximum lead (ms)", S_DMaxLeadMs);
    NormalizeGradeThresholds();
    UI::SeparatorText("Eligible transitions");
    S_MinIcing = UI::SliderFloat("Minimum average tire icing", S_MinIcing, 0.0f, 1.0f, "%.2f");
    S_MinSpeed = UI::InputInt("Minimum speed (km/h)", S_MinSpeed);
    S_MinFlight = UI::InputInt("Minimum flight (ms)", S_MinFlight);
    S_MinSpeed = Math::Clamp(S_MinSpeed, 0, 300);
    S_MinFlight = Math::Clamp(S_MinFlight, 50, 1000);
}

[Setting hidden]
bool S_EnableAudio = true;
[Setting hidden] float S_MasterVolume = 1.0f;
[Setting hidden] bool S_SoundTakeoff = true;
[Setting hidden] bool S_SoundFailure = true;
[Setting hidden] bool S_SoundVoices = true;
[Setting hidden] bool S_SoundResults = true;
[Setting hidden] bool S_GradeSEnabled = true;
[Setting hidden] bool S_GradeAEnabled = true;
[Setting hidden] bool S_GradeBEnabled = true;
[Setting hidden] bool S_GradeCEnabled = true;
[Setting hidden] bool S_GradeDEnabled = true;
[Setting hidden] bool S_GradePoolsMigrated = false;
[Setting hidden] string S_GradeSList = "";
[Setting hidden] string S_GradeAList = "";
[Setting hidden] string S_GradeBList = "";
[Setting hidden] string S_GradeCList = "";
[Setting hidden] string S_GradeDList = "";
[Setting hidden] bool S_FixedPoolsMigrated = false;
[Setting hidden] string S_JumpList = "";
[Setting hidden] string S_FailureList = "";
[Setting hidden] string S_ResultsList = "";
[Setting hidden] string S_JumpFile = "SP2_SND_GROUP_00000006.wav";
[Setting hidden] float S_JumpVolume = 0.65f;
[Setting hidden] string S_FailureFile = "SP2_SND_GROUP_00000002.wav";
[Setting hidden] float S_FailureVolume = 0.70f;

// Legacy single-clip settings are retained only to migrate existing users.
[Setting hidden] string S_LandSFile = "Sample_0064.wav";
[Setting hidden] float S_LandSVolume = 0.82f;
[Setting hidden] string S_LandAFile = "Sample_0065.wav";
[Setting hidden] float S_LandAVolume = 0.82f;
[Setting hidden] string S_LandBFile = "Sample_0063.wav";
[Setting hidden] float S_LandBVolume = 0.82f;
[Setting hidden] string S_LandCFile = "Sample_0058.wav";
[Setting hidden] float S_LandCVolume = 0.82f;
[Setting hidden] string S_LandDFile = "Sample_0053.wav";
[Setting hidden] float S_LandDVolume = 0.82f;

[Setting hidden] string S_ResultsFile = "WSR_Wakeboarding_Results.mp3";
[Setting hidden] float S_ResultsVolume = 0.60f;

class SoundSlotChoice {
    string file;
    float volume;
    bool add = false;
    bool remove = false;
}

array<string> g_availableSoundFiles;
bool g_soundFilesScanned = false;

void RefreshSoundFiles() {
    g_availableSoundFiles.RemoveRange(0, g_availableSoundFiles.Length);
    g_soundFilesScanned = true;
    string folder = IO::FromStorageFolder("LocalSounds");
    if (!IO::FolderExists(folder)) return;
    array<string>@ files = IO::IndexFolder(folder, false);
    if (files is null) return;
    for (uint i = 0; i < files.Length; i++) {
        string name = Path::GetFileName(files[i]);
        string extension = Path::GetExtension(name).ToLower();
        if (extension != ".wav" && extension != ".ogg" &&
            extension != ".mp3" && extension != "wav" &&
            extension != "ogg" && extension != "mp3") continue;
        string fullPath = IO::FromStorageFolder("LocalSounds/" + name);
        if (IO::FileExists(fullPath)) g_availableSoundFiles.InsertLast(name);
    }
    g_availableSoundFiles.SortAsc();
}

// Openplanet's AngelScript rejects &inout for string and value types, so this
// helper takes copies and returns the (possibly edited) values instead.
SoundSlotChoice RenderSoundSlot(const string &in file, float volume) {
    SoundSlotChoice choice;
    float available = UI::GetContentRegionAvail().x;
    // Give the picker and gain control space instead of repeating the name.
    float row = Math::Max(240.0f, available - 155.0f);
    float field = row * 0.325f;
    float picker = row * 0.325f;
    float gain = row * 0.35f;
    UI::SetNextItemWidth(field);
    choice.file = UI::InputText("##file", file);
    UI::SameLine();
    UI::SetNextItemWidth(picker);
    if (UI::BeginCombo("##pick", "Browse files")) {
        if (g_availableSoundFiles.Length == 0) UI::Text("No local sounds found");
        for (uint i = 0; i < g_availableSoundFiles.Length; i++) {
            string name = g_availableSoundFiles[i];
            if (UI::Selectable(name, name == choice.file)) choice.file = name;
        }
        UI::EndCombo();
    }
    UI::SameLine();
    UI::SetNextItemWidth(gain);
    choice.volume = UI::SliderFloat("##volume", volume, 0.0f, 1.0f, "%.2f");
    UI::SameLine();
    if (UI::Button("Play") && g_audio !is null)
        g_audio.PreviewFile(choice.file, choice.volume);
    UI::SameLine();
    choice.add = UI::Button("+");
    UI::SameLine();
    choice.remove = UI::Button("-");
    return choice;
}

[SettingsTab name="Sounds"]
void RenderSettingsSounds() {
    InitVoicePools();
    if (!g_soundFilesScanned) RefreshSoundFiles();
    if (UI::Button("Open LocalSounds folder")) {
        string folder = IO::FromStorageFolder("LocalSounds");
        if (!IO::FolderExists(folder)) IO::CreateFolder(folder, true);
        OpenExplorerPath(folder);
    }
    UI::SameLine();
    if (UI::Button("Reload files")) {
        RefreshSoundFiles();
        if (g_audio !is null) g_audio.Load();
    }
    UI::SameLine();
    if (UI::Button("Stop preview") && g_audio !is null)
        g_audio.StopPreview();
    S_EnableAudio = UI::Checkbox("Enable all sounds", S_EnableAudio);
    UI::Text("Master volume");
    UI::SetNextItemWidth(-1.0f);
    S_MasterVolume = UI::SliderFloat("##master", S_MasterVolume,
        0.0f, 1.0f, "%.2f");
    if (g_audio !is null && g_audio.previewStatus.Length > 0)
        UI::Text(g_audio.previewStatus);
    if (UI::CollapsingHeader("Takeoff")) {
        UI::Indent(12.0f);
        S_SoundTakeoff = RenderVoicePool(VoicePoolFor("jump"),
            S_SoundTakeoff, false);
        UI::Unindent(12.0f);
    }
    if (UI::CollapsingHeader("Grades")) {
        UI::Indent(12.0f);
        S_SoundVoices = UI::Checkbox("Enable S-D sounds", S_SoundVoices);
        S_GradeSEnabled = RenderVoicePool(VoicePoolFor("S"), S_GradeSEnabled);
        S_GradeAEnabled = RenderVoicePool(VoicePoolFor("A"), S_GradeAEnabled);
        S_GradeBEnabled = RenderVoicePool(VoicePoolFor("B"), S_GradeBEnabled);
        S_GradeCEnabled = RenderVoicePool(VoicePoolFor("C"), S_GradeCEnabled);
        S_GradeDEnabled = RenderVoicePool(VoicePoolFor("D"), S_GradeDEnabled);
        S_SoundFailure = RenderVoicePool(VoicePoolFor("failure"),
            S_SoundFailure);
        UI::Unindent(12.0f);
    }
    if (UI::CollapsingHeader("Finish")) {
        UI::Indent(12.0f);
        S_SoundResults = RenderVoicePool(VoicePoolFor("results"),
            S_SoundResults, false);
        UI::Unindent(12.0f);
    }
    SaveVoicePools();
}

bool RenderVoicePool(VoicePool@ pool, bool enabled, bool collapsible = true) {
    if (pool is null) return enabled;
    UI::PushID(pool.grade);
    string title = pool.grade == "failure" ? "Missed" : pool.grade;
    if (collapsible && !UI::CollapsingHeader(title)) {
        UI::PopID();
        return enabled;
    }
    enabled = UI::Checkbox("Enable", enabled);
    if (pool.entries.Length == 0) pool.entries.InsertLast(VoiceEntry("", 0.82f));
    for (uint i = 0; i < pool.entries.Length;) {
        UI::PushID(int(i));
        SoundSlotChoice choice = RenderSoundSlot(
            pool.entries[i].file, pool.entries[i].volume);
        if (choice.file != pool.entries[i].file) {
            if (g_audio !is null)
                @pool.entries[i].sample = g_audio.LoadLocal(choice.file);
            else @pool.entries[i].sample = null;
        }
        pool.entries[i].file = choice.file;
        pool.entries[i].volume = choice.volume;
        UI::PopID();
        if (choice.add) pool.entries.InsertAt(i + 1, VoiceEntry("", 0.82f));
        if (choice.remove && pool.entries.Length > 1) pool.entries.RemoveAt(i);
        else if (choice.remove) {
            pool.entries[i].file = "";
            @pool.entries[i].sample = null;
            i++;
        }
        else i++;
    }
    UI::PopID();
    return enabled;
}
