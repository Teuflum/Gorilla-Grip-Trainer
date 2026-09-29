# Hype cut soundtrack: synthesized drift phonk (130 BPM, C# minor) arranged per section,
# the narration, and sound effects from sfx.json. Writes mix.wav.
import json
import numpy as np
import soundfile as sf
from scipy.signal import lfilter, butter, resample_poly

SR = 44100
rng = np.random.default_rng(11)
TL = json.load(open("timeline.json"))
SFX = json.load(open("sfx.json"))
TOTAL = TL["total"]
BEAT, BAR = TL["beat"], TL["bar"]
STEP = BEAT / 4
N = int((TOTAL + 1.5) * SR)


def t_(d):
    return np.arange(int(d * SR)) / SR


def env(n, a=0.003, d=None, r=None):
    x = np.ones(n)
    na = max(1, min(n, int(a * SR)))
    x[:na] = np.linspace(0, 1, na)
    if d is not None:
        x[na:] *= np.exp(-np.arange(n - na) / (d * SR))
    if r is not None:
        nr = min(n, int(r * SR))
        x[-nr:] *= np.linspace(1, 0, nr)
    return x


def filt(x, kind, f):
    f = np.atleast_1d(f) / (SR / 2)
    b, a = butter(2, f if len(f) > 1 else f[0], kind)
    return lfilter(b, a, x)


def noise(d):
    return rng.standard_normal(int(d * SR))


def sweep(f0, f1, d, curve=1.0, shape="sine"):
    t = t_(d)
    f = f0 + (f1 - f0) * (t / d) ** curve
    ph = 2 * np.pi * np.cumsum(f) / SR
    if shape == "square":
        return np.sign(np.sin(ph))
    if shape == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1) - 1
    return np.sin(ph)


def mtof(m):
    return 440 * 2 ** ((m - 69) / 12)


def put(buf, start, sig, gain=1.0):
    i = int(round(start * SR))
    if i < 0:
        sig = sig[-i:]; i = 0
    if i >= len(buf):
        return
    j = min(len(buf), i + len(sig))
    buf[i:j] += sig[: j - i] * gain


# ---------------- instruments ----------------
def cowbell(f, d=0.32):
    t = t_(d)
    s = np.sign(np.sin(2 * np.pi * f * t)) + np.sign(np.sin(2 * np.pi * f * 1.48 * t))
    s = filt(s, "band", [f * 0.9, f * 6])
    return s * (0.75 * np.exp(-t / 0.05) + 0.25 * np.exp(-t / 0.2)) * 0.5


def bass808(f, d, glide_from=None):
    t = t_(d)
    f0 = glide_from if glide_from else f * 2.2
    freq = f + (f0 - f) * np.exp(-t / (0.06 if glide_from else 0.012))
    s = np.sin(2 * np.pi * np.cumsum(freq) / SR)
    s = np.tanh(s * 2.6) / np.tanh(2.6)
    return s * env(len(t), 0.002, d=0.45, r=0.03)


def kick():
    d = 0.3
    s = sweep(170, 42, d, curve=0.25) * env(int(d * SR), 0.001, d=0.1)
    click = filt(noise(0.006), "high", 2000) * 0.5
    s[:len(click)] += click
    return np.tanh(s * 2.2)


def clap():
    d = 0.35
    out = np.zeros(int(d * SR))
    for k, off in enumerate([0, 0.011, 0.023]):
        b = filt(noise(0.03), "band", [900, 4000]) * env(int(0.03 * SR), 0.0005, d=0.006)
        put_local(out, off, b)
    tail = filt(noise(d), "band", [1000, 5000]) * env(int(d * SR), 0.001, d=0.07) * 0.6
    return (out + tail) * 0.7


def put_local(buf, start, sig):
    i = int(start * SR); j = min(len(buf), i + len(sig)); buf[i:j] += sig[: j - i]


def hat(open_=False):
    d = 0.18 if open_ else 0.05
    return filt(noise(d), "high", 7500) * env(int(d * SR), 0.0005, d=0.05 if open_ else 0.012) * 0.6


def pad(freqs, d):
    t = t_(d)
    s = sum(sum(np.sin(2 * np.pi * f * (1 + det) * t + det * 100) for det in (-0.003, 0.0, 0.004)) for f in freqs)
    s = filt(s, "low", 1400) / (len(freqs) * 3)
    return s * env(len(t), 0.5, r=0.6)


def bell(f, d=1.4, bright=1.0):
    t = t_(d)
    return sum(a * np.sin(2 * np.pi * f * m * t) * np.exp(-t / (d * k)) for m, a, k in [(1, 1, 0.45), (2.0, 0.4 * bright, 0.25), (3.01, 0.2 * bright, 0.12), (4.2, 0.1 * bright, 0.06)])


