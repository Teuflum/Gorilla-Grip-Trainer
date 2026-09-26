# Gorilla Grip Trainer

Standalone Openplanet trainer for the timing of a Trackmania ice-slide direction switch before takeoff. The current implementation reads the physics direction, previews a validated S+–D switch in the air, and confirms the landing before changing score or combo.

- [Design specification](docs/superpowers/specs/2026-09-25-gorilla-grip-trainer.md)
- [Implementation plan](docs/superpowers/plans/2026-09-25-gorilla-grip-trainer.md)
- [Player guide to the gorilla grip mechanic](https://github.com/Teuflum/tm-gorilla-grip-reverse-engineering/blob/main/outputs/gorilla_grip_player_guide.md)
- [Physics research](https://github.com/Teuflum/tm-gorilla-grip-reverse-engineering)

The supplied jump, announcer, failure, and results audio files are for local testing only. They are excluded from this repository. No game audio or impact sound is bundled.

## Development install

Copy the `plugin` folder to `OpenplanetNext/Plugins/GorillaGripTrainer` and load it through Openplanet. It requires VehicleState. On the tested Trackmania build, the physics widget labels smoothed steering and the separate stored slide mode, shows icing, and displays the contacted tire-force multiplier. An unset mode timestamp shows no timer; in air, the widget distinguishes the 400 ms delay from the possible recovery window through 800 ms and checks actual force on landing. The sampler reads memory only after checking the executable signature and active vehicle. On an unsupported executable signature, Openplanet shows an amber warning that the offsets need manual review, then the plugin unloads before initializing its trainer features.

Open Openplanet Settings → Gorilla Grip Trainer → Layout to drag or resize the seven HUD widgets, including the finish summary. Expand a widget to enter its position and size as screen percentages or toggle it. Display has the overall widget enable switch and the option to show widgets when the game HUD is hidden. Debug keeps `Openplanet.log` quiet by default: **Log trainer events** turns on the routine lines (contact snapshots, previews, verdicts, audio, history saves), and **Log every tire-force change** adds a line for each tire-force and force-gate change for research traces. Problems such as missing sounds or a damaged history file are always logged. The Rating tab lets you change the maximum lead time for each S–D grade; the limits stay ordered, and **Reset rating defaults** restores the timing and eligibility values. `S+` has no setting: it requires a confirmed switch-lead interval of exactly `0–0 ms`, uses S points and sounds, and appears separately in history and the finish summary. The single Grade widget shows a small provisional timing grade only for a newly committed opposite physics direction before takeoff. A normal same-direction transition has no grade. On landing it becomes a larger animated grade after the contacted tire force confirms the result. The recovery timer starts at the pre-takeoff switch, so a landing before the 400 ms delay has run out still counts: confirmation waits on the ground until the delay ends and the tire force starts rising. It does not need the full recovered value, which the game reaches by 800 ms at the latest. If gas was released while the car slid backwards, the game holds tire force at its base value until gas returns, and confirmation waits up to 1 s for that. S and S+ use the [original gorilla image](plugin/assets/GORILLA_ASSET.md). A failed confirmation (the landing changed the stored direction, landing steering pointed the other way, or force did not rise once it could) shows `MISSED`. If the last wheel leaves between sampled frames that cross a grade boundary, the HUD shows the lower possible rank with a `+` marker, such as `A+`. The underlying score and sound remain A; the actual timing may have qualified higher. The measured timing range is saved in history. `UNRATED` is reserved for lost physics reads or contact timing.

The **Combo** widget starts at x1 and shows the multiplier that the next successful landing will use. After that landing it advances for the following jump; a miss returns it to x1. The multiplier caps at x8. **Best Combo** shows the highest multiplier reached, while **Score** counts up and briefly shows the exact points earned by each grade, including combo and spin bonuses.

## Local sounds

Use **Open LocalSounds folder** at the top of the Sounds tab to place WAV, OGG, or MP3 clips in the Trainer's local storage, then click **Reload files**. Alternatively, run `py -3 tools/install_local_audio.py --source-dir <folder-containing-your-clips>`; add `--file filename.wav` one or more times to copy only selected files. The plugin still works visually if a clip is missing.

| Moment | Local file |
| --- | --- |
| Eligible reversal-attempt takeoff | `SP2_SND_GROUP_00000006.wav` |
| Failed landing | `SP2_SND_GROUP_00000002.wav` |
| Landing S/A/B/C/D defaults | `Sample_0064.wav` (Incredible), `Sample_0065.wav` (Amazing), `Sample_0063.wav` (Excellent), `Sample_0058.wav` (Nice), `Sample_0053.wav` (Good) |
| Confirmed finish | `WSR_Wakeboarding_Results.mp3` |

The announcer speaks only on a confirmed landing. Takeoff, S–D, Missed, and Finish each have an editable list of local sounds with individual volumes. When a list has multiple loaded sounds, playback selects one at random without repeating the previous choice. An empty row stays editable but is ignored during playback. The old single-file settings seed the new lists on first use. The **Sounds** tab has collapsible Takeoff, Grades, and Finish sections; Grades contains its S–D and Missed lists. Each row lets you type a filename or choose one from LocalSounds, adjust its volume, preview it, insert a row below with `+`, or remove it with `-`. **Reload files** and **Stop preview** are at the top. The full-width master slider scales all sounds, while each category and grade list has an enable switch. There is no landing impact cue.

The controlled in-game rating check is `py -3 tests/test_trainer_in_game.py --research-root <path-to-research-repo> --case all`. It requires Trackmania, TICK, the research repository's Gorilla Grip Logger, and **Log trainer events** enabled; the in-game tests stop with a hint when it is off.

## Run history

Open **Plugins → Gorilla Grip Trainer → Run history** or use **VIEW HISTORY** on a finish summary. The same submenu has **Enable widgets**, which controls the Display setting, and **Finish summary** when one is available. The history window lists finished runs, even if they have no rated jumps, and resets with verdicts. It has filters for map and status. Its compact attempt and jump tables show the essential results; selecting a jump reveals its timing, preview, spins, score, and reason. Data stays only in `PluginStorage/GorillaGripTrainer/history.json`; a previous valid file is kept as `history.backup.json` for recovery. At most 500 attempts are retained. Clear local history requires two clicks inside the window.

A true map finish opens a movable summary with finish time, score, best combo, separate colored S+–D grade counts, misses, and best/median successful switch lead. Its automatic appearance can be disabled in Display settings, and the summary can be hidden or reopened from the plugin menu. The local results track starts once on finish, loops while the finished run remains active, and stops on restart, map exit, or audio disable. Its row's **Play** button previews it once. The controlled TICK finish test temporarily turns off TICK's **Disable Finish** setting and restores it afterward; it requires `--case finish --finish-revision-id <known-finishing-revision>`.
