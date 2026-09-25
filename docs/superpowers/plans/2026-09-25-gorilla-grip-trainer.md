# Gorilla Grip Trainer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a standalone, movable Gorilla Grip Trainer Openplanet plugin that grades physics direction-switch timing, confirms landings, plays local cues, records runs, and presents a finish summary.

**Architecture:** A validated read-only physics sampler produces timestamped snapshots. A transition tracker emits takeoff previews and landing verdicts; session/history state consumes only those events. Independent NanoVG widgets and optional Openplanet windows render the state, while an audio director plays local clips without influencing scores. The research repository supplies evidence and TICK automation but remains a separate project.

**Tech Stack:** Openplanet AngelScript, VehicleState, NanoVG, Openplanet UI/Audio/IO/Json APIs; Python 3 for local asset installation and TICK-driven integration checks; Git and GitHub CLI for release.

**Spec:** [Gorilla Grip Trainer design](../specs/2026-09-25-gorilla-grip-trainer.md)

## Global Constraints

- Current exact-memory build: executable SHA-256 `3FC7D8CDA542BEDA131C44306B123F4004D07D7E22F512B46B762AFC29F6EDDA`; keep the existing PE timestamp `0x6980d607` and image-size `0x2cba000` guards.
- Read Trackmania memory only; never write game memory or expose an inferred value as exact.
- Default eligibility: mean takeoff icing `>=0.65`, takeoff speed `>=50 km/h`, continuous airtime `>=100 ms`.
- Show a timing preview only for a new opposite stored mode committed with contact in the final `250 ms` before takeoff. Raw input reversal may trigger the jump cue but cannot earn a grade. With no preview, decide after landing: opposite steering plus delayed tire force is `MISSED`; a same-direction grip-preserving landing is ignored. Default grades: S `0–15 ms`, A `>15–35 ms`, B `>35–65 ms`, C `>65–110 ms`, D `>110–250 ms`; ambiguity or sample gap `>25 ms` is `UNRATED`.
- Final confirmation occurs about `80 ms` after visible contact; a successful mode must be at least `2 × model recovery delay` old at touchdown and the contacted multiplier must exceed `1.001x`.
- Supplied game WAV/MP3 files and run-history JSON stay local and are never staged or pushed. Only the new original impact sound may be committed.
- The Rater source and design documents have been removed from the research repository. Keep its installed local copy available until Trainer passes in-game checks; then disable its local installation.

## Review Focus

1. **No pre-takeoff physics reversal:** Task 2 leaves the preview empty, then distinguishes a same-direction grip-preserving landing (no event) from an opposite-direction delayed landing (`MISSED`). Task 4 plays no takeoff cue without a grounded input reversal; Task 5 saves no history row for the ordinary transition.
2. **Low display frame rate or a skipped physics sample:** a contact interval crossing a grade boundary produces `UNRATED`, never an unjustified S. Task 2 adds the TICK/log check and Task 3 exercises a frame-rate-limited run.
3. **Direction changes at first landing contact or shortly after:** freeze touchdown intent within 30 ms, then confirm the final mode and force at 80 ms. Task 2 tests the +13/+12 pair and post-contact reversal.
4. **Air voice still active at landing:** landing voice/impact takes priority, and the same file is never used in air and on landing. Task 4 checks the mapping and observes a short-flight game run.
5. **Run restart or map exit while history is open:** save one `RESET` attempt if it contains a rated jump; preserve already saved attempts across plugin reload. Task 5 tests duplicate prevention and persistence.
6. **Finish UI visited without a new local completion:** no duplicate summary or 30-second music, and a reset cannot trigger either. Task 6 tests Finish-state edges against the full 40.910 s replay and a reset.

## File map