def crash():
    d = 2.2
    return filt(noise(d), "high", 5000) * env(int(d * SR), 0.001, d=0.45) * 0.55


def riser(d):
    t = t_(d)
    n = filt(noise(d), "band", [800, 9000]) * (t / d) ** 2 * 0.35
    tone = sweep(200, 1400, d, curve=2, shape="saw")
    tone = filt(tone, "low", 3000) * (t / d) ** 2 * 0.12
    return n + tone


# ---------------- arrangement ----------------
ROOTS = [37, 37, 33, 35]            # C#1 C#1 A0 B0 (one per bar), + octave jumps
# 2-bar cowbell riff in C# minor: (step, midi)
RIFF = [(0, 73), (3, 76), (6, 73), (8, 68), (10, 71), (12, 73), (14, 76),
        (16, 73), (19, 76), (22, 78), (24, 76), (26, 73), (28, 71), (30, 68)]
BASS = [(0, 0, 6), (6, 0, 2), (8, 12, 3), (11, 7, 3), (14, 0, 2)]   # (step, semitone offset, length in steps)
CUTE = [(0, 85), (2, 88), (4, 92), (6, 90), (8, 88), (10, 85), (12, 83), (14, 85)]

music = np.zeros(N)
mode_at = {}
for s in TL["sections"]:
    for b in range(s["bars"]):
        m = "full"
        sid = s["id"]
        if sid == "cold":
            m = "intro" if b < 2 else "full"
        elif sid in ("secret",):
            m = "break"
        elif sid == "bullet":
            m = "break" if b < s["bars"] - 1 else "build"
        elif sid == "build":
            m = "build"
        elif sid == "uwu":
            m = "silent" if b == 0 else "cute"
        elif sid == "outro":
            m = "full" if b < s["bars"] - 2 else "end"
        mode_at[round(s["start"] + b * BAR, 4)] = (m, sid, b, s["bars"])

bar_index = 0
for t0, (m, sid, b, nb) in sorted(mode_at.items()):
    root = ROOTS[bar_index % 4]
    riff_half = (bar_index % 2) * 16
    if m in ("full", "intro", "break"):
        for st, note in RIFF:
            if riff_half <= st < riff_half + 16:
                cb = cowbell(mtof(note))
                if m != "full":
                    cb = filt(cb, "low", 900 if m == "intro" else 1300)
                put(music, t0 + (st - riff_half) * STEP, cb, 0.55 if m == "full" else 0.45)
                # dotted-8th echo
                put(music, t0 + (st - riff_half) * STEP + 3 * STEP, cb, 0.18)
    if m == "full":
        for st in (0, 3, 10):
            put(music, t0 + st * STEP, kick(), 0.7)
        put(music, t0 + 8 * STEP, clap(), 0.55)
        for st in range(0, 16, 2):
            put(music, t0 + st * STEP, hat(), 0.22 if st % 4 else 0.16)
        if bar_index % 2 == 1:   # 32nd roll at the end of every other bar
            for k in range(6):
                put(music, t0 + 13 * STEP + k * STEP / 2, hat(), 0.12 + 0.02 * k)
        put(music, t0 + 6 * STEP, hat(True), 0.14)
        prev = None
        for st, semi, ln in BASS:
            f = mtof(root + semi)
            put(music, t0 + st * STEP, bass808(f, ln * STEP + 0.05, glide_from=prev if st == 8 else None), 0.55)
            prev = f
    elif m == "intro":
        for st in range(0, 16, 4):
            put(music, t0 + st * STEP, hat(), 0.1)
        put(music, t0, pad([mtof(n) for n in (61, 64, 68)], BAR + 0.3), 0.35)
    elif m == "break":
        put(music, t0, bass808(mtof(root), BAR * 0.9), 0.45)
        put(music, t0, pad([mtof(n) for n in (root + 24, root + 27, root + 31)], BAR + 0.3), 0.4)
        for st in range(0, 16, 2):
            put(music, t0 + st * STEP, hat(), 0.08)
    elif m == "build":
        put(music, t0, riser(BAR), 0.9)
        hits = 8 if (sid == "build" and b == 0) else 16
        for k in range(hits):
            put(music, t0 + k * BAR / hits, clap() * (0.3 + 0.7 * k / hits), 0.35)
        put(music, t0, pad([mtof(n) for n in (root + 24, root + 27, root + 31)], BAR), 0.3)
    elif m == "cute":
        for st, note in CUTE:
            put(music, t0 + st * BEAT / 2, bell(mtof(note), 1.2), 0.22)
        put(music, t0, bell(mtof(61), 2.5, 0.3), 0.15)
    elif m == "end":
        if b == nb - 2:
            put(music, t0, kick(), 0.8); put(music, t0, crash(), 0.8)
            put(music, t0, bass808(mtof(37), BAR * 2), 0.6)
            put(music, t0, cowbell(mtof(73), 0.6), 0.5)
            for k in range(1, 6):
                put(music, t0 + k * 3 * STEP, cowbell(mtof(73), 0.4), 0.35 * 0.6 ** k)
            put(music, t0, pad([mtof(n) for n in (61, 64, 68, 73)], BAR * 2), 0.4)
    bar_index += 1

