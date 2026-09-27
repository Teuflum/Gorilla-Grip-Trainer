// Per-grade voice lists are persisted as hidden Openplanet settings. A row is
// <file name>|<gain>; file names cannot contain a path separator or '|'.
class VoiceEntry {
    string file;
    float volume;
    Audio::Sample@ sample;

    VoiceEntry(const string &in name, float gain) {
        file = name;
        volume = gain;
    }
}

class VoicePool {
    string grade;
    array<VoiceEntry@> entries;
    int lastPick = -1;

    VoicePool(const string &in rank) { grade = rank; }
}

array<VoicePool@> g_voicePools;

VoicePool@ VoicePoolFor(const string &in grade) {
    for (uint i = 0; i < g_voicePools.Length; i++)
        if (g_voicePools[i].grade == grade) return g_voicePools[i];
    return null;
}

void DecodeVoicePool(VoicePool@ pool, const string &in encoded) {
    if (pool is null || encoded.Length == 0) return;
    array<string> rows = encoded.Split("\n");
    for (uint i = 0; i < rows.Length; i++) {
        int split = rows[i].IndexOf("|");
        if (split < 0) continue;
        string name = rows[i].SubStr(0, split).Trim();
        string gainText = rows[i].SubStr(split + 1).Trim();
        if (name.Contains("|") || name.Contains("/") || name.Contains("\\") ||
            name.Contains(":") || name.Contains("..")) continue;
        pool.entries.InsertLast(VoiceEntry(name,
            Math::Clamp(Text::ParseFloat(gainText), 0.0f, 1.0f)));
    }
}

string EncodeVoicePool(VoicePool@ pool) {
    if (pool is null) return "";
    string result = "";
    for (uint i = 0; i < pool.entries.Length; i++) {
        if (i > 0) result += "\n";
        result += pool.entries[i].file + "|" +
            Text::Format("%.2f", pool.entries[i].volume);
    }
    return result;
}

// The shipped default lists. The plugin ships no audio; these names match
// the author's local clips, and any file with the same name is picked up.
string DefaultVoiceList(const string &in grade) {
    if (grade == "jump") return "SP2_SND_GROUP_00000006.wav|0.35";
    if (grade == "S") return "Sample_0064.wav|0.40\nSample_0061.wav|0.40";
    if (grade == "A") return "Sample_0065.wav|0.40";
    if (grade == "B") return "Sample_0063.wav|0.40";
    if (grade == "C") return "Sample_0058.wav|0.40";
    if (grade == "D") return "Sample_0053.wav|0.40";
    if (grade == "failure") return "SP2_SND_GROUP_00000002.wav|0.35";
    if (grade == "results") return "WSR_Wakeboarding_Results.mp3|0.25";
    return "";
}

// Keeps only the rows whose file is in LocalSounds.
string ExistingSoundsOnly(const string &in encoded) {
    array<string> rows = encoded.Split("\n");
    string kept = "";
    for (uint i = 0; i < rows.Length; i++) {
        int split = rows[i].IndexOf("|");
        if (split < 0) continue;
        string name = rows[i].SubStr(0, split);
        if (!IO::FileExists(IO::FromStorageFolder("LocalSounds/" + name))) continue;
        if (kept.Length > 0) kept += "\n";
        kept += rows[i];
    }
    return kept;
}

string DefaultSoundsFor(const string &in grade, bool onlyExisting) {
    return onlyExisting ? ExistingSoundsOnly(DefaultVoiceList(grade)) : DefaultVoiceList(grade);
}

void ApplyDefaultSounds(bool onlyExisting) {
    S_JumpList = DefaultSoundsFor("jump", onlyExisting);
    S_GradeSList = DefaultSoundsFor("S", onlyExisting);
    S_GradeAList = DefaultSoundsFor("A", onlyExisting);
    S_GradeBList = DefaultSoundsFor("B", onlyExisting);
    S_GradeCList = DefaultSoundsFor("C", onlyExisting);
    S_GradeDList = DefaultSoundsFor("D", onlyExisting);
    S_FailureList = DefaultSoundsFor("failure", onlyExisting);
    S_ResultsList = DefaultSoundsFor("results", onlyExisting);
}

void InitVoicePools() {
    if (g_voicePools.Length > 0) return;
    // A fresh install starts from the defaults it has files for, so missing
    // clips never show up as errors; Reset to default adds the rest.
    if (!S_GradePoolsMigrated) {
        ApplyDefaultSounds(true);
        S_GradePoolsMigrated = true;
    }
    BuildVoicePools();
}

void ReloadVoicePools() {
    g_voicePools.RemoveRange(0, g_voicePools.Length);
    BuildVoicePools();
}

void BuildVoicePools() {
    array<string> grades = {"jump", "S", "A", "B", "C", "D", "failure", "results"};
    array<string> encoded = {S_JumpList, S_GradeSList, S_GradeAList,
        S_GradeBList, S_GradeCList, S_GradeDList, S_FailureList, S_ResultsList};
    for (uint i = 0; i < grades.Length; i++) {
        VoicePool@ pool = VoicePool(grades[i]);
        DecodeVoicePool(pool, encoded[i]);
        g_voicePools.InsertLast(pool);
    }
}

void SaveVoicePools() {
    S_JumpList = EncodeVoicePool(VoicePoolFor("jump"));
    S_GradeSList = EncodeVoicePool(VoicePoolFor("S"));
    S_GradeAList = EncodeVoicePool(VoicePoolFor("A"));
    S_GradeBList = EncodeVoicePool(VoicePoolFor("B"));
    S_GradeCList = EncodeVoicePool(VoicePoolFor("C"));
    S_GradeDList = EncodeVoicePool(VoicePoolFor("D"));
    S_FailureList = EncodeVoicePool(VoicePoolFor("failure"));
    S_ResultsList = EncodeVoicePool(VoicePoolFor("results"));
}
