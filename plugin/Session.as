class JumpVerdict {
    Grade grade = Grade::None;
    string reason;
    // Short HUD caption for an UNRATED verdict.
    string caption;
    int leadMs = -1;
    int takeoffTime = -1;
    int landingTime = -1;
    int points = 0;
    bool exact = false;
}

// Multiplier for the next successful landing; the HUD shows the streak itself.
int ScoringMultiplier(int completedStreak) {
    return Math::Min(completedStreak + 1, 8);
}

class SessionState {
    int combo = 0;
    int bestCombo = 0;
    int score = 0;
    int hits = 0;
    int misses = 0;

    void Apply(JumpVerdict@ verdict) {
        if (verdict is null || !verdict.exact) return;
        if (verdict.grade == Grade::Missed) {
            combo = 0;
            misses++;
            return;
        }
        int basePoints = GradePoints(verdict.grade);
        if (basePoints == 0) return;
        int multiplier = ScoringMultiplier(combo);
        combo++;
        hits++;
        bestCombo = Math::Max(bestCombo, combo);
        verdict.points = basePoints * multiplier;
        score += verdict.points;
    }
}
