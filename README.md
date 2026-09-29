# Gorilla Grip Trainer

An [Openplanet](https://openplanet.dev) plugin for Trackmania that trains the "gorilla grip": switching the ice-slide direction just before the car leaves the ground, so the tires grip again when it lands. The plugin reads the game's physics, grades how early you switched (S+ to D), and confirms on landing that the new direction held.

New to the mechanic? The [player guide](https://github.com/Teuflum/tm-gorilla-grip-reverse-engineering/blob/main/outputs/gorilla_grip_player_guide.md) explains it.

## Install

1. Install [Openplanet](https://openplanet.dev). The plugin also needs VehicleState, which ships with Openplanet.
2. Copy the `plugin` folder to `OpenplanetNext/Plugins/GorillaGripTrainer`.
3. Load or reload the plugin in Openplanet.

Each time it loads, the plugin finds the physics data in the game's own code, so it keeps working after most Trackmania updates. If an update changes that code, Openplanet shows an amber warning and the plugin unloads itself until it is updated.

The plugin also checks what it reads. If an update changes a field in a way the code search doesn't catch, the plugin still loads, but after 3 seconds of driving the Stadium car without a single good physics read it shows the same amber warning, and the Physics widget says PHYSICS READ FAILED. No jumps are rated until the plugin is updated. If only the wheel contact times look wrong, it warns once and keeps rating, with landings timed to the frame instead of the physics tick.

## How a jump is rated

1. **Takeoff.** When the game stores the opposite slide direction while a wheel still touches the ground, a small preview grade appears in the air. A jump that keeps its slide direction shows nothing.
2. **Landing.** Shortly after touchdown the plugin checks that the stored direction held and the tires still average at least 34% icing. If both hold, the preview becomes the final grade. Otherwise the result is `MISSED`. A jump without a switch before takeoff is also `MISSED` if the direction switches on landing, because the tire force then waits after touchdown.

The grade depends only on how early the direction switched before the last wheel left the ground. Landing force and airtime are left out on purpose: countersteering early costs speed, so the best switch is the latest one that still counts.

| Grade | Switch lead (default) | Base points |
| --- | --- | --- |
| S+ | exactly 0 ms | 180 |
| S | up to 10 ms | 150 |
| A | up to 30 ms | 120 |
| B | up to 60 ms | 90 |
| C | up to 110 ms | 60 |
| D | up to 250 ms | 30 |

- **Score:** base points × combo multiplier (up to ×8).
- **`UNRATED`:** the plugin lost the physics read or the contact timing, or the tire force never became ready after landing, so it doesn't guess a grade.

Timing comes from the game's own physics clock, so grades don't depend on frame rate or game speed. The physics runs in 10 ms ticks, so every lead is a multiple of 10 ms: S is one tick early, A two or three, B four to six.

### Which jumps count

A jump is rated only if it comes out of an ice slide. The takeoff icing, speed and flight limits can be changed on the Rating tab; these are the defaults:

- **Icing:** the four tires average at least 65% icing as the last wheel leaves. The landing check only needs a fixed 34%, because tires lose icing in the air.
- **Slide:** the car's slip angle reached 20° in the last 500 ms on the ground, so steering through a bobsleigh turn is never rated.
- **Speed and flight:** at least 50 km/h at takeoff and 100 ms in the air.
- **Car:** Only the Stadium car is rated. The Snow, Rally and Desert cars don't ice slide, so their jumps are ignored, and a jump in progress when a gate changes the car is dropped.

With **Log trainer events** on (Debug tab, developer mode), a direction switch that these filters drop writes a line to `Openplanet.log` naming each failed filter and the value it saw.

## HUD widgets

| Widget | Shows |
| --- | --- |
| Physics | Steering, stored slide direction, each wheel's contact and icing, tire force, recovery timer |
| Grade | The takeoff preview, then the animated landing result |
| Stats | Score, combo and best combo |
| Last run | Your latest rated attempt on this map |
| Finish summary | After a finish: time, score, best combo, grade counts, misses, best and median switch lead |

Open **Settings → Gorilla Grip Trainer → Layout** to drag and resize them.

## Settings

| Tab | Contents |
| --- | --- |
| Display | Turn widgets on or off, show them with the game HUD hidden, open the finish summary automatically |
| Rating | Grade limits and which jumps count (icing, speed, flight time) |
| Sounds | Sound lists and volumes per cue |
| Popup | Animation style, effects, intensity and pictures for the landing popup |
| Layout | Widget positions and sizes |
| Debug | Event logging; only shown in Openplanet's developer mode |

Every reset button asks for a second click (**Confirm reset** or **Cancel**).

## Landing popup

- **Styles:** Ice shatter (default), Arcade slam or Broadcast sheen. Each style comes with its own effects, and any effect can be turned on or off with any style.
- **Intensity:** 0–200 %. Better grades always get bigger effects.
- **Pictures:** one per result, shown on both sides of the grade. Pick from five emoji sets (Fluent Flat, Fluent 3D, Twemoji, Noto, OpenMoji), mixed per result, or use your own PNG or JPG files from the `LocalImages` folder. Only S and S+ pictures bounce.
- **Preview** plays any result's popup with your current settings.

## Sounds

The plugin ships no audio. Put WAV, OGG or MP3 files into the `LocalSounds` folder (**Open LocalSounds folder** on the Sounds tab), then click **Reload files**. The default lists expect these names:

| Cue | Default file | Volume |
| --- | --- | --- |
| Takeoff | `SP2_SND_GROUP_00000006.wav` | 0.35 |
| S and S+ | `Sample_0064.wav` (Incredible), `Sample_0061.wav` (Great Air) | 0.40 |
| A | `Sample_0065.wav` (Amazing) | 0.40 |
| B | `Sample_0063.wav` (Excellent) | 0.40 |
| C | `Sample_0058.wav` (Nice) | 0.40 |
| D | `Sample_0053.wav` (Good) | 0.40 |
| Missed | `SP2_SND_GROUP_00000002.wav` | 0.35 |
| Finish | `WSR_Wakeboarding_Results.mp3` | 0.25 |

If you have the Wakeboarding sounds from Wii Sports Resort under these names, they work right away. Master volume starts at 0.50.

- On a fresh install, the lists only contain the files you already have. After adding more, **Reset to default** on the Sounds tab fills in the rest.
- Each cue can hold several clips; the plugin picks one at random and never the same one twice in a row.
- The announcer only speaks on a confirmed landing. The finish music loops until you restart or leave the map.

## Run history

**Plugins → Gorilla Grip Trainer → Run history** (or **VIEW HISTORY** on the finish summary) lists your attempts with their jumps, filtered by map and status. Selecting a jump shows its timing, preview, score and reason. The last 500 attempts are kept locally in `PluginStorage/GorillaGripTrainer/history.json`, with `history.backup.json` as a fallback.

## Development

- **Offline tests** check the plugin source and need no game: `python tests/<name>.py`, for example `python tests/test_rating_settings.py`. [AGENTS.md](AGENTS.md) has the full workflow.
- **In-game tests** (`test_trainer_in_game.py`, `test_current_input.py`, `test_finish_reset_in_game.py`, `test_improve_reset_in_game.py`, `test_frame_independence_in_game.py`) drive a real run. They need:
  - Trackmania and TICK;
  - **Log trainer events** turned on (Debug tab, developer mode);
  - for all but `test_improve_reset_in_game.py`, a local clone of the [research repository](https://github.com/Teuflum/tm-gorilla-grip-reverse-engineering), passed as `--research-root` where the script asks for it. The tests import TICK's local client from its `work/tick_client.py` and replay runs through its Gorilla Grip Logger plugin. The Trainer itself does not need the Logger.

  Example: `py -3 tests/test_trainer_in_game.py --research-root <path-to-research-repo> --case all`. The finish case also needs `--finish-revision-id <known-finishing-revision>`.
- **Tools:** `tools/install_local_audio.py` copies your clips into `LocalSounds`; `tools/render_emoji.py` rebuilds the shipped emoji pictures from their pinned sources.

## More

- Design documents: [trainer](docs/superpowers/specs/2026-09-25-gorilla-grip-trainer.md), [tick-exact timing](docs/superpowers/specs/2026-09-27-tick-exact-timing-design.md) and [landing popup](docs/superpowers/specs/2026-09-27-grade-popup-pictures-design.md). The plans next to them are the step lists these were built from.
- [Physics research and reverse engineering](https://github.com/Teuflum/tm-gorilla-grip-reverse-engineering)
- Emoji pictures: [Fluent Emoji](https://github.com/microsoft/fluentui-emoji) by Microsoft (MIT), [Twemoji](https://github.com/jdecked/twemoji) by Twitter, Inc. and other contributors (CC-BY 4.0), [Noto Emoji](https://github.com/googlefonts/noto-emoji) by Google (Apache 2.0) and [OpenMoji](https://openmoji.org) (CC BY-SA 4.0); details in `plugin/assets/emoji/ATTRIBUTION.md`.
