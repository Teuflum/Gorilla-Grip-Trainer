# Grade popup pictures and Ice shatter animation

## Purpose

The confirmed-landing popup in the Grade widget should feel like a reward,
most of all for gorilla grip (S and S+). This change gives every result an
"Ice shatter" animation whose intensity follows the grade, lets each result
show a picture chosen on a new Images tab, and replaces the AI-generated
gorilla with real Twemoji art shipped in the repository.

Scoring, timing, verdicts, audio, and the small in-air preview grade do not
change.

## Decisions

- The animation direction is **Ice shatter** (chosen from three live
  prototypes: Arcade slam, Broadcast sheen, Ice shatter).
- Each result has **one** picture, drawn on both sides of the panel as the
  gorilla is today. Only S and S+ pictures bounce ("dance"); the others stand
  still.
- Shipped pictures are **Twemoji only**. The AI-generated
  `plugin/assets/gorilla-emoji.png` leaves the repository and lives on as a
  user file in `LocalImages`.
- Pictures can be turned off globally and per result.
- Picture settings live on a new **Images** tab, not on Layout.

## Ice shatter animation

The popup keeps today's timing envelope: the effect plays in the first
~0.7 s and everything fades out between 0.7 s and 1.0 s after the verdict.
All sizes are in the widget's base units and scale with the Grade widget as
today (`s = min(w / 500, h / 125)`).

| Time (ms) | Element |
| --- | --- |
| 0–110 | Frost flash: an ice-blue fill over the panel, alpha 0.6 → 0. |
| 0–180 | Panel widens from 180 to 480 units (ease-out cubic). |
| 0–220 | Crack lines grow outward from the letter as jagged 4-segment polylines, 60–150 units long; they fade out over 350–750 ms. |
| 0–800 | Ice shards: small triangles fly outward, spin, and fall under gravity; each fades out by 800 ms. |
| 0–260 | Grade letter lands oversized (scale 1.9 → 1) with a small overshoot bounce. |
| 120–420 | Letter colour warms from ice-white (with a frosty glow) into the grade colour; the glow fades as it warms. |
| 60 / 100 → 400 | Left / right picture pops in with an overshoot. |
| 120–320 | Caption fades in, as today. |
| 700–1000 | Everything fades out. |

Intensity by result:

| Result | Cracks | Shards | Extras |
| --- | --- | --- | --- |
| S+ | 12 | 40 | Rotating gold light rays behind the panel (12 wedges, alpha 0.12); burst of 10 snowflakes |
| S | 10 | 33 | Burst of 6 snowflakes |
| A | 8 | 25 | — |
| B | 7 | 20 | — |
| C | 6 | 16 | — |
| D | 5 | 13 | — |
| MISSED | 8 | 23 | Grey shards with 2.5× gravity; from 250 ms the panel slumps 10 units and the letter slumps 14 units and tilts 0.12 rad; no warm-up glow |
| UNRATED (and other non-results) | 0 | 0 | Calm: panel, letter, and caption only; no flash, cracks, shards, or picture |

Shard speed is `120 + 320 × power` units/s, with power 1.0 for S+, 0.8 for S,
0.55 for A, 0.4 for B, 0.3 for C, 0.2 for D, and 0.5 for MISSED. Snowflakes
are drawn as six-armed strokes (no font glyph) that drift outward and fade by
800 ms. The shard, crack, and snowflake layout comes from a pseudo-random
generator seeded with the verdict's race time, so a popup never flickers or
reshuffles between frames. The conservative `+` marker (for example `A+`)
still appears after the letter.

Pictures are drawn 72 units square at 150 units left and right of centre, as
today. S and S+ pictures bob up to 12 units and tilt up to 0.18 rad
(`|sin(t × 0.012 + side × 1.8)|`); other pictures are still.

## Pictures

### Choices and defaults

Each result stores one choice string:

- `emoji:<name>` — a shipped Twemoji picture,
- `local:<file>` — a PNG or JPG in `LocalImages`,
- empty — no picture.

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

### Images tab

The tab order becomes Rating, Sounds, **Images**, Layout, and Debug (developer
mode only). Like the other custom tabs it has no tab icon.

- Top row: **Show pictures**, **Open LocalImages folder**, **Reload files**,
  and **Reset to default** (restores the switch and the seven defaults).
- One row per result (S+, S, A, B, C, D, Missed):
  - a small thumbnail of the current picture (blank for None);
  - a picker listing *None*, the twelve shipped emoji by readable name
    ("Gorilla", "Oncoming fist", …), then the local files;
  - **Preview**, which plays that result's full popup at the Grade widget's
    position.

A preview runs on its own clock (`Time::Now`) for one second. It draws even
outside a run, while the car is stopped, when the Grade widget is hidden, or
when all widgets are disabled, because the user asked for it. It respects
**Show pictures**. A new preview replaces a running one; a real
verdict replaces a preview.

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
  S+ is updated to describe per-result pictures and the Ice shatter popup.

## Code structure

- `plugin/Pictures.as`: the shipped catalogue (name, label, file), the
  picture settings and their defaults, `LocalImages` scanning, one texture
  cache per choice holding both an `nvg::Texture` for drawing and a
  `UI::Texture` for thumbnails, and the Images tab.
- `plugin/GradeAnimation.as`: `RenderResult` moves here from `Widgets.as` and
  becomes the Ice shatter popup. The per-result intensity table is data
  (cracks, shards, power, extras), and the seeded generator lives here.
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
  gone from `plugin/assets`; the seven defaults (🦍 for S+ and S, 💀 for
  MISSED); the choice prefixes; the tab name and order; `LocalImages/` is
  ignored by Git.
- `tests/test_grade_animation.py`: the intensity table matches this spec;
  only S and S+ pictures bounce; UNRATED draws no cracks, shards, or picture;
  the generator is seeded from the verdict time; the fade ends at 1000 ms.
- Updated: the logging test's list of always-logged problems and its call
  count, the tab-order check in `test_presentation_contract.py`, and any test
  that refers to the gorilla texture.

In game: install, reload, then press every **Preview** button and land real
jumps (at least S, a lower grade, and a miss). Check the Openplanet log for
load errors and that the S+ popup does not visibly slow the game.

## Out of scope

- Animating the small in-air preview grade.
- Multiple pictures per result, random picks, or per-side pictures.
- Changing the finish summary, Stats card, or sounds.
