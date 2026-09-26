[Setting category="Display" name="Hide widgets with game UI"]
bool S_HideWithUI = true;
[Setting category="Display" name="Show finish summary automatically"]
bool S_AutoFinishSummary = true;

[Setting category="Rating" name="Minimum average tire icing" min=0 max=1]
float S_MinIcing = 0.65f;
[Setting category="Rating" name="Minimum speed (km/h)" min=0 max=300]
int S_MinSpeed = 50;
[Setting category="Rating" name="Minimum flight (ms)" min=50 max=1000]
int S_MinFlight = 100;

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
    bool enabled;
    string file;
    float volume;
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
SoundSlotChoice RenderSoundSlot(const string &in label,
    const string &in file, float volume, bool removable = false) {
    UI::PushID(label);
    SoundSlotChoice choice;
    UI::Text(label);
    UI::SameLine();
    float available = UI::GetContentRegionAvail().x;
    UI::SetNextItemWidth(Math::Max(100.0f, available - 253.0f));
    choice.file = UI::InputText("##file", file);
    UI::SameLine();
    UI::SetNextItemWidth(56.0f);
    if (UI::BeginCombo("##pick", "Pick")) {
        if (g_availableSoundFiles.Length == 0) UI::Text("No local clips found");
        for (uint i = 0; i < g_availableSoundFiles.Length; i++) {
            string name = g_availableSoundFiles[i];
            if (UI::Selectable(name, name == choice.file)) choice.file = name;
        }
        UI::EndCombo();
    }
    UI::SameLine();
    UI::SetNextItemWidth(85.0f);
    choice.volume = UI::SliderFloat("##volume", volume, 0.0f, 1.0f, "%.2f");
    UI::SameLine();
    if (UI::Button("Play") && g_audio !is null)
        g_audio.PreviewFile(choice.file, choice.volume);
    if (removable) {
        UI::SameLine();
        choice.remove = UI::Button("X");
    }
    UI::PopID();
    return choice;
}

SoundSlotChoice RenderCue(const string &in label, bool enabled,
    const string &in file, float volume) {
    UI::PushID(label);
    bool nextEnabled = UI::Checkbox("Enabled", enabled);
    SoundSlotChoice choice = RenderSoundSlot("Clip", file, volume);
    choice.enabled = nextEnabled;
    UI::PopID();
    return choice;
}

[SettingsTab name="Sounds"]
void RenderSettingsSounds() {
    InitVoicePools();
    if (!g_soundFilesScanned) RefreshSoundFiles();
    S_EnableAudio = UI::Checkbox("Enable all sounds", S_EnableAudio);
    S_MasterVolume = UI::SliderFloat("Master volume", S_MasterVolume,
        0.0f, 1.0f, "%.2f");
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
    if (g_audio !is null && g_audio.previewStatus.Length > 0)
        UI::Text(g_audio.previewStatus);
    SoundSlotChoice slot;
    if (UI::CollapsingHeader("Jump chime")) {
        slot = RenderCue("jump", S_SoundTakeoff, S_JumpFile, S_JumpVolume);
        S_SoundTakeoff = slot.enabled; S_JumpFile = slot.file;
        S_JumpVolume = slot.volume;
    }
    if (UI::CollapsingHeader("Failed landing")) {
        slot = RenderCue("failure", S_SoundFailure, S_FailureFile,
            S_FailureVolume);
        S_SoundFailure = slot.enabled; S_FailureFile = slot.file;
        S_FailureVolume = slot.volume;
    }
    S_SoundVoices = UI::Checkbox("Enable grade voices", S_SoundVoices);
    S_GradeSEnabled = RenderVoicePool(VoicePoolFor("S"), S_GradeSEnabled);
    S_GradeAEnabled = RenderVoicePool(VoicePoolFor("A"), S_GradeAEnabled);
    S_GradeBEnabled = RenderVoicePool(VoicePoolFor("B"), S_GradeBEnabled);
    S_GradeCEnabled = RenderVoicePool(VoicePoolFor("C"), S_GradeCEnabled);
    S_GradeDEnabled = RenderVoicePool(VoicePoolFor("D"), S_GradeDEnabled);
    SaveVoicePools();
    if (UI::CollapsingHeader("Finish music")) {
        slot = RenderCue("finish", S_SoundResults, S_ResultsFile,
            S_ResultsVolume);
        S_SoundResults = slot.enabled; S_ResultsFile = slot.file;
        S_ResultsVolume = slot.volume;
    }
}

bool RenderVoicePool(VoicePool@ pool, bool enabled) {
    if (pool is null) return enabled;
    UI::PushID(pool.grade);
    if (!UI::CollapsingHeader(pool.grade + " rank voices")) {
        UI::PopID();
        return enabled;
    }
    enabled = UI::Checkbox("Enable voices", enabled);
    for (uint i = 0; i < pool.entries.Length;) {
        UI::PushID("clip " + i);
        SoundSlotChoice choice = RenderSoundSlot("Clip " + (i + 1),
            pool.entries[i].file, pool.entries[i].volume, true);
        if (choice.file != pool.entries[i].file)
            @pool.entries[i].sample = null;
        pool.entries[i].file = choice.file;
        pool.entries[i].volume = choice.volume;
        UI::PopID();
        if (choice.remove) pool.entries.RemoveAt(i);
        else i++;
    }
    if (UI::Button("Add clip"))
        pool.entries.InsertLast(VoiceEntry("", 0.82f));
    UI::PopID();
    return enabled;
}
