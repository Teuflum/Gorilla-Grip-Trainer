// Hype cut of the Gorilla Grip Trainer intro. renderAt(t) draws one frame: a 3D shot from
// the simulation, then 2D overlays (plugin HUD, slams, captions). hud.js provides the
// plugin widget drawings and 2D helpers as globals.
import * as THREE from 'three';
import { makeTrack, simulate, createWorld, poseWorld, sample, WHEELS } from './world3d.js';

const TL = await (await fetch('timeline.json')).json();
const fonts = ['400 40px Anton', 'italic 900 40px "Inter Tight"', '900 40px "Inter Tight"', '800 40px "Inter Tight"', '700 40px "Inter Tight"',
  'italic 800 40px "Inter Tight"', '700 40px Fredoka', '600 40px Fredoka', '40px Russo', '700 40px Inter', '800 40px Inter', '900 40px Inter',
  '500 40px Inter', '700 40px Mono', '500 40px Mono', '40px "WenQuanYi Zen Hei"'];
for (const f of fonts) await document.fonts.load(f, 'ゴリラ先輩 abc');
await Promise.all(['noto-gorilla', 'twemoji-flexed-biceps', 'twemoji-thumbs-up', 'twemoji-ok-hand', 'twemoji-slightly-smiling-face',
  'twemoji-skull', 'fluent-3d-snowflake', 'fluent-3d-trophy'].map(n => new Promise((res, rej) => {
  const im = new Image(); im.onload = () => { IMG[n] = im; res(); }; im.onerror = rej; im.src = 'emoji/' + n + '.png';
})));

const BEAT = TL.beat, BAR = TL.bar;
const SEC = Object.fromEntries(TL.sections.map(s => [s.id, s]));
const LINE = Object.fromEntries(TL.lines.map(l => [l.key, l]));
const LS = k => LINE[k].start, LE = k => LINE[k].start + LINE[k].dur;
function WT(key, word, occ = 0) {   // estimated time a subtitle word is spoken
  const ws = LINE[key].words; let n = 0;
  for (const [w, t] of ws) if (w.replace(/[^\w+×]/g, '').toLowerCase().startsWith(word.toLowerCase()) && n++ === occ) return t;
  throw new Error('word ' + word + ' not in ' + key);
}
const beatT = (sec, b) => SEC[sec].start + b * BEAT;

// ---------------- 3D setup ----------------
const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
renderer.setSize(W, H, false);
renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 0.85;
const glCanvas = renderer.domElement;
const track = makeTrack([300, 560, 820, 1080, 1340]);
const world = createWorld(renderer, track);
const cam = new THREE.PerspectiveCamera(50, W / H, 0.1, 5000);
const deg = Math.PI / 180;
const jumpCfg = (spin, lead, from, to, afterTau = 0.9) => ({ spin: spin * deg, landSlip: to * deg, lead, approachSlip: from * deg, after: { slip: (to * 0.8) * deg, tau: afterTau } });
const RUN = {
  // the good one: countersteer lands on the takeoff tick (S+)
  trick: simulate({ track, x0: 0, speed: 55, slip0: 100 * deg, jumps: [jumpCfg(160, 0, 100, -100)] }, 14),
  // switches only on landing: 400 ms of waiting after touchdown
  prob: simulate({ track, x0: 0, speed: 55, slip0: 100 * deg, jumps: [{ ...jumpCfg(160, null, 100, -100), after: { slip: -100 * deg, tau: 2.5 } }] }, 14),
  // teaser with a big spin
  tease: simulate({ track, x0: 0, speed: 56, slip0: 105 * deg, phase: 1.2, jumps: [jumpCfg(520, 0, 105, -100)] }, 14),
  // a run for the in-game HUD: S+, A, S, missed
  game: simulate({ track, x0: 0, speed: 55, slip0: 100 * deg, phase: 2.1, jumps: [jumpCfg(160, 0, 100, -100), jumpCfg(-160, 20, -100, 100), jumpCfg(200, 10, 100, -100), { ...jumpCfg(-200, null, -100, 100), after: { slip: 100 * deg, tau: 2.5 } }] }, 30),
};
window.RUNINFO = Object.fromEntries(Object.entries(RUN).map(([k, r]) => [k, r.jumps]));
const J = (run, i = 0) => RUN[run].jumps[i];

// piecewise-linear time remap video t -> simulation s; slope continues past the ends
function remap(t, keys) {
  if (t <= keys[0][0]) return keys[0][1] + (t - keys[0][0]) * ((keys[1][1] - keys[0][1]) / (keys[1][0] - keys[0][0]));
  for (let i = 1; i < keys.length; i++) if (t <= keys[i][0]) {
    const [t0, s0] = keys[i - 1], [t1, s1] = keys[i]; return s0 + (s1 - s0) * (t - t0) / (t1 - t0);
  }
  const [t0, s0] = keys[keys.length - 2], [t1, s1] = keys[keys.length - 1];
  return s1 + (t - t1) * ((s1 - s0) / (t1 - t0));
}
const V3 = (x, y, z) => new THREE.Vector3(x, y, z);
function dirOf(st) { return V3(Math.cos(st.phi), 0, -Math.sin(st.phi)); }
function rightOf(st) { return V3(Math.sin(st.phi), 0, Math.cos(st.phi)); }
let shake = 0;
function applyCam(pos, look, fov, t) {
  const sh = shake;
  cam.position.copy(pos).add(V3(Math.sin(t * 91) * sh * 0.3, Math.sin(t * 77 + 1) * sh * 0.25, Math.cos(t * 83) * sh * 0.3));
  cam.fov = fov; cam.updateProjectionMatrix(); cam.lookAt(look);
}
const CAMS = {
  chase: (st, t, o = {}) => { const d = dirOf(st), r = rightOf(st); applyCam(V3(st.x, st.y * 0.6, st.z).addScaledVector(d, -(o.dist ?? 13)).addScaledVector(r, o.side ?? 0).add(V3(0, o.h ?? 4.2, 0)), V3(st.x, st.y + 1, st.z).addScaledVector(d, o.look ?? 6), o.fov ?? 55, t); },
  side: (st, t, o = {}) => { const d = dirOf(st), r = rightOf(st); applyCam(V3(st.x, st.y, st.z).addScaledVector(r, o.side ?? 9).addScaledVector(d, o.fwd ?? 3).add(V3(0, o.h ?? 1.2, 0)), V3(st.x, st.y + 0.8, st.z).addScaledVector(d, o.lookFwd ?? 0), o.fov ?? 45, t); },
  front: (st, t, o = {}) => { const d = dirOf(st), r = rightOf(st); applyCam(V3(st.x, 0, st.z).addScaledVector(d, o.dist ?? 16).addScaledVector(r, o.side ?? 3).add(V3(0, o.h ?? 1.0, 0)), V3(st.x, st.y + 1, st.z), o.fov ?? 40, t); },
  orbit: (st, t, o = {}) => { const a = o.ang; applyCam(V3(st.x + Math.cos(a) * (o.r ?? 9), st.y + (o.h ?? 2.5), st.z + Math.sin(a) * (o.r ?? 9)), V3(st.x, st.y + 0.7, st.z), o.fov ?? 50, t); },
  fixed: (st, t, o = {}) => { applyCam(o.pos, V3(st.x, st.y + 0.8, st.z), o.fov ?? 35, t); },
};
// render the 3D world for one run at simulation time s and paint it into the 2D canvas
function shot3d(runKey, s, camName, camOpts, t, opts = {}) {
  const S = RUN[runKey];
  const st = poseWorld(world, S, s, opts);
  CAMS[camName](st, t, camOpts || {});
  renderer.render(world.scene, cam);
  ctx.save();
  if (opts.filter) ctx.filter = opts.filter;
  ctx.drawImage(glCanvas, 0, 0, W, H);
  ctx.restore();
  return st;
}

