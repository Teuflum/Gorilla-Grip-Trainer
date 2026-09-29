# Mixes narration, synthesized music and sound effects into mix.wav.
import json
import numpy as np
import soundfile as sf
from scipy.signal import lfilter, butter, resample_poly

SR = 44100
rng = np.random.default_rng(7)
TM = json.load(open("timings.json"))
SFX = json.load(open("sfx.json"))
TOTAL = TM["total"]
N = int((TOTAL + 1.0) * SR)


def t_(d):
    return np.arange(int(d * SR)) / SR


def env(n, a=0.005, r=None, d=None):
    """Attack then exponential decay (d seconds time constant) or linear release r."""
    x = np.ones(n)
    na = max(1, int(a * SR))
    x[:na] = np.linspace(0, 1, na)
    if d is not None:
        x[na:] *= np.exp(-np.arange(n - na) / (d * SR))
    if r is not None:
        nr = min(n, int(r * SR))
        x[-nr:] *= np.linspace(1, 0, nr)
    return x


def lp(x, fc, order=2):
    b, a = butter(order, min(fc, SR / 2 - 100) / (SR / 2), "low")
    return lfilter(b, a, x)


def hp(x, fc, order=2):
    b, a = butter(order, fc / (SR / 2), "high")
    return lfilter(b, a, x)


def bp(x, lo, hi):
    b, a = butter(2, [lo / (SR / 2), hi / (SR / 2)], "band")
    return lfilter(b, a, x)


def sweep(f0, f1, d, shape="sine", curve=1.0):
    t = t_(d)
    f = f0 + (f1 - f0) * (t / d) ** curve
    ph = 2 * np.pi * np.cumsum(f) / SR
    if shape == "sine":
        return np.sin(ph)
    if shape == "square":
        return np.sign(np.sin(ph)) * 0.6
    if shape == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1) - 1
    raise ValueError(shape)


def noise(d):
    return rng.standard_normal(int(d * SR))


def bell(f, d=1.2):
    t = t_(d)
    return sum(a * np.sin(2 * np.pi * f * m * t) * np.exp(-t / (d * k))
               for m, a, k in [(1, 1, 0.5), (2.76, 0.35, 0.2), (5.4, 0.18, 0.1)])


# ---------- sound effects ----------
def s_whoosh(p=1):
    d = 0.7
    n = noise(d)
    out = np.zeros_like(n)
    # sweep a band through the noise
    for i, (lo, hi) in enumerate([(300, 900), (600, 1800), (1200, 3600), (2400, 7000)]):
        seg = bp(n, lo, hi)
        w = np.exp(-((t_(d) - (0.15 + i * 0.12)) ** 2) / 0.01)
        out += seg * w
    return out * 0.6


def s_ding(p=1):
    return bell(1320 * p, 1.0) * 0.5


def s_pop(p=1):
    return sweep(380 * p, 950 * p, 0.07) * env(int(0.07 * SR), 0.002, d=0.03) * 0.6


def s_blip(p=1):
    return lp(sweep(660 * p, 660 * p, 0.09, "square"), 4000) * env(int(0.09 * SR), 0.002, r=0.05) * 0.4


def s_tick(p=1):
    return hp(noise(0.012), 3000) * env(int(0.012 * SR), 0.0005, d=0.003) * 0.5


def s_poke(p=1):
    d = 0.35
    t = t_(d)
    f = 150 + 60 * np.exp(-t * 12) + 25 * np.sin(2 * np.pi * 14 * t) * np.exp(-t * 6)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(t), 0.003, d=0.12) * 0.8


def s_boing(p=1):
    d = 0.7
    t = t_(d)
    f = 180 + 320 * (t / d) + 60 * np.sin(2 * np.pi * 9 * t)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(t), 0.01, r=0.25) * 0.5


def s_jump(p=1):
    d = 0.45
    return (hp(noise(d), 1500) * 0.3 + sweep(200, 600, d) * 0.4) * env(int(d * SR), 0.03, r=0.3) * 0.6