| Path in this new repository | Responsibility |
| --- | --- |
| `plugin/info.toml`, `plugin/Main.as`, `plugin/Settings.as` | Plugin identity, lifecycle, shared settings |
| `plugin/Physics.as` | Guarded car pointer and exact snapshot reads |
| `plugin/Transitions.as` | Eligibility, contact bounds, S–D preview, landing confirmation, points |
| `plugin/Session.as` | Active run, combo, score, and per-jump records |
| `plugin/History.as`, `plugin/HistoryWindow.as` | Local versioned JSON and optional history browser |
| `plugin/Widgets.as`, `plugin/Layout.as` | Seven independent HUD widgets and Dashboard-style editor |
| `plugin/AudioDirector.as`, `plugin/assets/impact.wav` | Local cue loading and playback priority; original impact asset |
| `plugin/Finish.as` | Confirmed finish event, summary panel, one-shot results music |
| `tools/install_local_audio.py` | Copy only user-owned local clip paths into Openplanet plugin storage |
| `tests/test_trainer_in_game.py`, `tests/test_history_schema.py`, `tests/test_audio_manifest.py` | End-to-end physics checks and local-data/asset contract checks |
| `README.md`, `.gitignore` | Installation and publication boundary |

All plugin `.as` files live beside `Main.as`, matching Openplanet's multi-file script compilation pattern. Keep the user-visible name `Gorilla Grip Trainer` and the installed plugin folder `GorillaGripTrainer`.

## Task 1: Standalone plugin and exact physics snapshots

**Files:** Create `plugin/info.toml`, `plugin/Main.as`, `plugin/Physics.as`, `plugin/Settings.as`, `README.md`, `.gitignore`; inspect the retained local Rater installation or `git show 2299079:outputs/GorillaGripRater/Main.as` in the research checkout as the read-only starting reference.

**Interfaces:** `PhysicsSnapshot@ ReadPhysics(CSceneVehicleVisState@ vis, int gameTime)` produces `exact`, `gameTime`, `rawSteer`, `smoothedSteer`, `mode`, `modeAt`, `force`, `recoveryDelayMs`, four contact flags, mean icing, and speed. Later tasks consume only this snapshot, not raw pointers.

- [ ] **Step 1: Establish the safety baseline.** Save the current Rater source and its PE guards in a local comparison log, then run the existing research test once: `py -3 work/test_rater_in_game.py` from the research checkout. Record the observed +13/+12 verdicts; do not change TICK inputs here.
- [ ] **Step 2: Add the new plugin identity and source boundary.** Put this manifest in `plugin/info.toml`; keep the local audio storage directory outside the repo and ignore local data names:

  ```toml
  [meta]
  name = "Gorilla Grip Trainer"
  author = "Teuflum"
  category = "Race"
  version = "0.1.0"

  [script]
  dependencies = [ "VehicleState" ]
  ```

- [ ] **Step 3: Split and extend the exact sampler.** Preserve the Rater's `CSmPlayer+0x1118` pointer, PE signature, active-car position/raw-input checks, and safe-read ranges. Add the fields below after validation; return `exact=false` and no timing claim on any failed check:

  ```angelscript
  snap.modeAt = Dev::SafeReadUint32(vehicle + 0x14d8);
  snap.mode = int(Dev::SafeReadUint8(vehicle + 0x14e5));
  snap.force = Dev::SafeReadFloat(vehicle + 0x14dc);
  snap.rawSteer = Dev::SafeReadFloat(vehicle + 0xa0);
  snap.smoothedSteer = Dev::SafeReadFloat(vehicle + 0x1430);
  for (uint i = 0; i < 4; i++)
      snap.contact[i] = Dev::SafeReadUint32(vehicle + 0x17b4 + 0xb8 * i) != 0;
  snap.recoveryDelayMs = int(Dev::SafeReadUint32(model + 0x1194));
  ```