// ---------------- 2D look ----------------
const Y = '#ffe600', CY = '#39e6ff', PK = '#ff4fb8', WH = '#ffffff', BK = '#07080d';
const grain = (() => {
  const c = document.createElement('canvas'); c.width = c.height = 512; const g = c.getContext('2d'); const d = g.createImageData(512, 512);
  for (let i = 0; i < d.data.length; i += 4) { const v = Math.floor(rnd(i * 0.37) * 255); d.data[i] = d.data[i + 1] = d.data[i + 2] = v; d.data[i + 3] = 255; }
  g.putImageData(d, 0, 0); return c;
})();
function drawGrain(t, a = 0.07) {
  ctx.save(); ctx.globalAlpha = a; ctx.globalCompositeOperation = 'overlay';
  const ox = Math.floor(rnd(Math.floor(t * 30)) * 512), oy = Math.floor(rnd(Math.floor(t * 30) + 7) * 512);
  for (let x = -ox; x < W; x += 512) for (let y = -oy; y < H; y += 512) ctx.drawImage(grain, x, y);
  ctx.restore();
}
function vignette(a = 0.55) {
  const g = ctx.createRadialGradient(W / 2, H / 2, H * 0.35, W / 2, H / 2, H * 0.95);
  g.addColorStop(0, 'rgba(0,0,0,0)'); g.addColorStop(1, `rgba(0,0,0,${a})`);
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
}
function flash(t, t0, dur = 0.18, col = '255,255,255') {
  const a = 1 - prog(t, t0, dur); if (t < t0 || a <= 0) return;
  ctx.fillStyle = `rgba(${col},${a * 0.85})`; ctx.fillRect(0, 0, W, H);
}
function speedLines(t, k = 1, cx = W / 2, cy = H / 2) {
  ctx.save(); ctx.globalAlpha = 0.35 * k;
  for (let i = 0; i < 70; i++) {
    const a = rnd(i) * Math.PI * 2, ph = (t * (2.5 + rnd(i + 3) * 3) + rnd(i + 9)) % 1;
    const r0 = 380 + ph * 900, r1 = r0 + 90 + rnd(i + 2) * 260;
    ctx.strokeStyle = '#ffffff'; ctx.lineWidth = 1 + rnd(i + 5) * 2.5;
    ctx.beginPath(); ctx.moveTo(cx + Math.cos(a) * r0, cy + Math.sin(a) * r0); ctx.lineTo(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1); ctx.stroke();
  }
  ctx.restore();
}
// big condensed type that punches in
function slam(str, x, y, size, t0, t, o = {}) {
  if (t < t0) return 0;
  const k = t - t0, out = o.until ? 1 - prog(t, o.until - 0.08, 0.08) : 1;
  if (out <= 0) return 0;
  const sc = lerp(o.from ?? 1.7, 1, eo(k / 0.13)) * (1 + (o.pulse ? 0.03 * Math.sin(k * 20) * Math.exp(-k * 4) : 0));
  ctx.save(); ctx.globalAlpha *= clamp(k / 0.05) * out;
  ctx.translate(x, y); ctx.rotate(o.rot ?? -0.035); ctx.scale(sc, sc); ctx.transform(1, 0, o.skew ?? -0.12, 1, 0, 0);
  const fam = o.font ?? 'Anton';
  ctx.font = (fam === 'Anton' ? '400 ' : 'italic 900 ') + size + 'px ' + (fam === 'Anton' ? 'Anton' : '"Inter Tight"');
  ctx.textAlign = o.align ?? 'center'; ctx.textBaseline = 'middle';
  const m = ctx.measureText(str);
  if (o.bg) {
    const w = m.width + size * 0.5, hh = size * 1.12;
    const bx = ctx.textAlign === 'center' ? -w / 2 : ctx.textAlign === 'left' ? -size * 0.25 : -w + size * 0.25;
    ctx.fillStyle = o.bg; ctx.fillRect(bx, -hh / 2, w, hh);
  }
  if (o.stroke !== false) { ctx.lineWidth = size * 0.12; ctx.strokeStyle = o.strokeCol ?? BK; ctx.lineJoin = 'round'; ctx.strokeText(str, 0, 0); }
  ctx.fillStyle = o.color ?? WH; ctx.fillText(str, 0, 0);
  ctx.restore();
  return m.width;
}
function chip(str, x, y, size, col, fg = BK, a = 1, align = 'center') {
  withAlpha(a, () => {
    ctx.font = 'italic 900 ' + size + 'px "Inter Tight"'; const w = ctx.measureText(str).width + size * 0.9;
    const bx = align === 'center' ? x - w / 2 : align === 'left' ? x : x - w;
    ctx.save(); ctx.translate(bx + w / 2, y); ctx.transform(1, 0, -0.15, 1, 0, 0);
    ctx.fillStyle = col; ctx.fillRect(-w / 2, -size * 0.72, w, size * 1.44);
    ctx.fillStyle = fg; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(str, 0, 2); ctx.restore();
  });
}
// TikTok-style captions: 3-4 word chunks, current word in yellow
const NO_CAPTION = new Set(['uwu', 'name', 'gg', 'build', 'out1', 'out2']);
function captions(t) {
  for (const l of TL.lines) {
    if (l.key.startsWith('grade_') || NO_CAPTION.has(l.key)) continue;
    if (t < l.start - 0.05 || t > l.start + l.dur + 0.35) continue;
    const words = l.words;
    const chunks = []; let cur = [];
    words.forEach((w, i) => { cur.push(i); if (cur.length >= 4 || /[,.!?…:]$/.test(w[0])) { chunks.push(cur); cur = []; } });
    if (cur.length) chunks.push(cur);
    let wi = 0; words.forEach((w, i) => { if (t >= w[1] - 0.04) wi = i; });
    const ch = chunks.find(c => c.includes(wi)) || chunks[0];
    const chunkStart = words[ch[0]][1];
    const pop = lerp(1.18, 1, eo((t - chunkStart + 0.04) / 0.12));
    const size = 66;
    ctx.save(); ctx.font = 'italic 900 ' + size + 'px "Inter Tight"'; ctx.textBaseline = 'middle';
    const parts = ch.map(i => words[i][0].toUpperCase());
    const widths = parts.map(p => ctx.measureText(p + ' ').width);
    const total = widths.reduce((a, b) => a + b, 0);
    ctx.translate(W / 2, H - 120); ctx.scale(pop, pop);
    let x = -total / 2;
    ch.forEach((i, k) => {
      const active = i === wi && t <= l.start + l.dur + 0.1;
      ctx.lineWidth = 14; ctx.lineJoin = 'round'; ctx.strokeStyle = BK; ctx.textAlign = 'left';
      ctx.strokeText(parts[k], x, 0);
      ctx.fillStyle = active ? Y : WH; ctx.fillText(parts[k], x, 0);
      x += widths[k];
    });
    ctx.restore();
  }
}
// small HUD-style readout used in the explainer shots
function forceMeter(x, y, f, label, a = 1) {
  withAlpha(a, () => {
    ctx.save(); ctx.translate(x, y); ctx.transform(1, 0, -0.12, 1, 0, 0);
    ctx.fillStyle = 'rgba(7,8,13,0.82)'; ctx.fillRect(0, 0, 470, 150);
    const col = f >= 1.99 ? Y : f > 1.02 ? '#ffb347' : '#ff3b5c';
    ctx.fillStyle = col; ctx.fillRect(0, 0, 10, 150);
    ctx.font = 'italic 800 22px "Inter Tight"'; ctx.fillStyle = '#c9d6e6'; ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
    ctx.fillText(label, 34, 32);
    ctx.font = '400 84px Anton'; ctx.fillStyle = col; ctx.fillText(f.toFixed(2) + '×', 30, 96);
    ctx.fillStyle = '#1b2233'; ctx.fillRect(240, 84, 200, 22); ctx.fillStyle = col; ctx.fillRect(240, 84, 200 * clamp(f - 1), 22);
    ctx.restore();
  });
}
function modeTag(x, y, mode, a = 1, locked = false) {
  const col = mode === 2 ? CY : mode === 1 ? PK : '#9fb0c4';
  chip((locked ? 'LOCKED · ' : 'STORED: ') + (mode === 2 ? 'RIGHT' : mode === 1 ? 'LEFT' : 'NONE'), x, y, 34, col, BK, a);
}
function timerBar(x, y, w, ageMs, a = 1, label = 'FORCE TIMER') {
  withAlpha(a, () => {
    ctx.save(); ctx.translate(x, y); ctx.transform(1, 0, -0.12, 1, 0, 0);
    ctx.fillStyle = 'rgba(7,8,13,0.82)'; ctx.fillRect(-20, -54, w + 40, 124);
    ctx.font = 'italic 800 22px "Inter Tight"'; ctx.fillStyle = '#c9d6e6'; ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
    ctx.fillText(label, 0, -28);
    ctx.textAlign = 'right'; ctx.font = '400 40px Anton'; ctx.fillStyle = WH; ctx.fillText(Math.max(0, Math.floor(ageMs)) + ' MS', w, -26);
    ctx.fillStyle = '#1b2233'; ctx.fillRect(0, 0, w, 26);
    const f = clamp(ageMs / 800);
    ctx.fillStyle = '#ff3b5c'; ctx.fillRect(0, 0, w * Math.min(f, 0.5), 26);
    if (f > 0.5) { ctx.fillStyle = Y; ctx.fillRect(w * 0.5, 0, w * (f - 0.5), 26); }
    ctx.fillStyle = WH; ctx.fillRect(w * 0.5 - 2, -6, 4, 38); ctx.fillRect(w - 2, -6, 4, 38);
    ctx.font = 'italic 800 18px "Inter Tight"'; ctx.textAlign = 'center';
    ctx.fillStyle = '#ff6b85'; ctx.fillText('400: DELAY OVER', w * 0.5, 50); ctx.fillStyle = Y; ctx.textAlign = 'right'; ctx.fillText('800: FULL', w, 50);
    ctx.restore();
  });
}
function hudFromState(st, S, s, extra = {}) {
  const c = st.contact;
  const air = !!st.air;
  const age = (s - st.modeTime) * 1000;
  const lastTake = S.jumps.filter(j => j.takeoff <= s).pop();
  return {
    steer: st.steer, mode: st.mode, contact: [c & 1, c >> 1 & 1, c >> 2 & 1, c >> 3 & 1].map(Boolean),
    icing: [0.94, 0.95, 0.9, 0.91],
    phase: air && lastTake ? 'AIR ' + Math.max(0, Math.floor((s - lastTake.takeoff) * 1000)) + ' ms' : 'GROUND',
    force: air ? (age < 400 ? 'FORCE DELAY' : age < 800 ? 'RECOVERY WINDOW' : 'WINDOW ELAPSED') : 'FORCE ' + st.force.toFixed(2) + 'x',
    detail: 'MODE AGE ' + Math.max(0, Math.floor(age)) + ' ms',
    expl: air ? '400 ms delay | 800 ms max | check on landing' : 'FRONT WHEELS RAISE TIRE FORCE', ...extra,
  };
}
function gradePreview(cx, cy, s, label, lead, a = 1) {
  withAlpha(a, () => {
    ctx.save(); ctx.translate(cx, cy); ctx.scale(s, s);
    box(-112, -45, 225, 91, 13, 'rgba(6,10,23,0.9)'); box(-112, -45, 225, 2, 1, hexA(GRADE[label], 0.72));
    text('TAKEOFF PREVIEW', 0, -31, 10, '#adc7e0', 'center', 'Inter', 700);
    text(label, 0, -1, 48, GRADE[label], 'center', 'Inter', 700);
    text(lead + ' ms BEFORE TAKEOFF', 0, 31, 10, '#c4dbf0', 'center', 'Inter', 700);
    ctx.restore();
  });
}

