// Gorilla Grip Trainer intro video: a deterministic canvas timeline.
// renderAt(t) draws the frame at t seconds; SFX lists the sound cues.
'use strict';
const W = 1920, H = 1080;
const cv = document.getElementById('c');
const ctx = cv.getContext('2d');
let TM = null;
const IMG = {};
const SFX = [];

// ---------- palette (from the plugin's HudColor values) ----------
const C = {
  bg0: '#040711', bg1: '#0a1430', card: 'rgba(6,10,23,0.93)', cardEdge: 'rgba(120,200,255,0.18)',
  cyan: '#08e8de', right: '#0af2de', pink: '#ff63c2', gold: '#ffd147', white: '#e8f5ff',
  label: '#8fadc7', dim: '#5c7896', blue: '#78d1ff', orange: '#ff9459', red: '#ff5787', ice: '#bfeaff',
};
const GRADE = { 'S+': '#fff08c', S: '#ffd647', A: '#0afac7', B: '#61c7ff', C: '#a1a8ff', D: '#ff8c38', MISSED: '#ff5787', UNRATED: '#abc7e6' };
const GRADE_PIC = { 'S+': 'noto-gorilla', S: 'noto-gorilla', A: 'twemoji-flexed-biceps', B: 'twemoji-thumbs-up',
  C: 'twemoji-ok-hand', D: 'twemoji-slightly-smiling-face', MISSED: 'twemoji-skull' };
const CAPTION = { 'S+': 'PERFECT GORILLA GRIP', S: 'GORILLA GRIP', A: 'CLEAN TIMING', B: 'SOLID TIMING',
  C: 'GOOD SETUP', D: 'EARLY SETUP', MISSED: 'GRIP MISSED' };
const POWER = { 'S+': 1, S: 0.8, A: 0.55, B: 0.4, C: 0.3, D: 0.2, MISSED: 0.5 };

// ---------- math ----------
const clamp = (x, a = 0, b = 1) => Math.max(a, Math.min(b, x));
const lerp = (a, b, t) => a + (b - a) * t;
const eo = x => 1 - Math.pow(1 - clamp(x), 3);
const eio = x => { x = clamp(x); return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; };
const back = x => { x = clamp(x); const m = x - 1; return 1 + 2.70158 * m * m * m + 1.70158 * m * m; };
const prog = (t, a, d) => clamp((t - a) / d);
const rnd = i => { const x = Math.sin(i * 12.9898 + 78.233) * 43758.5453; return x - Math.floor(x); };
const inOut = (t, a, b, f = 0.3) => Math.min(prog(t, a, f), 1 - prog(t, b - f, f));

// ---------- timing helpers ----------
const Ls = i => TM.lines[i].start;
const Le = i => TM.lines[i].start + TM.lines[i].dur;
// Approximate the moment a word is spoken from its position in the line.
function Wd(i, word, occ = 0) {
  const txt = TM.lines[i].text;
  let idx = -1, from = 0;
  for (let k = 0; k <= occ; k++) { idx = txt.indexOf(word, from); from = idx + 1; }
  if (idx < 0) throw new Error('cue word not found: ' + word + ' in line ' + i);
  return Ls(i) + TM.lines[i].dur * (idx / txt.length);
}
const scene = id => TM.scenes.find(s => s.id === id);

