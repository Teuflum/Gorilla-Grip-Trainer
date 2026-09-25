# Gorilla Grip Trainer

Standalone Openplanet trainer for the timing of a Trackmania ice-slide direction switch before takeoff. The implementation branch currently contains the validated read-only physics sampler; timing grades and the modular interface are in progress.

- [Design specification](docs/superpowers/specs/2026-09-25-gorilla-grip-trainer.md)
- [Implementation plan](docs/superpowers/plans/2026-09-25-gorilla-grip-trainer.md)
- [Physics research](https://github.com/Teuflum/tm-gorilla-grip-reverse-engineering)

The supplied jump, announcer, failure, and results audio files are for local testing only. They are excluded from this repository. The implementation plan includes a local audio installer; an original impact sound may be included with the plugin.

## Development install

Copy the `plugin` folder to `OpenplanetNext/Plugins/GorillaGripTrainer` and load it through Openplanet. It requires VehicleState. On the tested Trackmania build, the diagnostics window identifies an exact physics read and shows the internal steering value, stored slide direction, icing, and the current tire-force multiplier. The sampler reads memory only after checking the executable signature and active vehicle; unsupported builds display `ESTIMATE`.

The controlled in-game telemetry check is `py -3 tests/test_trainer_in_game.py --research-root <path-to-research-repo> --physics-only`. It requires Trackmania, TICK, and the research repository's Gorilla Grip Logger.