- [ ] **Step 4: Verify in game.** Install a copy as `OpenplanetNext/Plugins/GorillaGripTrainer`, reload it, and inspect the Openplanet log. On ANGULAR ↻ MOMENTUM the source must say `EXACT PHYSICS`; an invalid signature must say `ESTIMATE` without reading offsets. Log one compact snapshot at each contact transition, including `modeAt` and four contact bits. Compare the target +13 and +12 TICK runs with `work/analyze_phy_memory.py` in the research checkout.
- [ ] **Step 5: Commit the working sampler.** Stage only the new repo's manifest/source/docs/ignore file, run `git status --short`, and commit `Build guarded Gorilla Grip Trainer telemetry`.

## Task 2: Timing preview and confirmed landing verdict

**Files:** Create `plugin/Transitions.as`, `plugin/Session.as`, `tests/test_trainer_in_game.py`; modify `plugin/Main.as`, `plugin/Settings.as`.

**Interfaces:** `TransitionTracker::Update(PhysicsSnapshot@ snap)` emits a `JumpPreview` only for an observed recent opposite physics-mode switch, then emits at most one `JumpVerdict` after landing if the jump succeeds or an opposite-direction slowdown confirms a miss. `SessionState::Apply(JumpVerdict@ verdict)` owns combo, score, best combo, and the ordered event list. `JumpVerdict` contains `label`, `reason`, `leadMinMs`, `leadMaxMs`, `takeoffTime`, `landingTime`, `spinCount`, `points`, and `exact`. Add `rawSteer` to `PhysicsSnapshot` only for the optional takeoff cue; use `modeAt` and `mode` for grading.

- [ ] **Step 1: Write failing attempt and integration assertions.** Make `tests/test_trainer_in_game.py` run the existing `right_13_from_1126_through_1131` and `right_12_from_1126_through_1131` TICK variants through `work/auto_trials.py`, parsing only fresh Openplanet log output. Require one preview and one final S for +13; require **no preview** and one landing `MISSED` for +12. Add a TICK variant that keeps the current slide direction through takeoff and landing; assert zero preview, verdict, sound, score, or history jump. Add a no-presteer variant that changes to the opposite direction in air and lands with a delayed force update; assert no preview and one `MISSED` on landing. Before implementation, the new Trainer logs should be absent. Assert each verdict appears within 120 ms of visible landing. Run `baseline_right` separately for the first landing near 6.2 s.
- [ ] **Step 2: Detect only recent committed reversals for the preview.** Track the previous nonzero grounded mode and its observed transition to the opposite mode. Require the new `modeAt` to fall within the last 250 ms, with a contact sample proving the switch occurred before full airtime. Store the old and new modes, switch time, and contact interval. A raw-input reversal can mark a takeoff-cue candidate, but if no opposite mode commits, leave the timing preview blank. A stable old mode cannot produce D. Preserve the takeoff mode and landing-intent capture even for a flight with no preview, so the landing can still reveal a miss.
- [ ] **Step 3: Implement bounded timing.** On the final grounded snapshot and first all-air snapshot, calculate `leadMinMs = max(0, lastContactGameTime - modeAt)` and `leadMaxMs = firstAirGameTime - modeAt`. Require `modeAt <= firstAirGameTime`, `0 <= leadMinMs <= leadMaxMs`, `firstAirGameTime-lastContactGameTime <= 25`, and both leads in the same configured grade region. In the measured +13 run, the last contact sample was game clock `6,771,501 ms`, modeAt was `6,771,510 ms`, and the first all-air sample was `6,771,512 ms`; the valid lead interval is `0–2 ms`. Use explicit boundaries, for example:

  ```angelscript
  string GradeLead(int lo, int hi) {
      if (lo < 0 || hi < 0) return "UNRATED";
      if (lo <= 15 && hi <= 15) return "S";
      if (lo > 15 && hi <= 35) return "A";
      if (lo > 35 && hi <= 65) return "B";
      if (lo > 65 && hi <= 110) return "C";
      if (lo > 110 && hi <= 250) return "D";
      return "UNRATED";
  }
  ```

