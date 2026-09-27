// Pictures beside the grade popup: shipped emoji art or the user's own PNG
// and JPG files in LocalImages. Each result stores one choice string:
// "emoji:<set>/<name>", "local:<file>", or "" for no picture, so every result
// can mix its own emoji set.
[Setting hidden] bool S_ShowPictures = true;
[Setting hidden] string S_PictureSPlus = "emoji:noto/gorilla";
[Setting hidden] string S_PictureS = "emoji:noto/gorilla";
[Setting hidden] string S_PictureA = "emoji:twemoji/flexed-biceps";
[Setting hidden] string S_PictureB = "emoji:twemoji/thumbs-up";
[Setting hidden] string S_PictureC = "emoji:twemoji/ok-hand";
[Setting hidden] string S_PictureD = "emoji:twemoji/slightly-smiling-face";
[Setting hidden] string S_PictureMissed = "emoji:twemoji/skull";

array<string> g_pictureResults = {"S+", "S", "A", "B", "C", "D", "MISSED"};
array<string> g_emojiNames = {"gorilla", "oncoming-fist", "flexed-biceps",
    "fire", "thumbs-up", "ok-hand", "slightly-smiling-face", "skull",
    "loudly-crying-face", "ice", "snowflake", "trophy", "star"};
array<string> g_emojiLabels = {"Gorilla", "Oncoming fist", "Flexed biceps",
    "Fire", "Thumbs up", "OK hand", "Slightly smiling face", "Skull",
    "Loudly crying face", "Ice", "Snowflake", "Trophy", "Star"};
array<string> g_emojiSets = {"fluent-flat", "fluent-3d", "twemoji", "noto", "openmoji"};
array<string> g_emojiSetLabels = {"Fluent Flat", "Fluent 3D", "Twemoji", "Noto (Android)", "OpenMoji"};

string DefaultPicture(const string &in result) {
    if (result == "S+" || result == "S") return "emoji:noto/gorilla";
    if (result == "A") return "emoji:twemoji/flexed-biceps";
    if (result == "B") return "emoji:twemoji/thumbs-up";
    if (result == "C") return "emoji:twemoji/ok-hand";
    if (result == "D") return "emoji:twemoji/slightly-smiling-face";
    if (result == "MISSED") return "emoji:twemoji/skull";
    return "";
}

string PictureSetting(const string &in result) {
    if (result == "S+") return S_PictureSPlus;
    if (result == "S") return S_PictureS;
    if (result == "A") return S_PictureA;
    if (result == "B") return S_PictureB;
    if (result == "C") return S_PictureC;
    if (result == "D") return S_PictureD;
    if (result == "MISSED") return S_PictureMissed;
    return "";
}

void SetPictureSetting(const string &in result, const string &in choice) {
    if (result == "S+") S_PictureSPlus = choice;
    else if (result == "S") S_PictureS = choice;
    else if (result == "A") S_PictureA = choice;
    else if (result == "B") S_PictureB = choice;
    else if (result == "C") S_PictureC = choice;
    else if (result == "D") S_PictureD = choice;
    else if (result == "MISSED") S_PictureMissed = choice;
}

void ResetPictureSettings() {
    S_ShowPictures = true;
    for (uint i = 0; i < g_pictureResults.Length; i++)
        SetPictureSetting(g_pictureResults[i], DefaultPicture(g_pictureResults[i]));
}

int EmojiIndex(const string &in name) {
    for (uint i = 0; i < g_emojiNames.Length; i++)
        if (g_emojiNames[i] == name) return int(i);
    return -1;
}

// A local choice names one file directly inside LocalImages.
bool IsSafeLocalName(const string &in name) {
    return name.Length > 0 && !name.Contains("/") && !name.Contains("\\") &&
        !name.Contains("..");
}

int EmojiSetIndex(const string &in emojiSet) {
    for (uint i = 0; i < g_emojiSets.Length; i++)
        if (g_emojiSets[i] == emojiSet) return int(i);
    return -1;
}

// "emoji:<set>/<name>" -> {set, name}. The older "emoji:<name>" reads as
// Twemoji, the first shipped set. Anything else, or an unknown set or
// picture, gives null.
array<string>@ EmojiChoiceParts(const string &in choice) {
    if (!choice.StartsWith("emoji:")) return null;
    string rest = choice.SubStr(6);
    int slash = rest.IndexOf("/");
    string emojiSet = slash < 0 ? "twemoji" : rest.SubStr(0, slash);
    string emojiName = slash < 0 ? rest : rest.SubStr(slash + 1);
    // Fluent Color was dropped as too close to Fluent 3D.
    if (emojiSet == "fluent-color") emojiSet = "fluent-3d";
    if (EmojiSetIndex(emojiSet) < 0 || EmojiIndex(emojiName) < 0) return null;
    array<string>@ parts = array<string>();
    parts.InsertLast(emojiSet);
    parts.InsertLast(emojiName);
    return parts;
}

// "" for none, "local" for a LocalImages file, otherwise the emoji set.
string PictureSource(const string &in choice) {
    if (choice.StartsWith("local:")) return "local";
    array<string>@ parts = EmojiChoiceParts(choice);
    if (parts !is null) return parts[0];
    return "";
}