// ---------------- blushing gorilla (uwu) ----------------
function heart(x, y, s, col) {
  ctx.save(); ctx.translate(x, y); ctx.scale(s, s); ctx.beginPath();
  ctx.moveTo(0, 12); ctx.bezierCurveTo(-26, -6, -12, -30, 0, -14); ctx.bezierCurveTo(12, -30, 26, -6, 0, 12);
  ctx.fillStyle = col; ctx.fill(); ctx.restore();
}
function sparkle(x, y, s, col, rot = 0) {
  ctx.save(); ctx.translate(x, y); ctx.rotate(rot); ctx.scale(s, s); ctx.beginPath();
  for (let i = 0; i < 4; i++) { ctx.rotate(Math.PI / 2); ctx.moveTo(0, 0); ctx.quadraticCurveTo(3, -3, 0, -22); ctx.quadraticCurveTo(-3, -3, 0, 0); }
  ctx.fillStyle = col; ctx.fill(); ctx.restore();
}
function blushGorilla(cx, cy, s, t, blush = 1) {
  ctx.save(); ctx.translate(cx, cy); ctx.scale(s, s);
  const bob = Math.sin(t * 5) * 6;
  ctx.translate(0, bob);
  const fur = '#3a3844', furHi = '#4b4857', skin = '#8e7d8c', skinDk = '#6d5e6c';
  // shoulders
  ctx.beginPath(); ctx.ellipse(0, 330, 360, 210, 0, Math.PI, 0); ctx.fillStyle = fur; ctx.fill();
  // ears
  for (const sx of [-1, 1]) { ctx.beginPath(); ctx.arc(sx * 215, 10, 48, 0, Math.PI * 2); ctx.fillStyle = fur; ctx.fill(); ctx.beginPath(); ctx.arc(sx * 215, 10, 26, 0, Math.PI * 2); ctx.fillStyle = skinDk; ctx.fill(); }
  // head + crest
  ctx.beginPath(); ctx.ellipse(0, -10, 225, 215, 0, 0, Math.PI * 2); ctx.fillStyle = fur; ctx.fill();
  ctx.beginPath(); ctx.ellipse(0, -205, 95, 60, 0, 0, Math.PI * 2); ctx.fillStyle = fur; ctx.fill();
  ctx.beginPath(); ctx.ellipse(-40, -150, 80, 40, -0.3, 0, Math.PI * 2); ctx.fillStyle = furHi; ctx.globalAlpha = 0.5; ctx.fill(); ctx.globalAlpha = 1;
  // face mask
  ctx.beginPath(); ctx.ellipse(-70, -20, 88, 80, 0, 0, Math.PI * 2); ctx.ellipse(70, -20, 88, 80, 0, 0, Math.PI * 2); ctx.fillStyle = skin; ctx.fill();
  ctx.beginPath(); ctx.ellipse(0, 85, 140, 100, 0, 0, Math.PI * 2); ctx.fillStyle = skin; ctx.fill();
  // brow
  ctx.beginPath(); ctx.moveTo(-160, -70); ctx.quadraticCurveTo(-80, -120, 0, -78); ctx.quadraticCurveTo(80, -120, 160, -70); ctx.lineTo(160, -52); ctx.quadraticCurveTo(80, -96, 0, -58); ctx.quadraticCurveTo(-80, -96, -160, -52); ctx.closePath();
  ctx.fillStyle = skinDk; ctx.fill();
  // uwu eyes (closed, curved)
  ctx.strokeStyle = '#1a141c'; ctx.lineWidth = 16; ctx.lineCap = 'round';
  for (const sx of [-1, 1]) { ctx.beginPath(); ctx.arc(sx * 72, -30, 34, 0.15 * Math.PI, 0.85 * Math.PI); ctx.stroke(); }
  // lashes
  ctx.lineWidth = 7;
  for (const sx of [-1, 1]) { ctx.beginPath(); ctx.moveTo(sx * 108, -20); ctx.lineTo(sx * 128, -34); ctx.stroke(); }
  // blush
  withAlpha(blush, () => {
    for (const sx of [-1, 1]) {
      ctx.beginPath(); ctx.ellipse(sx * 118, 32, 56, 30, 0, 0, Math.PI * 2); ctx.fillStyle = 'rgba(255,92,160,0.75)'; ctx.fill();
      ctx.strokeStyle = 'rgba(255,255,255,0.9)'; ctx.lineWidth = 5;
      for (let i = -1; i <= 1; i++) { ctx.beginPath(); ctx.moveTo(sx * 118 + i * 20 - 8, 46); ctx.lineTo(sx * 118 + i * 20 + 8, 18); ctx.stroke(); }
    }
  });
  // nose
  ctx.beginPath(); ctx.moveTo(-58, 52); ctx.quadraticCurveTo(-40, 8, 0, 14); ctx.quadraticCurveTo(40, 8, 58, 52); ctx.quadraticCurveTo(0, 68, -58, 52); ctx.fillStyle = '#4e404d'; ctx.fill();
  for (const sx of [-1, 1]) { ctx.beginPath(); ctx.ellipse(sx * 22, 46, 13, 8, sx * 0.5, 0, Math.PI * 2); ctx.fillStyle = '#1e161d'; ctx.fill(); }
  // ω mouth
  ctx.strokeStyle = '#1a141c'; ctx.lineWidth = 9; ctx.beginPath();
  ctx.arc(-18, 108, 18, 0, Math.PI); ctx.arc(18, 108, 18, 0, Math.PI); ctx.stroke();
  ctx.restore();
}
function sceneUwu(t, t0) {
  const k = t - t0;
  // pink shoujo burst
  ctx.fillStyle = '#ffd1e8'; ctx.fillRect(0, 0, W, H);
  ctx.save(); ctx.translate(W / 2, H / 2); ctx.rotate(k * 0.25);
  for (let i = 0; i < 24; i++) { ctx.rotate(Math.PI * 2 / 24); ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(1400, -120); ctx.lineTo(1400, 120); ctx.closePath(); ctx.fillStyle = i % 2 ? '#ffb8da' : '#ffc6e2'; ctx.fill(); }
  ctx.restore();
  // screentone dots
  ctx.fillStyle = 'rgba(255,120,180,0.18)';
  for (let y = 0; y < H; y += 26) for (let x = (y / 26 % 2) * 13; x < W; x += 26) { const r = 4 + 3 * Math.sin(x * 0.004 + y * 0.003 + k); ctx.beginPath(); ctx.arc(x, y, Math.max(0, r), 0, Math.PI * 2); ctx.fill(); }
  // floating hearts & sparkles
  for (let i = 0; i < 22; i++) {
    const x = rnd(i) * W, y = (H + 100 - ((k * (80 + rnd(i + 1) * 120) + rnd(i + 2) * H) % (H + 200)));
    heart(x, y, 1 + rnd(i + 3) * 1.6, i % 3 ? '#ff4fa0' : '#ffffff');
  }
  for (let i = 0; i < 16; i++) sparkle(rnd(i + 40) * W, rnd(i + 60) * H, (0.8 + 0.8 * Math.abs(Math.sin(k * 4 + i))) * 1.4, '#ffffff', k + i);
  const zoom = lerp(0.72, 0.92, eo(k / 0.5)) + 0.02 * Math.sin(k * 6);
  blushGorilla(W / 2 - 330, H / 2 + 90, zoom, t, 0.7 + 0.3 * Math.sin(k * 9));
  // text
  const tu = LS('uwu');
  if (t >= tu - 0.05) {
    const kk = t - tu + 0.05;
    ctx.save(); ctx.translate(1370, 440); ctx.rotate(-0.08); ctx.scale(lerp(2.2, 1, eo(kk / 0.18)), lerp(2.2, 1, eo(kk / 0.18)));
    ctx.font = '700 300px Fredoka'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.lineWidth = 30; ctx.strokeStyle = '#ffffff'; ctx.lineJoin = 'round'; ctx.strokeText('uwu', 0, 0);
    ctx.fillStyle = '#ff3d97'; ctx.fillText('uwu', 0, 0); ctx.restore();
    heart(1640, 300, 3 * back(kk / 0.4), '#ff3d97');
  }
  withAlpha(eo((k - 0.3) / 0.3), () => {
    ctx.save(); ctx.translate(1370, 700); ctx.rotate(-0.05);
    ctx.font = '700 64px "WenQuanYi Zen Hei"'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.lineWidth = 14; ctx.strokeStyle = '#ffffff'; ctx.strokeText('ゴリラ先輩が', 0, 0); ctx.fillStyle = '#5a2a52'; ctx.fillText('ゴリラ先輩が', 0, 0);
    ctx.font = '700 58px Fredoka'; ctx.strokeText('noticed your S+', 0, 84); ctx.fillStyle = '#5a2a52'; ctx.fillText('noticed your S+', 0, 84);
    ctx.font = '600 30px Fredoka'; ctx.fillStyle = '#b0588f'; ctx.fillText('(gorilla senpai)', 0, 144);
    ctx.restore();
  });
}

