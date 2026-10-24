// Colours and nvg drawing helpers shared by the HUD cards.
namespace Hud {
    const vec4 Card = vec4(0.025f, 0.039f, 0.09f, 0.90f);
    const vec4 Tile = vec4(0.035f, 0.065f, 0.13f, 0.88f);
    const vec4 Shadow = vec4(0.0f, 0.0f, 0.0f, 0.28f);
    const vec4 Line = vec4(0.16f, 0.25f, 0.35f, 1.0f);
    const vec4 Gold = vec4(1.0f, 0.85f, 0.36f, 1.0f);
    const vec4 Cyan = vec4(0.60f, 0.89f, 1.0f, 1.0f);
    const vec4 Ice = vec4(0.47f, 0.82f, 1.0f, 1.0f);
    const vec4 Teal = vec4(0.04f, 0.95f, 0.87f, 1.0f);
    const vec4 Magenta = vec4(1.0f, 0.39f, 0.76f, 1.0f);
    const vec4 Pink = vec4(1.0f, 0.48f, 0.58f, 1.0f);
    const vec4 Orange = vec4(1.0f, 0.58f, 0.36f, 1.0f);
    const vec4 White = vec4(1.0f, 1.0f, 1.0f, 1.0f);
    const vec4 Bright = vec4(0.90f, 0.96f, 1.0f, 1.0f);
    const vec4 Label = vec4(0.60f, 0.73f, 0.84f, 1.0f);
    const vec4 Dim = vec4(0.45f, 0.59f, 0.70f, 1.0f);

    vec4 WithAlpha(const vec4 &in color, float alpha) {
        return vec4(color.x, color.y, color.z, alpha);
    }

    void Box(float x, float y, float w, float h, float radius, const vec4 &in color) {
        nvg::BeginPath();
        nvg::RoundedRect(x, y, w, h, radius);
        nvg::FillColor(color);
        nvg::Fill();
    }

    void Text(float x, float y, const string &in value, float size,
        const vec4 &in color, int align) {
        nvg::FontSize(size);
        nvg::TextAlign(align);
        nvg::FillColor(color);
        nvg::Text(x, y, value);
    }

    // Equal tiles side by side, each with a caption over a value in its colour;
    // accentBars adds a thin bar in that colour along each tile's top.
    void TileRow(float x, float y, float width, float height, float gap,
        const array<string> &in captions, const array<string> &in values,
        const array<vec4> &in colors, bool accentBars) {
        float tileW = (width - gap*float(captions.Length - 1)) / float(captions.Length);
        int center = nvg::Align::Center | nvg::Align::Middle;
        for (uint i = 0; i < captions.Length; i++) {
            float tx = x + float(i)*(tileW + gap);
            Box(tx, y, tileW, height, height*0.15f, Tile);
            if (accentBars)
                Box(tx + height*0.15f, y + height*0.02f, tileW - height*0.3f, height*0.04f,
                    height*0.02f, WithAlpha(colors[i], 0.75f));
            Text(tx + tileW*0.5f, y + height*0.32f, captions[i], height*0.18f, Label, center);
            Text(tx + tileW*0.5f, y + height*0.70f, values[i], height*0.37f, colors[i], center);
        }
    }

    // A card's shadow, background and the accent bar on its left edge.
    void CardBase(const vec4 &in r, const vec4 &in accent) {
        Box(r.x + 3, r.y + 4, r.z, r.w, 13, Shadow);
        Box(r.x, r.y, r.z, r.w, 13, Card);
        Box(r.x, r.y, 4, r.w, 2, accent);
    }
}
