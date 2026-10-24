// Results of a jump, best first. history.json stores them by name.
enum Grade {
    SPlus,
    S,
    A,
    B,
    C,
    D,
    Missed,
    Unrated,
    None
}

array<string> g_gradeNames = {"S+", "S", "A", "B", "C", "D", "MISSED", "UNRATED"};
array<int> g_gradePoints = {180, 150, 120, 90, 60, 30, 0, 0};
array<string> g_gradeCaptions = {"PERFECT GORILLA GRIP", "GORILLA GRIP", "CLEAN TIMING",
    "SOLID TIMING", "GOOD SETUP", "EARLY SETUP", "GRIP MISSED", "TIMING NOT EXACT"};
// How big the landing popup's effects get.
array<float> g_gradePower = {1.0f, 0.8f, 0.55f, 0.4f, 0.3f, 0.2f, 0.5f, 0.0f};
array<vec4> g_gradeColors = {
    vec4(1.0f, 0.94f, 0.55f, 1.0f),
    vec4(1.0f, 0.84f, 0.28f, 1.0f),
    vec4(0.04f, 0.98f, 0.78f, 1.0f),
    vec4(0.38f, 0.78f, 1.0f, 1.0f),
    vec4(0.63f, 0.66f, 1.0f, 1.0f),
    vec4(1.0f, 0.55f, 0.22f, 1.0f),
    vec4(1.0f, 0.34f, 0.53f, 1.0f),
    vec4(0.67f, 0.78f, 0.90f, 1.0f)
};

string GradeName(Grade grade) {
    return grade == Grade::None ? "" : g_gradeNames[uint(grade)];
}

Grade GradeFromName(const string &in name) {
    int i = g_gradeNames.Find(name);
    return i < 0 ? Grade::None : Grade(i);
}

bool IsRated(Grade grade) {
    return grade <= Grade::D;
}

int GradePoints(Grade grade) {
    return grade == Grade::None ? 0 : g_gradePoints[uint(grade)];
}

float GradePower(Grade grade) {
    return grade == Grade::None ? 0.0f : g_gradePower[uint(grade)];
}

string GradeCaption(Grade grade) {
    return grade == Grade::None ? "" : g_gradeCaptions[uint(grade)];
}

vec4 GradeColor(Grade grade, float alpha = 1.0f) {
    vec4 color = grade == Grade::None ? g_gradeColors[uint(Grade::Missed)] :
        g_gradeColors[uint(grade)];
    color.w = alpha;
    return color;
}
