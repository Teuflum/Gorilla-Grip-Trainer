// Local run history. No replay or user media is stored here.
const uint HISTORY_LIMIT = 500;

class HistoryJump {
    string preview;
    string label;
    string reason;
    int takeoffMs;
    int landingMs;
    int leadMinMs;
    int leadMaxMs;
    int spins;
    int combo;
    int points;
    int scoreAfter = -1;
    bool timingEstimated = false;

    HistoryJump() {}

    HistoryJump(JumpVerdict@ verdict, int currentCombo, int currentScore,
        JumpPreview@ timingPreview) {
        preview = timingPreview is null ? "" : timingPreview.label;
        label = verdict.label;
        reason = verdict.reason;
        takeoffMs = verdict.takeoffTime;
        landingMs = verdict.landingTime;
        leadMinMs = verdict.leadMinMs;
        leadMaxMs = verdict.leadMaxMs;
        spins = verdict.spinCount;
        combo = currentCombo;
        points = verdict.points;
        scoreAfter = currentScore;
        timingEstimated = verdict.timingEstimated;
    }

    Json::Value@ ToJson() {
        Json::Value@ value = Json::Object();
        value["preview"] = preview;
        value["label"] = label;
        value["reason"] = reason;
        value["takeoffMs"] = takeoffMs;
        value["landingMs"] = landingMs;
        value["leadMinMs"] = leadMinMs;
        value["leadMaxMs"] = leadMaxMs;
        value["spins"] = spins;
        value["combo"] = combo;
        value["points"] = points;
        if (scoreAfter >= 0) value["scoreAfter"] = scoreAfter;
        value["timingEstimated"] = timingEstimated;
        return value;
    }

    void FromJson(Json::Value@ value) {
        preview = string(value["preview"]);
        label = string(value["label"]);
        reason = string(value["reason"]);
        takeoffMs = int(value["takeoffMs"]);
        landingMs = int(value["landingMs"]);
        leadMinMs = int(value["leadMinMs"]);
        leadMaxMs = int(value["leadMaxMs"]);
        spins = int(value["spins"]);
        combo = int(value["combo"]);
        points = int(value["points"]);
        scoreAfter = value.HasKey("scoreAfter") ? int(value["scoreAfter"]) : -1;
        timingEstimated = value.HasKey("timingEstimated") ?
            bool(value["timingEstimated"]) : false;
    }
}

class RunRecord {
    string id;
    string mapUid;
    string mapName;
    int64 startedAt;
    string status = "RESET";
    int finishMs = -1;
    int score = 0;
    int bestCombo = 0;
    int hits = 0;
    int misses = 0;
    array<HistoryJump@> jumps;