- [ ] **Step 4: Implement one landing confirmation path.** Freeze the first contact steering direction, accepting the first non-neutral physics update within 30 ms. At 80 ms, a previewed jump applies the spec's contact, mode-match, unchanged `modeAt`, `ageAtTouchdown >= 2 * recoveryDelayMs`, landing icing, and `force > 1.001f` checks. With no preview, emit `MISSED` only when landing steering is opposite the frozen takeoff mode and the exact contact force update falls near `1.00x`; otherwise emit nothing. An inexact or ambiguous landing gives `UNRATED` in diagnostics and no score event. Apply points only for S–D:

  ```angelscript
  if (verdict.label == "MISSED") { combo = 0; misses++; }
  else if (verdict.label != "UNRATED") {
      combo++; hits++;
      score += BasePoints(verdict.label) * Math::Min(combo, 8)
             + 50 * verdict.spinCount;
      bestCombo = Math::Max(bestCombo, combo);
  }
  ```

- [ ] **Step 5: Run the physics regressions.** The +13/+12 pair must separate as preview S/final S versus blank preview/final MISSED; the same-direction jump must emit no event; a no-presteer opposite-direction landing must emit MISSED without an air preview. The baseline's 6.2 s landing must show no later than 120 ms after contact; the post-contact reversal must not rewrite frozen touchdown steering. Feed a short hop and a sampled gap above 25 ms; both must be `UNRATED` with no score change. Verify a 20 ms early exact switch gives A, and a stored mode older than 250 ms cannot receive D. Log the lead interval and why any case is ungraded.
- [ ] **Step 6: Commit the rating engine.** Stage only `plugin/Transitions.as`, `plugin/Session.as`, touched entry/settings files, and the regression script; commit `Grade pre-takeoff physics timing and landing result`.

## Task 3: Independent HUD widgets and drag editor

**Files:** Create `plugin/Widgets.as`, `plugin/Layout.as`; modify `plugin/Main.as`, `plugin/Settings.as`; add layout checks to `tests/test_trainer_in_game.py`.

**Interfaces:** `WidgetLayout` holds `id`, normalized `pos`, pixel `size`, and `visible`; `RenderWidgets(SessionState@ state, PhysicsSnapshot@ snap)` only reads state; `RenderInterface()` draws edit outlines when the Layout tab is open. Widget IDs: `diagnostics`, `timing`, `result`, `combo`, `score`, `best`, `last`.

- [ ] **Step 1: Add a failing layout persistence check.** Record default widget rectangles, change one widget's saved position and size through Openplanet settings, reload, and compare the restored rectangle within 2 screen pixels. Repeat at the user's display size and a second resolution; no rectangle may extend off screen.
- [ ] **Step 2: Render each widget separately.** Move the existing diagnostics and animated grade drawing out of the Rater's single 500×231 canvas. Use the existing centered grade animation for `result`, and smaller S–D text for `timing`; leave the timing widget empty when no opposite physics mode committed before takeoff. Give combo, score, best combo, and last run their own small cards. In air, diagnostics show `MODE AGE` and `READY ON CONTACT`; on ground they show the exact multiplier. Nothing in rendering may call `SessionState::Apply`.
- [ ] **Step 3: Add Dashboard-style layout mode.** The Layout settings tab sets an edit flag; `RenderInterface` creates a movable/resizable UI window over every visible NanoVG widget, then writes normalized positions and sizes back to hidden settings. Show sample content for normally transient widgets. Follow the proven pattern in Dashboard's `Source/SettingsWidgets.as`:

  ```angelscript
  vec2 screen = Display::GetSize();
  vec2 pos = widget.pos * (screen - widget.size);
  UI::SetNextWindowPos(int(pos.x / UI::GetScale()), int(pos.y / UI::GetScale()), UI::Cond::Appearing);
  UI::SetNextWindowSize(int(widget.size.x / UI::GetScale()), int(widget.size.y / UI::GetScale()), UI::Cond::Appearing);
  UI::Begin(widget.name, UI::WindowFlags::NoCollapse | UI::WindowFlags::NoSavedSettings);
  widget.size = UI::GetWindowSize();
  widget.pos = UI::GetWindowPos() / (screen - widget.size);
  UI::End();
  ```