# crashes on the drops
for sid in ("problem", "gg", "reveal", "features"):
    s = next(x for x in TL["sections"] if x["id"] == sid)
    put(music, s["start"], crash(), 0.6)
put(music, BAR * 2, crash(), 0.6)
# record scratch: hard cut of the music for a moment at the secret
sec = next(x for x in TL["sections"] if x["id"] == "secret")
i0, i1 = int((sec["start"] - 0.02) * SR), int((sec["start"] + 0.55) * SR)
music[i0:i1] *= np.linspace(1, 0, 400).tolist() + [0] * (i1 - i0 - 400)
music = filt(music, "high", 28)

# ---------------- narration ----------------
voice = np.zeros(N)
for line in TL["lines"]:
    v, sr = sf.read(f"vo/{line['key'].replace('+', 'p')}.wav")
    v = resample_poly(v, SR, sr)
    if line["key"] == "uwu":
        v = resample_poly(v, 4, 5)   # pitched up and a touch faster: kawaii
        v = v * 1.2
    gain = 1.15 if line["key"].startswith("grade_") else 1.0
    put(voice, line["start"], v, gain)
voice /= np.abs(voice).max()
voice *= 0.9
# light compression-ish saturation for presence
voice = np.tanh(voice * 1.4) / np.tanh(1.4)

# duck the music under the voice
win = int(0.03 * SR)
e = np.abs(voice)
blocks = np.pad(e, (0, (-len(e)) % win)).reshape(-1, win).max(axis=1)
sm = np.zeros_like(blocks)
for i in range(1, len(blocks)):
    a = 0.6 if blocks[i] > sm[i - 1] else 0.08
    sm[i] = sm[i - 1] + a * (blocks[i] - sm[i - 1])
duck = 1 - 0.6 * np.clip(np.repeat(sm, win)[:N] / 0.3, 0, 1)
music *= duck


# ---------------- effects ----------------
def s_impact(p=1):
    d = 1.0
    boom = sweep(90, 32, d, curve=0.3) * env(int(d * SR), 0.001, d=0.28)
    hit = filt(noise(d), "low", 3500) * env(int(d * SR), 0.0005, d=0.03) * 0.8
    return np.tanh((boom + hit) * 1.8) * 0.9


def s_whoosh(p=1):
    d = 0.6
    n = noise(d); out = np.zeros_like(n); t = t_(d)
    for i, (lo, hi) in enumerate([(300, 900), (700, 2200), (1500, 5000), (3000, 9000)]):
        out += filt(n, "band", [lo, hi]) * np.exp(-((t - (0.12 + i * 0.1)) ** 2) / 0.008)
    return out * 0.6


def s_jump(p=1):
    d = 0.45
    return (filt(noise(d), "high", 1500) * 0.3 + sweep(200, 700, d) * 0.3) * env(int(d * SR), 0.03, r=0.3)


def s_land(p=1):
    d = 0.5
    body = sweep(120, 36, d, curve=0.35) * env(int(d * SR), 0.001, d=0.12)
    crunch = filt(noise(d), "low", 4000) * env(int(d * SR), 0.0005, d=0.05) * 0.6
    ice = filt(noise(d), "high", 5000) * env(int(d * SR), 0.001, d=0.15) * 0.3
    return np.tanh((body + crunch + ice) * 1.5)


def s_buzz(p=1):
    d = 0.4
    return filt(sweep(110, 105, d, shape="square"), "low", 1800) * env(int(d * SR), 0.005, r=0.05) * 0.35


def s_scratch(p=1):
    # record scratch: bandpassed noise swept fast forward and back
    d = 0.42
    t = t_(d)
    n = noise(d)
    lo = filt(n, "band", [300, 1200]); hi = filt(n, "band", [1200, 4200])
    mix = np.where((t % 0.14) < 0.07, hi, lo)
    tone = np.sin(2 * np.pi * np.cumsum(400 + 600 * np.abs(np.sin(2 * np.pi * 7 * t))) / SR) * 0.3
    return (mix + tone) * env(len(t), 0.002, r=0.08) * 0.8


