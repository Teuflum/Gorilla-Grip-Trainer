# Trainer repository guide

This repository owns the Gorilla Grip Trainer plugin. `plugin/` is the source
of truth; the installed Openplanet copy and `PluginStorage` are runtime state.
Read `README.md` and the design documents under `docs/` before changing
rating behavior or the HUD.

- Run focused offline scripts in `tests/` with Python, such as
  `python tests/test_rating_settings.py` and
  `python tests/test_presentation_contract.py`. Do not run every test file
  blindly: `test_trainer_in_game.py`, `test_current_input.py`, and the
  finish/reset tests interact with Trackmania or TICK.
- For live verification, install the changed `plugin/` files, reload in
  Openplanet, inspect its compile/runtime log, and check the actual HUD
  behavior. Preserve the user's active TICK input, revision, map, and settings.
- The timing preview is provisional until landing confirms tire force.
  `UNRATED` means required physics/contact data was unavailable. The Combo
  widget starts at x1 and shows the multiplier for the next successful
  landing; Best Combo shows the highest displayed multiplier reached.
- Exact physics reads are gated by the supported executable signature.
  VehicleState front-wheel steering angles are visual wheel angles, not the
  normalized internal steering value used for the direction threshold.
- `LocalSounds/`, local audio, maps, replays, binaries, and runtime history
  stay out of Git. Do not delete or reset `PluginStorage` as test cleanup.
  Check `git diff --check`, focused tests, and the staged file list before
  committing or pushing.
