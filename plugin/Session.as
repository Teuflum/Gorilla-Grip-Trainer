class JumpVerdict {
    string label;
    string reason;
    int leadMinMs = -1;
    int leadMaxMs = -1;
    int takeoffTime = -1;
    int landingTime = -1;
    int spinCount = 0;
    int points = 0;
    bool exact = false;
}

int GradeBasePoints(const string &in label) {
    if (label == "S") return 150;
    if (label == "A") return 120;
    if (label == "B") return 90;
    if (label == "C") return 60;
    if (label == "D") return 30;
    return 0;
}

class SessionState {
    int combo = 0;
    int bestCombo = 0;
    int score = 0;
    int hits = 0;
    int misses = 0;

    void Reset() {
        combo = 0;
        bestCombo = 0;
        score = 0;
        hits = 0;
        misses = 0;
    }

    void Apply(JumpVerdict@ verdict) {
        if (verdict is null || !verdict.exact) return;
        if (verdict.label == "MISSED") {
            combo = 0;
            misses++;
            return;
        }
        int basePoints = GradeBasePoints(verdict.label);
        if (basePoints == 0) return;
        combo++;
        hits++;
        bestCombo = Math::Max(bestCombo, combo);
        verdict.points = basePoints * Math::Min(combo, 8) + 50 * verdict.spinCount;
        score += verdict.points;
    }
}

class LastRunSummary {
    bool hasRun = false;
    int score = 0;
    int hits = 0;
    int misses = 0;
    int bestCombo = 0;

    void Capture(SessionState@ session) {
        if (session is null || session.hits + session.misses == 0) return;
        hasRun = true;
        score = session.score;
        hits = session.hits;
        misses = session.misses;
        bestCombo = session.bestCombo;
    }
}
