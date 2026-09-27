# Tick-exact timing

## Purpose

Trackmania's physics is deterministic, but the Trainer samples it once per
rendered frame. At low frame rates, or with TICK running the game faster,
one frame covers 50 ms or more of game time. The takeoff is then only known
to lie somewhere inside that gap, so the same replay gets a worse
conservative grade (`A+`) or `UNRATED` depending on the frame rate.

After this change, one TICK replay produces the same grade, lead in
milliseconds, reason, spin count, and score at any frame rate and game
speed. The Trainer stays read-only: it reads timestamps the physics engine
already stores instead of hooking game code.

Grade limits, points, combo rules, audio, popup, and widgets do not change.
The work happens on the branch `tick-exact-timing`.

## Decisions

- **Approach:** read the engine's own timestamps (per-wheel contact changes
  and the stored-mode switch). A hook into the physics tick (`Dev::Hook`) is
  held back as a fallback, researched only if a remaining estimate turns out
  to matter or stage 0 disproves the timestamps.
- **Scope:** everything that decides a result is exact: takeoff tick, switch
  tick, lead, grade, landing tick, landing direction, force check, verdict.
  The takeoff cue, the late-reversal lead in a miss reason, the slide window,
  and spin counting become safe against frame gaps; they are estimates that
  never decide a grade.
- The landing direction comes from the stored mode, not from the steering
  seen on the first grounded frame (see *Landing*).
- `A+`, the lead range, and the 50 ms sample-gap rule go away.
- Version 0.3.0.

## Evidence so far

Each wheel's block in the physics car (`vehicle + 0x17b4 + 0xb8·i`, where
`+0x0` is the contact flag) holds a 32-bit game-clock timestamp at `+0x6c`,
that is `vehicle + 0x1820 + 0xb8·i`. In all eight takeoff captures in the
research repository (`Analysis/work/memory_takeoff_*.bin`), every change of a
wheel's contact flag wrote the current game clock to that wheel's timestamp.
Twice a wheel lifted between samples 30–40 ms apart, and the timestamp still
held the exact tick inside the gap. The clock is the one `modeAt`
(`vehicle + 0x14d8`) and `PlaygroundClientScriptAPI.GameTime` use.

At the first all-air sample, the latest wheel timestamp equals that sample's
clock, and in the gorilla-grip captures `modeAt` equals it too: the mode
switched on the tick the last wheel left, which today's rule already grades
as a 0 ms lead (S+).

Open points for stage 0:

- In one capture (`jump3_left_*`), front-left's timestamp moved again one
  tick after takeoff while all four flags read zero. It may be a touch and
  lift inside one tick. The captures stop right after takeoff, so flight and
  landing behaviour is unmeasured.
- No angular-velocity field is documented yet.

## Stage 0: live check

Before any rating code changes:

1. A temporary developer-mode trace logs, on each frame where any contact
   flag or wheel timestamp changes: game clock, the four flags, the four
   timestamps, `mode`, `modeAt`, and the 0x40 bytes after the position
   (`vehicle + 0x538`).
2. One TICK replay of a known gorilla-grip revision runs three times: 1× at
   the normal frame rate, 4× game speed, and 1× with the Trainer processing
   every 5th frame (see *Testing*). The user's game speed and revision are
   restored afterwards.
3. Check that each timestamp changes exactly once at lift-off and once at
   touchdown with identical values across the three runs; explain the
   one-tick update seen above; and look for an angular-velocity vector whose
   vertical part matches the frame-to-frame yaw change.

Go on with this design if the timestamps agree across the runs. If they
misbehave in flight or on landing, stop and research the hook. If no angular
velocity is found, spins use the fallback in *Spins*. The trace is then
removed or folded into the existing snapshot debug line.

## Takeoff, switch, and grade

`PhysicsSnapshot` gains `wheelChangedAt[4]`, read from the four timestamps.

- **Takeoff tick.** On the first frame with all four wheels airborne,
  takeoff is the latest of the four timestamps. It is valid only if it lies
  after the previous frame's clock and at or before the current one, and
  every wheel that was grounded in the previous frame has a timestamp in
  that interval. Otherwise the flight is uncertain, and a flight that would
  have been rated becomes `UNRATED` with the reason "Contact timestamps were
  inconsistent at takeoff".
- **Race times.** Takeoff race time is `raceTime − (gameTime − takeoffTick)`
  of the first all-air frame. It feeds the minimum flight time, popup, and
  history.
- **Switch.** Still `modeAt`. The switch is recorded when a grounded frame's
  mode differs from the previous frame's and `modeAt` lies in
  `(previous.gameTime, gameTime]`; the 50 ms gap condition is dropped. The
  old direction is the previous frame's mode and must be the opposite
  direction, not neutral, as today.
- **Lead and grade.** Lead is `takeoffTick − modeAt`, one number graded with
  the existing limits (0 ms is S+).