// ---------- drawing primitives ----------
function rr(x, y, w, h, r) {
  r = Math.min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
}
function box(x, y, w, h, r, fill) { rr(x, y, w, h, r); ctx.fillStyle = fill; ctx.fill(); }
function font(size, fam = 'Inter', weight = 700) {
  ctx.font = (fam === 'Russo' ? '' : weight + ' ') + size + 'px ' + fam;
}
function text(str, x, y, size, color, align = 'left', fam = 'Inter', weight = 700) {
  font(size, fam, weight); ctx.fillStyle = color; ctx.textAlign = align; ctx.textBaseline = 'middle';
  ctx.fillText(str, x, y);
}
function spaced(str, x, y, size, color, align = 'left', spacing = 2, fam = 'Inter', weight = 800) {
  font(size, fam, weight); ctx.letterSpacing = spacing + 'px';
  text(str, x, y, size, color, align, fam, weight); ctx.letterSpacing = '0px';
}
function card(x, y, w, h, accent, r = 22) {
  ctx.save();
  ctx.shadowColor = 'rgba(0,0,0,0.5)'; ctx.shadowBlur = 30; ctx.shadowOffsetY = 10;
  box(x, y, w, h, r, C.card);
  ctx.restore();
  rr(x, y, w, h, r); ctx.strokeStyle = C.cardEdge; ctx.lineWidth = 1.5; ctx.stroke();
  if (accent) { ctx.save(); rr(x, y, w, h, r); ctx.clip(); box(x, y, 7, h, 0, accent); ctx.restore(); }
}
function img(key, x, y, size, alpha = 1, rot = 0) {
  const im = IMG[key]; if (!im) return;
  ctx.save(); ctx.globalAlpha *= alpha; ctx.translate(x, y); ctx.rotate(rot);
  ctx.drawImage(im, -size / 2, -size / 2, size, size); ctx.restore();
}
function withAlpha(a, fn) { if (a <= 0.001) return; ctx.save(); ctx.globalAlpha *= a; fn(); ctx.restore(); }
function hexA(hex, a) {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${n >> 16 & 255},${n >> 8 & 255},${n & 255},${a})`;
}
function wrapLines(str, maxW) {
  const words = str.split(' '); const out = []; let cur = '';
  for (const w of words) {
    const test = cur ? cur + ' ' + w : w;
    if (ctx.measureText(test).width > maxW && cur) { out.push(cur); cur = w; } else cur = test;
  }
  if (cur) out.push(cur); return out;
}
function iceText(str, x, y, size, align = 'center', glow = 1) {
  font(size, 'Russo'); ctx.textAlign = align; ctx.textBaseline = 'middle';
  const g = ctx.createLinearGradient(0, y - size / 2, 0, y + size / 2);
  g.addColorStop(0, '#ffffff'); g.addColorStop(0.5, '#bff4ff'); g.addColorStop(1, '#4fd6ff');
  ctx.save(); ctx.shadowColor = hexA('#3fd9ff', 0.8 * glow); ctx.shadowBlur = 40 * glow;
  ctx.fillStyle = g; ctx.fillText(str, x, y); ctx.restore();
}

// ---------- background ----------
function background(t, tint = 0) {
  const g = ctx.createLinearGradient(0, 0, 0, H);
  g.addColorStop(0, C.bg1); g.addColorStop(1, C.bg0);
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
  const blobs = [[0.25, 0.2, '#08e8de', 0.10], [0.78, 0.25, '#ff63c2', 0.07], [0.55, 0.9, '#3f7bff', 0.10]];
  blobs.forEach(([bx, by, col, a], i) => {
    const x = W * bx + Math.sin(t * 0.13 + i * 2) * 180, y = H * by + Math.cos(t * 0.11 + i) * 90;
    const rg = ctx.createRadialGradient(x, y, 0, x, y, 700);
    rg.addColorStop(0, hexA(col, a)); rg.addColorStop(1, hexA(col, 0));
    ctx.fillStyle = rg; ctx.fillRect(0, 0, W, H);
  });
}
function snow(t, n = 120, alpha = 1) {
  for (let i = 0; i < n; i++) {
    const sz = 1 + rnd(i * 7) * 3.2;
    const x = ((rnd(i) * W + t * (8 + rnd(i + 1) * 22) + Math.sin(t * 0.6 + i) * 18) % W + W) % W;
    const y = ((rnd(i + 2) * H + t * (25 + sz * 16)) % (H + 20)) - 10;
    ctx.fillStyle = `rgba(220,240,255,${(0.18 + rnd(i + 3) * 0.5) * alpha})`;
    ctx.beginPath(); ctx.arc(x, y, sz, 0, Math.PI * 2); ctx.fill();
  }
}

// ---------- side-view car ----------
const WB = 190; // wheelbase in px (rear wheel to front wheel)
function drawCar(rx, ry, a, opts = {}) {
  // (rx, ry): rear wheel ground contact; a: pitch (radians, nose up positive).
  const roll = opts.roll || 0, rearC = opts.rearC, frontC = opts.frontC;
  ctx.save(); ctx.translate(rx, ry); ctx.rotate(-a);
  // shadow-ish glow under
  // body
  ctx.save();
  ctx.shadowColor = 'rgba(0,0,0,0.45)'; ctx.shadowBlur = 20; ctx.shadowOffsetY = 8;
  ctx.beginPath();
  ctx.moveTo(-52, -40); ctx.lineTo(-58, -78); ctx.lineTo(-22, -86); ctx.lineTo(42, -92);
  ctx.quadraticCurveTo(80, -128, 128, -114); ctx.lineTo(158, -90); ctx.lineTo(252, -64);
  ctx.quadraticCurveTo(272, -58, 268, -46); ctx.lineTo(236, -36); ctx.closePath();
  const bg = ctx.createLinearGradient(0, -120, 0, -36);
  bg.addColorStop(0, '#ffffff'); bg.addColorStop(1, '#b9c8dc');
  ctx.fillStyle = bg; ctx.fill();
  ctx.restore();
  // livery stripes
  ctx.beginPath(); ctx.moveTo(-56, -62); ctx.lineTo(262, -54); ctx.lineTo(258, -47); ctx.lineTo(-54, -52); ctx.closePath();
  ctx.fillStyle = C.cyan; ctx.fill();
  ctx.beginPath(); ctx.moveTo(-55, -70); ctx.lineTo(160, -76); ctx.lineTo(160, -71); ctx.lineTo(-55, -65); ctx.closePath();
  ctx.fillStyle = C.pink; ctx.fill();
  // canopy
  ctx.beginPath(); ctx.moveTo(52, -93); ctx.quadraticCurveTo(84, -122, 124, -110); ctx.lineTo(148, -91); ctx.closePath();
  const cg = ctx.createLinearGradient(60, -120, 140, -90); cg.addColorStop(0, '#1b2a44'); cg.addColorStop(1, '#3a6fa0');
  ctx.fillStyle = cg; ctx.fill();
  // rear wing
  box(-70, -114, 58, 9, 3, '#e8f0fa'); box(-44, -106, 6, 22, 2, '#9fb0c4');
  box(-70, -114, 58, 3, 2, C.pink);
  // number
  text('GG', 10, -76, 17, '#0b1830', 'center', 'Russo');
  // wheels
  const wheel = (x, r, contact, front) => {
    ctx.save(); ctx.translate(x, -r);
    if (contact) {
      ctx.shadowColor = front ? C.gold : C.blue; ctx.shadowBlur = 26;
      ctx.beginPath(); ctx.arc(0, 0, r + 5, 0, Math.PI * 2); ctx.strokeStyle = front ? C.gold : C.blue; ctx.lineWidth = 5; ctx.stroke();
      ctx.shadowBlur = 0;
    }
    ctx.beginPath(); ctx.arc(0, 0, r, 0, Math.PI * 2); ctx.fillStyle = '#111722'; ctx.fill();
    ctx.beginPath(); ctx.arc(0, 0, r * 0.58, 0, Math.PI * 2); ctx.fillStyle = '#9fb3c8'; ctx.fill();
    ctx.rotate(roll / r);
    ctx.strokeStyle = '#3c4c60'; ctx.lineWidth = 4;
    for (let k = 0; k < 5; k++) { ctx.rotate(Math.PI * 2 / 5); ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(r * 0.55, 0); ctx.stroke(); }
    ctx.beginPath(); ctx.arc(0, 0, 5, 0, Math.PI * 2); ctx.fillStyle = '#dfe8f2'; ctx.fill();
    // icy rim sparkle
    ctx.beginPath(); ctx.arc(0, 0, r - 3, -1.2, -0.3); ctx.strokeStyle = 'rgba(200,240,255,0.55)'; ctx.lineWidth = 3; ctx.stroke();
    ctx.restore();
  };
  wheel(0, 34, rearC, false); wheel(WB, 30, frontC, true);
  ctx.restore();
}
// Ground profile for a jump shot.
function jumpGeo(rampStart, lip, lipY, land, groundY) {
  const tanA = (groundY - lipY) / (lip - rampStart);
  const landX = land + 170;
  const k = (groundY - lipY + tanA * (landX - lip)) / Math.pow(landX - lip, 2);
  return { rampStart, lip, lipY, land, landX, groundY, tanA, ang: Math.atan(tanA), k };
}
function groundAt(G, x) {
  if (x < G.rampStart) return G.groundY;
  if (x <= G.lip) return G.groundY - (x - G.rampStart) * G.tanA;
  if (x < G.land) return null;
  return G.groundY;
}
function carPose(G, rx) {
  if (rx <= G.lip) {
    const ry = groundAt(G, rx);
    let a = 0;
    for (let it = 0; it < 4; it++) {
      const fx = rx + WB * Math.cos(a);
      const fy = fx <= G.lip ? groundAt(G, fx) : null;
      a = fy === null ? G.ang : Math.asin(clamp((ry - fy) / WB, -1, 1));
    }
    const fx = rx + WB * Math.cos(a);
    return { x: rx, y: ry, a, rearC: true, frontC: fx <= G.lip + 0.5 };
  }
  if (rx < G.landX) {
    const d = rx - G.lip;
    const y = G.lipY - G.tanA * d + G.k * d * d;
    const f = d / (G.landX - G.lip);
    return { x: rx, y, a: lerp(G.ang, 0, eio(f)), rearC: false, frontC: false };
  }
  return { x: rx, y: G.groundY, a: 0, rearC: true, frontC: true };
}
function drawTrack(G, t) {
  const top = G.groundY;
  const iceFill = (path) => {
    const g = ctx.createLinearGradient(0, top - 170, 0, H);
    g.addColorStop(0, '#d8f4ff'); g.addColorStop(0.08, '#8fd4f5'); g.addColorStop(0.35, '#2d6f9e'); g.addColorStop(1, '#0a1c34');
    path(); ctx.fillStyle = g; ctx.fill();
  };
  iceFill(() => {
    ctx.beginPath(); ctx.moveTo(-10, top); ctx.lineTo(G.rampStart, top); ctx.lineTo(G.lip, G.lipY);
    ctx.lineTo(G.lip, H); ctx.lineTo(-10, H); ctx.closePath();
  });
  iceFill(() => { ctx.beginPath(); ctx.rect(G.land, top, W - G.land + 10, H - top); });
  // glossy edge lines
  ctx.strokeStyle = 'rgba(255,255,255,0.9)'; ctx.lineWidth = 4;
  ctx.beginPath(); ctx.moveTo(-10, top); ctx.lineTo(G.rampStart, top); ctx.lineTo(G.lip, G.lipY); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(G.land, top); ctx.lineTo(W + 10, top); ctx.stroke();
  // lip marker
  ctx.fillStyle = 'rgba(255,255,255,0.18)';
  for (let i = 0; i < 6; i++) { const yy = G.lipY + 12 + i * 22; ctx.fillRect(G.lip - 6, yy, 6, 12); }
  // reflections / sparkle
  for (let i = 0; i < 26; i++) {
    const x = rnd(i + 40) * W, yy = top + 20 + rnd(i + 90) * 180;
    if (groundAt(G, x) === null || yy < groundAt(G, x) + 10) continue;
    const a = 0.25 + 0.25 * Math.sin(t * 3 + i);
    ctx.fillStyle = `rgba(255,255,255,${a})`; ctx.fillRect(x, yy, 40 + rnd(i) * 60, 2);
  }
}
function iceSpray(x, y, t, n = 18, dir = -1, alpha = 1) {
  for (let i = 0; i < n; i++) {
    const life = (t * 2.2 + rnd(i)) % 1;
    const px = x + dir * life * (80 + rnd(i + 3) * 160);
    const py = y - life * (40 + rnd(i + 5) * 60) + life * life * 90;
    ctx.fillStyle = `rgba(220,245,255,${(1 - life) * 0.8 * alpha})`;
    ctx.beginPath(); ctx.arc(px, py, 2 + rnd(i + 7) * 4 * (1 - life), 0, Math.PI * 2); ctx.fill();
  }
}

// ---------- HUD pieces for jump shots ----------
function jumpHud(x, y, st) {
  // st: {mode, force, age, slow, rearC, frontC, note}
  card(x, y, 600, 250, C.cyan);
  spaced('STORED SLIDE MODE', x + 32, y + 36, 17, C.label, 'left', 2);
  const mcol = st.mode === 'RIGHT' ? C.right : st.mode === 'LEFT' ? C.pink : C.label;
  text(st.mode, x + 32, y + 78, 44, mcol, 'left', 'Russo');
  spaced('TIRE FORCE', x + 330, y + 36, 17, C.label, 'left', 2);
  const fcol = st.force >= 1.99 ? C.gold : st.force > 1.01 ? '#ffe39a' : C.orange;
  text(st.force.toFixed(2) + '×', x + 330, y + 80, 48, fcol, 'left', 'Mono', 700);
  box(x + 32, y + 128, 536, 16, 8, '#132338');
  box(x + 32, y + 128, 536 * clamp(st.force - 1), 16, 8, fcol);
  spaced('MODE AGE', x + 32, y + 178, 15, C.label, 'left', 2);
  text(st.age === null ? '--' : Math.floor(st.age) + ' ms', x + 32, y + 212, 30, C.white, 'left', 'Mono', 700);
  spaced('WHEELS', x + 330, y + 178, 15, C.label, 'left', 2);
  const dot = (dx, lab, on, col) => {
    box(x + dx, y + 196, 112, 34, 10, on ? hexA(col, 0.22) : '#0c1627');
    rr(x + dx, y + 196, 112, 34, 10); ctx.strokeStyle = on ? col : '#2b3d52'; ctx.lineWidth = 2; ctx.stroke();
    text(lab, x + dx + 56, y + 213, 16, on ? col : C.dim, 'center', 'Inter', 800);
  };
  dot(330, 'REAR', st.rearC, C.blue); dot(456, 'FRONT', st.frontC, C.gold);
  if (st.slow) {
    box(x + 440, y - 22, 160, 38, 19, C.pink);
    text(st.slow, x + 520, y - 3, 17, '#1a0615', 'center', 'Inter', 900);
  }
}
function modeTimer(x, y, w, age, label = 'MODE TIMER') {
  card(x, y, w, 130, C.gold);
  spaced(label, x + 30, y + 32, 16, C.label, 'left', 2);
  const bx = x + 30, by = y + 62, bw = w - 60;
  box(bx, by, bw, 26, 13, '#132338');
  const f = clamp((age || 0) / 800);
  if (age !== null) {
    box(bx, by, bw * Math.min(f, 0.5), 26, 13, C.orange);
    if (f > 0.5) box(bx + bw * 0.5, by, bw * (f - 0.5), 26, 0, C.gold);
  }
  ctx.fillStyle = '#fff'; ctx.fillRect(bx + bw * 0.5 - 1.5, by - 8, 3, 42); ctx.fillRect(bx + bw - 3, by - 8, 3, 42);
  text('0', bx, by + 52, 15, C.label, 'left', 'Mono', 700);
  text('400 ms · delay ends', bx + bw * 0.5, by + 52, 15, C.orange, 'center', 'Mono', 700);
  text('800 ms · full', bx + bw, by + 52, 15, C.gold, 'right', 'Mono', 700);
}
function forceAt(age) { // multiplier vs. mode age with both front wheels down (after touchdown)
  if (age === null) return 1;
  if (age < 400) return 1;
  return Math.min(2, 1 + (age - 400) / 200);
}
function bubble(x, y, str, col, alpha = 1, size = 30) {
  withAlpha(alpha, () => {
    font(size, 'Inter', 900); const w = ctx.measureText(str).width + 44;
    box(x - w / 2, y - 32, w, 64, 32, col);
    ctx.beginPath(); ctx.moveTo(x - 12, y + 30); ctx.lineTo(x, y + 48); ctx.lineTo(x + 12, y + 30); ctx.fillStyle = col; ctx.fill();
    text(str, x, y + 1, size, '#07101f', 'center', 'Inter', 900);
  });
}
function tag(x, y, str, col, alpha = 1, size = 22) {
  withAlpha(alpha, () => {
    font(size, 'Inter', 900); const w = ctx.measureText(str).width + 34;
    box(x - w / 2, y - 22, w, 44, 12, hexA(col, 0.16));
    rr(x - w / 2, y - 22, w, 44, 12); ctx.strokeStyle = col; ctx.lineWidth = 2.5; ctx.stroke();
    text(str, x, y + 1, size, col, 'center', 'Inter', 900);
  });
}

// ---------- the landing popup (three styles) ----------
function drawPopup(style, label, cx, cy, age, sc = 2.1, alpha = 1) {
  if (age < 0) return;
  const p = POWER[label] || 0.3, miss = label === 'MISSED';
  const accent = GRADE[label];
  const k = 1;
  const intro = clamp(age / 0.35);
  const fade = alpha * clamp(intro * 3) * (1 - prog(age, 3.2, 0.5));
  if (fade <= 0) return;
  ctx.save(); ctx.globalAlpha *= fade;
  let ox = 0, oy = 0;
  if (style === 'arcade') {
    const sh = (1 - clamp(age / 0.5)) * 16 * (0.4 + p);
    ox = Math.sin(age * 90) * sh; oy = Math.cos(age * 77) * sh * 0.7;
  }
  if (miss) oy += Math.sin(age * 30) * 6 * (1 - clamp(age / 0.6));
  ctx.translate(cx + ox, cy + oy);
  const scale = sc * (style === 'arcade' ? lerp(1.9, 1, eo(age / 0.22)) : back(age / 0.45) * 0.3 + 0.7 * eo(age / 0.3));
  ctx.scale(scale, scale);
  const pw = 250, ph = 105;
  // rays behind
  if (style !== 'broadcast' && !miss) {
    ctx.save(); ctx.rotate(age * 0.5);
    const n = 12, len = 170 + 90 * p;
    for (let i = 0; i < n; i++) {
      ctx.rotate(Math.PI * 2 / n);
      ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(len, -14); ctx.lineTo(len, 14); ctx.closePath();
      ctx.fillStyle = hexA(accent, 0.10 * (0.5 + p) * clamp(age * 3)); ctx.fill();
    }
    ctx.restore();
  }
  // shockwave
  if (style === 'arcade') {
    const sw = clamp(age / 0.6);
    ctx.beginPath(); ctx.ellipse(0, 0, 40 + 260 * eo(sw), 20 + 130 * eo(sw), 0, 0, Math.PI * 2);
    ctx.strokeStyle = hexA(accent, 0.8 * (1 - sw)); ctx.lineWidth = 6 * (1 - sw) + 1; ctx.stroke();
  }
  // shards / sparks
  const np = Math.floor((6 + 34 * p) * k);
  for (let i = 0; i < np; i++) {
    const ang = rnd(i * 7 + 3) * Math.PI * 2, sp = (120 + 320 * p) * (0.4 + rnd(i * 13) * 0.8);
    const tt = age;
    const px = Math.cos(ang) * sp * tt * 0.9, py = Math.sin(ang) * sp * tt * 0.6 + 160 * tt * tt;
    const life = 1 - clamp(tt / (0.9 + rnd(i) * 0.6));
    if (life <= 0) continue;
    if (style === 'ice') {
      ctx.save(); ctx.translate(px, py); ctx.rotate(tt * (3 + rnd(i) * 6));
      ctx.beginPath(); ctx.moveTo(0, -7); ctx.lineTo(5, 4); ctx.lineTo(-4, 5); ctx.closePath();
      ctx.fillStyle = miss ? `rgba(140,150,165,${life})` : `rgba(160,225,255,${life})`; ctx.fill(); ctx.restore();
    } else if (style === 'arcade') {
      const cols = ['#ffd647', '#59d9ff', '#ff6d91', '#73e673'];
      ctx.strokeStyle = hexA(miss ? '#8c96a5' : cols[i % 4], life); ctx.lineWidth = 3;
      ctx.beginPath(); ctx.moveTo(px, py); ctx.lineTo(px - Math.cos(ang) * 14, py - Math.sin(ang) * 10); ctx.stroke();
    }
  }
  // snowflakes for S / S+
  if (style === 'ice' && (label === 'S+' || label === 'S')) {
    const nf = label === 'S+' ? 10 : 6;
    for (let i = 0; i < nf; i++) {
      const side = i % 2 ? 1 : -1, fx = side * (140 + rnd(i * 17) * 120), fy = -110 + ((age * (40 + rnd(i) * 30) + rnd(i * 3) * 160) % 220);
      img('fluent-3d-snowflake', fx, fy, 14 + rnd(i) * 10, 0.75 * clamp(age * 2) * (1 - prog(age, 2.4, 0.8)), age * (rnd(i) - 0.5) * 3);
    }
  }
  // panel
  ctx.save(); ctx.shadowColor = 'rgba(0,0,0,0.5)'; ctx.shadowBlur = 20; ctx.shadowOffsetY = 5;
  box(-pw / 2, -ph / 2, pw, ph, 16, 'rgba(6,9,23,0.94)'); ctx.restore();
  rr(-pw / 2, -ph / 2, pw, ph, 16); ctx.strokeStyle = hexA(accent, 0.45); ctx.lineWidth = 1.5; ctx.stroke();
  box(-pw / 2 + 16, -ph / 2, pw - 32, 3, 1.5, hexA(accent, 0.9));
  // broadcast outline chase
  if (style === 'broadcast') {
    const per = 2 * (pw + ph), dash = 120;
    ctx.save(); rr(-pw / 2 - 4, -ph / 2 - 4, pw + 8, ph + 8, 19);
    ctx.setLineDash([dash, per - dash]); ctx.lineDashOffset = -age * 700;
    ctx.strokeStyle = accent; ctx.lineWidth = 3; ctx.shadowColor = accent; ctx.shadowBlur = 12; ctx.stroke(); ctx.restore();
  }
  // grade letters
  const letterIn = style === 'broadcast' ? eo(age / 0.35) : back(age / 0.4);
  ctx.save(); ctx.translate(0, -8);
  const ls = style === 'broadcast' ? 1 : lerp(1.6, 1, clamp(letterIn));
  ctx.scale(ls, ls);
  font(miss ? 38 : 60, 'Russo'); ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.shadowColor = accent; ctx.shadowBlur = 18 * (0.4 + p);
  ctx.fillStyle = accent; ctx.fillText(label, 0, miss ? 2 : 0);
  ctx.restore();
  spaced(CAPTION[label], 0, 36, 11, 'rgba(224,245,255,0.95)', 'center', 2.5, 'Inter', 800);
  // sheen
  if (style === 'broadcast') {
    ctx.save(); rr(-pw / 2, -ph / 2, pw, ph, 16); ctx.clip();
    const sx = lerp(-pw, pw, clamp((age - 0.15) / 0.7));
    const g = ctx.createLinearGradient(sx - 60, 0, sx + 60, 0);
    g.addColorStop(0, 'rgba(255,255,255,0)'); g.addColorStop(0.5, 'rgba(255,255,255,0.45)'); g.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = g; ctx.transform(1, 0, -0.5, 1, 0, 0); ctx.fillRect(sx - 80, -ph, 160, ph * 2); ctx.restore();
  }
  // pictures on both sides
  const pic = GRADE_PIC[label];
  const bounce = (label === 'S+' || label === 'S') ? Math.abs(Math.sin(age * 7)) * 8 * (1 - prog(age, 1.8, 1)) : 0;
  const pin = back((age - 0.08) / 0.4);
  img(pic, -pw / 2 - 52, -bounce, 76 * pin, 1, -0.12);
  img(pic, pw / 2 + 52, -bounce, 76 * pin, 1, 0.12);
  // cracks
  if (style === 'ice') {
    const n = Math.floor(4 + 8 * p);
    ctx.save(); ctx.strokeStyle = `rgba(210,242,255,${0.45 * (1 - prog(age, 0.6, 1.2))})`; ctx.lineWidth = 1;
    for (let i = 0; i < n; i++) {
      const ang = rnd(i * 3 + 1) * Math.PI * 2; const len = (60 + rnd(i * 5) * 70) * eo(age / 0.25);
      ctx.beginPath(); let px = Math.cos(ang) * 30, py = Math.sin(ang) * 16; ctx.moveTo(px, py);
      for (let s = 1; s <= 4; s++) {
        const aa = ang + (rnd(i * 11 + s) - 0.5) * 0.7;
        px += Math.cos(aa) * len / 4; py += Math.sin(aa) * len / 4 * 0.6; ctx.lineTo(px, py);
      }
      ctx.stroke();
    }
    ctx.restore();
  }
  ctx.restore();
}

// ---------- plugin widget recreations ----------
function physicsWidget(x, y, s, st) {
  // Mirrors RenderDiagnostics (Widgets.as) at scale s.
  const w = 500 * s, h = 215 * s;
  ctx.save();
  ctx.shadowColor = 'rgba(0,0,0,0.45)'; ctx.shadowBlur = 24 * s; box(x + 3, y + 4, w, h, 13 * s, 'rgba(0,0,0,0.28)');
  ctx.restore();
  box(x, y, w, h, 13 * s, 'rgba(6,10,23,0.93)'); ctx.save(); rr(x, y, w, h, 13 * s); ctx.clip(); box(x, y, 4 * s, h, 0, C.cyan); ctx.restore();
  text('SMOOTHED STEER', x + 20 * s, y + 17 * s, 10 * s, '#8fadc7', 'left', 'Inter', 700);
  text((st.steer >= 0 ? '+' : '') + (st.steer * 100).toFixed(1) + '%', x + 20 * s, y + 42 * s, 28 * s, '#fff', 'left', 'Inter', 700);
  text('STORED SLIDE MODE', x + w - 18 * s, y + 17 * s, 10 * s, '#8fadc7', 'right', 'Inter', 700);
  const mc = st.mode === 2 ? '#0af2de' : st.mode === 1 ? '#ff63c2' : '#99b3cc';
  text(['NEUTRAL', 'LEFT', 'RIGHT'][st.mode], x + w - 18 * s, y + 44 * s, 19 * s, mc, 'right', 'Inter', 800);
  const bx = x + 21 * s, by = y + 67 * s, bw = w - 42 * s;
  box(bx, by, bw, 15 * s, 7 * s, '#17263b');
  box(bx + bw * 0.45, by - 3 * s, 2 * s, 21 * s, 0, '#ff63c2');
  box(bx + bw * 0.55, by - 3 * s, 2 * s, 21 * s, 0, '#0af2de');
  box(bx + bw * clamp((st.steer + 1) / 2) - 3 * s, by - 5 * s, 6 * s, 25 * s, 3 * s, '#fff');
  text('LEFT GATE', bx, by + 29 * s, 10 * s, '#ff63c2', 'left', 'Inter', 700);
  text('RIGHT GATE', bx + bw, by + 29 * s, 10 * s, '#0af2de', 'right', 'Inter', 700);
  const names = ['FL', 'FR', 'RL', 'RR'], tw = 100 * s, th = 40 * s, gx = x + 20 * s, gy = y + 112 * s;
  for (let i = 0; i < 4; i++) {
    const tx = gx + (i % 2) * (tw + 10 * s), ty = gy + Math.floor(i / 2) * (th + 6 * s);
    const front = i < 2, con = st.contact[i];
    const border = !con ? '#2e4057' : front ? '#ffd95c' : '#78d1ff';
    const edge = con ? 2 * s : 1 * s;
    box(tx, ty, tw, th, 7 * s, border);
    box(tx + edge, ty + edge, tw - 2 * edge, th - 2 * edge, 6 * s, con ? '#0f1c30' : '#0a1221');
    box(tx + edge, ty + edge, (tw - 2 * edge) * st.icing[i], th - 2 * edge, 6 * s, `rgba(120,209,255,${con ? 0.22 : 0.10})`);
    text(names[i], tx + 8 * s, ty + 11 * s, 10 * s, con ? border : '#6b8299', 'left', 'Inter', 700);
    text(Math.round(st.icing[i] * 100) + '%', tx + tw - 8 * s, ty + th - 12 * s, 16 * s, con ? '#e8f5ff' : '#8a9eb3', 'right', 'Inter', 700);
  }
  const cx = gx + 2 * tw + 32 * s, cr = x + w - 18 * s;
  text(st.phase, cx, y + 124 * s, 14 * s, '#e6f2ff', 'left', 'Inter', 800);
  text(st.force, cr, y + 124 * s, 12 * s, '#ffd96e', 'right', 'Inter', 800);
  text('ICE AVG ' + Math.round(st.icing.reduce((a, b) => a + b) / 4 * 100) + '%', cx, y + 150 * s, 11 * s, '#78d1ff', 'left', 'Inter', 700);
  text(st.detail, cr, y + 150 * s, 11 * s, '#8cabc4', 'right', 'Inter', 700);
  box(cx, y + 168 * s, cr - cx, 1 * s, 0, '#385775');
  text(st.expl, cx, y + 186 * s, 10 * s, '#7396b3', 'left', 'Inter', 700);
}
function statsWidget(x, y, s, st) {
  const w = 320 * s, h = 150 * s;
  card(x, y, w, h, C.gold, 13 * s);
  const pulse = st.pulse || 0;
  text('SCORE', x + 22 * s, y + 26 * s, 10 * s, '#99bad6', 'left', 'Inter', 800);
  ctx.save(); ctx.translate(x + 22 * s, y + 62 * s); ctx.scale(1 + pulse * 0.12, 1 + pulse * 0.12);
  text(st.score.toLocaleString('en-US'), 0, 0, 40 * s, '#e6faff', 'left', 'Inter', 900); ctx.restore();
  if (st.gain) withAlpha(st.gainA, () => text('+' + st.gain, x + w - 22 * s, y + 62 * s, 18 * s, C.gold, 'right', 'Inter', 800));
  box(x + 22 * s, y + 92 * s, w - 44 * s, 1 * s, 0, '#1c2a3d');
  text('COMBO', x + 22 * s, y + 116 * s, 10 * s, '#99bad6', 'left', 'Inter', 800);
  const cc = st.broken ? C.red : C.gold;
  ctx.save(); ctx.translate(x + 80 * s, y + 117 * s); ctx.scale(1 + (st.cpulse || 0) * 0.3, 1 + (st.cpulse || 0) * 0.3);
  text('x' + st.combo, 0, 0, 26 * s, cc, 'left', 'Inter', 900); ctx.restore();
  text('BEST', x + w - 70 * s, y + 116 * s, 10 * s, '#99bad6', 'right', 'Inter', 800);
  text('x' + st.best, x + w - 22 * s, y + 117 * s, 22 * s, '#75c9ff', 'right', 'Inter', 900);
  if (st.broken) withAlpha(st.brokenA, () => spaced('COMBO BROKEN', x + 80 * s, y + 140 * s, 9 * s, C.red, 'left', 2));
}
function finishSummary(x, y, s, t0, t, skullHi) {
  const w = 650 * s, h = 380 * s;
  card(x, y, w, h, C.gold, 13 * s);
  const cx = x + w / 2, left = x + 25 * s, inner = w - 50 * s;
  text('RUN COMPLETE', cx, y + 36 * s, 27 * s, '#ffdb5e', 'center', 'Russo');
  text('ANGULAR ↻ MOMENTUM', cx, y + 69 * s, 17 * s, '#cfe8ff', 'center', 'Inter', 700);
  const labels = ['FINISH', 'SCORE', 'BEST COMBO'], vals = ['0:41.370', '3,630', 'x6'];
  const gap = 9 * s, sw = (inner - 2 * gap) / 3;
  labels.forEach((l, i) => {
    const bx = left + i * (sw + gap);
    box(bx, y + 91 * s, sw, 68 * s, 10 * s, 'rgba(9,17,33,0.9)');
    text(l, bx + sw / 2, y + 111 * s, 11 * s, '#99bad6', 'center', 'Inter', 800);
    const vc = i === 1 ? '#ffd95c' : i === 2 ? '#99e3ff' : '#fff';
    text(vals[i], bx + sw / 2, y + 138 * s, 24 * s, vc, 'center', 'Inter', 900);
  });
  const grades = ['S+', 'S', 'A', 'B', 'C', 'D'], counts = [2, 5, 4, 3, 1, 1];
  const gg = 7 * s, gw = (inner - 5 * gg) / 6;
  grades.forEach((g, i) => {
    const tx = left + i * (gw + gg), a = eo((t - t0 - 0.25 - i * 0.07) / 0.3);
    withAlpha(a, () => {
      box(tx, y + 181 * s, gw, 88 * s, 10 * s, 'rgba(9,17,33,0.92)');
      box(tx, y + 181 * s, gw, 3 * s, 1.5 * s, GRADE[g]);
      text(g, tx + gw / 2, y + 211 * s, 26 * s, GRADE[g], 'center', 'Russo');
      text('' + counts[i], tx + gw / 2, y + 248 * s, 22 * s, '#fff', 'center', 'Inter', 900);
    });
  });
  // misses + leads
  const my = y + 290 * s;
  box(left, my, inner, 70 * s, 10 * s, skullHi > 0 ? hexA(C.red, 0.12 + 0.2 * skullHi) : 'rgba(9,17,33,0.9)');
  if (skullHi > 0) { rr(left, my, inner, 70 * s, 10 * s); ctx.strokeStyle = hexA(C.red, skullHi); ctx.lineWidth = 3; ctx.stroke(); }
  img('twemoji-skull', left + 36 * s, my + 35 * s, 38 * s * (1 + 0.25 * skullHi * Math.abs(Math.sin(t * 9))), 1);
  text('MISSED  3', left + 64 * s, my + 35 * s, 20 * s, C.red, 'left', 'Inter', 900);
  text('BEST LEAD 0 ms', left + inner * 0.52, my + 24 * s, 14 * s, '#cfe8ff', 'left', 'Inter', 800);
  text('MEDIAN LEAD 20 ms', left + inner * 0.52, my + 48 * s, 14 * s, '#99bad6', 'left', 'Inter', 800);
}

// ---------- scene: intro ----------
function mountains(t, push) {
  const layers = [[0.55, '#1f3a6b', 0.8, 1], [0.64, '#152b54', 1.1, 2], [0.73, '#0b1a38', 1.5, 3]];
  layers.forEach(([base, col, amp, seed]) => {
    ctx.beginPath(); ctx.moveTo(-50, H);
    const pts = [];
    for (let i = 0; i <= 14; i++) {
      const x = -50 + i * (W + 100) / 14 - push * seed * 20;
      const y = H * base - (rnd(i * 13 + seed * 7) * 180 + 40) * amp;
      pts.push([x, y]); ctx.lineTo(x, y);
    }
    ctx.lineTo(W + 50, H); ctx.closePath(); ctx.fillStyle = col; ctx.fill();
    // snowcaps
    pts.forEach(([x, y], i) => {
      if (i === 0 || i === pts.length - 1) return;
      const [px, py] = pts[i - 1], [nx, ny] = pts[i + 1];
      if (y < py && y < ny) {
        ctx.beginPath(); ctx.moveTo(x, y);
        ctx.lineTo(lerp(x, px, 0.22), lerp(y, py, 0.22)); ctx.lineTo(lerp(x, px, 0.1), lerp(y, py, 0.25) + 10);
        ctx.lineTo(x, y + 18); ctx.lineTo(lerp(x, nx, 0.12), lerp(y, ny, 0.25) + 8); ctx.lineTo(lerp(x, nx, 0.22), lerp(y, ny, 0.22));
        ctx.closePath(); ctx.fillStyle = `rgba(220,240,255,${0.25 + seed * 0.12})`; ctx.fill();
      }
    });
  });
}
function sceneIntro(t, S) {
  const lt = t - S.start, push = lt / (S.end - S.start);
  // moon
  const mg = ctx.createRadialGradient(1480, 250, 10, 1480, 250, 260);
  mg.addColorStop(0, 'rgba(230,245,255,0.95)'); mg.addColorStop(0.25, 'rgba(200,235,255,0.35)'); mg.addColorStop(1, 'rgba(200,235,255,0)');
  ctx.fillStyle = mg; ctx.fillRect(1100, 0, 800, 600);
  ctx.beginPath(); ctx.arc(1480, 250, 62, 0, Math.PI * 2); ctx.fillStyle = '#eef8ff'; ctx.fill();
  mountains(t, push);
  // frozen lake
  const g = ctx.createLinearGradient(0, 790, 0, H);
  g.addColorStop(0, '#bfe9ff'); g.addColorStop(0.05, '#5aa8d6'); g.addColorStop(1, '#0b2342');
  ctx.fillStyle = g; ctx.fillRect(0, 790, W, H - 790);
  ctx.strokeStyle = 'rgba(255,255,255,0.8)'; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(0, 790); ctx.lineTo(W, 790); ctx.stroke();
  // the car slides in on "The ice slider."
  const t1 = Ls(1) - 1.4, tf = Le(1) + 0.05;
  const cp = clamp((t - t1) / (tf - t1));
  if (t > t1) {
    const x = lerp(-420, 760, eo(cp));
    iceSpray(x - 20, 790, t, 24, -1, 1 - cp * 0.6);
    iceSpray(x + WB - 10, 790, t + 0.3, 12, -1, 1 - cp * 0.6);
    drawCar(x, 790, 0, { roll: x, rearC: true, frontC: true });
    // documentary pointer label
    const la = eo((t - Ls(1)) / 0.4);
    withAlpha(la, () => {
      ctx.strokeStyle = '#fff'; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.moveTo(x + 120, 670); ctx.lineTo(x + 250, 560); ctx.lineTo(x + 330, 560); ctx.stroke();
      ctx.beginPath(); ctx.arc(x + 120, 670, 6, 0, Math.PI * 2); ctx.fillStyle = '#fff'; ctx.fill();
      text('THE ICE SLIDER', x + 345, 540, 44, '#fff', 'left', 'Russo');
      text('Pilotus glacialis  ·  habitat: RoadIce, occasionally a wall', x + 347, 590, 22, '#bfe0ff', 'left', 'Inter', 500);
    });
  }
  // letterbox + lower third
  const lb = 110 * eo(lt / 1.2);
  ctx.fillStyle = '#000'; ctx.fillRect(0, 0, W, lb); ctx.fillRect(0, H - lb, W, lb);
  const a3 = inOut(t, Ls(0) + 0.2, Ls(1) - 0.9, 0.5);
  withAlpha(a3, () => {
    ctx.fillStyle = '#fff'; ctx.fillRect(120, 200, 4, 92);
    spaced('A GORILLA GRIP NATURE DOCUMENTARY', 144, 222, 20, '#bfe0ff', 'left', 5, 'Inter', 700);
    text('The Frozen Wilderness', 142, 266, 52, '#ffffff', 'left', 'Inter', 800);
  });
}

// ---------- scene: problem ----------
function topDownCar(x, y, rot, s = 1) {
  ctx.save(); ctx.translate(x, y); ctx.rotate(rot); ctx.scale(s, s);
  ctx.save(); ctx.shadowColor = 'rgba(0,0,0,0.5)'; ctx.shadowBlur = 25; ctx.shadowOffsetY = 12;
  box(-125, -58, 250, 116, 40, '#dfe8f3'); ctx.restore();
  [[-80, -62], [-80, 50], [78, -60], [78, 48]].forEach(([wx, wy]) => box(wx - 26, wy, 52, 14, 5, '#0f1520'));
  box(-125, -58, 250, 116, 40, '#eef4fb');
  box(-120, -8, 240, 16, 6, C.cyan); box(-120, -20, 170, 6, 3, C.pink);
  ctx.beginPath(); ctx.ellipse(10, 0, 48, 36, 0, 0, Math.PI * 2); ctx.fillStyle = '#23385a'; ctx.fill();
  box(-140, -52, 22, 104, 6, '#e8f0fa'); box(-140, -52, 5, 104, 2, C.pink);
  ctx.restore();
}
function sceneProblem(t, S) {
  const tCut = Ls(3) - 1.25;
  if (t < tCut) {
    // top-down slide, road scrolling
    const lt = t - S.start;
    ctx.save();
    ctx.fillStyle = '#0c2440'; ctx.fillRect(0, 300, W, 520);
    const rg = ctx.createLinearGradient(0, 330, 0, 790);
    rg.addColorStop(0, '#9fdcff'); rg.addColorStop(0.5, '#d7f3ff'); rg.addColorStop(1, '#9fdcff');
    ctx.fillStyle = rg; ctx.fillRect(0, 330, W, 460);
    ctx.fillStyle = '#ffffff'; ctx.fillRect(0, 322, W, 8); ctx.fillRect(0, 790, W, 8);
    for (let i = 0; i < 40; i++) {
      const x = ((rnd(i) * W * 1.5 - lt * 900) % (W * 1.5) + W * 1.5) % (W * 1.5) - 200;
      ctx.fillStyle = 'rgba(255,255,255,0.55)'; ctx.fillRect(x, 340 + rnd(i + 5) * 440, 90 + rnd(i + 2) * 180, 3);
    }
    // tire marks
    ctx.strokeStyle = 'rgba(40,110,160,0.25)'; ctx.lineWidth = 14;
    [-50, 50].forEach(o => { ctx.beginPath(); ctx.moveTo(0, 560 + o * 1.4); ctx.bezierCurveTo(500, 600 + o, 800, 540 + o, 960, 560 + o); ctx.stroke(); });
    const wob = Math.sin(lt * 1.3) * 0.12;
    const rot = -1.05 + wob;
    for (let i = 0; i < 40; i++) {
      const life = (lt * 1.6 + rnd(i)) % 1;
      const px = 900 - life * (300 + rnd(i + 1) * 500), py = 560 + (rnd(i + 2) - 0.5) * 220 * (0.3 + life);
      ctx.fillStyle = `rgba(255,255,255,${(1 - life) * 0.8})`;
      ctx.beginPath(); ctx.arc(px, py, 3 + rnd(i + 3) * 7 * (1 - life), 0, Math.PI * 2); ctx.fill();
    }
    topDownCar(960, 560, rot, 1.25);
    ctx.restore();
    // speedo + slip
    card(1380, 110, 440, 150, C.cyan);
    spaced('SPEED', 1410, 150, 16, C.label, 'left', 2); spaced('SLIP ANGLE', 1620, 150, 16, C.label, 'left', 2);
    text(Math.round(214 + Math.sin(lt * 2) * 4) + '', 1410, 205, 56, '#fff', 'left', 'Mono', 700);
    text('km/h', 1540, 214, 20, C.label, 'left', 'Inter', 700);
    text(Math.round(62 + wob * 57) + '°', 1620, 205, 56, C.gold, 'left', 'Mono', 700);
    tag(960, 230, 'MAJESTIC', C.cyan, eo((t - Wd(2, 'gracefully')) / 0.3) * (1 - prog(t, tCut - 0.3, 0.3)));
    return;
  }
  const G = jumpGeo(300, 600, 640, 1080, 800);
  const tTake = Wd(3, 'jumps') + 0.15, tLand = Wd(3, 'lands') + 0.12;
  const vx = (G.landX - G.lip) / (tLand - tTake);
  const slow = 0.075; // after landing: game ms per anim ms
  let rx;
  if (t < tLand) rx = G.lip + vx * (t - tTake);
  else { const dt = t - tLand; rx = G.landX + vx * slow * dt * 1.2; }
  drawTrack(G, t);
  const P = carPose(G, rx);
  if (P.rearC && t < tLand) iceSpray(P.x - 10, P.y, t, 16, -1, 0.9);
  drawCar(P.x, P.y, P.a, { roll: rx, rearC: P.rearC, frontC: P.frontC });
  const age = t < tLand ? null : (t - tLand) * 1000 * slow;
  const force = forceAt(age);
  jumpHud(60, 90, { mode: t < tLand ? 'LEFT' : 'RIGHT', force: t < tLand ? 2 : force, age: t < tLand ? 5200 : age, slow: t >= tLand ? 'SLOW-MO' : '', rearC: P.rearC, frontC: P.frontC });
  if (t >= tLand) modeTimer(1180, 90, 680, age, 'TIMER STARTED AT TOUCHDOWN');
  // flip note at touchdown
  if (t >= tLand) {
    const a = eo((t - tLand) / 0.25) * (1 - prog(t, tLand + 2.0, 0.4));
    tag(P.x + 95, P.y - 250, 'DIRECTION SWITCHED ON LANDING', C.orange, a, 22);
  }
  // loading grip bar + question marks
  if (t > tLand + 1.9) {
    const qa = eo((t - tLand - 1.9) / 0.4);
    const pct = Math.round(clamp(force - 1) * 100);
    withAlpha(qa, () => {
      card(700, 330, 520, 120, C.orange);
      text(pct >= 100 ? 'GRIP LOADED. FINALLY.' : 'LOADING GRIP…', 730, 368, 26, pct >= 100 ? C.gold : '#fff', 'left', 'Inter', 900);
      text(pct + '%', 1190, 368, 26, C.gold, 'right', 'Mono', 700);
      box(730, 400, 460, 18, 9, '#132338');
      box(730, 400, 460 * Math.max(0.015, pct / 100), 18, 9, pct >= 100 ? C.gold : C.orange);
    });
  }
  if (t > Wd(4, 'confused') - 0.2) {
    for (let i = 0; i < 3; i++) {
      const a = eo((t - Wd(4, 'confused') + 0.2 - i * 0.15) / 0.3);
      const bob = Math.sin(t * 5 + i) * 8;
      withAlpha(a, () => text('?', P.x + 40 + i * 70, P.y - 200 - i * 26 + bob, 80 + i * 8, i === 1 ? C.gold : '#fff', 'center', 'Russo'));
    }
  }
}

// ---------- scene: science ----------
function sceneScience(t, S) {
  const tDebug = Wd(5, 'debugger');
  const tModes = Ls(6) - 0.2, tChart = Ls(7) + 0.3;
  if (t < tModes) {
    // physics blob being poked
    const pokes = [0.9, 1.6, 2.1, 2.5, 2.8].map(d => Ls(5) + d);
    let wob = 0, stickX = 0;
    pokes.forEach(p => { const d = t - p; if (d > 0) wob += Math.exp(-d * 5) * Math.sin(d * 28) * 18; });
    pokes.forEach(p => { const d = t - p + 0.18; if (d > 0 && d < 0.36) stickX = Math.max(stickX, Math.sin(d / 0.36 * Math.PI) * 60); });
    const bx = 620, by = 380;
    ctx.save(); ctx.translate(bx + 250, by + 170); ctx.scale(1 + wob / 300, 1 - wob / 300);
    card(-250, -170, 500, 340, C.pink, 40);
    text('TRACKMANIA', 0, -80, 28, C.label, 'center', 'Inter', 800);
    text('PHYSICS', 0, -20, 86, '#fff', 'center', 'Russo');
    text('(please do not poke)', 0, 60, 24, C.dim, 'center', 'Inter', 500);
    ctx.restore();
    // stick
    const sx = 180 + stickX;
    ctx.save(); ctx.translate(sx, 560); ctx.rotate(-0.08);
    ctx.fillStyle = '#8a5a2b'; ctx.beginPath(); ctx.moveTo(-200, -9); ctx.lineTo(260, -6); ctx.lineTo(262, 6); ctx.lineTo(-200, 12); ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#6b431f'; ctx.fillRect(40, -18, 30, 8);
    ctx.restore();
    // debugger window
    const da = eo((t - tDebug + 0.2) / 0.35);
    if (da > 0) {
      const dx = lerp(W + 50, 1180, da);
      card(dx, 180, 680, 620, C.cyan, 16);
      text('debugger — Trackmania.exe', dx + 30, 216, 18, C.label, 'left', 'Mono', 700);
      const lines = [
        ['vehicle+0x1430', 'smoothed steer', '+0.102362', C.white],
        ['vehicle+0x14dc', 'tire-force mult', '1.000000', C.orange],
        ['model+0x1194', 'recovery delay', '400', C.gold],
        ['cmp', 'steer, ±0.1', '→ slide mode', C.cyan],
        ['wheel[2].contact', 'rear-right', '1', C.blue],
        ['vehicle+0x1c44', 'icing coef', '0.800000', C.ice],
      ];
      lines.forEach(([a, b, c, col], i) => {
        const la = eo((t - tDebug - 0.1 - i * 0.12) / 0.2);
        withAlpha(la, () => {
          const yy = 270 + i * 82;
          box(dx + 24, yy - 30, 632, 66, 10, 'rgba(20,36,58,0.7)');
          text(a, dx + 44, yy - 8, 20, col, 'left', 'Mono', 700);
          text(b, dx + 44, yy + 18, 16, C.label, 'left', 'Mono', 500);
          text(c, dx + 636, yy + 2, 22, '#fff', 'right', 'Mono', 700);
        });
      });
    }
    return;
  }
  if (t < tChart) {
    // the note: left or right
    const tl = Wd(6, 'which'), tr = Wd(6, 'right.');
    const flip = t < tr - 0.1 ? 0 : 1;
    const fl = t < tl - 0.1 ? -1 : flip;
    const cx = 960, cy = 520;
    card(cx - 380, cy - 220, 760, 400, C.gold, 30);
    spaced('THE GAME QUIETLY REMEMBERS', cx, cy - 160, 22, C.label, 'center', 4);
    const flipT = fl < 0 ? 0 : clamp((t - (fl === 0 ? tl : tr) + 0.1) / 0.3);
    const sc = Math.abs(Math.cos(flipT * Math.PI));
    const show = fl < 0 ? '???' : (flipT < 0.5 ? (fl === 0 ? '???' : 'LEFT') : (fl === 0 ? 'LEFT' : 'RIGHT'));
    const col = show === 'LEFT' ? C.pink : show === 'RIGHT' ? C.right : C.dim;
    ctx.save(); ctx.translate(cx, cy - 10); ctx.scale(1, Math.max(0.05, sc));
    text(show, 0, 0, 150, col, 'center', 'Russo'); ctx.restore();
    text(show === 'LEFT' ? '◀ sliding left' : show === 'RIGHT' ? 'sliding right ▶' : 'stored slide direction', cx, cy + 120, 30, '#cfe3f5', 'center', 'Inter', 700);
    return;
  }
  // chart: multiplier vs time since the direction changed
  const x0 = 260, y0 = 830, cw = 1400, ch = 500;
  const X = ms => x0 + ms / 1000 * cw, Y = f => y0 - (f - 0.8) / 1.4 * ch;
  const ca = eo((t - tChart) / 0.4);
  withAlpha(ca, () => {
    text('Tire-force multiplier after a direction change', x0, 190, 40, '#fff', 'left', 'Inter', 800);
    text('measured on ice · both front wheels on the ground', x0, 238, 24, C.label, 'left', 'Inter', 500);
    ctx.strokeStyle = '#2b4260'; ctx.lineWidth = 2;
    [1, 1.5, 2].forEach(f => { ctx.beginPath(); ctx.moveTo(x0, Y(f)); ctx.lineTo(x0 + cw, Y(f)); ctx.stroke(); text(f.toFixed(1) + '×', x0 - 20, Y(f), 22, C.label, 'right', 'Mono', 700); });
    [0, 200, 400, 600, 800, 1000].forEach(ms => text(ms + ' ms', X(ms), y0 + 34, 20, C.label, 'center', 'Mono', 500));
    // zones
    box(X(0), Y(2.2), X(400) - X(0), Y(0.8) - Y(2.2), 0, hexA(C.orange, 0.10));
    spaced('FORCE DELAY', X(200), Y(2.12), 20, C.orange, 'center', 3);
    box(X(400), Y(2.2), X(800) - X(400), Y(0.8) - Y(2.2), 0, hexA(C.gold, 0.06));
    spaced('RECOVERY WINDOW', X(600), Y(2.12), 20, C.gold, 'center', 3);
    ctx.setLineDash([10, 10]); ctx.strokeStyle = C.gold; ctx.beginPath(); ctx.moveTo(X(800), Y(2.2)); ctx.lineTo(X(800), y0); ctx.stroke(); ctx.setLineDash([]);
  });
  const t400 = Wd(7, '400'), tBack = Wd(7, 'climb');
  const drawTo = t < t400 ? lerp(0, 380, prog(t, tChart + 0.3, t400 - tChart - 0.3)) : lerp(380, 1000, prog(t, t400 + 0.3, tBack - t400 + 0.3));
  ctx.save(); ctx.beginPath();
  for (let ms = 0; ms <= drawTo; ms += 5) { const f = forceAt(ms); ms === 0 ? ctx.moveTo(X(ms), Y(f)) : ctx.lineTo(X(ms), Y(f)); }
  ctx.strokeStyle = C.cyan; ctx.lineWidth = 7; ctx.lineJoin = 'round'; ctx.shadowColor = C.cyan; ctx.shadowBlur = 20; ctx.stroke(); ctx.restore();
  const hx = X(drawTo), hy = Y(forceAt(drawTo));
  ctx.beginPath(); ctx.arc(hx, hy, 12, 0, Math.PI * 2); ctx.fillStyle = '#fff'; ctx.fill();
  tag(X(200), Y(1) - 70, 'STUCK AT 1.0×', C.orange, eo((t - Wd(7, 'drops')) / 0.3));
  tag(X(700), Y(2) - 70, 'BACK TO 2.0×', C.gold, eo((t - tBack - 0.3) / 0.3));
}

// ---------- scene: trick ----------
function sceneTrick(t, S) {
  const G = jumpGeo(520, 820, 640, 1250, 800);
  const tSwitch = Wd(9, 'clinging') + 0.05, tTake = tSwitch + 0.22, tLand = Wd(10, 'land') + 0.1;
  const vx = (G.landX - G.lip) / (tLand - tTake);
  const tA = tSwitch - 1.2;
  let rx = G.lip + vx * (t - tTake);
  if (t < tA) rx = G.lip + vx * (tA - tTake) - vx * 0.5 * (tA - t);
  drawTrack(G, t);
  const P = carPose(G, rx);
  if (P.rearC) iceSpray(P.x - 10, P.y, t, 14, -1, 0.9);
  // "any wheel on the ground" callouts during line 8
  const a8 = inOut(t, Wd(8, 'wheel') - 0.3, tSwitch - 0.4, 0.3);
  // glow the last wheel
  if (t > tSwitch - 0.9 && t < tTake + 0.25 && P.rearC) {
    const pul = 0.5 + 0.5 * Math.sin(t * 16);
    ctx.save(); ctx.strokeStyle = hexA(C.blue, 0.6 + 0.4 * pul); ctx.lineWidth = 5; ctx.setLineDash([10, 8]);
    ctx.beginPath(); ctx.arc(P.x, P.y - 34, 64, 0, Math.PI * 2); ctx.stroke(); ctx.restore();
    tag(P.x - 60, P.y + 80, 'LAST WHEEL, CLINGING ON', C.blue, eo((t - tSwitch + 0.9) / 0.3));
  }
  drawCar(P.x, P.y, P.a, { roll: rx, rearC: P.rearC, frontC: P.frontC });
  withAlpha(a8, () => {
    card(760, 330, 640, 140, C.cyan);
    text('Wheel on the ground →  direction can change', 790, 375, 28, '#fff', 'left', 'Inter', 800);
    text('All wheels in the air →  locked', 790, 425, 28, C.label, 'left', 'Inter', 800);
  });
  // switch flash
  if (t > tSwitch) {
    const f = t - tSwitch;
    withAlpha(1 - clamp(f / 0.5), () => { ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, W, H); });
    bubble(P.x + 80, P.y - 230, 'SWITCH!', C.gold, eo(f / 0.2) * (1 - prog(f, 1.2, 0.3)), 34);
  }
  const age = t < tSwitch ? null : (t - tSwitch) / (tLand - tTake) * 1000;
  let force = 1;
  if (t < tSwitch) force = 2;
  else if (t >= tLand) force = age >= 800 ? 2 : forceAt(age);
  jumpHud(60, 90, { mode: t < tSwitch ? 'LEFT' : 'RIGHT', force, age: t < tSwitch ? 6400 : age, slow: t < tLand + 0.4 ? 'SLOW-MO' : '', rearC: P.rearC, frontC: P.frontC });
  if (t >= tSwitch) modeTimer(1180, 90, 680, age, t < tLand ? 'TIMER RUNNING — IN THE AIR' : 'TIMER DONE BEFORE TOUCHDOWN');
  if (t > tLand) {
    const f = t - tLand;
    tag(G.landX + 100, G.groundY + 70, 'FULL GRIP ON LANDING  2.00×', C.gold, eo(f / 0.25) * (1 - prog(f, 1.6, 0.3)), 24);
  }
  // the gorilla grip popup
  const tPop = Wd(10, 'gorilla') - 0.15;
  if (t > tPop) {
    withAlpha(clamp((t - tPop) / 0.2) * 0.45, () => { ctx.fillStyle = '#02050c'; ctx.fillRect(0, 0, W, H); });
    drawPopup('ice', 'S+', 960, 560, t - tPop, 2.6);
  }
}

// ---------- scene: catch (speed cost bar chart) ----------
const COST = [[0, 0, 'S+'], [10, 0.78, 'S'], [20, 1.83, 'A'], [30, 2.92, 'A'], [50, 5.14, 'B'], [70, 7.93, 'C'], [100, 11.93, 'C'], [160, 19.07, 'D'], [220, 26.59, 'D']];
function sceneCatch(t, S) {
  const lt = t - S.start;
  text('Speed lost at takeoff vs. how early you switched', 200, 170, 42, '#fff', 'left', 'Inter', 800);
  text('measured with TICK · first ice jump of ANGULAR ↻ MOMENTUM · deep 111–126° slide', 200, 220, 22, C.label, 'left', 'Inter', 500);
  const x0 = 260, y0 = 780, cw = 1440, ch = 470;
  const bw = 110, gap = (cw - COST.length * bw) / (COST.length - 1);
  ctx.strokeStyle = '#2b4260'; ctx.lineWidth = 2;
  [0, 10, 20, 30].forEach(v => {
    const y = y0 - v / 30 * ch; ctx.beginPath(); ctx.moveTo(x0 - 20, y); ctx.lineTo(x0 + cw, y); ctx.stroke();
    text(v ? '−' + v : '0', x0 - 34, y, 20, C.label, 'right', 'Mono', 700);
  });
  text('km/h', x0 - 34, y0 - ch - 40, 20, C.label, 'right', 'Inter', 700);
  const tStart = Ls(11) + 1.0;
  COST.forEach(([lead, loss, g], i) => {
    const x = x0 + i * (bw + gap);
    const gp = eo((t - tStart - i * 0.28) / 0.6);
    const h = Math.max(4, loss / 30 * ch * gp);
    const col = GRADE[g];
    ctx.save(); ctx.shadowColor = col; ctx.shadowBlur = 16;
    box(x, y0 - h, bw, h, 10, hexA(col, 0.85)); ctx.restore();
    text(lead + ' ms', x + bw / 2, y0 + 34, 22, '#fff', 'center', 'Mono', 700);
    text(g, x + bw / 2, y0 + 70, 26, col, 'center', 'Russo');
    withAlpha(gp, () => text(loss ? '−' + loss.toFixed(1) : '0', x + bw / 2, y0 - h - 26, 22, '#fff', 'center', 'Mono', 700));
  });
  const tOuch = tStart + 8 * 0.28 + 0.5;
  const xl = x0 + 8 * (bw + gap) + bw / 2;
  bubble(xl - 60, y0 - ch - 30, 'OUCH.', C.red, eo((t - tOuch) / 0.25) * (1 - prog(t, Ls(12) + 3, 0.3)));
  const tBest = Wd(12, 'best');
  const ba = eo((t - tBest) / 0.35);
  if (ba > 0) {
    const bx = x0 + bw / 2;
    ctx.save(); ctx.strokeStyle = hexA(GRADE['S+'], ba); ctx.lineWidth = 4; ctx.setLineDash([10, 8]);
    rr(x0 - 16, y0 - 120, bw + 32, 210, 18); ctx.stroke(); ctx.restore();
    img('fluent-3d-trophy', bx, y0 - 190, 110 * back((t - tBest) / 0.5), ba);
    withAlpha(ba, () => {
      card(x0 + 170, y0 - 330, 620, 110, GRADE['S+']);
      text('Latest switch that still counts', x0 + 200, y0 - 292, 30, '#fff', 'left', 'Inter', 800);
      text('= switch on the takeoff tick = S+', x0 + 200, y0 - 250, 24, GRADE['S+'], 'left', 'Inter', 700);
    });
  }
}

// ---------- scene: plugin ----------
function logo(cx, cy, s, t, a = 1) {
  withAlpha(a, () => {
    img('noto-gorilla', cx, cy - 150 * s, 200 * s, 1, Math.sin(t * 2) * 0.05);
    iceText('GORILLA GRIP', cx, cy + 20 * s, 150 * s);
    spaced('T R A I N E R', cx, cy + 130 * s, 48 * s, C.gold, 'center', 10 * s, 'Inter', 900);
  });
}
function scenePlugin(t, S) {
  const tIntro = Wd(14, 'Gorilla') - 0.2, tWidget = Wd(14, 'reads') - 0.3, tJudge = Wd(15, 'Mercilessly') - 0.05;
  if (t < tIntro) {
    // personal trainer: gorilla with a whistle and clipboard
    const a = eo((t - S.start - 0.2) / 0.5);
    const bob = Math.sin(t * 3) * 10;
    img('noto-gorilla', 960, 470 + bob, 360 * back((t - S.start - 0.2) / 0.6), a);
    withAlpha(a, () => {
      // whistle on a string
      ctx.strokeStyle = '#ff63c2'; ctx.lineWidth = 4; ctx.beginPath(); ctx.moveTo(900, 560 + bob); ctx.quadraticCurveTo(960, 660 + bob, 1020, 560 + bob); ctx.stroke();
      box(940, 640 + bob, 60, 30, 12, C.gold); ctx.beginPath(); ctx.arc(975, 655 + bob, 9, 0, Math.PI * 2); ctx.fillStyle = '#8a6a14'; ctx.fill();
      // clipboard
      ctx.save(); ctx.translate(1240, 560 + bob * 0.5); ctx.rotate(0.12);
      box(-90, -120, 180, 240, 12, '#b98545'); box(-75, -100, 150, 205, 6, '#f4f7fb'); box(-30, -130, 60, 26, 6, '#7d8ea3');
      ['S+ ✓', 'S  ✓', 'A  ✓', 'D  …'].forEach((l, i) => text(l, -55, -60 + i * 44, 26, i < 3 ? '#1f7a4d' : '#b04a2a', 'left', 'Inter', 800));
      ctx.restore();
    });
    tag(960, 820, 'PERSONAL TRAINER', C.gold, eo((t - Wd(13, 'personal')) / 0.3), 34);
    return;
  }
  const lg = eo((t - tIntro) / 0.6);
  const toTop = eo((t - tWidget) / 0.6);
  const cy = lerp(500, 170, toTop), s = lerp(1, 0.48, toTop);
  logo(960, cy, s, t, lg);
  withAlpha(lg * (1 - toTop), () => text('an Openplanet plugin for Trackmania', 960, 800, 34, C.label, 'center', 'Inter', 700));
  if (t > tWidget) {
    const wa = eo((t - tWidget) / 0.5);
    const lt = t - tWidget - 0.6;
    // one tick = 0.1 s of animation: steer sweeps −1 → +1 in 0.2 steps; it crosses +0.1 on
    // tick 6 (the switch) and the last wheel leaves on tick 7, a 10 ms lead → S.
    const TK = 0.18, tick = Math.floor(lt / TK);
    const step = clamp(tick, 0, 10);
    const steer = -1 + step * 0.2;
    const switched = tick >= 6, air = tick >= 7;
    const modeAge = switched ? Math.max(0, (lt / TK - 6) * 10) : 6120;
    const st = {
      steer, mode: switched ? 2 : 1,
      contact: air ? [false, false, false, false] : tick >= 5 ? [false, false, false, true] : [true, true, true, true],
      icing: [0.93, 0.95, 0.88, 0.9],
      phase: air ? 'AIR ' + Math.floor((lt / TK - 7) * 10) + ' ms' : 'GROUND',
      force: air ? (modeAge < 400 ? 'FORCE DELAY' : 'RECOVERY WINDOW') : 'FORCE ' + (switched ? '1.00x' : (Math.abs(steer) ** 1.5 + 1).toFixed(2) + 'x'),
      detail: 'MODE AGE ' + Math.floor(modeAge) + ' ms',
      expl: air ? '400 ms delay | 800 ms max | check on landing' : 'FRONT WHEELS RAISE TIRE FORCE',
    };
    ctx.save(); ctx.translate(0, (1 - wa) * 60); ctx.globalAlpha *= wa;
    physicsWidget(170, 330, 1.9, st);
    // physics tick ruler with playhead
    const rx = 190, ry = 810, rw = 910, n = 16;
    text('10 ms PHYSICS TICKS', rx, ry - 44, 18, C.label, 'left', 'Inter', 800);
    for (let i = 0; i <= n; i++) {
      const x = rx + i * rw / n, sw = i === 6, to = i === 7;
      const col = sw ? C.cyan : to ? C.gold : i <= tick ? '#7c9cbd' : '#34506e';
      box(x - 2, ry - (sw || to ? 20 : 12), 4, sw || to ? 40 : 24, 2, col);
    }
    const ph = rx + clamp(lt / TK, 0, n) * rw / n;
    box(ph - 1, ry - 30, 2, 60, 1, '#fff');
    if (tick >= 6) text('switch', rx + 6 * rw / n, ry + 42, 18, C.cyan, 'center', 'Inter', 800);
    if (tick >= 7) text('takeoff', rx + 7 * rw / n + 22, ry + 42, 18, C.gold, 'left', 'Inter', 800);
    ctx.restore();
    // takeoff preview (RenderGradePreview) pops in after takeoff
    const pa = back((lt - 7 * TK) / 0.4);
    if (lt > 7 * TK) {
      ctx.save(); ctx.translate(1450, 540); ctx.scale(pa, pa);
      box(-240, -110, 480, 220, 26, 'rgba(6,10,23,0.95)'); box(-240, -110, 480, 5, 2, GRADE.S);
      text('TAKEOFF PREVIEW', 0, -68, 22, '#adc7e0', 'center', 'Inter', 800);
      text('S', 0, 2, 96, GRADE.S, 'center', 'Russo');
      text('10 ms BEFORE TAKEOFF', 0, 72, 22, '#c4dbf0', 'center', 'Inter', 800);
      ctx.restore();
    }
  }
  if (t > tJudge) {
    const f = t - tJudge;
    const sc = lerp(3, 1, eo(f / 0.18));
    const shake = f < 0.4 ? Math.sin(f * 80) * (0.4 - f) * 30 : 0;
    ctx.save(); ctx.translate(1450 + shake, 560); ctx.rotate(-0.18); ctx.scale(sc, sc);
    ctx.globalAlpha *= clamp(f / 0.1);
    ctx.strokeStyle = C.red; ctx.lineWidth = 10; rr(-230, -75, 460, 150, 18); ctx.stroke();
    ctx.lineWidth = 3; rr(-214, -59, 428, 118, 12); ctx.stroke();
    text('JUDGED', 0, 4, 100, C.red, 'center', 'Russo');
    ctx.restore();
  }
}

// ---------- scene: grades ----------
const LADDER = [['S+', 'exactly 0 ms', 180], ['S', 'up to 10 ms', 150], ['A', 'up to 30 ms', 120], ['B', 'up to 60 ms', 90], ['C', 'up to 110 ms', 60], ['D', 'up to 250 ms', 30], ['MISSED', 'direction did not hold', 0]];
function sceneGrades(t, S) {
  const cues = [Wd(16, 'S+'), Wd(16, 'S.', 0), Wd(17, 'A,'), Wd(17, 'B,'), Wd(17, 'C '), Wd(17, 'D '), Wd(18, 'MISSED')];
  const tRules = Wd(19, 'you do') - 0.2;
  const shiftL = eo((t - tRules) / 0.6);
  const lx = lerp(460, 110, shiftL);
  spaced('SWITCH LEAD BEFORE TAKEOFF', lx + 30, 120, 20, C.label, 'left', 3);
  spaced('BASE POINTS', lx + 960, 120, 20, C.label, 'right', 3);
  LADDER.forEach(([g, lead, pts], i) => {
    const a = eo((t - cues[i] + 0.1) / 0.3);
    if (a <= 0) return;
    const y = 160 + i * 112, col = GRADE[g];
    const miss = g === 'MISSED';
    let dx = (1 - a) * -80;
    if (miss) dx += Math.sin((t - cues[i]) * 40) * 10 * (1 - clamp((t - cues[i]) / 0.8));
    withAlpha(a, () => {
      ctx.save(); ctx.translate(dx, 0);
      box(lx, y, 1000, 96, 18, miss ? 'rgba(60,10,25,0.8)' : 'rgba(8,14,30,0.9)');
      box(lx, y, 8, 96, 4, col);
      text(g, lx + 60, y + 50, miss ? 38 : 52, col, 'left', 'Russo');
      img(GRADE_PIC[g], lx + (miss ? 340 : 200), y + 48, 70 * back((t - cues[i]) / 0.4));
      text(lead, lx + (miss ? 400 : 270), y + 50, 30, '#fff', 'left', 'Inter', 700);
      if (!miss) text(pts + '', lx + 960, y + 50, 38, C.gold, 'right', 'Mono', 700);
      else text('×0', lx + 960, y + 50, 38, C.red, 'right', 'Mono', 700);
      ctx.restore();
    });
  });
  // the Rating tab
  if (shiftL > 0) {
    const x = lerp(W + 40, 1180, shiftL), y = 150;
    card(x, y, 640, 740, '#8fadc7', 14);
    // imgui-ish tabs
    ['Display', 'Rating', 'Sounds', 'Popup'].forEach((tb, i) => {
      box(x + 26 + i * 150, y + 26, 138, 46, 8, i === 1 ? '#2a5b8f' : '#15243a');
      text(tb, x + 95 + i * 150, y + 49, 20, i === 1 ? '#fff' : C.label, 'center', 'Inter', 700);
    });
    const rows = [['S up to', 10, 50, 'ms'], ['A up to', 30, 100, 'ms'], ['B up to', 60, 150, 'ms'], ['C up to', 110, 200, 'ms'], ['D up to', 250, 400, 'ms'], ['Takeoff icing', 65, 100, '%'], ['Min speed', 50, 200, 'km/h'], ['Min flight', 100, 500, 'ms']];
    rows.forEach(([lab, v, max, unit], i) => {
      const yy = y + 120 + i * 76;
      text(lab, x + 30, yy, 22, '#dbe9f5', 'left', 'Inter', 700);
      const wig = i < 5 ? Math.sin((t - tRules) * 2.5 + i) * 0.04 * clamp((t - tRules - 0.6) / 0.5) : 0;
      const f = clamp(v / max + wig);
      box(x + 250, yy - 16, 290, 32, 6, '#1a2c44'); box(x + 250, yy - 16, 290 * f, 32, 6, '#2d6db0');
      box(x + 250 + 290 * f - 8, yy - 20, 16, 40, 4, '#9fd0ff');
      text(Math.round(f * max) + ' ' + unit, x + 612, yy, 20, '#fff', 'right', 'Mono', 700);
    });
  }
}

// ---------- scene: features ----------
function sceneFeatures(t, S) {
  const tStyles = Ls(21) - 0.3, tRest = Ls(22) - 0.3;
  if (t < tStyles) {
    // combo climbing to x8
    const t0 = Ls(20) - 0.4, per = (tStyles - t0 - 0.6) / 8;
    const n = clamp(Math.floor((t - t0) / per), 0, 8);
    let score = 0; const grades = ['S', 'A', 'S+', 'S', 'B', 'S', 'A', 'S+'];
    const base = { 'S+': 180, S: 150, A: 120, B: 90 };
    for (let i = 0; i < n; i++) score += base[grades[i]] * Math.min(i + 1, 8);
    const since = (t - t0) - n * per;
    const pulse = n > 0 ? Math.max(0, 1 - since / 0.3) : 0;
    const last = n > 0 ? base[grades[n - 1]] * Math.min(n, 8) : 0;
    statsWidget(560, 200, 2.5, { score, combo: n, best: n, pulse, cpulse: pulse, gain: last, gainA: pulse });
    if (n > 0 && since < 1) drawPopup('ice', grades[n - 1], 960, 760, since, 1.3, 1 - clamp((since - 0.6) / 0.3));
    tag(960, 140, n >= 8 ? 'MAXIMUM ×8 — SCORE = BASE × COMBO' : 'SCORE = BASE POINTS × COMBO', n >= 8 ? C.gold : C.cyan, 1, 26);
    return;
  }
  if (t < tRest) {
    const cues = [Wd(21, 'Ice'), Wd(21, 'Arcade'), Wd(21, 'Broadcast')];
    const styles = [['ice', 'S+', 'ICE SHATTER'], ['arcade', 'A', 'ARCADE SLAM'], ['broadcast', 'S', 'BROADCAST SHEEN']];
    styles.forEach(([st, g, name], i) => {
      const cx = 360 + i * 600;
      const age = t - cues[i] + 0.1;
      withAlpha(eo(age / 0.3) || 0, () => spaced(name, cx, 780, 30, '#fff', 'center', 4, 'Inter', 900));
      // loop the animation so they keep performing
      if (age > 0) drawPopup(st, g, cx, 520, age % 2.6, 1.25);
    });
    spaced('PICK A STYLE · MIX ANY EFFECTS · 0–200% INTENSITY', 960, 180, 24, C.label, 'center', 3);
    return;
  }
  // announcer → run history → finish summary
  const tHist = Wd(22, 'relive') - 0.2, tSum = Wd(22, 'summary') - 0.3, tSkull = Wd(22, 'skulls') - 0.2;
  if (t < tHist) {
    const a = eo((t - tRest) / 0.3);
    withAlpha(a, () => {
      card(560, 260, 800, 520, C.pink);
      text('LocalSounds/', 600, 320, 34, '#fff', 'left', 'Inter', 800);
      const files = ['my_announcer_INCREDIBLE.wav', 'my_announcer_amazing.ogg', 'dramatic_airhorn.mp3', 'mom_saying_nice.wav', 'sad_trombone.wav'];
      files.forEach((f, i) => {
        const fa = eo((t - tRest - 0.3 - i * 0.18) / 0.25);
        withAlpha(fa, () => { box(600, 370 + i * 76, 720, 60, 10, '#10203a'); text('♪  ' + f, 624, 400 + i * 76, 26, i === 3 ? C.gold : '#cfe3f5', 'left', 'Mono', 500); });
      });
      text('The plugin ships no audio. Bring your own.', 960, 830, 26, C.label, 'center', 'Inter', 700);
    });
    return;
  }
  if (t < tSum) {
    const a = eo((t - tHist) / 0.3);
    withAlpha(a, () => {
      card(360, 170, 1200, 720, C.blue, 14);
      text('Run history', 400, 220, 34, '#fff', 'left', 'Inter', 800);
      text('last 500 attempts · filter by map and status', 1520, 222, 20, C.label, 'right', 'Inter', 500);
      const rows = [['Jump 1', 'S', 10, '150 × 1'], ['Jump 2', 'A', 20, '120 × 2'], ['Jump 3', 'S+', 0, '180 × 3'], ['Jump 4', 'MISSED', null, 'switched on landing'], ['Jump 5', 'B', 50, '90 × 1'], ['Jump 6', 'S', 10, '150 × 2']];
      rows.forEach(([j, g, lead, sc], i) => {
        const ra = eo((t - tHist - 0.2 - i * 0.12) / 0.25), y = 290 + i * 96;
        withAlpha(ra, () => {
          box(400, y, 1120, 80, 10, i === 2 ? '#173356' : '#0e1b31');
          text(j, 430, y + 40, 26, '#cfe3f5', 'left', 'Inter', 700);
          text(g, 640, y + 40, g === 'MISSED' ? 28 : 36, GRADE[g], 'left', 'Russo');
          img(GRADE_PIC[g], 870, y + 40, 52);
          text(lead === null ? '—' : lead + ' ms before takeoff', 920, y + 40, 24, '#fff', 'left', 'Inter', 700);
          text(sc, 1490, y + 40, 24, g === 'MISSED' ? C.red : C.gold, 'right', 'Mono', 700);
        });
      });
    });
    return;
  }
  const a = eo((t - tSum) / 0.35);
  withAlpha(a, () => finishSummary(391, 130, 1.75, tSum, t, clamp((t - tSkull) / 0.3)));
}

// ---------- scene: robust ----------
function sceneRobust(t, S) {
  const tScan = Ls(24) - 0.3, tCombo = Wd(24, 'Which') - 0.2;
  if (t < tScan) {
    const labels = [['30 FPS', 'potato mode'], ['240 FPS', 'gaming chair'], ['0.5× SPEED', 'TAS energy']];
    labels.forEach(([l, sub], i) => {
      const x = 170 + i * 540, a = eo((t - S.start - 0.2 - i * 0.35) / 0.4);
      withAlpha(a, () => {
        card(x, 260, 500, 420, [C.orange, C.cyan, C.pink][i], 18);
        text(l, x + 250, 330, 50, '#fff', 'center', 'Russo');
        text(sub, x + 250, 380, 24, C.label, 'center', 'Inter', 600);
        // mini takeoff preview (RenderGradePreview)
        box(x + 90, 430, 320, 180, 18, 'rgba(6,10,23,0.95)');
        box(x + 90, 430, 320, 4, 2, GRADE.S);
        text('TAKEOFF PREVIEW', x + 250, 465, 16, '#adc7e0', 'center', 'Inter', 800);
        text('S', x + 250, 525, 76, GRADE.S, 'center', 'Russo');
        text('10 ms BEFORE TAKEOFF', x + 250, 585, 16, '#c4dbf0', 'center', 'Inter', 800);
      });
    });
    const ja = eo((t - Wd(23, 'physics')) / 0.3);
    tag(960, 790, 'ONE PHYSICS CLOCK · 10 ms TICKS · SAME GRADE', C.gold, ja, 30);
    text('?', 1780, 200, 0, '#000');
    return;
  }
  if (t < tCombo) {
    // scan the game code for physics offsets
    const lt = t - tScan;
    card(160, 120, 1000, 750, C.cyan, 14);
    text('LocatePhysics()', 200, 168, 30, C.cyan, 'left', 'Mono', 700);
    text('searching Trackmania.exe …', 520, 170, 22, C.label, 'left', 'Mono', 500);
    const cols = 16, rows = 16, scanRow = Math.floor(lt * 7) % rows;
    for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) {
      const v = Math.floor(rnd(r * 31 + c * 7 + Math.floor(lt * 3) * 97) * 256);
      const hit = [[3, 4], [6, 10], [9, 2], [12, 7], [14, 12]].some(([hr, hc], k) => hr === r && c >= hc && c < hc + 4 && lt > 1 + k * 0.9);
      const x = 200 + c * 58, y = 228 + r * 40;
      if (hit) box(x - 6, y - 16, 54, 32, 6, hexA(C.cyan, 0.3));
      text(v.toString(16).padStart(2, '0').toUpperCase(), x, y, 22, hit ? C.cyan : r === scanRow ? '#fff' : '#3d5874', 'left', 'Mono', 700);
    }
    box(190, 212 + scanRow * 40, 940, 32, 6, 'rgba(8,232,222,0.08)');
    const found = ['smoothed steer', 'stored slide mode', 'tire-force multiplier', 'wheel contact times', 'physics tick clock'];
    found.forEach((f, k) => {
      const a = eo((t - tScan - 1 - k * 0.9) / 0.3);
      withAlpha(a, () => { box(1200, 250 + k * 110, 560, 86, 14, 'rgba(9,40,48,0.9)'); text('✓  ' + f, 1230, 293 + k * 110, 30, C.cyan, 'left', 'Inter', 800); });
    });
    return;
  }
  // "more than can be said for your combo"
  const f = t - tCombo, brk = Wd(24, 'combo') - 0.15;
  const broken = t > brk;
  statsWidget(560, 360, 2.5, { score: 12840, combo: broken ? 0 : 7, best: 7, pulse: 0, cpulse: broken ? Math.max(0, 1 - (t - brk) / 0.4) : 0, broken, brokenA: clamp((t - brk) / 0.3) });
  if (broken) {
    const k = t - brk;
    ctx.save(); ctx.strokeStyle = `rgba(255,120,150,${0.9 * (1 - prog(k, 1.5, 0.6))})`; ctx.lineWidth = 3;
    for (let i = 0; i < 9; i++) {
      const ang = rnd(i * 5) * Math.PI * 2; let px = 830, py = 650; ctx.beginPath(); ctx.moveTo(px, py);
      for (let s = 0; s < 4; s++) { px += Math.cos(ang + (rnd(i + s * 3) - 0.5)) * 50 * eo(k / 0.2); py += Math.sin(ang + (rnd(i + s * 3) - 0.5)) * 36 * eo(k / 0.2); ctx.lineTo(px, py); }
      ctx.stroke();
    }
    ctx.restore();
    img('fluent-3d-loudly-crying-face', 1480, 540, 180 * back(k / 0.5), 1, Math.sin(t * 6) * 0.1);
  }
}

// ---------- scene: outro ----------
function sceneOutro(t, S) {
  const tGor = Ls(26) - 0.25, tLogo = Ls(27) - 0.3;
  if (t < tGor) {
    const items = [['Ice your tires', Wd(25, 'Ice')], ['Countersteer late', Wd(25, 'Countersteer')], ['Land clean', Wd(25, 'Land')]];
    items.forEach(([l, c], i) => {
      const a = eo((t - c + 0.1) / 0.3), y = 360 + i * 150;
      withAlpha(a, () => {
        box(560, y - 55, 800, 110, 20, 'rgba(8,14,30,0.9)');
        box(600, y - 30, 60, 60, 12, hexA(C.cyan, 0.2));
        rr(600, y - 30, 60, 60, 12); ctx.strokeStyle = C.cyan; ctx.lineWidth = 3; ctx.stroke();
        const ck = clamp((t - c) / 0.25);
        if (ck > 0) { ctx.strokeStyle = C.gold; ctx.lineWidth = 8; ctx.beginPath(); ctx.moveTo(610, y); ctx.lineTo(610 + 18 * Math.min(1, ck * 2), y + 18 * Math.min(1, ck * 2)); if (ck > 0.5) ctx.lineTo(628 + 26 * (ck - 0.5) * 2, y + 18 - 40 * (ck - 0.5) * 2); ctx.stroke(); }
        text(l, 700, y + 2, 48, '#fff', 'left', 'Inter', 800);
      });
    });
    return;
  }
  if (t < tLogo) {
    const k = t - tGor;
    drawPopup('ice', 'S+', 960, 790, k - 0.3, 1.7);
    img('noto-gorilla', 960, 400, lerp(120, 520, eo(k / 0.6)), 1, Math.sin(k * 3) * 0.05);
    return;
  }
  const k = t - tLogo;
  logo(960, 400, 1, t, eo(k / 0.6));
  const a2 = eo((k - 0.6) / 0.5);
  withAlpha(a2, () => {
    box(460, 640, 1000, 90, 45, 'rgba(8,14,30,0.9)');
    rr(460, 640, 1000, 90, 45); ctx.strokeStyle = C.cyan; ctx.lineWidth = 2; ctx.stroke();
    text('github.com/Teuflum/Gorilla-Grip-Trainer', 960, 686, 38, '#fff', 'center', 'Mono', 700);
    text('Free · Openplanet plugin for Trackmania · needs VehicleState', 960, 770, 26, C.label, 'center', 'Inter', 600);
    text('The research: github.com/Teuflum/tm-ice-physics-reverse-engineering', 960, 812, 24, C.dim, 'center', 'Inter', 600);
  });
  const a3 = eo((k - 2.2) / 0.6);
  withAlpha(a3, () => {
    text('No gorillas were harmed in the making of this video. Several combos were.', 960, 900, 24, '#cfe3f5', 'center', 'Inter', 500);
    text('Emoji: Noto Emoji (Apache 2.0), Twemoji (CC-BY 4.0), Fluent Emoji (MIT)  ·  Voice: Kokoro TTS', 960, 940, 18, C.dim, 'center', 'Inter', 500);
  });
}

// ---------- subtitles ----------
function subtitles(t) {
  for (const l of TM.lines) {
    const a = inOut(t, l.start - 0.05, l.start + l.dur + 0.25, 0.12);
    if (a <= 0) continue;
    withAlpha(a, () => {
      font(38, 'Inter', 700);
      const lines = wrapLines(l.text, 1500);
      const lh = 50, bh = lines.length * lh + 26;
      const bw = Math.max(...lines.map(s => ctx.measureText(s).width)) + 60;
      const by = H - 44 - bh;
      box(W / 2 - bw / 2, by, bw, bh, 16, 'rgba(2,5,12,0.72)');
      lines.forEach((s, i) => text(s, W / 2, by + 13 + lh / 2 + i * lh, 38, '#ffffff', 'center', 'Inter', 700));
    });
  }
}

// ---------- main ----------
const SCENES = { intro: sceneIntro, problem: sceneProblem, science: sceneScience, trick: sceneTrick, catch: sceneCatch,
  plugin: scenePlugin, grades: sceneGrades, features: sceneFeatures, robust: sceneRobust, outro: sceneOutro };
function renderAt(t) {
  ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.globalAlpha = 1;
  background(t);
  snow(t, 90, 0.7);
  const S = TM.scenes.find(s => t >= s.start && t < s.end) || TM.scenes[TM.scenes.length - 1];
  const a = Math.min(clamp((t - S.start) / 0.35), S.id === 'outro' ? 1 : clamp((S.end - t) / 0.3));
  ctx.save(); ctx.globalAlpha = a; SCENES[S.id](t, S); ctx.restore();
  // final fade to black
  const fo = prog(t, TM.total - 1.2, 1.2);
  if (fo > 0) { ctx.fillStyle = `rgba(0,0,0,${fo})`; ctx.fillRect(0, 0, W, H); }
  subtitles(t);
}

// ---------- sound cues (mixed in Python) ----------
function buildSfx() {
  const add = (t, name, gain = 1, pitch = 1) => SFX.push({ t: +t.toFixed(3), name, gain, pitch });
  TM.scenes.forEach((s, i) => { if (i > 0) add(s.start - 0.15, 'whoosh', 0.5); });
  add(0.2, 'wind', 0.6);
  add(Ls(1) - 1.4, 'slide', 0.6);
  add(Ls(1) + 0.05, 'ding', 0.5, 1);
  // problem
  add(Wd(3, 'jumps') + 0.15, 'jump', 0.8); add(Wd(3, 'lands') + 0.12, 'land', 0.9);
  add(Wd(4, 'confused') - 0.2, 'boing', 0.5);
  // science
  [0.9, 1.6, 2.1, 2.5, 2.8].forEach(d => add(Ls(5) + d, 'poke', 0.7));
  add(Wd(5, 'debugger') - 0.2, 'whoosh', 0.5);
  for (let i = 0; i < 6; i++) add(Wd(5, 'debugger') + 0.1 + i * 0.12, 'tick', 0.35, 1.3);
  add(Wd(6, 'left,') - 0.1, 'flip', 0.6, 0.9); add(Wd(6, 'right.') - 0.1, 'flip', 0.6, 1.2);
  add(Wd(7, 'drops'), 'down', 0.5); add(Wd(7, 'climb') + 0.3, 'up', 0.5);
  // trick
  const tSwitch = Wd(9, 'clinging') + 0.05;
  add(tSwitch, 'switch', 0.9); add(tSwitch + 0.22, 'jump', 0.7); add(Wd(10, 'land') + 0.1, 'land', 0.9);
  add(Wd(10, 'land') + 0.2, 'ding', 0.6, 1.5);
  add(Wd(10, 'gorilla') - 0.15, 'shatter', 1.0); add(Wd(10, 'gorilla') - 0.1, 'fanfare', 0.6);
  // catch
  const tStart = Ls(11) + 1.0;
  COST.forEach((c, i) => add(tStart + i * 0.28, 'blip', 0.35, 1 + i * 0.08));
  add(tStart + 8 * 0.28 + 0.5, 'ouch', 0.7);
  add(Wd(12, 'best'), 'ding', 0.6, 1.2);
  // plugin
  add(Wd(13, 'personal'), 'whistle', 0.55);
  add(Wd(14, 'Gorilla') - 0.2, 'reveal', 0.8);
  add(Wd(15, 'Mercilessly') - 0.05, 'stamp', 1.0);
  // grades
  const cues = [Wd(16, 'S+'), Wd(16, 'S.', 0), Wd(17, 'A,'), Wd(17, 'B,'), Wd(17, 'C '), Wd(17, 'D ')];
  cues.forEach((c, i) => add(c - 0.1, 'ding', 0.45, 1.6 - i * 0.12));
  add(Wd(18, 'MISSED') - 0.1, 'trombone', 0.75);
  add(Wd(19, 'you do') - 0.2, 'whoosh', 0.4);
  // features
  const t0 = Ls(20) - 0.4, per = (Ls(21) - 0.3 - t0 - 0.6) / 8;
  for (let i = 1; i <= 8; i++) add(t0 + i * per, 'coin', 0.4, 1 + i * 0.07);
  [Wd(21, 'Ice'), Wd(21, 'Arcade'), Wd(21, 'Broadcast')].forEach((c, i) => add(c - 0.1, ['shatter', 'slam', 'sheen'][i], 0.8));
  add(Ls(22) - 0.3, 'pop', 0.5);
  add(Wd(22, 'relive') - 0.2, 'whoosh', 0.35); add(Wd(22, 'summary') - 0.3, 'whoosh', 0.35);
  add(Wd(22, 'skulls') - 0.2, 'trombone', 0.45);
  // robust
  for (let i = 0; i < 3; i++) add(scene('robust').start + 0.2 + i * 0.35, 'pop', 0.4, 1 + i * 0.1);
  for (let k = 0; k < 5; k++) add(Ls(24) - 0.3 + 1 + k * 0.9, 'blip', 0.35, 1.4);
  add(Wd(24, 'combo') - 0.15, 'crack', 0.9);
  // outro
  [Wd(25, 'Ice'), Wd(25, 'Countersteer'), Wd(25, 'Land')].forEach((c, i) => add(c, 'check', 0.5, 1 + i * 0.12));
  add(Ls(26) - 0.25, 'shatter', 0.9); add(Ls(26) - 0.2, 'fanfare', 0.7);
  add(Ls(27) - 0.3, 'reveal', 0.6);
  SFX.sort((a, b) => a.t - b.t);
}

window.ready = (async () => {
  TM = await (await fetch('timings.json')).json();
  const names = ['noto-gorilla', 'twemoji-flexed-biceps', 'twemoji-thumbs-up', 'twemoji-ok-hand', 'twemoji-slightly-smiling-face',
    'twemoji-skull', 'fluent-3d-trophy', 'fluent-3d-snowflake', 'fluent-3d-loudly-crying-face'];
  await Promise.all(names.map(n => new Promise((res, rej) => { const im = new Image(); im.onload = () => { IMG[n] = im; res(); }; im.onerror = rej; im.src = 'emoji/' + n + '.png'; })));
  await document.fonts.load('40px Russo'); await document.fonts.load('700 40px Inter'); await document.fonts.load('900 40px Inter');
  await document.fonts.load('800 40px Inter'); await document.fonts.load('500 40px Inter'); await document.fonts.load('700 40px Mono'); await document.fonts.load('500 40px Mono');
  buildSfx();
  window.SFX = SFX; window.TOTAL = TM.total;
  renderAt(0);
  return true;
})();
window.renderAt = renderAt;
