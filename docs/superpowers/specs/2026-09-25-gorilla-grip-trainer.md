# Gorilla Grip Trainer design

## Purpose and ownership

Gorilla Grip Trainer is a standalone Openplanet plugin for practicing icy-tire jumps. It rates **when the physics engine commits the intended slide direction before the last wheel leaves**, confirms the result on landing, and records attempts for review. Its source belongs in `Teuflum/Gorilla-Grip-Trainer`. The separate `tm-gorilla-grip-reverse-engineering` repository remains the source for the physics report and controlled evidence; the old Gorilla Grip Rater plugin is removed from that repository when the Trainer is ready to replace it locally.

The plugin is a trainer, not a speedometer or a claim that one multiplier alone determines acceleration. It reads game memory but never writes it. Build-specific exact reads must pass the existing executable and active-car checks. An unsupported build or uncertain contact sample shows `UNRATED` with a reason; it must never advertise a frame-perfect grade from an estimate.

## Player experience

| Moment | Display | Audio |
| --- | --- | --- |
| 100 ms of eligible continuous airtime | Small `S TIMING` through `D TIMING` preview, or `SETUP MISSED`; no points yet | Local `SP2_SND_GROUP_00000006.wav` jump cue for every eligible jump |
| 350 ms of continuous airtime, if the timing preview is S–D | Preview remains; diagnostics show direction-mode age/readiness | One short airborne call from the preview's tier |
| About 80 ms after first landing contact | Large animated final S–D or `MISSED`; combo and score settle once | Success: original impact plus grade-specific landing call. Miss: local `SP2_SND_GROUP_00000002.wav`, with no success call or impact |
| Confirmed map finish | Optional finish summary; run enters history as `FINISHED` | Local `WSR_Wakeboarding_Results.mp3` plays once |
| Restart or map exit after at least one rated jump | Attempt enters history as `RESET`; active score and combo reset | Stop finish music; no finish summary |

A 100 ms minimum flight suppresses tiny bounces. The takeoff cue is delayed until that minimum has passed, so it still feels attached to takeoff without playing for an unrated hop. The 350 ms air call is skipped when landing happens sooner. Landing audio has priority: if an air voice is still playing, stop or quickly fade it before the landing effect. The visual result must appear when the verdict is ready, independent of audio duration.

## Timing and success rules

The exact source is the active physics vehicle's smoothed steering (`vehicle+0x1430`), stored direction (`+0x14e5`), mode-change game timestamp (`+0x14d8`), and stored force multiplier (`+0x14dc`) on the tested build. The vehicle-model recovery delay is `400 ms` in the tested build. The plugin also samples all four wheel-contact flags and their icing values. Average takeoff icing of at least `0.65` and speed of at least `50 km/h` make a jump eligible by default; these are configurable *rating filters*, not universal slide thresholds. The surface material is not itself an eligibility filter, so icy tires can be evaluated on non-ice takeoff material.

At first all-wheel airtime, freeze the pre-takeoff mode and the latest exact mode-change timestamp. Use the last contact sample and first all-air sample, both on the same game clock, to bound the time between the committed direction switch and last-wheel departure. Calibrate that clock and the contact samples against the existing controlled TICK +13/+12 variants. If the sampling gap exceeds `25 ms`, or the possible lead interval crosses a grade boundary, display `TIMING UNVERIFIED` and do not score that transition. This allows lower frame rates to receive unambiguous grades without pretending that an uncertain last-wheel tick was observed.

Use these default timing regions after calibration. The grade depends only on switch timing, never on how close the force field is to `2.0x`:

| Physics switch lead before last-wheel departure | Preview and successful final grade | Base points |
| --- | --- | ---: |
| 0–15 ms | S | 150 |
| >15–35 ms | A | 120 |
| >35–65 ms | B | 90 |
| >65–110 ms | C | 60 |
| >110 ms | D | 30 |

A switch after the last contact opportunity, no committed direction, or a negative lead produces `SETUP MISSED`. A previously committed matching direction with an old timestamp can still produce successful grip but receives D for timing. The 10 ms physics tick and display sampling mean S represents the final contact opportunity within the validated interval; do not claim sub-tick precision.

Capture the landing steering direction at first visible contact, allowing at most `30 ms` for the first grounded physics update. Roughly `80 ms` after visible contact, confirm all of the following: the car is still in contact; the frozen takeoff mode matches the captured landing steering direction; the stored mode has not switched on landing; the mode-change age at touchdown has reached twice the model recovery delay; landing icing remains above the configured minimum; and the contacted-wheel force multiplier is above `1.001x`. The small force floor is corroboration that the contact branch updated, not a grade threshold. If any confirmation fails, final result is `MISSED`, with a plain diagnostic reason in the log and history. If the exact read disappears or contact timing is ambiguous, final result is `UNRATED` and does not affect combo, score, success counts, or miss counts.

Only confirmed S–D results earn points or extend the combo. A confirmed `MISSED` gives zero points and breaks the combo. Award `base points × min(combo, 8)` plus `50` points per complete airborne spin, while keeping spin points separate from the timing grade. The preview never changes score. Preserve the existing per-run best combo and previous-run summary semantics.

During airtime, diagnostics show elapsed time since the committed mode change and a readiness cue: the first 400 ms is waiting; 400–800 ms is recovery; after 800 ms it is `READY ON CONTACT`. These are timer states, not a claim that a force already exists in the air. On contact, show the actual multiplier. The 400 ms value is read from the validated vehicle model when possible, with the tested build's value used only for this build.

