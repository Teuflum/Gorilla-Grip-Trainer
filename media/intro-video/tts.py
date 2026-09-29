import json, os, soundfile as sf, numpy as np
from kokoro_onnx import Kokoro
from script import LINES, SCENE_TAIL
VOICES = os.environ.get("KOKORO_DIR", "voices")
k = Kokoro(os.path.join(VOICES, "kokoro-v1.0.int8.onnx"), os.path.join(VOICES, "voices-v1.0.bin"))
os.makedirs("vo", exist_ok=True)
t = 0.0; out = []; scenes = []; prev = None
for i, (scene, pre, sub, tts) in enumerate(LINES):
    if scene != prev:
        if prev is not None:
            t += SCENE_TAIL[prev]; scenes[-1]["end"] = t
        scenes.append({"id": scene, "start": t}); prev = scene
    s, sr = k.create(tts or sub, voice="bm_george", speed=1.04, lang="en-gb")
    # trim silence
    a = np.abs(s); idx = np.where(a > 0.01)[0]
    s = s[max(0, idx[0]-240): idx[-1]+1200]
    sf.write(f"vo/{i:02d}.wav", s, sr)
    t += pre
    d = len(s)/sr
    out.append({"i": i, "scene": scene, "start": round(t, 3), "dur": round(d, 3), "text": sub})
    t += d
t += SCENE_TAIL[prev]; scenes[-1]["end"] = t
json.dump({"lines": out, "scenes": scenes, "total": t}, open("timings.json", "w"), indent=1)
for s in scenes: print(s["id"], round(s["start"],2), round(s["end"]-s["start"],2))
print("total", t)