// ---------------- sections ----------------
function secCold(t) {
  const s0 = SEC.cold.start;
  const slams = [['ICE.', 0, WH], ['SIDEWAYS.', 2, CY], ['200 KM/H.', 4, Y], ['ZERO GRIP?', 6, PK]];
  const b = Math.floor((t - s0) / BEAT);
  if (t < beatT('cold', 8)) {
    // one-beat 3D flashes between the slams
    const flashes = { 1: ['tease', 3.0, 'side', { side: 7, fwd: 2, h: 0.8, fov: 40 }], 3: ['tease', 3.6, 'front', { dist: 14, side: -4, h: 0.6 }], 5: ['tease', 4.2, 'chase', { dist: 9, h: 2.2, side: 3, fov: 60 }], 7: ['tease', 4.8, 'orbit', { ang: 2.2, r: 7, h: 1.2 }] };
    if (flashes[b]) {
      const [run, sBase, camN, co] = flashes[b];
      shot3d(run, sBase + (t - beatT('cold', b)), camN, co, t);
      speedLines(t, 0.8);
      flash(t, beatT('cold', b), 0.1);
    } else {
      ctx.fillStyle = BK; ctx.fillRect(0, 0, W, H);
    }
    for (const [str, bb, col] of slams) if (b === bb) { shake = 0; slam(str, W / 2, H / 2, 260, beatT('cold', bb), t, { color: col, pulse: true }); }
    return;
  }
  // teaser: big-spin jump, slow motion in the air
  const j = J('tease'), tT = beatT('cold', 10.5);
  const s = remap(t, [[beatT('cold', 8), j.takeoff - 1.4], [tT, j.takeoff], [tT + 1.6, j.takeoff + 0.55], [tT + 2.1, j.land + 0.05]]);
  shake = t > tT + 2.0 && t < tT + 2.3 ? 1.2 : 0;
  shot3d('tease', s, t < tT - 0.2 ? 'side' : 'chase', t < tT - 0.2 ? { side: 8, fwd: 5, h: 1.0, fov: 42 } : { dist: 12, h: 3.2, side: -3, fov: 58 }, t);
  if (t > tT - 0.2) speedLines(t, 0.5);
  flash(t, tT - 0.2, 0.12);
  chip('SLOW-MO', 1720, 80, 30, PK, WH, t > tT && t < tT + 1.8 ? 1 : 0);
}
function secProblem(t) {
  const j = J('prob'), tLand = WT('prob1', 'land') + 0.05;
  const tTake = tLand - (j.land - j.takeoff);
  const slow = tLand + 0.25;
  // after touchdown time crawls at 0.1x so the 400 ms wait fills "…400 milliseconds. Of nothing."
  const s = remap(t, [[SEC.problem.start, j.takeoff - (tTake - SEC.problem.start)], [tTake, j.takeoff], [tLand, j.land], [slow, j.land + 0.25 * 0.4], [WT('prob2', 'nothing') + 0.4, j.land + 0.41], [SEC.problem.end, j.land + 0.62]]);
  shake = t > tLand && t < tLand + 0.25 ? 1.5 : 0;
  const st = shot3d('prob', s, 'chase', { dist: 12, h: 3.8, side: 2, fov: 56 }, t);
  const S = RUN.prob;
  // HUD: stored mode + force
  modeTag(W / 2, 110, st.mode, 1, !!st.air && st.steer > 0.1 && st.mode === 1);
  if (t > tLand - 0.05) {
    forceMeter(80, 760, st.force, 'TIRE FORCE', 1);
    timerBar(1280, 820, 520, (s - st.modeTime) * 1000, 1, 'TIMER STARTED AT TOUCHDOWN');
    slam('NOTHING.', W / 2, 420, 200, WT('prob2', 'nothing'), t, { color: '#ff3b5c', until: SEC.problem.end });
    chip('SWITCHED ON LANDING', W / 2, 190, 30, '#ff3b5c', WH, eo((t - tLand) / 0.2));
    if (t > slow) chip('SLOW-MO ×0.1', 1720, 80, 26, PK, WH);
  }
  flash(t, tLand, 0.12);
}
function secSecret(t) {
  const t0 = SEC.secret.start, j = J('prob');
  // record-scratch rewind: race back from the landing to the approach
  if (t < t0 + 0.7) {
    const k = (t - t0) / 0.7;
    const s = lerp(j.land + 0.9, j.takeoff - 1.2, eio(k));
    shot3d('prob', s, 'chase', { dist: 12, h: 3.8, side: 2, fov: 56 }, t, { filter: 'saturate(0.3) contrast(1.3)' });
    ctx.fillStyle = 'rgba(255,255,255,0.12)';
    for (let i = 0; i < 12; i++) ctx.fillRect(0, (rnd(i + Math.floor(t * 30)) * H) | 0, W, 3 + rnd(i) * 8);
    slam('◀◀ REWIND', 220, 90, 60, t0, t, { color: WH, align: 'left', font: 'Inter' });
    return;
  }
  // slow approach, mode tag rides above the car
  const tA = t0 + 0.7;
  const s = remap(t, [[tA, j.takeoff - 1.2], [tA + 5.2, j.takeoff + 0.05], [tA + 6.5, j.takeoff + 0.6]]);
  const st = shot3d('prob', s, 'side', { side: 10, fwd: 2, h: 1.6, fov: 42 }, t, {
    highlight: (i, st) => (st.contact >> i & 1) ? 0.85 : 0,
  });
  const inAir = !!st.air;
  modeTag(W / 2, 120, st.mode, 1, inAir);
  const tw = WT('secret', 'remembers');
  withAlpha(eo((t - tw) / 0.2), () => {
    slam('LEFT OR RIGHT', W / 2, 300, 120, tw, t, { color: WH, until: WT('secret', 'only') });
  });
  const tg = WT('secret', 'wheel');
  if (t > tg) {
    chip(inAir ? 'ALL WHEELS UP → LOCKED' : 'WHEEL DOWN → CAN CHANGE', W / 2, 860, 44, inAir ? '#ff3b5c' : Y, inAir ? WH : BK, eo((t - tg) / 0.2));
  }
}
function secBullet(t) {
  const t0 = SEC.bullet.start, j = J('trick'), S = RUN.trick;
  const tLip = WT('bt1', 'last', 1) - 0.1;       // "...while the last wheel is still on the lip"
  const tResume = LS('bt2') - 0.1;
  const tLand = WT('bt2', 'land');
  // time: approach at 0.3x, then nearly frozen through the final 80 ms, then flight, landing on "land"
  const sSw = j.switchT;
  const keys = [[t0, sSw - 0.75], [tLip - 1.2, sSw - 0.09], [tResume, sSw + 0.012], [tLand, j.land], [tLand + 3, j.land + 1.6]];
  const s = remap(t, keys);
  const st = sample(S, s);
  const frozen = t > tLip - 1.2 && t < tResume;
  const orbitA = frozen ? lerp(0.6, 2.5, eio((t - tLip + 1.2) / (tResume - tLip + 1.2))) : 0.6;
  const lastWheel = (() => { // wheel that leaves last: largest distance behind the lip
    let best = 0, bx = 1e9; for (let i = 0; i < 4; i++) { const w = WHEELS[i], c = Math.cos(st.yaw), sn = Math.sin(st.yaw); const wx = st.x + w.x * c + w.z * sn; if (wx < bx) { bx = wx; best = i; } } return best;
  })();
  shot3d('trick', s, t < tResume ? (frozen ? 'orbit' : 'side') : 'chase',
    t < tResume ? (frozen ? { ang: orbitA, r: 8.5, h: 1.8, fov: 46 } : { side: 9, fwd: 3, h: 1.4, fov: 44 }) : { dist: 13, h: 4, side: -2, fov: 56 }, t,
    { highlight: (i, sst) => (frozen && (sst.contact >> i & 1)) ? (i === lastWheel ? 1 : 0.5) : 0 });
  shake = t > tLand && t < tLand + 0.3 ? 1.6 : 0;
  // overlays
  modeTag(W / 2, 110, st.mode, 1, false);
  if (frozen) {
    chip('BULLET TIME', 1720, 80, 26, PK, WH);
    // steering gauge: smoothed steer moves 20% per tick, the gate at +10% decides
    withAlpha(eo((t - tLip + 1.2) / 0.3), () => {
      ctx.save(); ctx.translate(W / 2 - 400, 330); ctx.transform(1, 0, -0.12, 1, 0, 0);
      ctx.fillStyle = 'rgba(7,8,13,0.85)'; ctx.fillRect(-30, -70, 860, 150);
      ctx.font = 'italic 800 22px "Inter Tight"'; ctx.fillStyle = '#c9d6e6'; ctx.textAlign = 'left'; ctx.fillText('SMOOTHED STEERING', 0, -40);
      ctx.font = '400 44px Anton'; ctx.textAlign = 'right'; ctx.fillStyle = WH; ctx.fillText((st.steer >= 0 ? '+' : '') + Math.round(st.steer * 100) + '%', 800, -38);
      ctx.fillStyle = '#1b2233'; ctx.fillRect(0, 0, 800, 24);
      ctx.fillStyle = PK; ctx.fillRect(800 * 0.45 - 2, -8, 4, 40); ctx.fillStyle = CY; ctx.fillRect(800 * 0.55 - 2, -8, 4, 40);
      ctx.fillStyle = WH; ctx.fillRect(800 * clamp((st.steer + 1) / 2) - 6, -12, 12, 48);
      ctx.font = 'italic 800 18px "Inter Tight"'; ctx.textAlign = 'left'; ctx.fillStyle = PK; ctx.fillText('−10% GATE', 800 * 0.45 - 110, 50);
      ctx.fillStyle = CY; ctx.fillText('+10% GATE', 800 * 0.55 + 10, 50);
      ctx.restore();
    });
    // the switch moment
    const swT = keys.length && (() => { // video time when sim reaches the switch tick
      for (let tt = tLip - 1.2; tt < tResume; tt += 1 / 120) if (remap(tt, keys) >= sSw) return tt; return tResume;
    })();
    if (t > swT) {
      slam('L → R', W / 2, 560, 220, swT, t, { color: CY, pulse: true });
      chip('ON THE TAKEOFF TICK', W / 2, 720, 38, Y, BK, eo((t - swT) / 0.2));
      flash(t, swT, 0.15, '57,230,255');
    }
    chip('LAST WHEEL ON THE LIP', W / 2, 200, 34, '#78d1ff', BK, eo((t - tLip + 1.0) / 0.3) * (st.contact ? 1 : 0));
  } else if (t >= tResume) {
    const age = (s - st.modeTime) * 1000;
    timerBar(W / 2 - 300, 880, 600, Math.min(age, 1400), 1, st.air ? 'TIMER BURNING IN THE AIR' : 'TIMER DONE BEFORE TOUCHDOWN');
    if (t > tLand - 0.05) {
      forceMeter(80, 120, st.force, 'TIRE FORCE ON LANDING', 1);
      slam('FULL GRIP', W / 2, 420, 200, tLand, t, { color: Y, pulse: true });
      flash(t, tLand, 0.15);
    }
    speedLines(t, 0.4);
  }
}
function secGG(t) {
  const t0 = SEC.gg.start, j = J('trick');
  const s = j.land + 0.4 + (t - t0) * 0.9;
  shake = Math.max(0, 1.4 - (t - t0) * 3);
  shot3d('trick', s, 'front', { dist: 18 - (t - t0) * 1.5, side: 4, h: 0.8, fov: 38 }, t);
  speedLines(t, 1);
  ctx.fillStyle = 'rgba(0,0,0,0.25)'; ctx.fillRect(0, 0, W, H);
  const tg = WT('gg', 'gorilla');
  slam("THAT'S THE", W / 2, 300, 110, LS('gg'), t, { color: WH });
  slam('GORILLA GRIP', W / 2, 520, 330, tg, t, { color: Y, pulse: true });
  if (t > tg) drawPopup('ice', 'S+', W / 2, 800, t - tg, 1.6);
  flash(t, t0, 0.2);
}
const COST = [[0, 0, 'S+'], [10, 0.78, 'S'], [20, 1.83, 'A'], [30, 2.92, 'A'], [50, 5.14, 'B'], [70, 7.93, 'C'], [100, 11.93, 'C'], [160, 19.07, 'D'], [220, 26.59, 'D']];
function secCatch(t) {
  const t0 = SEC.catch.start;
  ctx.fillStyle = '#0c0d14'; ctx.fillRect(0, 0, W, H);
  // diagonal stripes
  ctx.save(); ctx.globalAlpha = 0.06; ctx.fillStyle = Y;
  for (let x = -H; x < W + H; x += 120) { ctx.beginPath(); ctx.moveTo(x + (t * 60) % 120, 0); ctx.lineTo(x + 50 + (t * 60) % 120, 0); ctx.lineTo(x + 50 - H + (t * 60) % 120, H); ctx.lineTo(x - H + (t * 60) % 120, H); ctx.fill(); }
  ctx.restore();
  slam('SPEED LOST AT TAKEOFF', 140, 130, 90, t0, t, { align: 'left', color: WH, rot: 0 });
  text('measured with TICK on ANGULAR ↻ MOMENTUM, deep-slide jump', 150, 200, 26, '#9aa7ba', 'left', 'Inter', 700);
  const x0 = 220, y0 = 760, cw = 1500, ch = 470, bw = 120, gap = (cw - 9 * bw) / 8;
  COST.forEach(([lead, loss, g], i) => {
    const tb = t0 + BEAT * (1 + i * 0.5);
    const k = eo((t - tb) / 0.15);
    const x = x0 + i * (bw + gap), h = Math.max(6, loss / 27 * ch * k);
    if (t < tb) return;
    ctx.save(); ctx.translate(x, y0); ctx.transform(1, 0, -0.1, 1, 0, 0);
    ctx.fillStyle = GRADE[g]; ctx.fillRect(0, -h, bw, h);
    ctx.restore();
    text(lead + ' MS', x + bw / 2, y0 + 40, 30, WH, 'center', 'Mono', 700);
    text(g, x + bw / 2, y0 + 90, 40, GRADE[g], 'center', 'Russo');
    ctx.save(); ctx.font = '400 48px Anton'; ctx.textAlign = 'center'; ctx.fillStyle = WH; ctx.fillText(loss ? '−' + loss.toFixed(1) : '0', x + bw / 2 + 10, y0 - h - 30); ctx.restore();
  });
  const tOuch = t0 + BEAT * 6;
  slam('OUCH', x0 + 8 * (bw + gap) - 30, y0 - ch - 90, 110, tOuch, t, { color: '#ff3b5c', rot: 0.08 });
  const tBest = WT('catch', 'every');
  if (t > tBest) {
    slam('LATEST SWITCH WINS', 700, 330, 110, tBest, t, { color: BK, bg: Y, stroke: false });
  }
}
function secBuild(t) {
  const t0 = SEC.build.start;
  ctx.fillStyle = BK; ctx.fillRect(0, 0, W, H);
  const words = ['SO', 'WE', 'BUILT', 'YOU', 'A…'];
  let x = 260;
  words.forEach((w, i) => {
    const tw = LINE.build.words[i] ? LINE.build.words[i][1] : t0 + i * BEAT / 2;
    if (t >= tw) { const width = slam(w, x, H / 2, 170, tw, t, { align: 'left', color: i === 4 ? Y : WH, rot: 0 }); x += (width || 0) + 60; }
  });
  // glitch bars on the last beats
  if (t > SEC.build.end - BEAT * 2) {
    for (let i = 0; i < 8; i++) { ctx.fillStyle = i % 2 ? CY : PK; ctx.globalAlpha = 0.25; ctx.fillRect(0, rnd(i + Math.floor(t * 24)) * H, W, 4 + rnd(i) * 30); }
    ctx.globalAlpha = 1;
  }
  speedLines(t, prog(t, SEC.build.end - BEAT * 4, BEAT * 4));
}
function logoBlock(cx, cy, s, t, a = 1) {
  withAlpha(a, () => {
    ctx.save(); ctx.translate(cx, cy); ctx.scale(s, s);
    img('noto-gorilla', 0, -250, 230, 1, Math.sin(t * 3) * 0.06);
    slam('GORILLA GRIP', 0, -40, 250, -1, 0, { color: Y, rot: -0.03 });
    slam('TRAINER', 0, 150, 150, -1, 0, { color: WH, bg: PK, stroke: false, rot: -0.03 });
    ctx.restore();
  });
}
function secReveal(t) {
  const t0 = SEC.reveal.start, j = J('game', 1);
  shot3d('game', j.takeoff + 0.3 + (t - t0) * 0.15, 'orbit', { ang: 1 + (t - t0) * 0.4, r: 9, h: 2 }, t, { filter: 'blur(5px) brightness(0.6)' });
  shake = Math.max(0, 1.5 - (t - t0) * 3);
  const k = t - t0;
  ctx.save(); ctx.translate(W / 2, H / 2 + 40); const sc = lerp(1.6, 1, eo(k / 0.18)); ctx.scale(sc, sc);
  logoBlock(0, 0, 1, t, clamp(k / 0.06));
  ctx.restore();
  withAlpha(eo((t - LS('name') - 0.6) / 0.3), () => chip('OPENPLANET PLUGIN · TRACKMANIA', W / 2, 980, 34, WH, BK));
  flash(t, t0, 0.25);
}
function secIngame(t) {
  const t0 = SEC.ingame.start, S = RUN.game, j = S.jumps[0];
  const tTake = t0 + 1.9;
  const s = remap(t, [[t0, j.takeoff - 1.9], [tTake, j.takeoff], [tTake + 5, j.takeoff + 5]]);
  const st = shot3d('game', s, 'chase', { dist: 13, h: 4.2, side: 1.5, fov: 56 }, t);
  shake = s > j.land && s < j.land + 0.25 ? 1.2 : 0;
  // plugin HUD as it sits on screen in game
  physicsWidget(36, 36, 1.15, hudFromState(st, S, s));
  const combo = s > j.land + 0.3 ? 1 : 0;
  const since = s - (j.land + 0.3);
  statsWidget(1480, 40, 1.25, { score: combo ? 180 : 0, combo, best: combo, pulse: combo ? Math.max(0, 1 - since / 0.3) : 0, cpulse: combo ? Math.max(0, 1 - since / 0.3) : 0, gain: 180, gainA: combo ? Math.max(0, 1 - since / 0.8) : 0 });
  if (s > j.takeoff && s < j.land + 0.3) gradePreview(W / 2, 170, 1.6, j.label, j.lead, eo((s - j.takeoff) / 0.1));
  if (s > j.land + 0.3) drawPopup('ice', j.label, W / 2, 200, since, 1.7);
}
const GRADE_ROW = { 'S+': 'EXACTLY 0 MS', S: '≤ 10 MS', A: '≤ 30 MS', B: '≤ 60 MS', C: '≤ 110 MS', D: '≤ 250 MS', MISSED: 'DIDN’T HOLD' };
const GRADE_PTS = { 'S+': 180, S: 150, A: 120, B: 90, C: 60, D: 30, MISSED: 0 };
function secGrades(t) {
  const t0 = SEC.grades.start, j = J('game', 2);
  const calls = TL.lines.filter(l => l.key.startsWith('grade_'));
  let cur = calls[0]; for (const c of calls) if (t >= c.start - 0.05) cur = c;
  const label = cur.text, k = t - cur.start + 0.05;
  const miss = label === 'MISSED';
  shot3d('game', j.takeoff + 0.2 + (t - t0) * 0.08, 'orbit', { ang: 0.4 + (t - t0) * 0.35, r: 8, h: 1.6 }, t,
    { filter: miss ? 'grayscale(1) brightness(0.45)' : 'brightness(0.5) saturate(1.2)' });
  shake = miss ? Math.max(0, 1.6 - k * 4) : Math.max(0, 0.6 - k * 3);
  drawPopup(miss ? 'arcade' : 'ice', label, W / 2, 470, k, 2.4);
  slam(GRADE_ROW[label], W / 2, 760, 90, cur.start, t, { color: GRADE[label] });
  slam(miss ? 'COMBO RESET' : GRADE_PTS[label] + ' PTS × COMBO', W / 2, 870, 54, cur.start + 0.08, t, { color: WH, font: 'Inter' });
  // ladder ticker
  calls.forEach((c, i) => {
    const on = t >= c.start - 0.05;
    const x = W / 2 - 3 * 170 + i * 170;
    withAlpha(on ? 1 : 0.25, () => text(c.text === 'MISSED' ? '☠' : c.text, x, 110, c === cur ? 64 : 44, c === cur ? GRADE[c.text] : '#8fa0b5', 'center', 'Russo'));
  });
  flash(t, cur.start - 0.05, 0.1, miss ? '255,60,90' : '255,255,255');
}
function secUwu(t) {
  const t0 = SEC.uwu.start, tb = WT('blush', 'blushes');
  if (t < tb) {
    // S+ popup frozen over a still of the landing, blush creeping in
    const j = J('game', 0);
    shot3d('game', j.land + 0.3, 'orbit', { ang: 1.3 + (t - t0) * 0.1, r: 10, h: 2 }, t, { filter: 'brightness(0.6)' });
    drawPopup('ice', 'S+', W / 2, 420, 0.9 + (t - t0) * 0.05, 2.6);
    withAlpha(prog(t, tb - 0.8, 0.8), () => { ctx.fillStyle = 'rgba(255,120,190,0.35)'; ctx.fillRect(0, 0, W, H); });
    return;
  }
  sceneUwu(t, tb);
  flash(t, tb, 0.2, '255,200,230');
}
function secFeatures(t) {
  const t0 = SEC.features.start;
  const beats = [
    ['combo', t0], ['popups', WT('feat1', 'Three') - 0.1], ['sounds', lerp(WT('feat1', 'Three'), WT('feat1', 'Every'), 0.52) - 0.1], ['runs', WT('feat1', 'Every') - 0.1],
    ['fps', LS('feat2')], ['updates', WT('feat2', 'Survives')],
  ];
  let cur = beats[0]; for (const b of beats) if (t >= b[1] - 0.08) cur = b;
  const k = t - cur[1] + 0.08;
  const bgRun = { combo: ['game', 2, 'chase'], popups: ['game', 1, 'side'], sounds: ['tease', 0, 'orbit'], runs: ['game', 0, 'front'], fps: ['trick', 0, 'side'], updates: ['tease', 0, 'chase'] }[cur[0]];
  const jj = RUN[bgRun[0]].jumps[bgRun[1]];
  shot3d(bgRun[0], jj.takeoff - 0.6 + k * 0.5, bgRun[2], { ang: 1 + k * 0.3, side: 8, fwd: 2, h: 1.2, dist: 14 }, t, { filter: 'brightness(0.42) saturate(1.3)' });
  flash(t, cur[1] - 0.08, 0.08);
  shake = Math.max(0, 0.8 - k * 4);
  if (cur[0] === 'combo') {
    const n = clamp(Math.floor(k / 0.28) + 1, 1, 8);
    statsWidget(W / 2 - 400, 380, 2.5, { score: [180, 480, 840, 1320, 1770, 2490, 3330, 4770][n - 1], combo: n, best: n, pulse: Math.max(0, 1 - (k % 0.28) / 0.2), cpulse: Math.max(0, 1 - (k % 0.28) / 0.2), gain: 0, gainA: 0 });
    slam('COMBO ×8', W / 2, 220, 170, cur[1], t, { color: Y });
  } else if (cur[0] === 'popups') {
    [['ice', 'S+', 'ICE SHATTER'], ['arcade', 'A', 'ARCADE SLAM'], ['broadcast', 'S', 'BROADCAST SHEEN']].forEach(([st, g, n], i) => {
      const a = k - i * 0.12; if (a < 0) return;
      drawPopup(st, g, 380 + i * 580, 560, a % 2.5, 1.2);
      slam(n, 380 + i * 580, 780, 60, cur[1] + i * 0.12, t, { color: WH, font: 'Inter' });
    });
    slam('3 POPUP STYLES', W / 2, 220, 170, cur[1], t, { color: CY });
  } else if (cur[0] === 'sounds') {
    slam('YOUR OWN SOUNDS', W / 2, 220, 170, cur[1], t, { color: PK });
    ['my_announcer_INCREDIBLE.wav', 'airhorn_x3.mp3', 'mom_saying_nice.ogg'].forEach((f, i) => {
      if (k > 0.1 + i * 0.15) chip('♪ ' + f, W / 2, 470 + i * 130, 48, i === 2 ? Y : WH, BK);
    });
  } else if (cur[0] === 'runs') {
    slam('EVERY RUN SAVED', W / 2, 190, 150, cur[1], t, { color: Y });
    withAlpha(eo(k / 0.2), () => finishSummary(W / 2 - 520, 300, 1.6, cur[1], t + 2, 0));
  } else if (cur[0] === 'fps') {
    slam('ANY FRAME RATE', W / 2, 220, 170, cur[1], t, { color: CY });
    ['30 FPS', '144 FPS', '0.5× SPEED'].forEach((f, i) => {
      if (k < 0.08 + i * 0.12) return;
      gradePreview(420 + i * 540, 560, 2.0, 'S', 10);
      slam(f, 420 + i * 540, 780, 70, cur[1] + 0.08 + i * 0.12, t, { color: WH });
    });
  } else {
    slam('SURVIVES UPDATES', W / 2, 220, 170, cur[1], t, { color: '#7dff9a' });
    ['smoothed steer', 'stored slide mode', 'tire-force multiplier', 'wheel contact ticks'].forEach((f, i) => {
      if (k > 0.1 + i * 0.12) chip('✓ ' + f.toUpperCase(), W / 2, 400 + i * 100, 42, '#7dff9a', BK);
    });
    withAlpha(eo((k - 0.5) / 0.2), () => text('finds its physics offsets in the game code on every load', W / 2, 840, 30, '#c9d6e6', 'center', 'Inter', 700));
  }
}
function secOutro(t) {
  const t0 = SEC.outro.start, j = J('game', 1);
  const tLogo = LS('out2') - 0.15;
  if (t < tLogo) {
    shot3d('game', j.land - 1.8 + (t - t0) * 0.55, 'front', { dist: 22, side: -5, h: 0.7, fov: 34 }, t);
    const ws = [['COUNTERSTEER LATE.', 'Countersteer', CY], ['LAND CLEAN.', 'Land', Y], ['BECOME THE GORILLA.', 'Become', PK]];
    ws.forEach(([str, w, col], i) => { const tw = WT('out1', w); if (t >= tw) slam(str, W / 2, 260 + i * 190, 150, tw, t, { color: col }); });
    shake = 0;
    return;
  }
  ctx.fillStyle = BK; ctx.fillRect(0, 0, W, H);
  shot3d('game', j.land + 2 + (t - tLogo) * 0.3, 'orbit', { ang: 2 + (t - tLogo) * 0.25, r: 11, h: 2.2 }, t, { filter: 'blur(4px) brightness(0.45)' });
  const k = t - tLogo;
  ctx.save(); ctx.translate(W / 2, H / 2 - 20); const sc = lerp(1.4, 1, eo(k / 0.2)); ctx.scale(sc * 0.85, sc * 0.85);
  logoBlock(0, 0, 1, t, clamp(k / 0.06)); ctx.restore();
  withAlpha(eo((k - 0.4) / 0.25), () => chip('github.com/Teuflum/Gorilla-Grip-Trainer', W / 2, 850, 44, WH, BK));
  withAlpha(eo((k - 0.8) / 0.25), () => text('FREE · OPENPLANET PLUGIN · NEEDS VEHICLESTATE', W / 2, 935, 28, '#c9d6e6', 'center', 'Inter', 800));
  withAlpha(eo((k - 1.4) / 0.4), () => {
    text('no gorillas were harmed in the making of this video. several combos were.', W / 2, 1010, 24, '#8fa0b5', 'center', 'Inter', 500);
    ctx.save(); ctx.translate(1700, 240); ctx.rotate(0.12); blushGorilla(0, 0, 0.3, t, 1); ctx.restore();
    ctx.save(); ctx.translate(1700, 380); ctx.rotate(0.12); ctx.font = '700 60px Fredoka'; ctx.textAlign = 'center'; ctx.lineWidth = 10; ctx.strokeStyle = WH; ctx.strokeText('uwu', 0, 0); ctx.fillStyle = '#ff3d97'; ctx.fillText('uwu', 0, 0); ctx.restore();
  });
  flash(t, tLogo, 0.2);
}
const SECTIONS = { cold: secCold, problem: secProblem, secret: secSecret, bullet: secBullet, gg: secGG, catch: secCatch, build: secBuild,
  reveal: secReveal, ingame: secIngame, grades: secGrades, uwu: secUwu, features: secFeatures, outro: secOutro };

