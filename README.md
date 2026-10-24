# Gorilla Grip Trainer

An [Openplanet](https://openplanet.dev) plugin for Trackmania that trains the "gorilla grip". You switch the ice-slide direction just before the car leaves the ground, so the tires grip again when it lands. The plugin grades how early you switched (S+ to D) and checks on landing that the new direction held.

New to the mechanic? The [player guide](https://github.com/Teuflum/tm-ice-physics-reverse-engineering/blob/main/outputs/gorilla_grip_player_guide.md) explains it, and the [interactive graphs](https://teuflum.github.io/tm-ice-physics-reverse-engineering/) let you try the numbers.

## Install

1. Install [Openplanet](https://openplanet.dev). The plugin also needs VehicleState, which ships with Openplanet.
2. Download this repository (**Code → Download ZIP** on GitHub) and extract it.
3. Copy its `plugin` folder into `%USERPROFILE%\OpenplanetNext\Plugins` and rename the copy to `GorillaGripTrainer`, so you end up with `%USERPROFILE%\OpenplanetNext\Plugins\GorillaGripTrainer\info.toml`.
4. The plugin is not signed yet, so Openplanet only loads it in developer mode: open the Openplanet overlay (F3), choose **Developer → Signature Mode → Developer**, then load **Gorilla Grip Trainer** from the Developer menu. If it shows up disabled, enable it in the plugin list.

To update, download the repository again and replace the `GorillaGripTrainer` folder with the new `plugin` folder the same way. Your settings, history, `LocalSounds` and `LocalImages` live in `PluginStorage` and are kept.

Each time it loads, the plugin looks up the physics data in the game's code, so it keeps working after most Trackmania updates. If an update breaks this, Openplanet shows an amber warning and the plugin unloads until it's updated.

If the plugin loads but can't read the physics for 3 seconds of driving the Stadium car, it shows the same warning and the Physics widget says PHYSICS READ FAILED. Jumps aren't rated until the plugin is updated. If only the wheel contact times look wrong, it warns once and keeps rating, but landings are timed less exactly.

## How a jump is rated

1. **Takeoff.** If the game stored your switch to the other slide direction before the last wheel left the ground, a small preview grade shows up in the air. A jump without a switch shows nothing.
2. **Landing.** Shortly after touchdown the plugin checks that the direction held and that the tires still average at least 34% icing. If both are true, the preview becomes the final grade. If not, it's `MISSED`. A jump without a switch before takeoff is also `MISSED` if the direction switches on landing, because the grip then comes back too late.

The grade only depends on how early the direction switched before the last wheel left the ground, called the lead. Landing force and airtime aren't part of it, because countersteering early costs speed, so the best switch is the latest one that still counts.

| Grade | Lead (default) | Base points |
| --- | --- | --- |
| S+ | exactly 0 ms | 180 |
| S | up to 10 ms | 150 |
| A | up to 30 ms | 120 |
| B | up to 60 ms | 90 |
| C | up to 110 ms | 60 |
| D | up to 250 ms | 30 |

- **Score:** base points × combo multiplier (up to ×8).
- **`UNRATED`:** the plugin couldn't time the jump exactly or lost the physics read, so it doesn't guess a grade.

Timing comes from the game's own physics clock, so grades don't depend on frame rate or game speed. The physics runs in 10 ms ticks, so every lead is a whole number of ticks. S is one tick early, A two or three, B four to six.

### Which jumps count

A jump is rated only if it comes out of an ice slide. The takeoff icing, speed and flight limits can be changed on the Rating tab; these are the defaults:

- **Icing:** the four tires average at least 65% icing as the last wheel leaves. The landing check only needs a fixed 34%, because tires lose icing in the air.
- **Slide:** the car's slip angle reached 20° in the last 500 ms on the ground, so steering through a bobsleigh turn is never rated.
- **Speed and flight:** at least 50 km/h at takeoff and 100 ms in the air.
- **Car:** Only the Stadium car is rated. The Snow, Rally and Desert cars don't ice slide, so their jumps are ignored, and a jump in progress when a gate changes the car is dropped.

## HUD widgets

| Widget | Shows |
| --- | --- |
| Physics | Steering, stored slide direction, each wheel's contact and icing, tire force, recovery timer. Hidden by default; turn it on under **Layout**. |
| Grade | The takeoff preview, then the animated landing result |
| Stats | Score, combo and best combo |
| Last run | Your latest rated attempt on this map |
| Finish | After a finish: time, score, best combo, grade counts, misses, best and median switch lead |

Each widget is a plain box: black at 70% with a white border and white text by default. You can change the colours, the border and the corner radius on the **Display** tab.

Open **Settings → Gorilla Grip Trainer → Layout** to drag and resize them, or type in their position and size.

## Settings

| Tab | Contents |
| --- | --- |
| Display | Turn widgets on or off, show them with the game HUD hidden, open the finish summary automatically, widget colours, border and corner radius |
| Rating | Grade limits and which jumps count (icing, speed, flight time) |
| Sounds | Sound folders, and an on/off switch and volume per cue |
| Popup | Popup animation on or off; pictures beside the landing grade |
| Layout | Which widgets show, and their positions and sizes |
| Debug | Event logging; only in Openplanet's developer mode |

## Landing popup

The landing grade drops onto a panel in the same colours as the widgets and turns from white to its grade colour. A miss sinks and tips over.

Turn off **Popup animation** on the Popup tab to show the grade without any motion.

- **Pictures:** one per result, shown on both sides of the grade. Pick one of the shipped emoji pictures, or use your own PNG or JPG files from the `LocalImages` folder. Only S and S+ pictures bounce.
- **Preview** plays any result's popup with your current pictures.

## Sounds

The plugin ships no audio. **Open LocalSounds folder** on the Sounds tab creates one folder per cue inside `LocalSounds`:

| Folder | Plays |
| --- | --- |
| `takeoff` | When a rated jump leaves the ground |
| `S` | On an S or S+ landing |
| `A`, `B`, `C`, `D` | On a landing with that grade |
| `missed` | On a missed landing |
| `finish` | At the finish; it loops until you restart or leave the map |

Put WAV, OGG or MP3 files into them and click **Reload files**. When a folder holds several files, the plugin picks one at random and never the same one twice in a row. Each cue has its own switch and volume, and master volume starts at 0.50.

## Run history

**Plugins → Gorilla Grip Trainer → Run history** lists your attempts, and you can filter them by map and status. Select an attempt to see its jumps. Hover over a jump to see why it got its grade, its grade at takeoff if the landing changed it, and the score after it. The last 500 attempts are saved locally in `PluginStorage/GorillaGripTrainer/history.json`, with `history.backup.json` as a fallback.

## Development

- [docs/physics.md](docs/physics.md) lists the physics fields the plugin reads and the game code each offset comes from.
- `python tests/test_physics_patterns.py` checks the physics code patterns against your Trackmania binary (set `TRACKMANIA_EXE` if the game is not in the default Ubisoft folder). It needs no running game.
- `tools/render_emoji.py` rebuilds the shipped emoji pictures from their pinned sources.

## More

- [Physics research and reverse engineering](https://github.com/Teuflum/tm-ice-physics-reverse-engineering)
- Emoji pictures: [Twemoji](https://github.com/jdecked/twemoji) by Twitter, Inc. and other contributors (CC-BY 4.0), and the gorilla from [Noto Emoji](https://github.com/googlefonts/noto-emoji) by Google (Apache 2.0); details in `plugin/assets/emoji/ATTRIBUTION.md`.
