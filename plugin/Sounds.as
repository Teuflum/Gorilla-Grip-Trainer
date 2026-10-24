// Sounds come from the user's own files: one folder per cue inside
// PluginStorage/GorillaGripTrainer/LocalSounds. Each play picks one file of
// the cue's folder at random.
[Setting hidden name="Enable sounds"]
bool S_EnableAudio = true;
[Setting hidden name="Master volume" min=0 max=1]
float S_MasterVolume = 0.5f;
[Setting hidden name="Takeoff"]
bool S_SoundTakeoff = true;
[Setting hidden name="Takeoff volume" min=0 max=1]
float S_VolumeTakeoff = 0.35f;
[Setting hidden name="S and S+"]
[SettingAlias key="S_GradeSEnabled"]
bool S_SoundS = true;
[Setting hidden name="S volume" min=0 max=1]
float S_VolumeS = 0.4f;
[Setting hidden name="A"]
[SettingAlias key="S_GradeAEnabled"]
bool S_SoundA = true;
[Setting hidden name="A volume" min=0 max=1]
float S_VolumeA = 0.4f;
[Setting hidden name="B"]
[SettingAlias key="S_GradeBEnabled"]
bool S_SoundB = true;
[Setting hidden name="B volume" min=0 max=1]
float S_VolumeB = 0.4f;
[Setting hidden name="C"]
[SettingAlias key="S_GradeCEnabled"]
bool S_SoundC = true;
[Setting hidden name="C volume" min=0 max=1]
float S_VolumeC = 0.4f;
[Setting hidden name="D"]
[SettingAlias key="S_GradeDEnabled"]
bool S_SoundD = true;
[Setting hidden name="D volume" min=0 max=1]
float S_VolumeD = 0.4f;
[Setting hidden name="Missed"]
[SettingAlias key="S_SoundFailure"]
bool S_SoundMissed = true;
[Setting hidden name="Missed volume" min=0 max=1]
float S_VolumeMissed = 0.35f;
[Setting hidden name="Finish music"]
[SettingAlias key="S_SoundResults"]
bool S_SoundFinish = true;
[Setting hidden name="Finish volume" min=0 max=1]
float S_VolumeFinish = 0.25f;

enum Cue {
    Takeoff,
    GradeS,
    GradeA,
    GradeB,
    GradeC,
    GradeD,
    Missed,
    Finish
}

array<string> g_cueFolders = {"takeoff", "S", "A", "B", "C", "D", "missed", "finish"};
// The cue's part of its S_Sound... and S_Volume... setting names.
array<string> g_cueSettings = {"Takeoff", "S", "A", "B", "C", "D", "Missed", "Finish"};

// Each cue's switch and volume setting, in Cue order.
array<Meta::PluginSetting@> g_cueSwitches;
array<Meta::PluginSetting@> g_cueVolumes;

void FindCueSettings() {
    auto plugin = Meta::ExecutingPlugin();
    for (uint i = 0; i < g_cueSettings.Length; i++) {
        g_cueSwitches.InsertLast(plugin.GetSetting("S_Sound" + g_cueSettings[i]));
        g_cueVolumes.InsertLast(plugin.GetSetting("S_Volume" + g_cueSettings[i]));
    }
}

bool CueEnabled(Cue cue) {
    return g_cueSwitches[uint(cue)].ReadBool();
}

float CueVolume(Cue cue) {
    return g_cueVolumes[uint(cue)].ReadFloat();
}

// The landing cue for a grade; S+ shares the S sounds. Unrated has none.
bool GradeCue(Grade grade, Cue &out cue) {
    switch (grade) {
        case Grade::SPlus:
        case Grade::S: cue = Cue::GradeS; return true;
        case Grade::A: cue = Cue::GradeA; return true;
        case Grade::B: cue = Cue::GradeB; return true;
        case Grade::C: cue = Cue::GradeC; return true;
        case Grade::D: cue = Cue::GradeD; return true;
        case Grade::Missed: cue = Cue::Missed; return true;
    }
    return false;
}