string PictureSourceLabel(const string &in source) {
    if (source == "local") return "Local file";
    int i = EmojiSetIndex(source);
    return i >= 0 ? g_emojiSetLabels[i] : "None";
}

// The picture's own name; the source picker shows the set.
string PictureLabel(const string &in choice) {
    array<string>@ parts = EmojiChoiceParts(choice);
    if (parts !is null) return g_emojiLabels[EmojiIndex(parts[1])];
    if (choice.StartsWith("local:"))
        return IsSafeLocalName(choice.SubStr(6)) ? choice.SubStr(6) : "Choose a file";
    return "None";
}

class PictureTexture {
    string choice;
    nvg::Texture@ drawing;
    UI::Texture@ thumbnail;
}

array<PictureTexture@> g_pictureCache;
array<string> g_localImages;
bool g_localImagesScanned = false;

MemoryBuffer@ ReadLocalImage(const string &in path) {
    IO::File file(path, IO::FileMode::Read);
    MemoryBuffer@ buffer = file.Read(file.Size());
    file.Close();
    return buffer;
}

// Openplanet returns a 0x0 texture for data it cannot decode.
bool TextureUsable(nvg::Texture@ texture) {
    return texture !is null && texture.GetSize().x > 0 && texture.GetSize().y > 0;
}

bool TextureUsable(UI::Texture@ texture) {
    return texture !is null && texture.GetSize().x > 0 && texture.GetSize().y > 0;
}

PictureTexture@ LoadPicture(const string &in choice) {
    array<string>@ parts = EmojiChoiceParts(choice);
    bool isEmoji = parts !is null;
    bool isLocal = choice.StartsWith("local:") && IsSafeLocalName(choice.SubStr(6));
    if (!isEmoji && !isLocal) return null;
    PictureTexture@ picture = PictureTexture();
    picture.choice = choice;
    // An unreadable file throws; catching it keeps the failed entry cached
    // instead of retrying on every frame.
    try {
        if (isEmoji) {
            string asset = "assets/emoji/" + parts[0] + "/" + parts[1] + ".png";
            @picture.drawing = nvg::LoadTexture(asset, nvg::TextureFlags::GenerateMipmaps);
            @picture.thumbnail = UI::LoadTexture(asset);
        } else {
            string path = IO::FromStorageFolder("LocalImages/" + choice.SubStr(6));
            if (IO::FileExists(path)) {
                MemoryBuffer@ buffer = ReadLocalImage(path);
                @picture.drawing = nvg::LoadTexture(buffer, nvg::TextureFlags::GenerateMipmaps);
                buffer.Seek(0);
                @picture.thumbnail = UI::LoadTexture(buffer);
            }
        }
    } catch {
        @picture.drawing = null;
        @picture.thumbnail = null;
    }
    if (!TextureUsable(picture.drawing)) @picture.drawing = null;
    if (!TextureUsable(picture.thumbnail)) @picture.thumbnail = null;
    if (picture.drawing is null)
        print("Gorilla Grip Trainer images: could not load " + choice);
    return picture;
}

// Loads each choice once; a failed load stays cached so it is logged once.
PictureTexture@ GetPicture(const string &in choice) {
    if (choice.Length == 0) return null;
    for (uint i = 0; i < g_pictureCache.Length; i++)
        if (g_pictureCache[i].choice == choice) return g_pictureCache[i];
    PictureTexture@ picture = LoadPicture(choice);
    if (picture !is null) g_pictureCache.InsertLast(picture);
    return picture;
}

void ClearPictureCache() {
    g_pictureCache.RemoveRange(0, g_pictureCache.Length);
}

nvg::Texture@ PictureForResult(const string &in result) {
    if (!S_ShowPictures) return null;
    PictureTexture@ picture = GetPicture(PictureSetting(result));
    if (picture is null) return null;
    return picture.drawing;
}

void RefreshLocalImages() {
    g_localImages.RemoveRange(0, g_localImages.Length);
    g_localImagesScanned = true;
    string folder = IO::FromStorageFolder("LocalImages");
    if (!IO::FolderExists(folder)) return;
    array<string>@ files = IO::IndexFolder(folder, false);
    if (files is null) return;
    for (uint i = 0; i < files.Length; i++) {
        string name = Path::GetFileName(files[i]);
        // Path::GetExtension may or may not include the dot, as in
        // RefreshSoundFiles, so accept both forms.
        string extension = Path::GetExtension(name).ToLower();
        if (extension != ".png" && extension != ".jpg" && extension != ".jpeg" &&
            extension != "png" && extension != "jpg" && extension != "jpeg") continue;
        if (IsSafeLocalName(name)) g_localImages.InsertLast(name);
    }
    g_localImages.SortAsc();
}

// Scan LocalImages and load the chosen pictures so the first popup does not
// stall on a texture load.
void InitPictures() {
    RefreshLocalImages();
    for (uint i = 0; i < g_pictureResults.Length; i++)
        PictureForResult(g_pictureResults[i]);
}