- [ ] **Step 4: Guard the edges.** Clamp normalized position and minimum size on load and resize; add show/hide and individual/reset-all buttons. Ensure the edit windows exist only while Layout is open and do not capture mouse input during play. Check grade popups at center and screen edges, the result animation at multiple scales, and the ICE text alignment.
- [ ] **Step 5: Commit the layout.** Commit `Add movable Gorilla Grip Trainer widgets` after a clean Openplanet reload and layout persistence check.

## Task 4: Local audio cues and an original impact

**Files:** Create `plugin/AudioDirector.as`, `plugin/assets/impact.wav`, `tools/install_local_audio.py`, `tests/test_audio_manifest.py`; modify `plugin/Main.as`, `plugin/Settings.as`, `README.md`, `.gitignore`.

**Interfaces:** `AudioDirector::OnTakeoffCue()`, `OnPreview(JumpPreview@)`, `OnAirCall(JumpPreview@)`, `OnVerdict(JumpVerdict@)`, `OnFinish()`, and `StopTransient()` consume events; the director never changes a verdict. `OnTakeoffCue` requires a recent grounded raw-input reversal and the 100 ms flight filter; `OnAirCall` requires a real S–D preview. Clips live in `IO::FromStorageFolder("LocalSounds/<basename>")`; only the original `impact.wav` is packaged.

**Exact local cue map:** Takeoff is `SP2_SND_GROUP_00000006.wav` after an eligible grounded raw-input reversal; a missed landing is `SP2_SND_GROUP_00000002.wav`, even if there was no takeoff preview. Air S chooses `Sample_0061.wav` or `Sample_0051.wav`, A chooses `Sample_0059.wav` or `Sample_0050.wav`, B/C chooses `Sample_0060.wav` or `Sample_0052.wav`, and D uses `Sample_0055.wav`. Landing S uses `Sample_0064.wav` (Incredible), A uses `Sample_0065.wav` (Amazing), B uses `Sample_0063.wav` (Excellent), C uses `Sample_0058.wav` (Nice), and D uses `Sample_0053.wav` (Good). A true finish plays `WSR_Wakeboarding_Results.mp3`. No user-supplied file enters Git.

- [ ] **Step 1: Write a failing manifest test.** `tests/test_audio_manifest.py` asserts that airborne file IDs `{0061,0051,0059,0050,0060,0052,0055}` and landing IDs `{0064,0065,0063,0058,0053}` are disjoint; it checks all twelve expected base names, the two SP2 cues, the results MP3, and that `git ls-files` contains none of those supplied media files.
- [ ] **Step 2: Add local-only installation.** `tools/install_local_audio.py --source-dir <folder>` checks all fifteen supplied files, copies them to the Openplanet `GorillaGripTrainer/LocalSounds` storage directory, and prints missing names without downloading anything. The repository's `.gitignore` covers `local_audio/`, `SP2_*.wav`, `Sample_*.wav`, `WSR_*.mp3`, and local history. Put the file-to-event table from the spec in `README.md`.
- [ ] **Step 3: Load and play samples.** At plugin start, use `IO::FromStorageFolder` and `Audio::LoadSample`; retain `Audio::Sample@` handles. `Audio::Play(sample, gain)` returns an `Audio::Voice@`; keep the active air/result voices so their gain can be set to zero when landing or a restart takes priority. Missing files log once per slot and leave visuals functional:

  ```angelscript
  string path = IO::FromStorageFolder("LocalSounds/" + fileName);
  if (IO::FileExists(path)) @sample = Audio::LoadSample(path);
  if (sample !is null) @voice = Audio::Play(sample, gain);
  ```