- **Removed:** `MAX_TIMING_SAMPLE_GAP`, the "contact sample gap exceeded
  50 ms" `UNRATED`, the lead range, the conservative `A+` grade, and
  `timingEstimated`. History keeps `leadMinMs`, `leadMaxMs`, and the
  estimated flag so older files load; new entries store the same value in
  both lead fields and never show `A+`.

## Landing

- **Landing tick.** On the first grounded frame after a flight, landing is
  the earliest timestamp, newer than the takeoff tick, among the grounded
  wheels. Landing race time is derived as for takeoff.
- **Touches in flight.** A timestamp that changes after takeoff while every
  wheel reads airborne means a wheel touched and lifted between frames. It
  counts like today's brief touch before the landing (`landingTouchLifted`),
  so a low frame rate cannot hide it. If stage 0 shows the one-tick update
  above is such a touch, it is contact, and the takeoff tick is the last
  lift-off after it.
- **Landing direction.** The engine's stored state decides:
  - *confirmed* when the stored mode and `modeAt` are unchanged at the check
    tick and force was eligible;
  - *opposite* (`MISSED`) when `modeAt` changed between the takeoff tick and
    the check tick.

  Behaviour change: a landing with neutral steering during the first 30 ms
  that then steers the matching way used to be `MISSED`; it is now confirmed,
  because the stored direction held and the tires keep their grip. A neutral
  landing held until the game clears the mode (300 ms) still ends as a miss
  once the direction is stored again.
- **Check tick.** Force becomes eligible at the later of the first front
  wheel's touchdown timestamp and `modeAt + recovery delay`. The check tick
  is the later of `landing + 80 ms` and `eligible + 30 ms`. The verdict is
  resolved on the first frame at or after the check tick, using the state at
  that tick:
  - a mode switch whose `modeAt` is after the check tick is ignored;
  - the force reading (above `1.001×`) is checked only while the stored mode
    is still unchanged; if a later switch reset the force, the tick rule
    decides.
- **Still sampled per frame:** the backwards-motion flag (`vehicle + 0x1600`)
  has no timestamp. While a frame shows it set, eligibility restarts at that
  frame. The 1000 ms "force never eligible" timeout is measured from the
  exact ticks.
- The no-preview miss rule (opposite landing or stored switch after the
  landing, enough icing, force at most `1.1×`) keeps working on the same
  stored state.

## Estimates that never decide a grade

- **Takeoff cue and late-reversal reason.** When a grounded frame first shows
  the raw steering reversed, the reversal tick is estimated from how far the
  smoothed steering has moved toward the new side since the previous frame,
  at 0.2 per 10 ms tick, counted back from the current frame and clamped to
  `(previous.gameTime, gameTime]`. If the smoothed steering has already
  reached the new raw value, the estimate is the earliest tick after the
  previous frame. The cue plays when the estimate is at most 250 ms before
  the exact takeoff tick; the "Steering reversed N ms before takeoff" reason
  uses the same number.
- **Slide window.** A sliding frame counts as sliding up to the next frame
  that shows no slide. The 500 ms window is measured to the exact takeoff
  tick. At low frame rates this errs toward accepting a jump.
- **Spins.** With an angular velocity `ω` from stage 0, each frame's yaw
  change is unwrapped to the whole-turn count closest to `ω_y · gap`, so a
  large gap cannot lose or add a turn. Without it, today's per-frame yaw sum
  stays, and the spin count is unreliable (no spin points) whenever a frame
  gap was long enough to hide more than half a turn at the fastest spin rate
  seen so far in that flight.
- **Unchanged:** speed and icing eligibility still come from the last
  grounded frame. The preview and cue may appear one frame later at low
  frame rates; their content is the same.

## Testing

- **Offline** (source-contract tests, like the existing ones):
  `test_tick_timing.py` checks the timestamp offsets, takeoff as the latest
  and landing as the earliest new timestamp, a single lead value from
  `takeoffTick − modeAt`, the removal of the gap rule, `A+`, and
  `timingEstimated` from the rating path, the check-tick rule for late mode
  switches, and the spin unwrapping or fallback. Existing tests that assert
  the gap rule, the lead range, or `A+` are updated. All offline tests pass.
- **Frame skipping.** A developer-mode Debug setting, "Process every Nth
  frame" (1–10, default 1), makes the Trainer skip frames to simulate a low
  frame rate without touching the game's settings. It has no effect outside
  developer mode.
- **In game** (`test_frame_independence_in_game.py`, run only on request):
  replays one TICK revision with several rated jumps, a spin, and a miss in
  four runs: 1×; 4× speed; 1× every 5th frame; 4× every 3rd frame. It
  compares every verdict line (grade, lead, reason, spins, score); all runs
  must match. Like the other in-game tests it uses the research repository's
  TICK client and restores the user's game speed and revision.

## Documentation

- The main design spec's timing paragraphs describe exact takeoff and
  landing ticks, the stored-mode landing direction, the neutral-landing
  change, and the estimates.
- README: remove the `A+` note; add one line that grades do not depend on
  frame rate or game speed.
- Research repository: a short note on the per-wheel contact timestamps in
  `outputs/gorilla_grip_mechanism.md`, committed there separately.
