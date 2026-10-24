// Pictures beside the grade popup: shipped emoji art or the user's own PNG
// and JPG files in LocalImages. Each result stores one choice string:
// "emoji:<name>", "local:<file>", or "" for no picture.
[Setting hidden] bool S_ShowPictures = true;
[Setting hidden] string S_PictureSPlus = "emoji:gorilla";
[Setting hidden] string S_PictureS = "emoji:gorilla";
[Setting hidden] string S_PictureA = "emoji:flexed-biceps";
[Setting hidden] string S_PictureB = "emoji:thumbs-up";
[Setting hidden] string S_PictureC = "emoji:ok-hand";
[Setting hidden] string S_PictureD = "emoji:slightly-smiling-face";
[Setting hidden] string S_PictureMissed = "emoji:skull";

array<string> g_emojiNames = {"gorilla", "oncoming-fist", "flexed-biceps",
    "fire", "thumbs-up", "ok-hand", "slightly-smiling-face", "skull",
    "loudly-crying-face", "ice", "snowflake", "trophy", "star"};
array<string> g_emojiLabels = {"Gorilla", "Oncoming fist", "Flexed biceps",
    "Fire", "Thumbs up", "OK hand", "Slightly smiling face", "Skull",
    "Loudly crying face", "Ice", "Snowflake", "Trophy", "Star"};

bool HasPicture(Grade grade) {
    return grade <= Grade::Missed;
}

// The picture setting of each grade from S+ to MISSED, in Grade order.
array<string> g_pictureSettingNames = {"S_PictureSPlus", "S_PictureS", "S_PictureA",
    "S_PictureB", "S_PictureC", "S_PictureD", "S_PictureMissed"};
array<Meta::PluginSetting@> g_pictureSettings;

Meta::PluginSetting@ PictureSettingOf(Grade grade) {
    if (g_pictureSettings.Length == 0) {
        auto plugin = Meta::ExecutingPlugin();
        for (uint i = 0; i < g_pictureSettingNames.Length; i++)
            g_pictureSettings.InsertLast(plugin.GetSetting(g_pictureSettingNames[i]));
    }
    return g_pictureSettings[uint(grade)];
}

string PictureSetting(Grade grade) {
    return HasPicture(grade) ? PictureSettingOf(grade).ReadString() : "";
}

void SetPictureSetting(Grade grade, const string &in choice) {
    if (HasPicture(grade)) PictureSettingOf(grade).WriteString(choice);
}

void ResetPictureSettings() {
    Meta::ExecutingPlugin().GetSetting("S_ShowPictures").Reset();
    for (int g = int(Grade::SPlus); g <= int(Grade::Missed); g++)
        PictureSettingOf(Grade(g)).Reset();
}

// One file directly inside LocalImages.
bool IsSafeLocalName(const string &in name) {
    return name.Length > 0 && !name.Contains("/") && !name.Contains("\\") &&
        !name.Contains("..") && !name.Contains(":");
}

// The emoji's file name, or "" if the choice is not a known emoji.
string EmojiName(const string &in choice) {
    if (!choice.StartsWith("emoji:")) return "";
    string name = choice.SubStr(6);
    return g_emojiNames.Find(name) >= 0 ? name : "";
}

string LocalName(const string &in choice) {
    if (!choice.StartsWith("local:")) return "";
    string name = choice.SubStr(6);
    return IsSafeLocalName(name) ? name : "";
}

string PictureLabel(const string &in choice) {
    string emoji = EmojiName(choice);
    if (emoji.Length > 0) return g_emojiLabels[uint(g_emojiNames.Find(emoji))];
    string local = LocalName(choice);
    return local.Length > 0 ? local : "None";
}

class PictureTexture {
    string choice;
    nvg::Texture@ drawing;
    UI::Texture@ thumbnail;
}

array<PictureTexture@> g_pictureCache;
array<string> g_localImages;
bool g_localImagesScanned = false;

// Openplanet returns a 0x0 texture for data it cannot decode.
bool HasArea(const vec2 &in size) {
    return size.x > 0 && size.y > 0;
}

PictureTexture@ LoadPicture(const string &in choice) {
    string emoji = EmojiName(choice);
    string local = LocalName(choice);
    if (emoji.Length == 0 && local.Length == 0) return null;
    PictureTexture@ picture = PictureTexture();
    picture.choice = choice;
    // An unreadable file throws; catching it keeps the failed entry cached
    // instead of retrying on every frame.
    try {
        if (emoji.Length > 0) {
            string asset = "assets/emoji/" + emoji + ".png";
            @picture.drawing = nvg::LoadTexture(asset, nvg::TextureFlags::GenerateMipmaps);
            @picture.thumbnail = UI::LoadTexture(asset);
        } else {
            string path = IO::FromStorageFolder("LocalImages/" + local);
            if (IO::FileExists(path)) {
                IO::File file(path, IO::FileMode::Read);
                MemoryBuffer@ buffer = file.Read(file.Size());
                file.Close();
                @picture.drawing = nvg::LoadTexture(buffer, nvg::TextureFlags::GenerateMipmaps);
                buffer.Seek(0);
                @picture.thumbnail = UI::LoadTexture(buffer);
            }
        }
    } catch {
        @picture.drawing = null;
        @picture.thumbnail = null;
    }
    if (picture.drawing !is null && !HasArea(picture.drawing.GetSize()))
        @picture.drawing = null;
    if (picture.thumbnail !is null && !HasArea(picture.thumbnail.GetSize()))
        @picture.thumbnail = null;
    if (picture.drawing is null) warn("Could not load picture " + choice);
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

nvg::Texture@ PictureForResult(Grade grade) {
    if (!S_ShowPictures || !HasPicture(grade)) return null;
    PictureTexture@ picture = GetPicture(PictureSetting(grade));
    return picture is null ? null : picture.drawing;
}

void RefreshLocalImages() {
    g_localImages.RemoveRange(0, g_localImages.Length);
    g_localImagesScanned = true;
    string folder = IO::FromStorageFolder("LocalImages");
    if (!IO::FolderExists(folder)) return;
    array<string>@ files = IO::IndexFolder(folder, false);
    for (uint i = 0; i < files.Length; i++) {
        string name = Path::GetFileName(files[i]);
        string extension = Path::GetExtension(name).ToLower();
        if ((extension == ".png" || extension == ".jpg" || extension == ".jpeg") &&
            IsSafeLocalName(name))
            g_localImages.InsertLast(name);
    }
    g_localImages.SortAsc();
}

// Scan LocalImages and load the chosen pictures so the first popup does not
// stall on a texture load.
void InitPictures() {
    RefreshLocalImages();
    for (int g = int(Grade::SPlus); g <= int(Grade::Missed); g++)
        PictureForResult(Grade(g));
}