- [ ] **Step 4: Generate the new impact and wire the sequence.** Synthesize a short original low thud plus bright icy transient with a small Python generator, save only its generated `plugin/assets/impact.wav`, and document how to regenerate it. At 100 ms continuous flight after an observed grounded input reversal play `SP2...06`; at 350 ms play an air call only if an S–D timing preview exists, from its allowed pool without immediate repetition. At confirmed landing mute any remaining air call, then play impact plus S=`0064`, A=`0065`, B=`0063`, C=`0058`, D=`0053`; for `MISSED` play only `SP2...02`. Provide independent volume settings for each cue category.
- [ ] **Step 5: Verify actual audio.** Reload in Openplanet and play the 6.2 s and 12.58 s jumps plus a stable same-direction jump and a no-presteer opposite-direction miss. Confirm the ordinary jump is silent and the no-presteer miss has only the failure cue on landing; confirm no air/landing file identity reuse, no two announcer calls competing at landing, no failure impact, and no repeated cue on a tiny bounce. Ask the user to judge the audible balance once; adjust gains from that listening result. Run `py -3 tests/test_audio_manifest.py` and stage no supplied sound files.
- [ ] **Step 6: Commit.** Commit `Add local-only jump and announcer audio` with the original impact and source only.

## Task 5: Persistent run history and history window

**Files:** Create `plugin/History.as`, `plugin/HistoryWindow.as`, `tests/test_history_schema.py`; modify `plugin/Session.as`, `plugin/Main.as`.

**Interfaces:** `HistoryStore::Append(RunRecord@ run)` writes a version-1 JSON array of at most 500 runs; `HistoryStore::Load()` validates or recovers local data; `RenderHistoryWindow()` reads the store and never mutates scoring. A `RunRecord` contains map ID/name, start time, status, finish time if present, score, best combo, grade counts, and ordered `JumpVerdict` records.

- [ ] **Step 1: Write a failing schema test.** Create a synthetic history file with one finished run and one reset run. `tests/test_history_schema.py` must require version 1, one unique run ID per attempt, ordered jump times, numeric lead bounds, known labels `S/A/B/C/D/MISSED`, and no more than 500 attempts after pruning. Include a malformed file case that must be preserved for recovery rather than silently erased.
- [ ] **Step 2: Save runs exactly once.** On confirmed finish mark `FINISHED`; on restart, map change, or leaving play mark `RESET`. Save only runs with at least one final rated S–D/MISSED event. Use `Json::ToFile(IO::FromStorageFolder("history.json"), root)` with a backup of the previous valid data before replacement; load the backup when the primary is malformed and report the recovery in the log. Generate a stable per-run ID from local start time, map UID, and an incrementing sequence.
- [ ] **Step 3: Build the optional history window.** It starts closed, opens from the plugin menu, shows one attempt per row, and filters by map and `FINISHED/RESET`. Selecting a row shows jump time, lead interval, timing preview, final grade/reason, combo, and points. Implement clear-history as a two-click in-window confirmation affecting only the local storage file.
- [ ] **Step 4: Verify persistence.** Run a rated jump then restart twice; history gains exactly two `RESET` rows, not extra rows from reload. Finish a replay and check one `FINISHED` row. Reload plugin and game: rows persist, filter and detail view work, malformed JSON falls back to backup, and the current run remains independent of the history window.
- [ ] **Step 5: Commit.** Commit `Record and browse Gorilla Grip Trainer attempts` after schema and in-game checks.

## Task 6: True-finish summary and results music

**Files:** Create `plugin/Finish.as`; modify `plugin/Main.as`, `plugin/AudioDirector.as`, `plugin/Layout.as`, `plugin/Settings.as`, `tests/test_trainer_in_game.py`.

**Interfaces:** `FinishController::Update(int raceTime, bool hasLocalRun, int mapUidHash, bool finishSequence)` emits `OnFinish` once for the current attempt. `RenderFinishSummary(RunRecord@)` uses the same editable position/size contract as other widgets. `AudioDirector::OnFinish()` plays the local MP3 only on that event.

