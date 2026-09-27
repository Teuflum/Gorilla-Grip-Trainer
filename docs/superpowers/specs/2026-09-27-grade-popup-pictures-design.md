# Grade popup styles, effects, and pictures

## Purpose

The confirmed-landing popup in the Grade widget should feel like a reward,
most of all for gorilla grip (S and S+). This change gives the popup three
selectable animation styles whose effects can be mixed and scaled, lets each
result show a picture chosen on a new Popup tab, and replaces the
AI-generated gorilla with real Twemoji art shipped in the repository.

Scoring, timing, verdicts, audio, and the small in-air preview grade do not
change.

## Decisions

- Three styles come from the live prototypes: **Ice shatter** (default),
  **Arcade slam**, and **Broadcast sheen**.
- A style sets the base look and switches on its own effects; every effect
  can then be turned on or off with any style.
- One **Intensity** slider (0–200 %) scales all effects. Per-grade intensity
  may replace it later if testing shows a need; nothing else would change.
- Each result has **one** picture, drawn on both sides of the panel as the
  gorilla is today. Only S and S+ pictures bounce ("dance").
- Shipped pictures are **Twemoji only**. The AI-generated
  `plugin/assets/gorilla-emoji.png` leaves the repository and lives on as a
  user file in `LocalImages`.
- Pictures can be turned off globally and per result.
- Animation and picture settings share a new **Popup** tab.

## Popup animation

### Shared rules

The popup keeps today's timing envelope: effects play in the first ~0.8 s
and everything fades out between 0.7 s and 1.0 s after the verdict. All sizes
are in the widget's base units and scale with the Grade widget as today
(`s = min(w / 500, h / 125)`). The panel's full width is 480 units.

Each result has a **power** that scales its effects:

| Result | Power |
| --- | --- |
| S+ | 1.0 |
| S | 0.8 |
| A | 0.55 |
| B | 0.4 |
| C | 0.3 |
| D | 0.2 |
| MISSED | 0.5 |

Particle effects (sparks, shards) use a **particle count** of
`round(6 + 34 × power)` (S+ 40, S 33, A 25, B 20, C 16, D 13, MISSED 23) and a
speed of `120 + 320 × power` units/s. Cracks use `round(4 + 8 × power)` lines
(S+ 12, S 10, A 8, B 7, C 6, D 5, MISSED 8).

UNRATED and other non-results are always **calm**: the style's panel, letter
entrance, and caption only. No flash, effect, or picture.

Randomness (shake jitter, particle and crack layout) comes from a small
pseudo-random generator seeded with the verdict's race time (a fixed seed per
result for previews), so a popup never flickers or reshuffles between frames.
The conservative `+` marker (for example `A+`) still follows the letter.

### Styles: base look

A style's base look is always drawn and is not an effect. Timings are in ms
after the verdict.

**Ice shatter** (default)

- Panel widens from 180 to 480 units over 0–180 (ease-out cubic).
- Ice-blue frost flash over the panel, alpha 0.6 → 0 over 0–110.
- Letter lands at 1.9× scale and settles to 1× with a small overshoot over
  0–260. Its colour warms from ice-white, with a frosty glow, into the grade
  colour over 120–420; the glow fades as it warms.
- Pictures pop in with an overshoot, left from 60 and right from 100, both
  settled by 400.
- MISSED: no warm-up glow; from 250 to 600 the panel slumps 10 units and the
  letter slumps 14 units and tilts 0.12 rad.

**Arcade slam**

- Panel widens from 180 to 480 units over 0–170.
- White flash over the panel, alpha `0.55 × power` → 0 over 0–90.
- Letter slams from 3.2× scale with a −0.2 rad twist to 1× over 0–240 with an
  overshoot, glowing in the grade colour (blur `18 × power`).
- Pictures pop in with an overshoot over 60–320.
- MISSED: the letter swells from 1.6× to 1× over 0–220, the panel shakes
  sideways like a "no" (14 units, `sin(t × 0.09)`, decaying over 0–300), and
  the letter drops 6 units over 200–500.

