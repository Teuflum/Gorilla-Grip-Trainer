# Intro video

`gorilla-grip-trainer-intro.mp4` is a 92-second hype trailer for the plugin. A Stadium-style car slides sideways across an ice track at 200 km/h, spins off the jumps and lands in the opposite slide. The trailer shows why landing costs grip when the direction switches on touchdown, how a countersteer on the takeoff tick lets the 400 ms timer run out in the air, what an early switch costs in speed, and then the Trainer in game: the Physics widget, takeoff preview, landing popup, Stats combo, grades, popup styles, sounds, run history and the physics-offset search. There is also a blushing gorilla. uwu.

Everything in it is generated from this folder: no game footage and no recorded audio.

| File | Role |
| --- | --- |
| `script.py` | Voice lines and the section layout on a 130 BPM bar grid |
| `tts.py` | Speaks the lines with [Kokoro](https://github.com/thewh1teagle/kokoro-onnx), estimates word timings for the captions, writes `timeline.json` |
| `web/world3d.js` | The three.js ice track and car, plus a small slide/jump simulation. Stored slide mode, smoothed steering (0.2 per 10 ms tick, ±10% gate) and the tire-force multiplier (400 ms delay, +0.025 per front wheel per tick, full at 800 ms) follow the research report, so the HUD values and grades in the shots come from the simulated ticks |
| `web/main.js` | Shots, camera moves and overlays for each section |
| `web/hud.js` | The plugin's HUD pieces (landing popup, Physics and Stats widgets, finish summary) in its layout and colors |
| `render.js` | Steps the page frame by frame in headless Chromium and encodes with ffmpeg |
| `audio.py` | Synthesized drift-phonk soundtrack and sound effects, mixed under the narration |
| `build.sh` | Runs all of the above |

To rebuild, download `kokoro-v1.0.int8.onnx` and `voices-v1.0.bin` from the kokoro-onnx releases into `voices/`, install `kokoro-onnx soundfile numpy scipy` for Python, then run `./build.sh`. It needs Node.js and ffmpeg; set `CHROMIUM` if Playwright has no browser of its own. Without a GPU the WebGL frames render in software at about 2 s each. The numbers shown (grade limits, 400/800 ms timer, speed-loss bars) come from this repository's README and the research repository's reports; update them there first if they change.

Emoji pictures come from `plugin/assets/emoji` (Noto, Twemoji, Fluent; see `plugin/assets/emoji/ATTRIBUTION.md`). Fonts: Anton, Inter, Inter Tight, Fredoka, Russo One and JetBrains Mono (SIL Open Font License), fetched from npm by `build.sh`; the Japanese caption uses the system's WenQuanYi Zen Hei. three.js is MIT licensed.