def s_land(p=1):
    d = 0.4
    body = sweep(110, 38, d, curve=0.4) * env(int(d * SR), 0.002, d=0.12)
    crunch = lp(noise(d), 2500) * env(int(d * SR), 0.001, d=0.05) * 0.5
    return (body + crunch) * 0.9


def s_switch(p=1):
    d = 0.18
    z = lp(sweep(400, 1800, d, "square"), 6000) * env(int(d * SR), 0.002, r=0.05) * 0.35
    out = np.zeros(int(0.9 * SR))
    out[:len(z)] += z
    b = bell(1760, 0.8) * 0.35
    out[int(0.1 * SR):int(0.1 * SR) + len(b)] += b[:len(out) - int(0.1 * SR)]
    return out


def s_shatter(p=1):
    d = 1.4
    out = hp(noise(d), 2500) * env(int(d * SR), 0.001, d=0.12) * 0.6
    t = t_(d)
    for _ in range(26):
        st = rng.uniform(0, 0.45)
        f = rng.uniform(2500, 7500)
        k = np.clip(t - st, 0, None)
        out += (t > st) * np.sin(2 * np.pi * f * k) * np.exp(-k / rng.uniform(0.04, 0.2)) * 0.12
    return out


def s_fanfare(p=1):
    d = 1.6
    t = t_(d)
    out = np.zeros(len(t))
    for i, f in enumerate([523.25, 659.25, 783.99, 1046.5]):
        st = i * 0.09
        k = np.clip(t - st, 0, None)
        tone = sum(np.sin(2 * np.pi * f * h * k) / h for h in range(1, 7))
        out += (t > st) * tone * np.exp(-k / 0.7) * (1 - np.exp(-k / 0.01))
    return lp(out, 5000) * 0.18


def s_slam(p=1):
    d = 0.9
    body = sweep(90, 35, d, curve=0.3) * env(int(d * SR), 0.001, d=0.18)
    crash = hp(noise(d), 4000) * env(int(d * SR), 0.001, d=0.25) * 0.35
    return (body + crash) * 0.9


def s_sheen(p=1):
    d = 1.0
    t = t_(d)
    out = sum(np.sin(2 * np.pi * np.cumsum(f0 * (1 + 0.8 * t / d)) / SR) for f0 in [1200, 1800, 2400, 3000])
    return out * (0.5 + 0.5 * np.sin(2 * np.pi * 18 * t)) * env(len(t), 0.25, r=0.4) * 0.1


def s_trombone(p=1):
    notes = [(293.66, 0.38), (277.18, 0.38), (261.63, 0.38), (246.94, 1.3)]
    out = []
    for i, (f, d) in enumerate(notes):
        t = t_(d)
        vib = 1 + (0.02 * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.3) * 2, 0, 1) if i == 3 else 0)
        ph = 2 * np.pi * np.cumsum(f * vib) / SR
        tone = sum(np.sin(h * ph) / h for h in range(1, 9))
        x = 1 - np.exp(-t / 0.15)
        wah = lp(tone, 700) * (1 - x) + lp(tone, 1700) * x
        out.append(wah * env(len(t), 0.03, r=0.12 if i < 3 else 0.6))
    return np.concatenate(out) * 0.3


def s_ouch(p=1):
    d = 0.3
    return sweep(700, 180, d, curve=0.5) * env(int(d * SR), 0.002, d=0.1) * 0.6


def s_whistle(p=1):
    d = 0.55
    t = t_(d)
    f = 2900 + 250 * np.sign(np.sin(2 * np.pi * 28 * t))
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.35 + bp(noise(d), 2000, 5000) * 0.08
    return tone * env(len(t), 0.02, r=0.1)


def s_reveal(p=1):
    d = 2.0
    boom = sweep(70, 40, d, curve=0.3) * env(int(d * SR), 0.002, d=0.4) * 0.9
    shimmer = hp(noise(d), 6000) * env(int(d * SR), 0.002, d=0.5) * 0.12
    chord = sum(np.sin(2 * np.pi * f * t_(d)) for f in [220, 277.18, 329.63, 440]) * env(int(d * SR), 0.01, d=0.7) * 0.1
    return boom + shimmer + chord