def s_rewind(p=1):
    d = 0.7
    t = t_(d)
    chirps = sum(np.sin(2 * np.pi * np.cumsum(np.full(len(t), f) * (1 + 3 * (t % 0.08) / 0.08)) / SR) for f in (700, 1100))
    return filt(chirps, "band", [500, 5000]) * env(len(t), 0.02, r=0.2) * 0.22 + filt(noise(d), "high", 3000) * 0.08


def s_slowdown(p=1):
    # tape stop: pitch falls away
    d = 1.2
    t = t_(d)
    f = 220 * np.exp(-t * 2.2) + 30
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.4 * np.sign(np.sin(2 * np.pi * np.cumsum(f * 2) / SR))
    return filt(s, "low", 2000) * env(len(t), 0.01, r=0.3) * 0.35


def s_crash(p=1):
    return crash()


def s_shatter(p=1):
    d = 1.3
    out = filt(noise(d), "high", 2500) * env(int(d * SR), 0.001, d=0.1) * 0.6
    t = t_(d)
    for _ in range(24):
        st = rng.uniform(0, 0.4); f = rng.uniform(2500, 8000); k = np.clip(t - st, 0, None)
        out += (t > st) * np.sin(2 * np.pi * f * k) * np.exp(-k / rng.uniform(0.04, 0.2)) * 0.12
    return out


def s_blip(p=1):
    d = 0.09
    return filt(sweep(660 * p, 660 * p, d, shape="square"), "low", 4000) * env(int(d * SR), 0.002, r=0.05) * 0.35


def s_ouch(p=1):
    d = 0.3
    return sweep(700, 170, d, curve=0.5) * env(int(d * SR), 0.002, d=0.1) * 0.6


def s_tick(p=1):
    d = 0.25
    n = int(d * SR)
    out = filt(noise(d), "high", 4000) * env(n, 0.0005, d=0.01) * 0.4
    blip = sweep(1800, 1200, 0.05) * env(int(0.05 * SR), 0.001, d=0.02)
    out[:len(blip)] += blip * 0.4
    return out


def s_sparkle(p=1):
    out = np.zeros(int(1.6 * SR))
    for k, m in enumerate([85, 88, 92, 97, 100, 104]):
        put(out, k * 0.07, bell(mtof(m), 0.9, 1.3), 0.25)
    return out


def s_kawaii(p=1):
    d = 1.2
    out = np.zeros(int(d * SR))
    put(out, 0, bell(mtof(92), 0.8, 1.2), 0.35)
    put(out, 0.1, bell(mtof(97), 1.0, 1.2), 0.35)
    put(out, 0.0, sweep(900, 2400, 0.15) * env(int(0.15 * SR), 0.005, r=0.05), 0.2)
    return out


def s_vineboom(p=1):
    d = 1.6
    t = t_(d)
    body = np.sin(2 * np.pi * np.cumsum(58 + 30 * np.exp(-t / 0.05)) / SR) * env(len(t), 0.002, d=0.5)
    mid = filt(noise(d), "band", [150, 900]) * env(len(t), 0.001, d=0.06) * 0.8
    s = np.tanh((body + mid) * 3.0)
    # cheap room
    out = s.copy()
    for k, g in [(0.045, 0.35), (0.09, 0.22), (0.14, 0.12)]:
        i = int(k * SR); out[i:] += s[:-i] * g
    return out * 0.8


FX = {k[2:]: v for k, v in list(globals().items()) if k.startswith("s_")}

fx = np.zeros(N)
for c in SFX:
    put(fx, c["t"], FX[c["name"]](c.get("pitch", 1)), c.get("gain", 1))
fx = np.tanh(fx * 0.8) * 0.8

mix = voice + music * 0.34 + fx * 0.8
fade = np.ones(N); fo = int((TOTAL - 0.8) * SR); fade[fo:] = np.clip(np.linspace(1, 0, N - fo) * 1.6, 0, 1)
mix *= fade
mix /= np.abs(mix).max() / 0.95
mix = np.tanh(mix * 1.15) / np.tanh(1.15)
sf.write("mix.wav", np.stack([mix, mix], axis=1).astype(np.float32), SR)


def rms(x):
    return 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-9)


m = np.abs(voice) > 0.02
print("length %.1fs  voice %.1f dB  music %.1f dB (under voice %.1f)  fx peak %.2f" % (
    len(mix) / SR, rms(voice[m]), rms(music * 0.34), rms((music * 0.34)[m]), np.abs(fx * 0.8).max()))
