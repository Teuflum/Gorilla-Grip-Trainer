[SettingsTab name="Popup" icon="" order="4"]
void RenderSettingsPopup() {
    if (!g_localImagesScanned) RefreshLocalImages();
    if (UI::Button("Reset to default")) {
        Meta::ExecutingPlugin().GetSetting("S_PopupAnimate").Reset();
        ResetPictureSettings();
    }
    UI::SeparatorText("Animation");
    S_PopupAnimate = UI::Checkbox("Enabled", S_PopupAnimate);
    UI::SeparatorText("Pictures");
    S_ShowPictures = UI::Checkbox("Show pictures beside the grade", S_ShowPictures);
    if (UI::Button("Open LocalImages folder")) {
        string folder = IO::FromStorageFolder("LocalImages");
        if (!IO::FolderExists(folder)) IO::CreateFolder(folder, true);
        OpenExplorerPath(folder);
    }
    UI::SameLine();
    if (UI::Button("Reload files")) {
        RefreshLocalImages();
        ClearPictureCache();
    }
    UI::Separator();
    for (int g = int(Grade::SPlus); g <= int(Grade::Missed); g++)
        RenderPictureRow(Grade(g));
}

void RenderPictureRow(Grade grade) {
    UI::PushID(int(grade));
    string choice = PictureSetting(grade);
    float thumb = 28.0f*UI::GetScale();
    PictureTexture@ picture = GetPicture(choice);
    vec2 cell = UI::GetCursorScreenPos();
    UI::Dummy(vec2(thumb, thumb));
    if (picture !is null && picture.thumbnail !is null) {
        vec2 size = FitInSquare(picture.thumbnail.GetSize(), thumb);
        UI::GetWindowDrawList().AddImage(picture.thumbnail, cell + (vec2(thumb, thumb) - size)*0.5f, size);
    }
    UI::SameLine();
    UI::AlignTextToFramePadding();
    UI::Text(grade == Grade::Missed ? "Missed" : GradeName(grade));
    UI::SameLine(110.0f*UI::GetScale());
    UI::SetNextItemWidth(240.0f);
    if (UI::BeginCombo("##picture", PictureLabel(choice))) {
        if (UI::Selectable("None", choice.Length == 0))
            SetPictureSetting(grade, "");
        UI::SeparatorText("Emoji");
        for (uint i = 0; i < g_emojiNames.Length; i++)
            if (UI::Selectable(g_emojiLabels[i], EmojiName(choice) == g_emojiNames[i]))
                SetPictureSetting(grade, "emoji:" + g_emojiNames[i]);
        UI::SeparatorText("LocalImages");
        if (g_localImages.Length == 0) UI::TextDisabled("No PNG or JPG files yet");
        for (uint i = 0; i < g_localImages.Length; i++)
            if (UI::Selectable(g_localImages[i], LocalName(choice) == g_localImages[i]))
                SetPictureSetting(grade, "local:" + g_localImages[i]);
        UI::EndCombo();
    }
    UI::SameLine();
    if (UI::Button("Preview")) ShowResult(grade, GradeCaption(grade), true);
    UI::PopID();
}
