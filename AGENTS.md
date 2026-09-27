# Trainer repository guide

This repository owns the Gorilla Grip Trainer plugin. `plugin/` is the source
of truth; the installed Openplanet copy and `PluginStorage` are runtime state.
Read `README.md` and the design documents under `docs/` before changing
rating behavior or the HUD.

- Run focused offline scripts in `tests/` with Python, such as
  `python tests/test_rating_settings.py` and
  `python tests/test_presentation_contract.py`. Do not run every test file
  blindly: the `*_in_game.py` tests and `test_current_input.py` drive
  Trackmania and TICK. They also need
  Debug → Log trainer events on, since routine log lines are off by default.
  The Debug tab and its options exist only in Openplanet developer mode.
- For live verification, install the changed `plugin/` files, reload in
  Openplanet, inspect its compile/runtime log, and check the actual HUD
  behavior. Preserve the user's active TICK input, revision, map, and settings.
- The timing preview is provisional until the landing confirms that the
  stored direction held (tire force does not decide). The grade is the
  switch lead only; do not fold landing force or airtime into it.
  `UNRATED` means required physics/contact data was unavailable. The Stats
  widget's combo is the streak of successful landings, starting at x0;
  scoring uses min(streak + 1, 8) for the next landing. Best combo is the
  longest streak.
- Exact physics reads are gated by the supported executable signature.
  VehicleState front-wheel steering angles are visual wheel angles, not the
  normalized internal steering value used for the direction threshold.
- `LocalSounds/`, `LocalImages/`, local audio, maps, replays, binaries, and runtime history
  stay out of Git. Do not delete or reset `PluginStorage` as test cleanup.
  Check `git diff --check`, focused tests, and the staged file list before
  committing or pushing.