**Broadcast sheen**

- Panel opens from the centre to 480 units over 0–230, with 4-unit white bars
  on both moving edges that fade over 0–260.
- No flash.
- Letter is wiped in from the left over 120–380 (scissor clip, ease-out).
- A 120-unit underline in the grade colour grows from the centre over
  300–600.
- Pictures slide in from 30 units further out and fade in over 60–360.
- MISSED: over 150–450 the letter glitches, jumping up to ±5 units on every
  other 40 ms step, with a cyan ghost copy offset 3 units at alpha 0.6.

### Effects

| Effect | Arcade | Broadcast | Ice | Behaviour |
| --- | --- | --- | --- | --- |
| Screen shake | ✓ | | | Over 0–300 the panel, letter, and pictures jolt randomly up to ±9 × power units horizontally and ±6 × power vertically, decaying to zero. Not on MISSED with Arcade slam, which has its own sideways shake. |
| Shockwave ring | ✓ | | | A grade-coloured ellipse (height 0.42 × width) expands from radius 30 to 290 over 0–480; line width `2 + 7 × power` → 2, alpha 0.8 → 0. Not on MISSED. |
| Sparks | ✓ | | | Particle-count dots fly outward from the letter and fall (gravity 156 units/s²), fading by 750. On S+ half of them are spinning confetti rectangles in gold, cyan, pink, and green. MISSED sparks are grey and fall with 260 units/s². |
| Cracks | | | ✓ | Crack lines grow from the letter over 0–220 as jagged 4-segment polylines 60–150 units long, then fade over 350–750. |
| Ice shards | | | ✓ | Particle-count small ice-white triangles fly outward, spin, and fall (gravity 120 units/s²), fading by 800. MISSED shards are grey with 300 units/s². |
| Snowflakes | | | ✓ | S and S+ only: 6 (S) or 10 (S+) six-armed stroked snowflakes drift outward from the panel over 80–680 and fade by 800. |
| Light rays | ✓ | | ✓ | S+ only: 12 gold wedges, 320 units long, rotate slowly behind the panel at alpha 0.12, fading in over 150–450. |
| Light sheen | | ✓ | | A white band sweeps across the letter over 340 ms: once from 300 for S, A, and B; twice (from 260 and 520) for S+. It is the letter redrawn in white inside a moving scissor band, drawn as three nested bands of falling alpha for soft edges, so it stays on the glyph shape. |
| Glowing outline | | ✓ | | S+ only: the panel outline glows in the grade colour, pulsing with `sin(t × 0.02)`. |

Choosing a style in the dropdown switches its ✓ effects on and the rest off.
If the effect switches then differ from the chosen style's set, the dropdown
shows the style name followed by "(custom)", for example
"Ice shatter (custom)".

### Intensity

`S_PopupIntensity` is an integer from 0 to 200 (default 100); let
`k = intensity / 100`. It multiplies:

- particle, crack, and snowflake counts (rounded);
- particle speed and travel distance;
- shake amplitude;
- the style's flash alpha (the one base-look element that scales);
- light-ray, outline, and sheen alpha, clamped at 1.

It never changes timing, the panel, the letter entrance or its glow, the
caption, or the pictures. At 0 % no flash or effect plays: only the panel,
letter entrance, caption, and pictures. Per-result power applies on top of
intensity.

## Pictures

### Choices and defaults

Each result stores one choice string:

- `emoji:<name>`: a shipped Twemoji picture;
- `local:<file>`: a PNG or JPG in `LocalImages`;
- empty: no picture.

| Result | Setting | Default |
| --- | --- | --- |
| S+ | `S_PictureSPlus` | `emoji:gorilla` 🦍 |
| S | `S_PictureS` | `emoji:gorilla` 🦍 |
| A | `S_PictureA` | `emoji:flexed-biceps` 💪 |
| B | `S_PictureB` | `emoji:thumbs-up` 👍 |
| C | `S_PictureC` | `emoji:ok-hand` 👌 |
| D | `S_PictureD` | `emoji:slightly-smiling-face` 🙂 |
| MISSED | `S_PictureMissed` | `emoji:skull` 💀 |