def s_stamp(p=1):
    d = 0.5
    body = sweep(140, 45, d, curve=0.3) * env(int(d * SR), 0.001, d=0.08)
    slap = lp(noise(d), 3000) * env(int(d * SR), 0.0005, d=0.02) * 0.8
    return (body + slap) * 1.0


def s_flip(p=1):
    d = 0.12
    return bp(noise(d), 1500 * p, 5000 * p) * env(int(d * SR), 0.003, d=0.03) * 0.8


def s_down(p=1):
    d = 0.45
    return sweep(820, 300, d) * env(int(d * SR), 0.005, r=0.15) * 0.35


def s_up(p=1):
    d = 0.45
    return sweep(300, 950, d) * env(int(d * SR), 0.005, r=0.15) * 0.35


def s_coin(p=1):
    a = lp(sweep(988 * p, 988 * p, 0.06, "square"), 6000)
    b = lp(sweep(1319 * p, 1319 * p, 0.2, "square"), 6000) * env(int(0.2 * SR), 0.001, d=0.08)
    return np.concatenate([a, b]) * 0.3


def s_crack(p=1):
    d = 1.0
    out = hp(noise(d), 1500) * env(int(d * SR), 0.0005, d=0.04) * 0.9
    t = t_(d)
    for _ in range(14):
        st = rng.uniform(0, 0.25)
        k = np.clip(t - st, 0, None)
        out += (t > st) * np.sin(2 * np.pi * rng.uniform(1800, 5000) * k) * np.exp(-k / 0.08) * 0.15
    return out


def s_check(p=1):
    return bell(1046.5 * p, 0.6) * 0.4


def s_wind(p=1):
    d = 7.0
    t = t_(d)
    n = lp(noise(d), 700) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.23 * t))
    return n * env(len(t), 1.5, r=2.5) * 0.35


def s_slide(p=1):
    d = 1.6
    return hp(noise(d), 3500) * env(int(d * SR), 0.3, r=0.6) * 0.3


FX = {k[2:]: v for k, v in globals().items() if k.startswith("s_")}

# ---------- music ----------
BPM = 100
BEAT = 60 / BPM
BAR = 4 * BEAT
t_plugin = next(s["start"] for s in TM["scenes"] if s["id"] == "plugin")
t_outro_end = TOTAL - 1.0

# Am  F  C  G   (root, chord tones as MIDI)
PROG = [(57, [57, 60, 64]), (53, [53, 57, 60]), (48, [55, 60, 64]), (55, [55, 59, 62])]


def mtof(m):
    return 440 * 2 ** ((m - 69) / 12)


music = np.zeros(N)
drums = np.zeros(N)


def put(buf, start, sig, gain=1.0):
    i = int(start * SR)
    if i >= len(buf):
        return
    j = min(len(buf), i + len(sig))
    buf[i:j] += sig[: j - i] * gain


def pluck(f, d=0.5, bright=1.0):
    t = t_(d)
    tone = np.sin(2 * np.pi * f * t) + 0.3 * bright * np.sin(2 * np.pi * 2 * f * t) + 0.12 * bright * np.sin(2 * np.pi * 4 * f * t)
    return tone * env(len(t), 0.004, d=0.18)


def pad(freqs, d):
    t = t_(d)
    sig = np.zeros(len(t))
    for f in freqs:
        for det in (-0.004, 0.0, 0.005):
            ph = 2 * np.pi * f * (1 + det) * t
            sig += 2 * ((ph / (2 * np.pi)) % 1) - 1
    sig = lp(sig, 1100)
    return sig * env(len(t), 0.4, r=0.5) / (len(freqs) * 3)


def kick():
    return sweep(120, 42, 0.28, curve=0.35) * env(int(0.28 * SR), 0.001, d=0.09)


def snare():
    d = 0.22
    return (bp(noise(d), 1200, 6000) * 0.7 + np.sin(2 * np.pi * 190 * t_(d)) * 0.4) * env(int(d * SR), 0.001, d=0.06)


def hat():
    return hp(noise(0.05), 7000) * env(int(0.05 * SR), 0.0005, d=0.012)