    void Record(JumpVerdict@ verdict, SessionState@ session,
        JumpPreview@ timingPreview) {
        if (verdict is null || session is null ||
            (!verdict.exact && verdict.label != "UNRATED")) return;
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
        value["status"] = status;
        if (status == "FINISHED") value["finishMs"] = finishMs;
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
        status = string(value["status"]);
        finishMs = status == "FINISHED" ? int(value["finishMs"]) : -1;
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

bool HistoryField(Json::Value@ obj, const string &in key, Json::Type type) {
    return obj !is null && obj.GetType() == Json::Type::Object &&
        obj.HasKey(key) && obj[key].GetType() == type;
}

bool ValidHistory(Json::Value@ root) {
    if (!HistoryField(root, "version", Json::Type::Number) ||
        int(root["version"]) != 1 ||
        !HistoryField(root, "runs", Json::Type::Array)) return false;
    Json::Value@ records = root["runs"];
    for (uint i = 0; i < records.Length; i++) {
        Json::Value@ record = records[int(i)];
        if (!HistoryField(record, "id", Json::Type::String) ||
            !HistoryField(record, "mapUid", Json::Type::String) ||
            !HistoryField(record, "mapName", Json::Type::String) ||
            !HistoryField(record, "startedAt", Json::Type::Number) ||
            !HistoryField(record, "status", Json::Type::String) ||
            !HistoryField(record, "score", Json::Type::Number) ||
            !HistoryField(record, "bestCombo", Json::Type::Number) ||
            !HistoryField(record, "hits", Json::Type::Number) ||
            !HistoryField(record, "misses", Json::Type::Number) ||
            !HistoryField(record, "jumps", Json::Type::Array)) return false;
        string status = string(record["status"]);
        if (status != "FINISHED" && status != "RESET") return false;
        if (status == "FINISHED" &&
            !HistoryField(record, "finishMs", Json::Type::Number)) return false;
        if (status == "RESET" &&
            !HistoryField(record, "finishMs", Json::Type::Null)) return false;
        Json::Value@ jumps = record["jumps"];
        if (jumps.Length == 0 && status != "FINISHED") return false;
        int previousLanding = -1;
        for (uint j = 0; j < jumps.Length; j++) {
            Json::Value@ jump = jumps[int(j)];
            if (!HistoryField(jump, "preview", Json::Type::String) ||
                !HistoryField(jump, "label", Json::Type::String) ||
                !HistoryField(jump, "reason", Json::Type::String) ||
                !HistoryField(jump, "takeoffMs", Json::Type::Number) ||
                !HistoryField(jump, "landingMs", Json::Type::Number) ||
                !HistoryField(jump, "leadMinMs", Json::Type::Number) ||
                !HistoryField(jump, "leadMaxMs", Json::Type::Number) ||
                !HistoryField(jump, "spins", Json::Type::Number) ||
                !HistoryField(jump, "combo", Json::Type::Number) ||
                !HistoryField(jump, "points", Json::Type::Number)) return false;
            string label = string(jump["label"]);
            if (label != "S+" && label != "S" && label != "A" && label != "B" &&
                label != "C" && label != "D" && label != "MISSED" &&
                label != "UNRATED") return false;
            if (jump.HasKey("scoreAfter") &&
                !HistoryField(jump, "scoreAfter", Json::Type::Number)) return false;
            if (jump.HasKey("timingEstimated") &&
                !HistoryField(jump, "timingEstimated", Json::Type::Boolean))
                return false;
            int takeoff = int(jump["takeoffMs"]);
            int landing = int(jump["landingMs"]);
            if (takeoff > landing || landing < previousLanding) return false;
            previousLanding = landing;
        }
    }
    return true;
}

class HistoryStore {
    array<RunRecord@> runs;
    bool primaryValid = true;

    string Path() { return IO::FromStorageFolder("history.json"); }
    string BackupPath() { return IO::FromStorageFolder("history.backup.json"); }

    void ReadRuns(Json::Value@ root) {
        Json::Value@ records = root["runs"];
        uint first = records.Length > HISTORY_LIMIT ? records.Length - HISTORY_LIMIT : 0;
        for (uint i = first; i < records.Length; i++) {
            RunRecord@ run = RunRecord();
            run.FromJson(records[int(i)]);
            runs.InsertLast(run);
        }
    }

    void Load() {
        runs.RemoveRange(0, runs.Length);
        string path = Path();
        primaryValid = true;
        if (!IO::FileExists(path)) return;
        Json::Value@ root = Json::FromFile(path);
        if (ValidHistory(root)) {
            ReadRuns(root);
            return;
        }
        primaryValid = false;
        print("Gorilla Grip Trainer history: primary file invalid; preserving it");
        string backup = BackupPath();
        if (!IO::FileExists(backup)) return;
        @root = Json::FromFile(backup);
        if (ValidHistory(root)) {
            ReadRuns(root);
            print("Gorilla Grip Trainer history: recovered from backup");
        } else print("Gorilla Grip Trainer history: backup invalid too");
    }

    Json::Value@ ToJson() {
        Json::Value@ root = Json::Object();
        root["version"] = 1;
        Json::Value@ records = Json::Array();
        for (uint i = 0; i < runs.Length; i++) records.Add(runs[i].ToJson());
        root["runs"] = records;
        return root;
    }

    void Save() {
        string path = Path();
        if (IO::FileExists(path)) {
            if (primaryValid) {
                Json::Value@ old = Json::FromFile(path);
                if (ValidHistory(old)) Json::ToFile(BackupPath(), old, true);
                else primaryValid = false;
            }
            if (!primaryValid) {
                string corrupt = IO::FromStorageFolder("history.corrupt-" +
                    Text::Format("%lld", Time::MilliStamp) + ".json");
                IO::Copy(path, corrupt);
                print("Gorilla Grip Trainer history: preserved corrupt file at " + corrupt);
            }
        }
        Json::ToFile(path, ToJson(), true);
        primaryValid = true;
    }

    void Append(RunRecord@ run) {
        if (run is null || (run.jumps.Length == 0 && run.status != "FINISHED"))
            return;
        runs.InsertLast(run);
        while (runs.Length > HISTORY_LIMIT) runs.RemoveAt(0);
        Save();
        DebugLog("Gorilla Grip Trainer history: " + run.status + " " + run.id +
            " jumps " + run.jumps.Length);
    }

    void Clear() {
        runs.RemoveRange(0, runs.Length);
        string backup = BackupPath();
        if (IO::FileExists(backup)) IO::Delete(backup);
        Json::ToFile(Path(), ToJson(), true);
        primaryValid = true;
    }
}
