[SettingsTab name="Popup" icon="" order="3"]
void RenderSettingsPopup() {
    if (!g_localImagesScanned) RefreshLocalImages();
    if (ConfirmedResetButton("Reset to default", "popup")) {
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
    vec2 cell = UI::GetCursorScreenPos();
    UI::Dummy(vec2(thumb, thumb));
    if (picture !is null && picture.thumbnail !is null) {
        // Fit the picture inside the square cell without stretching it.
        vec2 dims = picture.thumbnail.GetSize();
        float aspect = dims.x / Math::Max(dims.y, 1.0f);
        vec2 size = aspect >= 1.0f ? vec2(thumb, thumb/aspect) : vec2(thumb*aspect, thumb);
        UI::GetWindowDrawList().AddImage(picture.thumbnail, cell + (vec2(thumb, thumb) - size)*0.5f, size);
    }
    UI::SameLine();
    UI::AlignTextToFramePadding();
    UI::Text(result == "MISSED" ? "Missed" : result);
    UI::SameLine(110.0f*UI::GetScale());
    string source = PictureSource(choice);
    array<string>@ parts = EmojiChoiceParts(choice);
    // Switching between emoji sets keeps the same picture.
    string keepName = "gorilla";
    if (parts !is null) {
        keepName = parts[1];
    } else {
        array<string>@ fallback = EmojiChoiceParts(DefaultPicture(result));
        if (fallback !is null) keepName = fallback[1];
    }
    UI::SetNextItemWidth(170.0f);
    if (UI::BeginCombo("##source", PictureSourceLabel(source))) {
        if (UI::Selectable("None", source.Length == 0))
            SetPictureSetting(result, "");
        for (uint i = 0; i < g_emojiSets.Length; i++)
            if (UI::Selectable(g_emojiSetLabels[i], source == g_emojiSets[i]))
                SetPictureSetting(result, "emoji:" + g_emojiSets[i] + "/" + keepName);
        if (UI::Selectable("Local file", source == "local") && source != "local")
            SetPictureSetting(result, g_localImages.Length > 0 ?
                "local:" + g_localImages[0] : "local:");
        UI::EndCombo();
    }
    if (source.Length > 0) {
        UI::SameLine();
        UI::SetNextItemWidth(200.0f);
        if (UI::BeginCombo("##picture", PictureLabel(choice))) {
            if (source == "local") {
                if (g_localImages.Length == 0) UI::Text("No files in LocalImages");
                for (uint i = 0; i < g_localImages.Length; i++)
                    if (UI::Selectable(g_localImages[i], choice == "local:" + g_localImages[i]))
                        SetPictureSetting(result, "local:" + g_localImages[i]);
            } else {
                for (uint i = 0; i < g_emojiNames.Length; i++)
                    if (UI::Selectable(g_emojiLabels[i], parts !is null && parts[1] == g_emojiNames[i]))
                        SetPictureSetting(result, "emoji:" + source + "/" + g_emojiNames[i]);
            }
            UI::EndCombo();
        }
    }
    UI::SameLine();
    if (UI::Button("Preview")) StartPopupPreview(result);
    UI::PopID();
}