`S_ShowPictures` (default on) turns all pictures off. UNRATED never shows a
picture.

Pictures are drawn 72 units square at 150 units left and right of centre, as
today. S and S+ pictures bob up to 12 units and tilt up to 0.18 rad
(`|sin(t × 0.012 + side × 1.8)|`); other pictures are still. How a picture
enters depends on the style (see above).

### Shipped set

Twelve Twemoji graphics, stored as 256×256 transparent PNGs in
`plugin/assets/twemoji/` and named after the emoji:

| File | Emoji | Codepoint |
| --- | --- | --- |
| `gorilla.png` | 🦍 | 1f98d |
| `oncoming-fist.png` | 👊 | 1f44a |
| `flexed-biceps.png` | 💪 | 1f4aa |
| `fire.png` | 🔥 | 1f525 |
| `thumbs-up.png` | 👍 | 1f44d |
| `ok-hand.png` | 👌 | 1f44c |
| `slightly-smiling-face.png` | 🙂 | 1f642 |
| `skull.png` | 💀 | 1f480 |
| `ice.png` | 🧊 | 1f9ca |
| `snowflake.png` | ❄️ | 2744 |
| `trophy.png` | 🏆 | 1f3c6 |
| `star.png` | ⭐ | 2b50 |

The PNGs are rendered from the official SVGs of the maintained Twemoji
project (`jdecked/twemoji`, fetched through cdn.jsdelivr.net). The 72 px PNGs
Twemoji also publishes would blur on a large or high-DPI Grade widget, and
NanoVG cannot draw SVG.

### Local pictures

`LocalImages` sits in the Trainer's Openplanet storage folder, next to
`LocalSounds`. PNG and JPG files there appear in every picker. Local files are
read with `IO::File` into a `MemoryBuffer` and passed to `LoadTexture`.

## Popup tab

The tab order becomes Rating, Sounds, **Popup**, Layout, and Debug (developer
mode only). Like the other custom tabs it has no tab icon.

- **Reset to default** at the top restores the style, effects, intensity,
  picture switch, and the seven picture defaults.
- **Animation** section:
  - **Style** dropdown (with the "(custom)" suffix described above);
  - **Intensity** slider, 0–200 %;
  - one checkbox per effect, in the order of the effects table.
- **Pictures** section:
  - **Show pictures**, **Open LocalImages folder**, and **Reload files**;
  - one row per result (S+, S, A, B, C, D, Missed) with a small thumbnail of
    the current picture (blank for None), a picker listing *None*, the twelve
    shipped emoji by readable name ("Gorilla", "Oncoming fist", …), then the
    local files, and **Preview**.

**Preview** plays that result's full popup with the current style, effects,
intensity, and picture at the Grade widget's position. It runs on its own
clock (`Time::Now`) for one second and draws even outside a run, while the
car is stopped, when the Grade widget is hidden, or when all widgets are
disabled, because the user asked for it. It respects **Show pictures**. A new
preview replaces a running one; a real verdict replaces a preview.

### Settings

| Setting | Type | Default |
| --- | --- | --- |
| `S_PopupStyle` | string: `ice`, `arcade`, or `broadcast` | `ice` |
| `S_PopupIntensity` | int 0–200 | 100 |
| `S_FxShake` | bool | false |
| `S_FxShockwave` | bool | false |
| `S_FxSparks` | bool | false |
| `S_FxCracks` | bool | true |
| `S_FxShards` | bool | true |
| `S_FxSnowflakes` | bool | true |
| `S_FxRays` | bool | true |
| `S_FxSheen` | bool | false |
| `S_FxOutline` | bool | false |
| `S_ShowPictures` | bool | true |
| `S_Picture…` | string (seven, see above) | see above |

All are `[Setting hidden]` and edited only on the Popup tab. An unknown style
string counts as `ice`.

