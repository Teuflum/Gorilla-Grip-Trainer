// Colours and nvg drawing helpers shared by the HUD widgets and the popup.
namespace Hud {
    const vec4 Gold = vec4(1.0f, 0.85f, 0.36f, 1.0f);
    const vec4 Ice = vec4(0.47f, 0.82f, 1.0f, 1.0f);
    const vec4 Teal = vec4(0.04f, 0.95f, 0.87f, 1.0f);
    const vec4 Magenta = vec4(1.0f, 0.39f, 0.76f, 1.0f);
    const vec4 Orange = vec4(1.0f, 0.58f, 0.36f, 1.0f);

    vec4 WithAlpha(const vec4 &in color, float alpha) {
        return vec4(color.x, color.y, color.z, alpha);
    }

    // The text colour without its alpha: Text, Box and Outline apply that
    // alpha to everything drawn on a widget, coloured values included.
    vec4 TextColor() { return WithAlpha(S_BoxText, 1.0f); }

    // Labels: the text colour, fainter.
    vec4 Muted() { return WithAlpha(S_BoxText, 0.6f); }

    vec4 Foreground(const vec4 &in color) { return WithAlpha(color, color.w * S_BoxText.w); }

    // Text spread over equal columns, each centred in its column; one colour
    // for all of them, or one per item.
    void Columns(float x, float y, float width, const array<string> &in items, float size,
        const array<vec4> &in colors) {
        float column = width / float(items.Length);
        for (uint i = 0; i < items.Length; i++)
            Text(x + column*(float(i) + 0.5f), y, items[i], size,
                colors[i < colors.Length ? i : colors.Length - 1],
                nvg::Align::Center | nvg::Align::Middle);
    }

    void Columns(float x, float y, float width, const array<string> &in items, float size,
        const vec4 &in color) {
        array<vec4> colors = {color};
        Columns(x, y, width, items, size, colors);
    }

    // A muted label and a coloured value on one line, placed as one piece
    // starting at x, or ending at x when alignRight is set.
    void LabelValue(float x, float y, const string &in label, const string &in value,
        float size, const vec4 &in color, bool alignRight) {
        float labelSize = size * 0.6f;
        nvg::FontSize(labelSize);
        // TextBounds leaves out trailing spaces, so the gap is added here.
        float labelW = nvg::TextBounds(label).x + size * 0.3f;
        nvg::FontSize(size);
        float start = alignRight ? x - labelW - nvg::TextBounds(value).x : x;
        int align = nvg::Align::Left | nvg::Align::Middle;
        Text(start, y, label, labelSize, Muted(), align);
        Text(start + labelW, y, value, size, color, align);
    }

    void Outline(float x, float y, float w, float h, float radius, const vec4 &in color,
        float width) {
        nvg::BeginPath();
        nvg::RoundedRect(x, y, w, h, radius);
        nvg::StrokeWidth(width);
        nvg::StrokeColor(Foreground(color));
        nvg::Stroke();
    }

    // A widget's box, in the Display tab's colours.
    void Panel(const vec4 &in r) {
        nvg::BeginPath();
        nvg::RoundedRect(r.x, r.y, r.z, r.w, Math::Min(S_BoxRadius, Math::Min(r.z, r.w) * 0.5f));
        nvg::FillColor(S_BoxBackground);
        nvg::Fill();
        if (S_BoxBorderWidth <= 0.0f) return;
        nvg::StrokeWidth(S_BoxBorderWidth);
        nvg::StrokeColor(S_BoxBorder);
        nvg::Stroke();
    }

    void Box(float x, float y, float w, float h, float radius, const vec4 &in color) {
        nvg::BeginPath();
        nvg::RoundedRect(x, y, w, h, radius);
        nvg::FillColor(Foreground(color));
        nvg::Fill();
    }

    void Text(float x, float y, const string &in value, float size,
        const vec4 &in color, int align) {
        nvg::FontSize(size);
        nvg::TextAlign(align);
        nvg::FillColor(Foreground(color));
        nvg::Text(x, y, value);
    }
}
