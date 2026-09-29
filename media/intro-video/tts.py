# Speaks the hype script and lays it out on the bar grid -> timeline.json + vo/*.wav
import json, math, os, re
import numpy as np
import soundfile as sf
from kokoro_onnx import Kokoro
from script import SECTIONS, GRADE_CALLS, BPM, NARRATOR

VOICES = os.environ.get("KOKORO_DIR", "voices")
k = Kokoro(os.path.join(VOICES, "kokoro-v1.0.int8.onnx"), os.path.join(VOICES, "voices-v1.0.bin"))
os.makedirs("vo", exist_ok=True)
BEAT = 60 / BPM
BAR = 4 * BEAT


def speak(key, text, voice, speed):
    s, sr = k.create(text, voice=voice, speed=speed, lang="en-us")
    a = np.abs(s)
    idx = np.where(a > 0.01)[0]
    s = s[max(0, idx[0] - 200): idx[-1] + 800]
    sf.write(f"vo/{key}.wav", s, sr)
    return s, sr


def word_times(sub, audio, sr):
    """Estimate when each subtitle word starts. Pauses in the audio are found on 10 ms
    frames; the longest ones become the boundaries between punctuation-separated chunks,
    and words are spread by length inside each chunk's voiced span."""
    fr = int(0.01 * sr)
    n = len(audio) // fr
    e = np.array([np.sqrt(np.mean(audio[i * fr:(i + 1) * fr] ** 2)) for i in range(n)])
    voiced = e > max(0.006, 0.08 * e.max())
    pauses = []   # (length, start_frame, end_frame)
    i = 0
    while i < n:
        if not voiced[i]:
            j = i
            while j < n and not voiced[j]:
                j += 1
            if i > 0 and j < n and j - i >= 6:
                pauses.append((j - i, i, j))
            i = j
        else:
            i += 1
    words = sub.split()
    chunks, cur = [], []
    for w in words:
        cur.append(w)
        if re.search(r"[,.!?…:]$", w):
            chunks.append(cur); cur = []
    if cur:
        chunks.append(cur)
    first = int(np.argmax(voiced)); last = n - int(np.argmax(voiced[::-1]))
    need = len(chunks) - 1
    aligned = len(pauses) >= need
    if aligned and need > 0:
        cut = sorted(sorted(pauses, reverse=True)[:need], key=lambda p: p[1])
        spans, s0 = [], first
        for _, ps, pe in cut:
            spans.append((s0, ps)); s0 = pe
        spans.append((s0, last))
    else:
        spans = [(first, last)]
        chunks = [words]
    out = []
    for ch, (a, b) in zip(chunks, spans):
        total = sum(len(w) + 1 for w in ch); acc = 0
        for w in ch:
            out.append((w, (a + (b - a) * acc / total) * fr / sr)); acc += len(w) + 1
    return out, aligned


def snap(t, grid=BEAT / 2):
    return math.ceil(t / grid - 1e-6) * grid


timeline = {"bpm": BPM, "beat": BEAT, "bar": BAR, "sections": [], "lines": []}
t = 0.0
for sid, min_bars, lines in SECTIONS:
    sec = {"id": sid, "start": t}
    cursor = t
    for key, sub, tts, (voice, speed), offset in lines:
        audio, sr = speak(key, tts or sub, voice, speed)
        start = snap(cursor + offset * BEAT)
        dur = len(audio) / sr
        words, aligned = word_times(sub, audio, sr)
        timeline["lines"].append({"key": key, "section": sid, "start": round(start, 3), "dur": round(dur, 3), "text": sub,
                                  "words": [[w, round(start + wt, 3)] for w, wt in words], "aligned": aligned, "voice": voice})
        cursor = start + dur
    if sid == "grades":
        for label, spoken, beat in GRADE_CALLS:
            audio, sr = speak("grade_" + label.replace("+", "p"), spoken, NARRATOR[0], 1.0)
            start = t + beat * BEAT
            timeline["lines"].append({"key": "grade_" + label, "section": sid, "start": round(start, 3), "dur": round(len(audio) / sr, 3),
                                      "text": label, "words": [[label, round(start, 3)]], "aligned": True, "voice": NARRATOR[0]})
        cursor = t + 14 * BEAT
    bars = max(min_bars, math.ceil((cursor - t + BEAT) / BAR - 1e-6))
    sec["bars"] = bars
    t += bars * BAR
    sec["end"] = t
    timeline["sections"].append(sec)
timeline["total"] = t
json.dump(timeline, open("timeline.json", "w"), indent=1)
for s in timeline["sections"]:
    print(f'{s["id"]:9s} {s["start"]:7.2f} {s["bars"]} bars')
for l in timeline["lines"]:
    print(f'  {l["key"]:10s} {l["start"]:7.2f} {l["dur"]:5.2f} aligned={l["aligned"]}')
print("total", round(t, 2))