string SoundsRoot() {
    return IO::FromStorageFolder("LocalSounds");
}

string CueFolder(Cue cue) {
    return SoundsRoot() + "/" + g_cueFolders[uint(cue)];
}

array<string> g_soundExtensions = {".wav", ".ogg", ".mp3"};

class SoundCue {
    array<Audio::Sample@> samples;
    int lastPick = -1;

    void Load(const string &in folder) {
        array<string> names = FilesIn(folder, g_soundExtensions);
        for (uint i = 0; i < names.Length; i++) {
            Audio::Sample@ sample = Audio::LoadSampleFromAbsolutePath(folder + "/" + names[i], false);
            if (sample is null) {
                warn("Could not load sound " + folder + "/" + names[i]);
                continue;
            }
            samples.InsertLast(sample);
        }
    }

    // A random file, never the same one twice in a row when there is a choice.
    Audio::Sample@ Pick() {
        int count = int(samples.Length);
        if (count == 0) return null;
        int pick = Math::Rand(0, count);
        if (count > 1 && pick == lastPick)
            pick = (pick + 1 + Math::Rand(0, count - 1)) % count;
        lastPick = pick;
        return samples[uint(pick)];
    }
}

array<SoundCue@> g_soundCues;

void LoadSoundCues() {
    g_soundCues.RemoveRange(0, g_soundCues.Length);
    for (uint i = 0; i < g_cueFolders.Length; i++) {
        SoundCue@ cue = SoundCue();
        cue.Load(CueFolder(Cue(int(i))));
        g_soundCues.InsertLast(cue);
    }
}

[SettingsTab name="Sounds" icon="" order="3"]
void RenderSettingsSounds() {
    array<string> general = {"S_EnableAudio", "S_MasterVolume"};
    if (UI::Button("Reset to default")) {
        ResetSettings(general);
        for (uint i = 0; i < g_cueSwitches.Length; i++) {
            g_cueSwitches[i].Reset();
            g_cueVolumes[i].Reset();
        }
    }
    RenderSoundFolders();
    RenderSettings(general);
    UI::Separator();
    // A cue's volume shows only while the cue is on.
    for (uint i = 0; i < g_cueSwitches.Length; i++) {
        g_cueSwitches[i].Render();
        if (g_cueSwitches[i].ReadBool()) g_cueVolumes[i].Render();
    }
}

void RenderSoundFolders() {
    UI::TextWrapped("Put WAV, OGG or MP3 files into the folders inside LocalSounds, one folder per cue, then click Reload files.");
    if (UI::Button("Open LocalSounds folder")) {
        for (uint i = 0; i < g_cueFolders.Length; i++) {
            string folder = CueFolder(Cue(int(i)));
            if (!IO::FolderExists(folder)) IO::CreateFolder(folder, true);
        }
        OpenExplorerPath(SoundsRoot());
    }
    UI::SameLine();
    if (UI::Button("Reload files")) g_audio.Load();
    UI::SameLine();
    if (UI::Button("Stop preview")) g_audio.StopPreview();
    if (UI::BeginTable("cues", 3, UI::TableFlags::SizingStretchProp)) {
        for (uint i = 0; i < g_soundCues.Length; i++) {
            UI::PushID(int(i));
            UI::TableNextRow();
            UI::TableNextColumn();
            UI::Text(g_cueSwitches[i].Name);
            UI::TableNextColumn();
            uint count = g_soundCues[i].samples.Length;
            UI::TextDisabled(g_cueFolders[i] + "/  " + count + (count == 1 ? " file" : " files"));
            UI::TableNextColumn();
            if (UI::Button("Play")) g_audio.PreviewCue(Cue(int(i)));
            UI::PopID();
        }
        UI::EndTable();
    }
    if (g_audio.previewStatus.Length > 0) UI::Text(g_audio.previewStatus);
    UI::Separator();
}
