# Gorilla Grip Trainer

Standalone Openplanet trainer for the timing of a Trackmania ice-slide direction switch before takeoff. The current implementation reads the physics direction, previews a validated S–D switch in the air, and confirms the landing before changing score or combo.

- [Design specification](docs/superpowers/specs/2026-09-25-gorilla-grip-trainer.md)
- [Implementation plan](docs/superpowers/plans/2026-09-25-gorilla-grip-trainer.md)
- [Physics research](https://github.com/Teuflum/tm-gorilla-grip-reverse-engineering)

The supplied jump, announcer, failure, and results audio files are for local testing only. They are excluded from this repository. No game audio or impact sound is bundled.

## Development install

Copy the `plugin` folder to `OpenplanetNext/Plugins/GorillaGripTrainer` and load it through Openplanet. It requires VehicleState. On the tested Trackmania build, the physics widget shows the internal steering value, stored slide direction, icing, and the contacted tire-force multiplier. The sampler reads memory only after checking the executable signature and active vehicle; unsupported builds display `UNRATED`.

Open Openplanet Settings → Gorilla Grip Trainer → Layout to drag or resize the seven HUD widgets, including the finish summary. Each widget also has numeric position and size fields in screen percentages; all controls are visible in a scrolling list. The single Grade widget shows a small provisional timing grade only for a newly committed opposite physics direction before takeoff. A normal same-direction transition has no grade. On landing it becomes a larger animated grade after the contacted tire force confirms the result. S uses the [original gorilla image](plugin/assets/GORILLA_ASSET.md). A failed confirmation shows `MISSED`. If display sampling leaves the takeoff timing between grade regions, the Trainer chooses the lower possible grade, marks it **conservative**, and saves the measured timing range. `UNRATED` is reserved for lost physics reads or contact timing.

## Local sounds

Use **Open LocalSounds folder** at the top of the Sounds tab to place WAV, OGG, or MP3 clips in the Trainer's local storage, then click **Reload files**. Alternatively, run `py -3 tools/install_local_audio.py --source-dir <folder-containing-your-clips>`; add `--file filename.wav` one or more times to copy only selected files. The plugin still works visually if a clip is missing.

| Moment | Local file |
| --- | --- |
| Eligible reversal-attempt takeoff | `SP2_SND_GROUP_00000006.wav` |
| Failed landing | `SP2_SND_GROUP_00000002.wav` |
| Landing S/A/B/C/D defaults | `Sample_0064.wav` (Incredible), `Sample_0065.wav` (Amazing), `Sample_0063.wav` (Excellent), `Sample_0058.wav` (Nice), `Sample_0053.wav` (Good) |
| Confirmed finish | `WSR_Wakeboarding_Results.mp3` |

The announcer speaks only on a confirmed landing. Each S–D grade has an editable list of clips with individual volumes; when a list has multiple loaded clips, playback selects one at random without repeating the previous choice. An empty clip row stays editable but is ignored during playback. The current single-clip landing settings seed the lists on first use. The **Sounds** tab has compact collapsible sections for the jump chime, failed landing, S–D voice lists, and finish music. Each clip row lets you type a filename or choose one from LocalSounds, adjust its volume, and play a one-shot preview. **Stop preview** is at the top. The master slider scales all cues, while each category and grade list has an enable switch. There is no landing impact cue.

The controlled in-game rating check is `py -3 tests/test_trainer_in_game.py --research-root <path-to-research-repo> --case all`. It requires Trackmania, TICK, and the research repository's Gorilla Grip Logger.

## Run history

Open **Gorilla Grip Trainer run history** from the Openplanet plugin menu. The window starts closed. It lists attempts with verdicts, including resets, with filters for map and status. Selecting an attempt shows each jump's timing interval, provisional takeoff grade, landing verdict, combo, spins, points, score after landing, and reason. Data stays only in `PluginStorage/GorillaGripTrainer/history.json`; a previous valid file is kept as `history.backup.json` for recovery. At most 500 attempts are retained. Clear local history requires two clicks inside the window.

A true map finish opens a movable summary with finish time, score, best combo, colored S–D grade counts, misses, and best/median successful switch lead. Its automatic appearance can be disabled in Display settings, and the summary can be hidden or reopened from the plugin menu. The local results track starts once on finish, loops while the finished run remains active, and stops on restart, map exit, or audio disable. Its row's **Play** button previews it once. The controlled TICK finish test temporarily turns off TICK's **Disable Finish** setting and restores it afterward; it requires `--case finish --finish-revision-id <known-finishing-revision>`.
