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

void InitVoicePools() {
    if (g_voicePools.Length > 0) return;
    if (!S_GradePoolsMigrated) {
        S_GradeSList = S_LandSFile + "|" + Text::Format("%.2f", S_LandSVolume);
        S_GradeAList = S_LandAFile + "|" + Text::Format("%.2f", S_LandAVolume);
        S_GradeBList = S_LandBFile + "|" + Text::Format("%.2f", S_LandBVolume);
        S_GradeCList = S_LandCFile + "|" + Text::Format("%.2f", S_LandCVolume);
        S_GradeDList = S_LandDFile + "|" + Text::Format("%.2f", S_LandDVolume);
        S_GradePoolsMigrated = true;
    }
    array<string> grades = {"S", "A", "B", "C", "D"};
    array<string> encoded = {S_GradeSList, S_GradeAList, S_GradeBList,
        S_GradeCList, S_GradeDList};
    for (uint i = 0; i < grades.Length; i++) {
        VoicePool@ pool = VoicePool(grades[i]);
        DecodeVoicePool(pool, encoded[i]);
        g_voicePools.InsertLast(pool);
    }
}

void SaveVoicePools() {
    S_GradeSList = EncodeVoicePool(VoicePoolFor("S"));
    S_GradeAList = EncodeVoicePool(VoicePoolFor("A"));
    S_GradeBList = EncodeVoicePool(VoicePoolFor("B"));
    S_GradeCList = EncodeVoicePool(VoicePoolFor("C"));
    S_GradeDList = EncodeVoicePool(VoicePoolFor("D"));
}