function renderAt(t) {
  ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.globalAlpha = 1; ctx.filter = 'none';
  const sec = TL.sections.find(s => t >= s.start && t < s.end) || TL.sections[TL.sections.length - 1];
  shake = 0;
  ctx.fillStyle = BK; ctx.fillRect(0, 0, W, H);
  SECTIONS[sec.id](t);
  if (sec.id !== 'uwu' || t < WT('blush', 'blushes')) vignette(0.5);
  captions(t);
  drawGrain(t, 0.06);
  const fo = prog(t, TL.total - 0.8, 0.8);
  if (fo > 0) { ctx.fillStyle = `rgba(0,0,0,${fo})`; ctx.fillRect(0, 0, W, H); }
}

// ---------------- sound cues ----------------
function buildSfx() {
  const add = (t, name, gain = 1, pitch = 1) => SFX.push({ t: +t.toFixed(3), name, gain, pitch });
  // cold open slams
  [0, 2, 4, 6].forEach(b => add(beatT('cold', b), 'impact', 0.9));
  [1, 3, 5, 7].forEach(b => add(beatT('cold', b) - 0.05, 'whoosh', 0.5));
  const tT = beatT('cold', 10.5); add(tT - 0.2, 'jump', 0.7); add(tT + 2.05, 'land', 0.9);
  // problem
  const jp = J('prob'), tLp = WT('prob1', 'land') + 0.05; add(tLp - (jp.land - jp.takeoff), 'jump', 0.7); add(tLp, 'land', 1.0);
  add(tLp + 0.05, 'buzz', 0.5);
  add(WT('prob2', 'nothing'), 'impact', 0.7);
  // secret: record scratch + rewind
  add(SEC.secret.start - 0.05, 'scratch', 1.0); add(SEC.secret.start + 0.05, 'rewind', 0.6);
  // bullet time
  add(WT('bt1', 'last', 1) - 1.3, 'slowdown', 0.7);
  add(LS('bt2') - 0.1, 'whoosh', 0.7); add(WT('bt2', 'land'), 'land', 1.0); add(WT('bt2', 'land') + 0.02, 'impact', 0.6);
  // gg drop
  add(SEC.gg.start, 'crash', 0.9); add(WT('gg', 'gorilla'), 'shatter', 0.9);
  // catch bars
  COST.forEach((c, i) => add(SEC.catch.start + BEAT * (1 + i * 0.5), 'blip', 0.4, 1 + i * 0.06));
  add(SEC.catch.start + BEAT * 6, 'ouch', 0.7); add(WT('catch', 'every'), 'impact', 0.6);
  // build + reveal
  LINE.build.words.forEach(([w, tw]) => add(tw, 'tick', 0.6));
  add(SEC.reveal.start, 'crash', 1.0); add(SEC.reveal.start, 'impact', 1.0);
  // in game
  const jg = J('game', 0), tTg = SEC.ingame.start + 1.9;
  add(tTg, 'jump', 0.6); add(tTg + (jg.land - jg.takeoff), 'land', 0.8); add(tTg + (jg.land - jg.takeoff) + 0.3, 'shatter', 0.8);
  // grades
  TL.lines.filter(l => l.key.startsWith('grade_')).forEach((l, i) => l.text === 'MISSED' ? add(l.start - 0.02, 'vineboom', 1.0) : add(l.start - 0.02, 'shatter', 0.45 + 0.1 * (6 - i) / 6));
  // uwu
  add(WT('blush', 'blushes'), 'sparkle', 0.8); add(LS('uwu') - 0.05, 'kawaii', 0.6);
  // features
  [SEC.features.start, WT('feat1', 'Three') - 0.1, lerp(WT('feat1', 'Three'), WT('feat1', 'Every'), 0.52) - 0.1, WT('feat1', 'Every') - 0.1].forEach(tt => add(tt, 'impact', 0.55));
  ['Any', 'Survives'].forEach(w => add(WT('feat2', w) - 0.08, 'impact', 0.55));
  // outro
  ['Countersteer', 'Land', 'Become'].forEach(w => add(WT('out1', w), 'impact', 0.6));
  add(LS('out2') - 0.15, 'crash', 0.9);
  SFX.sort((a, b) => a.t - b.t);
}
buildSfx();
window.renderAt = renderAt;
window.SFX = SFX; window.TOTAL = TL.total; window.ready = true;
