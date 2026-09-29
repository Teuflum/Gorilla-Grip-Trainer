# Intro video

`gorilla-grip-trainer-intro.mp4` is a three-minute introduction to the plugin, done as a nature documentary. It covers the delayed grip after landing, what the research found (stored slide direction, 400 ms timer, speed cost of an early countersteer), and the Trainer itself: the Physics widget, grades, combo, popup styles, sounds, run history, finish summary and the physics-offset search.

Everything in it is generated from this folder: no game footage and no recorded audio.

| File | Role |
| --- | --- |
| `script.py` | Narration lines, subtitles and scene order |
| `tts.py` | Speaks the lines with [Kokoro](https://github.com/thewh1teagle/kokoro-onnx) and writes `timings.json` |
| `web/video.js` | Draws every frame on a canvas; the HUD pieces copy the plugin's layout and colors |
| `render.js` | Steps the page frame by frame in headless Chromium and encodes with ffmpeg |
| `audio.py` | Synthesizes the music and sound effects and mixes them under the narration |
| `build.sh` | Runs all of the above |

To rebuild, download `kokoro-v1.0.int8.onnx` and `voices-v1.0.bin` from the kokoro-onnx releases into `voices/`, install `kokoro-onnx soundfile numpy scipy` for Python, then run `./build.sh`. It needs Node.js and ffmpeg; set `CHROMIUM` if Playwright has no browser of its own. The numbers shown (grade limits, 400/800 ms timer, speed-loss bars) come from this repository's README and the research repository's reports; update them there first if they change.

Emoji pictures come from `plugin/assets/emoji` (Noto, Twemoji, Fluent; see `plugin/assets/emoji/ATTRIBUTION.md`). Fonts: Russo One, Inter and JetBrains Mono (SIL Open Font License), fetched from npm by `build.sh`.