- [ ] **Step 1: Write failing finish/reset assertions.** Extend the in-game test to complete the baseline 40.910 s TICK replay and require one `FINISHED` history row, one summary event, and one results-music event. Restart near 12.8 s and require a `RESET` row with zero summary/music events. Re-enter the finish UI without a new run and require no duplicate.
- [ ] **Step 2: Detect the explicit game finish edge.** Use `CurrentPlayground.GameTerminals[0].UISequence_Current == CGamePlaygroundUIConfig::EUISequence::Finish` together with a valid local active run and stable map UID. Record the finishing race time from the local script player; latch the attempt ID so repeated finish frames emit once. If the terminal or player is absent, do not infer finish from a clock reset.
- [ ] **Step 3: Render the summary and control the music.** Show map, finish time, score, best combo, five grade counts, misses, and best/median successful lead. Handle an all-miss run with dashes for the timing statistics. Keep the summary open until dismissed or a new run/map; provide auto-show toggle and independent layout settings. Play `WSR_Wakeboarding_Results.mp3` once, at a configurable gain, and mute/fade the voice on restart, map exit, or audio disable.
- [ ] **Step 4: Verify in game.** Check the finish panel does not obstruct the game's essential finish controls at the default position; move/resize it in Layout and reload. Listen for one music start on a true finish and silence on reset. Confirm opening Run History does not replay music.
- [ ] **Step 5: Commit.** Commit `Show finish results and play local results cue` after the finish/reset regression passes.

## Task 7: Release the Trainer and verify the repository split

**Files:** Modify new repo `README.md` and `.gitignore`; preserve the already cleaned research repository's physics report and TICK tools.

- [ ] **Step 1: Complete the acceptance run.** Run `py -3 tests/test_audio_manifest.py`, `py -3 tests/test_history_schema.py`, and `py -3 tests/test_trainer_in_game.py --research-root <research-checkout>`. Reload Openplanet and inspect script errors; verify +13 S, +12 MISSED, an ambiguous sample UNRATED, true finish versus reset, audio priorities, history persistence, and widget positions at two display sizes.
- [ ] **Step 2: Install the verified Trainer.** Copy `plugin/` to `OpenplanetNext/Plugins/GorillaGripTrainer` and copy supplied audio only into the Trainer's local Openplanet storage folder. Disable/remove the old installed `GorillaGripRater` after the new HUD runs cleanly, so duplicate widgets and audio cannot occur.
- [ ] **Step 3: Audit the new repository.** `git status --short`, `git ls-files`, and `git diff --cached --stat` must show source, docs, tests, and only the original generated impact WAV. Check for `SP2_`, `Sample_`, `WSR_`, `.exe`, `.Gbx`, raw dumps, telemetry CSVs, and local history before pushing. Commit `Release Gorilla Grip Trainer`.
- [ ] **Step 4: Check the repository split again.** Confirm the research repository still contains the mechanism report and TICK tools, and its README points to `https://github.com/Teuflum/Gorilla-Grip-Trainer`. Confirm this repository contains the Trainer code and planning documents with no supplied media or copied game binary. Run `node --test graphs/model.test.js` in the research checkout if the report or graph model changed during implementation.
- [ ] **Step 5: Publish without overwriting remote work.** Inspect the Trainer remote branch first. Integrate any intervening commits before pushing. Push the verified Trainer main branch to `https://github.com/Teuflum/Gorilla-Grip-Trainer.git`; verify its remote head and the absence of supplied audio in GitHub's file list.

## Execution handoff

The user asked for this spec and plan before implementation. Review the plan and select **Native** execution in this task or **subagent-driven** execution. Native is recommended because the timing, audio, history, and finish modules all consume the same event contract and need frequent in-game checks against one running Trackmania session. Begin implementation only after the plan review.
