// Pictures beside the grade popup: shipped emoji art or the user's own PNG
// and JPG files in LocalImages. Each result stores one choice string:
// "emoji:<name>", "local:<file>", or "" for no picture. One emoji set decides
// which art every "emoji:" choice is drawn with.
[Setting hidden] bool S_ShowPictures = true;
[Setting hidden] string S_EmojiSet = "fluent-flat";
[Setting hidden] string S_PictureSPlus = "emoji:gorilla";
[Setting hidden] string S_PictureS = "emoji:gorilla";
[Setting hidden] string S_PictureA = "emoji:flexed-biceps";
[Setting hidden] string S_PictureB = "emoji:thumbs-up";
[Setting hidden] string S_PictureC = "emoji:ok-hand";
[Setting hidden] string S_PictureD = "emoji:slightly-smiling-face";
[Setting hidden] string S_PictureMissed = "emoji:skull";

array<string> g_pictureResults = {"S+", "S", "A", "B", "C", "D", "MISSED"};
array<string> g_emojiNames = {"gorilla", "oncoming-fist", "flexed-biceps",
    "fire", "thumbs-up", "ok-hand", "slightly-smiling-face", "skull", "ice",
    "snowflake", "trophy", "star"};
array<string> g_emojiLabels = {"Gorilla", "Oncoming fist", "Flexed biceps",
    "Fire", "Thumbs up", "OK hand", "Slightly smiling face", "Skull", "Ice",
    "Snowflake", "Trophy", "Star"};
array<string> g_emojiSets = {"fluent-flat", "fluent-color", "fluent-3d", "twemoji", "noto", "openmoji"};
array<string> g_emojiSetLabels = {"Fluent Flat", "Fluent Color", "Fluent 3D", "Twemoji", "Noto (Android)", "OpenMoji"};

// The shipped folder for the chosen set; an unknown name falls back to the default.
string EmojiSet() {
    for (uint i = 0; i < g_emojiSets.Length; i++)
        if (g_emojiSets[i] == S_EmojiSet) return S_EmojiSet;
    return "fluent-flat";
}

string EmojiSetLabel() {
    string set = EmojiSet();
    for (uint i = 0; i < g_emojiSets.Length; i++)
        if (g_emojiSets[i] == set) return g_emojiSetLabels[i];
    return g_emojiSetLabels[0];
}

string DefaultPicture(const string &in result) {
    if (result == "S+" || result == "S") return "emoji:gorilla";
    if (result == "A") return "emoji:flexed-biceps";
    if (result == "B") return "emoji:thumbs-up";
    if (result == "C") return "emoji:ok-hand";
    if (result == "D") return "emoji:slightly-smiling-face";
    if (result == "MISSED") return "emoji:skull";
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
    S_EmojiSet = "fluent-flat";
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

string PictureLabel(const string &in choice) {
    if (choice.StartsWith("emoji:")) {
        int i = EmojiIndex(choice.SubStr(6));
        if (i >= 0) return g_emojiLabels[i];
    }
    if (choice.StartsWith("local:") && IsSafeLocalName(choice.SubStr(6)))
        return choice.SubStr(6);
    return "None";
}

class PictureTexture {
    string key;
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
    bool isEmoji = choice.StartsWith("emoji:") && EmojiIndex(choice.SubStr(6)) >= 0;
    bool isLocal = choice.StartsWith("local:") && IsSafeLocalName(choice.SubStr(6));
    if (!isEmoji && !isLocal) return null;
    PictureTexture@ picture = PictureTexture();
    picture.choice = choice;
    // An unreadable file throws; catching it keeps the failed entry cached
    // instead of retrying on every frame.
    try {
        if (isEmoji) {
            string asset = "assets/emoji/" + EmojiSet() + "/" + choice.SubStr(6) + ".png";
            @picture.drawing = nvg::LoadTexture(asset, nvg::TextureFlags::GenerateMipmaps);
            @picture.thumbnail = UI::LoadTexture(asset);
        } else {
            string path = IO::FromStorageFolder("LocalImages/" + choice.SubStr(6));
            if (IO::FileExists(path)) {
                @picture.drawing = nvg::LoadTexture(ReadLocalImage(path), nvg::TextureFlags::GenerateMipmaps);
                @picture.thumbnail = UI::LoadTexture(ReadLocalImage(path));
            }
        }
    } catch {
        @picture.drawing = null;
        @picture.thumbnail = null;
    }
    if (!TextureUsable(picture.drawing)) @picture.drawing = null;
    if (!TextureUsable(picture.thumbnail)) @picture.thumbnail = null;
    if (picture.drawing is null)
        print("Gorilla Grip Trainer images: could not load " + PictureLabel(choice));
    return picture;
}

// Emoji pictures are cached per set, so switching sets loads the new art.
string PictureCacheKey(const string &in choice) {
    return choice.StartsWith("emoji:") ? choice + "@" + EmojiSet() : choice;
}

// Loads each choice once; a failed load stays cached so it is logged once.
PictureTexture@ GetPicture(const string &in choice) {
    if (choice.Length == 0) return null;
    string key = PictureCacheKey(choice);
    for (uint i = 0; i < g_pictureCache.Length; i++)
        if (g_pictureCache[i].key == key) return g_pictureCache[i];
    PictureTexture@ picture = LoadPicture(choice);
    if (picture is null) return null;
    picture.key = key;
    g_pictureCache.InsertLast(picture);
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