## Modular display and editing

One shared state machine feeds these independently placed widgets: (1) compact diagnostics containing steering, ±10% gate, direction, icing, and timer/force; (2) takeoff timing preview; (3) large animated landing result; (4) combo; (5) score; (6) best combo; and (7) last run. A separate finish-summary panel appears only after a true finish. The optional Run History is an Openplanet window, not a gameplay widget.

The `Layout` settings tab uses the interaction pattern of Dashboard: each enabled widget receives a visible edit outline, title, drag handle, and resize corner while the tab is open. Popups display sample content there so they can be placed without replaying a jump. During play, NanoVG draws the widgets without hit boxes or mouse capture. Save each widget's normalized screen position, independent width/height or scale, and visibility. Clamp restored positions to the visible screen after resolution changes. Provide per-widget reset plus reset-all, and separate show/hide settings. Keep settings for ratings and audio in their own tabs. The default layout puts diagnostics low and central, the timing preview just above it, the result near screen center, and scoring widgets near the sides; users can move every unit.

## Run history and finish summary

Store up to the newest `500` attempts in a local versioned JSON file in Openplanet plugin storage. No history is uploaded or checked into Git. A run contains map UID/name, local start timestamp, status (`FINISHED` or `RESET`), finish race time when present, final score, best combo, grade counts, and an ordered jump list. Each jump records takeoff and landing race times, direction-switch lead interval in milliseconds, preview grade, final verdict and reason, combo and score after landing, and complete-spin bonus. Save an attempt when it ends if it has at least one rated jump; an `UNRATED` diagnostic alone does not create a history entry. A restart, map change, or leaving play closes an unfinished rated attempt as `RESET` exactly once.

The optional Run History window starts closed. It lists attempts with map, date, status, finish time, score, best combo, and success/miss counts. It filters by map and status; selecting an attempt shows the ordered jump timings and grades. The window can be opened from the plugin menu, resized, and closed without affecting play. A clear-history command requires an in-window confirmation and changes only local trainer data.

The finish summary appears once when the local player's game state enters a confirmed finish state, never merely because the race clock resets. It shows map name, finish time, final score, best combo, S/A/B/C/D/MISSED counts, and best and median successful switch lead. It can be dismissed and has a setting to disable automatic appearance. It stays available until dismissed, restart, or map change. The 30-second local results track plays only for this true-finish transition, has its own volume setting, and stops or fades when a new run begins or the map changes. Reopening history must not replay it.

## Audio assets and local-only boundary

All user-supplied WAV/MP3 files are local test assets. The public repository contains only source, asset-name documentation, tests, and any newly created original impact sound. A local install step copies the supplied files from a user-selected source folder to the Trainer's Openplanet storage folder. Missing files disable only their own cue; the plugin remains usable and logs one clear load warning per missing slot. Separate controls cover jump cue, air voice, landing voice, failure cue, impact, and results music volumes.

| Cue | Grade or timing | Local file |
| --- | --- | --- |
| Jump cue | All eligible takeoffs | `SP2_SND_GROUP_00000006.wav` |
| Failed landing | MISSED only | `SP2_SND_GROUP_00000002.wav` |
| Air, high tier | S: `Great Air` or `Wow!` | `Sample_0061.wav`, `Sample_0051.wav` |
| Air, high tier | A: `Looks Great` or `Woah!` | `Sample_0059.wav`, `Sample_0050.wav` |
| Air, middle tier | B/C: `Nice Jump` or `Yeah!` | `Sample_0060.wav`, `Sample_0052.wav` |
| Air, encouraging | D: `Keep it up` | `Sample_0055.wav` |
| Landing | S: `Incredible` | `Sample_0064.wav` |
| Landing | A: `Amazing` | `Sample_0065.wav` |
| Landing | B: `Excellent` | `Sample_0063.wav` |
| Landing | C: `Nice` | `Sample_0058.wav` |
| Landing | D: `Good` | `Sample_0053.wav` |
| Results | Confirmed finish only | `WSR_Wakeboarding_Results.mp3` |

Choose among same-tier airborne variants without immediate repetition. No file appears in both the airborne and landing pools. All supplied WAVs are mono 16-bit at 22,050 Hz for the announcer files; the longest airborne clip is `1.266 s`, so landing priority is required. The result track is approximately 30 seconds. The impact cue is an original short sound generated for this plugin and may be committed. Do not copy or redistribute Nintendo game extracts in either Git repository.

## Architecture and verification

Split the current single-file Rater into a read-only physics sampler, transition/rating state machine, run-history store, audio director, widget layout/renderers, and history/finish windows. The entry point wires them together; presentation never determines the grade. Keep VehicleState as the only plugin dependency. Use Dashboard's public widget interaction as a reference for edit mode, but do not require Dashboard at runtime.

Verify against the known +13 instant and +12 delayed TICK variants, the first 6.2 s landing, a deliberate post-contact steering reversal, short hops, and an unsupported executable signature. Also verify a true finish versus a reset, one-shot music, history persistence across plugin reload, on-screen widget placement at the user's resolution and a second resolution, local-only asset handling, and that air and landing voice pools never overlap by file identity. Publish only after the new Trainer passes these checks; then remove the tracked Rater source and its obsolete design/plan from the research repository, update its README to link to the Trainer repository, and push both repositories. Keep the installed Rater until Trainer verification is complete, then disable/remove it locally so only one HUD runs.
