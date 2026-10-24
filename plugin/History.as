// Local run history. No replay or user media is stored here.
const uint HISTORY_LIMIT = 500;
const int HISTORY_VERSION = 2;

enum RunStatus {
    Reset,
    Finished
}

string StatusName(RunStatus status) {
    return status == RunStatus::Finished ? "FINISHED" : "RESET";
}

class HistoryJump {
    // Grade names as GradeName gives them.
    string preview;
    string label;
    string reason;
    int landingMs;
    int leadMs;
    int combo;
    int points;
    int scoreAfter = -1;

    HistoryJump() {}

    HistoryJump(JumpVerdict@ verdict, int currentCombo, int currentScore,
        JumpPreview@ timingPreview) {
        preview = timingPreview is null ? "" : GradeName(timingPreview.grade);
        label = GradeName(verdict.grade);
        reason = verdict.reason;
        landingMs = verdict.landingTime;
        leadMs = verdict.leadMs;
        combo = currentCombo;
        points = verdict.points;
        scoreAfter = currentScore;
    }

    Json::Value@ ToJson() {
        Json::Value@ value = Json::Object();
        value["preview"] = preview;
        value["label"] = label;
        value["reason"] = reason;
        value["landingMs"] = landingMs;
        value["leadMs"] = leadMs;
        value["combo"] = combo;
        value["points"] = points;
        if (scoreAfter >= 0) value["scoreAfter"] = scoreAfter;
        return value;
    }

    void FromJson(Json::Value@ value) {
        preview = string(value["preview"]);
        label = string(value["label"]);
        reason = string(value["reason"]);
        landingMs = int(value["landingMs"]);
        leadMs = int(value["leadMs"]);
        combo = int(value["combo"]);
        points = int(value["points"]);
        scoreAfter = value.HasKey("scoreAfter") ? int(value["scoreAfter"]) : -1;
    }
}

class RunRecord {
    string id;
    string mapUid;
    string mapName;
    int64 startedAt;
    RunStatus status = RunStatus::Reset;
    int finishMs = -1;
    int score = 0;
    int bestCombo = 0;
    int hits = 0;
    int misses = 0;
    array<HistoryJump@> jumps;

    void Record(JumpVerdict@ verdict, SessionState@ session,
        JumpPreview@ timingPreview) {
        jumps.InsertLast(HistoryJump(verdict, session.combo, session.score,
            timingPreview));
        score = session.score;
        bestCombo = session.bestCombo;
        hits = session.hits;
        misses = session.misses;
    }

    Json::Value@ ToJson() {
        Json::Value@ value = Json::Object();
        value["id"] = id;
        value["mapUid"] = mapUid;
        value["mapName"] = mapName;
        value["startedAt"] = startedAt;
        value["status"] = StatusName(status);
        if (status == RunStatus::Finished) value["finishMs"] = finishMs;
        else value["finishMs"] = Json::Value();
        value["score"] = score;
        value["bestCombo"] = bestCombo;
        value["hits"] = hits;
        value["misses"] = misses;
        Json::Value@ items = Json::Array();
        for (uint i = 0; i < jumps.Length; i++) items.Add(jumps[i].ToJson());
        value["jumps"] = items;
        return value;
    }

    void FromJson(Json::Value@ value) {
        id = string(value["id"]);
        mapUid = string(value["mapUid"]);
        mapName = string(value["mapName"]);
        startedAt = int64(double(value["startedAt"]));
        status = string(value["status"]) == "FINISHED" ? RunStatus::Finished : RunStatus::Reset;
        finishMs = status == RunStatus::Finished ? int(value["finishMs"]) : -1;
        score = int(value["score"]);
        bestCombo = int(value["bestCombo"]);
        hits = int(value["hits"]);
        misses = int(value["misses"]);
        Json::Value@ items = value["jumps"];
        for (uint i = 0; i < items.Length; i++) {
            HistoryJump@ jump = HistoryJump();
            jump.FromJson(items[int(i)]);
            jumps.InsertLast(jump);
        }
    }
}

class HistoryStore {
    array<RunRecord@> runs;
    // False while history.json holds something unreadable; it is not used as
    // a backup then.
    bool primaryReadable = true;

    string Path() { return IO::FromStorageFolder("history.json"); }
    string BackupPath() { return IO::FromStorageFolder("history.backup.json"); }

    // Missing fields or wrong types throw, so a damaged file reads as false.
    bool ReadFile(const string &in path) {
        array<RunRecord@> loaded;
        try {
            Json::Value@ root = Json::FromFile(path);
            if (int(root["version"]) != HISTORY_VERSION) return false;
            Json::Value@ records = root["runs"];
            uint first = records.Length > HISTORY_LIMIT ? records.Length - HISTORY_LIMIT : 0;
            for (uint i = first; i < records.Length; i++) {
                RunRecord@ run = RunRecord();
                run.FromJson(records[int(i)]);
                loaded.InsertLast(run);
            }
        } catch {
            return false;
        }
        runs = loaded;
        return true;
    }

    void Load() {
        string path = Path();
        primaryReadable = true;
        if (!IO::FileExists(path) || ReadFile(path)) return;
        primaryReadable = false;
        string kept = IO::FromStorageFolder("history.corrupt-" +
            Text::Format("%lld", Time::MilliStamp) + ".json");
        IO::Copy(path, kept);
        warn("Could not read the run history; kept a copy at " + kept);
        if (IO::FileExists(BackupPath()) && ReadFile(BackupPath()))
            print("Run history recovered from the backup");
    }

    Json::Value@ ToJson() {
        Json::Value@ root = Json::Object();
        root["version"] = HISTORY_VERSION;
        Json::Value@ records = Json::Array();
        for (uint i = 0; i < runs.Length; i++) records.Add(runs[i].ToJson());
        root["runs"] = records;
        return root;
    }

    void Save() {
        string path = Path();
        // The previous file becomes the backup, in case this write is cut short.
        if (primaryReadable && IO::FileExists(path)) {
            string backup = BackupPath();
            if (IO::FileExists(backup)) IO::Delete(backup);
            IO::Copy(path, backup);
        }
        Json::ToFile(path, ToJson(), true);
        primaryReadable = true;
    }

    void Append(RunRecord@ run) {
        if (run.jumps.Length == 0 && run.status != RunStatus::Finished) return;
        runs.InsertLast(run);
        while (runs.Length > HISTORY_LIMIT) runs.RemoveAt(0);
        Save();
        DebugLog("History: " + StatusName(run.status) + " " + run.id +
            " jumps " + run.jumps.Length);
    }

    void Clear() {
        runs.RemoveRange(0, runs.Length);
        string backup = BackupPath();
        if (IO::FileExists(backup)) IO::Delete(backup);
        Json::ToFile(Path(), ToJson(), true);
        primaryReadable = true;
    }
}