def bass(f, d):
    t = t_(d)
    ph = 2 * np.pi * f * t
    s = np.sin(ph) + 0.35 * (2 * ((ph / (2 * np.pi)) % 1) - 1)
    return lp(s, 600) * env(len(t), 0.005, r=0.05)


bar = 0
t0 = 0.4
while t0 < t_outro_end:
    root, chord = PROG[bar % 4]
    energetic = t0 >= t_plugin - 0.05
    put(music, t0, pad([mtof(m) for m in chord] + [mtof(root - 12)], BAR + 0.5), 0.55 if energetic else 0.7)
    # arpeggio in 8ths
    arp = chord + [chord[1] + 12, chord[2] + 12, chord[0] + 12, chord[2], chord[1]]
    for k in range(8):
        if not energetic and k % 2 == 1:
            continue
        put(music, t0 + k * BEAT / 2, pluck(mtof(arp[k % len(arp)] + 12), 0.45, 1.2 if energetic else 0.6), 0.16)
    if energetic:
        for k in range(4):
            put(drums, t0 + k * BEAT, kick(), 0.55)
            if k % 2 == 1:
                put(drums, t0 + k * BEAT, snare(), 0.25)
        for k in range(8):
            put(drums, t0 + k * BEAT / 2 + (BEAT / 4 if False else 0), hat(), 0.12 if k % 2 else 0.07)
        for k in range(8):
            put(music, t0 + k * BEAT / 2, bass(mtof(root - 12), BEAT / 2 - 0.02), 0.22)
    bar += 1
    t0 += BAR
# final chord
put(music, t_outro_end - 0.2, pad([mtof(m) for m in [57, 60, 64, 69]] + [mtof(45)], 4.0), 0.9)
put(music, t_outro_end - 0.2, pluck(mtof(81), 2.0), 0.25)

music = music + drums
# gentle fade in at start and fade out at the end
fade = np.ones(N)
fi = int(2.0 * SR)
fade[:fi] = np.linspace(0, 1, fi)
fo0 = int((TOTAL - 1.4) * SR)
fade[fo0:] = np.linspace(1, 0, N - fo0)
music *= fade

# ---------- narration ----------
voice = np.zeros(N)
for line in TM["lines"]:
    v, sr = sf.read(f"vo/{line['i']:02d}.wav")
    v = resample_poly(v, SR, sr)
    put(voice, line["start"], v, 1.0)
voice /= max(1e-6, np.abs(voice).max())
voice *= 0.85

# duck the music under the voice
e = np.abs(voice)
att = 1 - np.exp(-1 / (0.02 * SR))
rel = 1 - np.exp(-1 / (0.35 * SR))
# envelope follower (vectorized approximation: smoothed max over windows)
win = int(0.05 * SR)
padded = np.pad(e, (0, (-len(e)) % win))
blocks = padded.reshape(-1, win).max(axis=1)
sm = np.zeros_like(blocks)
for i in range(1, len(blocks)):
    a = 0.5 if blocks[i] > sm[i - 1] else 0.12
    sm[i] = sm[i - 1] + a * (blocks[i] - sm[i - 1])
sm = np.repeat(sm, win)[: len(e)]
duck = 1 - 0.55 * np.clip(sm / 0.3, 0, 1)
music *= duck

# ---------- effects ----------
fx = np.zeros(N)
for c in SFX:
    sig = FX[c["name"]](c.get("pitch", 1))
    put(fx, c["t"], sig, c.get("gain", 1))

fx = np.tanh(fx * 0.6 / 0.7) * 0.7
mix = voice + music * 0.45 + fx
peak = np.abs(mix).max()
mix = mix / peak * 0.93
# soft limiter
mix = np.tanh(mix * 1.2) / np.tanh(1.2)
sf.write("mix.wav", np.stack([mix, mix], axis=1).astype(np.float32), SR)
print("mix", len(mix) / SR, "s  peak", peak)
def rms(x):
    return 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-9)
m = np.abs(voice) > 0.02
print("voice rms (speech) %.1f dB, music %.1f dB, music under speech %.1f dB, fx peak %.2f" % (
    rms(voice[m]), rms(music * 0.45), rms((music * 0.45)[m]), np.abs(fx).max()))
