[SettingsTab name="Popup" icon="" order="3"]
void RenderSettingsPopup() {
    if (!g_localImagesScanned) RefreshLocalImages();
    if (UI::Button("Reset to default")) {
        ResetPopupSettings();
        ResetPictureSettings();
    }

    UI::SeparatorText("Animation");
    UI::SetNextItemWidth(260.0f);
    if (UI::BeginCombo("Style", PopupStyleLabel())) {
        for (uint i = 0; i < g_popupStyles.Length; i++)
            if (UI::Selectable(g_popupStyleLabels[i], g_popupStyles[i] == PopupStyle()))
                SelectPopupStyle(g_popupStyles[i]);
        UI::EndCombo();
    }
    UI::SetNextItemWidth(260.0f);
    S_PopupIntensity = Math::Clamp(UI::SliderInt("Intensity", S_PopupIntensity, 0, 200, "%d%%"), 0, 200);
    S_FxShake = UI::Checkbox("Screen shake", S_FxShake);
    S_FxShockwave = UI::Checkbox("Shockwave ring", S_FxShockwave);
    S_FxSparks = UI::Checkbox("Sparks", S_FxSparks);
    S_FxCracks = UI::Checkbox("Cracks", S_FxCracks);
    S_FxShards = UI::Checkbox("Ice shards", S_FxShards);
    S_FxSnowflakes = UI::Checkbox("Snowflakes (S, S+)", S_FxSnowflakes);
    S_FxRays = UI::Checkbox("Light rays (S+)", S_FxRays);
    S_FxSheen = UI::Checkbox("Light sheen", S_FxSheen);
    S_FxOutline = UI::Checkbox("Glowing outline (S+)", S_FxOutline);

    UI::SeparatorText("Pictures");
    S_ShowPictures = UI::Checkbox("Show pictures", S_ShowPictures);
    UI::SetNextItemWidth(260.0f);
    if (UI::BeginCombo("Emoji set", EmojiSetLabel())) {
        for (uint i = 0; i < g_emojiSets.Length; i++)
            if (UI::Selectable(g_emojiSetLabels[i], g_emojiSets[i] == EmojiSet()))
                S_EmojiSet = g_emojiSets[i];
        UI::EndCombo();
    }
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
    for (uint i = 0; i < g_pictureResults.Length; i++)
        RenderPictureRow(g_pictureResults[i]);
}

void RenderPictureRow(const string &in result) {
    UI::PushID(result);
    string choice = PictureSetting(result);
    float thumb = 28.0f*UI::GetScale();
    PictureTexture@ picture = GetPicture(choice);
    if (picture !is null && picture.thumbnail !is null)
        UI::Image(picture.thumbnail, vec2(thumb, thumb));
    else
        UI::Dummy(vec2(thumb, thumb));
    UI::SameLine();
    UI::AlignTextToFramePadding();
    UI::Text(result == "MISSED" ? "Missed" : result);
    UI::SameLine(110.0f*UI::GetScale());
    UI::SetNextItemWidth(240.0f);
    if (UI::BeginCombo("##picture", PictureLabel(choice))) {
        if (UI::Selectable("None", choice.Length == 0))
            SetPictureSetting(result, "");
        for (uint i = 0; i < g_emojiNames.Length; i++)
            if (UI::Selectable(g_emojiLabels[i], choice == "emoji:" + g_emojiNames[i]))
                SetPictureSetting(result, "emoji:" + g_emojiNames[i]);
        if (g_localImages.Length > 0) UI::Separator();
        for (uint i = 0; i < g_localImages.Length; i++)
            if (UI::Selectable(g_localImages[i], choice == "local:" + g_localImages[i]))
                SetPictureSetting(result, "local:" + g_localImages[i]);
        UI::EndCombo();
    }
    UI::SameLine();
    if (UI::Button("Preview")) StartPopupPreview(result);
    UI::PopID();
}