## Assets, licensing, and repository

- Twemoji graphics are licensed CC-BY 4.0. `plugin/assets/twemoji/ATTRIBUTION.md`
  credits "Twemoji by Twitter, Inc. and other contributors", links the
  licence, and lists the twelve files and their codepoints. The README gets
  a one-line credit.
- `plugin/assets/gorilla-emoji.png` and `plugin/assets/GORILLA_ASSET.md` are
  removed. The image is copied to the installed
  `PluginStorage/GorillaGripTrainer/LocalImages/gorilla-emoji.png` and to a
  Git-ignored `Trainer/LocalImages/`, so it stays available as a local choice.
  It remains in Git history; history is not rewritten.
- `.gitignore` adds `LocalImages/`.
- The main design document's line about "bouncing gorilla images" on S and
  S+ is updated to describe the popup styles and per-result pictures.

## Code structure

- `plugin/Pictures.as`: the shipped catalogue (name, label, file), the
  picture settings and defaults, `LocalImages` scanning, and one texture
  cache per choice holding both an `nvg::Texture` for drawing and a
  `UI::Texture` for thumbnails.
- `plugin/GradeAnimation.as`: `RenderResult` moves here from `Widgets.as`.
  It holds the popup settings, the power table, the seeded generator, one
  base-look function per style, one function per effect, and the preview
  clock. Effects read their on/off switch and `k`; styles never draw another
  style's effects themselves.
- `plugin/PopupTab.as`: the Popup settings tab (Animation and Pictures
  sections, Reset to default, Preview buttons).
- `plugin/Widgets.as`: loses `RenderSGorillas`, `DrawGorillaEmoji`,
  `DrawFallbackFlame`, `GorillaDot`, and `g_gorillaTexture`. `RenderWidgets`
  draws a running preview at the Grade widget's position before its
  "no snapshot" early return, and otherwise draws the real result as today.
- `plugin/Main.as`: initializes pictures at startup.

## Failures

- A missing or unreadable local file shows no picture for that result; the
  animation still plays. The problem is always logged, once per file, as
  "Gorilla Grip Trainer images: could not load <file>".
- A missing shipped PNG is handled the same way.
- A choice string that names an unknown emoji or has an unknown prefix counts
  as None.
- The old "gorilla emoji texture could not load" log line is removed.

## Testing

Offline (Python, no game):

- `tests/test_pictures.py`: all twelve PNGs exist and are 256×256; the
  attribution file lists them; `gorilla-emoji.png` and `GORILLA_ASSET.md` are
  gone from `plugin/assets`; the seven picture defaults (🦍 for S+ and S, 💀
  for MISSED); the choice prefixes; `LocalImages/` is ignored by Git.
- `tests/test_grade_animation.py`: the power table and count formulas; each
  style's default effect set matches the effects table; the "(custom)"
  suffix logic; intensity is clamped to 0–200 and multiplies counts, speed,
  shake, flash, and alpha but not timing; only S and S+ pictures bounce;
  UNRATED draws no flash, effect, or picture; the generator is seeded from the
  verdict time; the fade ends at 1000 ms.
- `tests/test_popup_tab.py`: the tab name and order (Rating, Sounds, Popup,
  Layout, Debug); Reset to default covers every popup and picture setting;
  each result row has a Preview button.
- Updated: the logging test's list of always-logged problems and its call
  count, the tab-order check in `test_presentation_contract.py`, and any test
  that refers to the gorilla texture.

In game: install, reload, then use **Preview** for every result with each
style, with a mix of effects, and at 0 %, 100 %, and 200 % intensity. Land
real jumps (at least S, a lower grade, and a miss). Check the Openplanet log
for load errors and that S+ at 200 % does not visibly slow the game.

## Out of scope

- Per-grade intensity (possible follow-up after testing).
- Animating the small in-air preview grade.
- Multiple pictures per result, random picks, or per-side pictures.
- Changing the finish summary, Stats card, or sounds.
