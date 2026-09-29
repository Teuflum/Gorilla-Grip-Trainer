// 2D drawing helpers and the plugin's HUD pieces (landing popup, Physics and Stats
// widgets, finish summary), copied from the plugin's layout and colors. Loaded as a
// classic script so main.js can use these as globals.
'use strict';
const W = 1920, H = 1080;
const cv = document.getElementById('c');
const ctx = cv.getContext('2d');
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
