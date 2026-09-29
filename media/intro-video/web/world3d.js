// 3D ice track, Stadium-style car and a small deterministic slide/jump simulation.
// The stored slide mode, smoothed steering and tire-force multiplier follow the
// research report's rules on 10 ms physics ticks.
import * as THREE from 'three';

export const G = 12;            // gravity (m/s²), a little snappier than earth
const DT = 0.002;               // simulation step (s)
const TICK = 0.010;             // physics tick (s)
const RAMP_LEN = 18, RAMP_H = 2.2, GAP = 30;
export const RAMP_ANG = Math.atan2(RAMP_H, RAMP_LEN);

// Wheel layout in car space (x forward, z right). Order FL, FR, RL, RR.
export const WHEELS = [
  { x: 1.35, z: -0.92, r: 0.36, w: 0.30, front: true },
  { x: 1.35, z: 0.92, r: 0.36, w: 0.30, front: true },
  { x: -1.35, z: -0.98, r: 0.43, w: 0.42, front: false },
  { x: -1.35, z: 0.98, r: 0.43, w: 0.42, front: false },
];

// ---------------- track layout ----------------
export function makeTrack(jumpXs) {
  // jumpXs: x of each ramp start. Flat ice everywhere else except gaps.
  const pieces = [];
  let x = -600;
  for (const r0 of jumpXs) {
    pieces.push({ type: 'flat', x0: x, x1: r0 });
    pieces.push({ type: 'ramp', x0: r0, x1: r0 + RAMP_LEN });
    pieces.push({ type: 'gap', x0: r0 + RAMP_LEN, x1: r0 + RAMP_LEN + GAP });
    x = r0 + RAMP_LEN + GAP;
  }
  pieces.push({ type: 'flat', x0: x, x1: x + 3000 });
  return { pieces, jumpXs };
}
export function surfaceY(track, x) {
  for (const p of track.pieces) {
    if (x >= p.x0 && x < p.x1) {
      if (p.type === 'flat') return 0;
      if (p.type === 'ramp') return (x - p.x0) / RAMP_LEN * RAMP_H;
      return null;
    }
  }
  return 0;
}
function pieceAt(track, x) { return track.pieces.find(p => x >= p.x0 && x < p.x1); }

// ---------------- simulation ----------------
// cfg: { track, x0, z0, speed (m/s), slip0 (rad),
//        jumps: [{ spin (rad, rotation during flight), landSlip (rad),
//                  lead (ms, null = switch only on landing), after: {slip, tau} }] }
export function simulate(cfg, duration) {
  const { track } = cfg;
  const n = Math.ceil(duration / DT) + 1;
  const S = { n, dt: DT, x: new Float32Array(n), y: new Float32Array(n), z: new Float32Array(n),
    yaw: new Float32Array(n), pitch: new Float32Array(n), steer: new Float32Array(n), speed: new Float32Array(n),
    phi: new Float32Array(n), contact: new Uint8Array(n), air: new Uint8Array(n), mode: new Int8Array(n),
    modeTime: new Float32Array(n), force: new Float32Array(n), spinAng: new Float32Array(n), events: [] };
  // first pass finds takeoff ticks (yaw does not depend on steering), second pass places the countersteer
  const plan = cfg.jumps.map(j => ({ ...j, cmd: null }));
  for (let pass = 0; pass < 5; pass++) {
    run(cfg, plan, S, pass > 0);
    if (pass < 4) {
      plan.forEach((j, i) => {
        const ev = S.events.find(e => e.type === 'takeoff' && e.jump === i);
        if (ev && j.lead !== null && j.lead !== undefined) {
          // steering crosses +0.1 on the 6th affected tick; place the input so that
          // tick lands exactly `lead` ms before the takeoff tick
          const target = ev.tick - j.lead / 1000;
          j.cmd = target - 5 * TICK - TICK * 0.5;
        }
      });
    }
  }
  return S;
}

function run(cfg, plan, S, final) {
  const { track } = cfg;
  let x = cfg.x0, z = cfg.z0 || 0, y = 0, vy = 0, v = cfg.speed;
  let slip = cfg.slip0, yaw = slip, air = false, spinRate = 0, pitch = 0;
  let steer = cfg.steer0 ?? (slip > 0 ? -1 : 1), rawSteer = steer;
  let mode = steer < 0 ? 1 : 2, modeTime = -5, force = 2;
  let jumpIdx = 0, afterTarget = slip, afterTau = 0.4, landTime = -1, takeoffTick = -1;
  let lastContactTick = -1, spinAng = 0;
  let nextTick = 0;
  S.events = [];
  const contacts = [0, 0, 0, 0];
  const wheelWorld = (i) => {
    const w = WHEELS[i], c = Math.cos(yaw), s = Math.sin(yaw);
    // car forward = (cos, -sin) in (x, z); right = (sin, cos)
    return [x + w.x * c + w.z * s, z - w.x * s + w.z * c];
  };
  for (let k = 0; k < S.n; k++) {
    const t = k * DT;
    const phi = 0.035 * Math.sin(0.45 * t + (cfg.phase || 0));
    // ---- ground / air ----
    let anyContact = 0;
    if (!air) {
      const p = pieceAt(track, x);
      const onRamp = p && p.type === 'ramp';
      const pastLip = p && p.type === 'gap';
      if (pastLip) {
        // supported only while some wheel is still on the ramp
        const lip = p.x0;
        let supported = false;
        for (let i = 0; i < 4; i++) { contacts[i] = wheelWorld(i)[0] < lip ? 1 : 0; supported ||= contacts[i]; }
        if (!supported) {
          air = true; vy = v * Math.tan(RAMP_ANG);
          const j = plan[jumpIdx] || { spin: 0 };
          // time to fall back to y=0 from RAMP_H
          const tAir = (vy + Math.sqrt(vy * vy + 2 * G * RAMP_H)) / G;
          spinRate = j.spin / tAir;
          S.events.push({ type: 'takeoff', t, jump: jumpIdx, tick: lastContactTick, tAir });
          takeoffTick = lastContactTick;
        } else { y = RAMP_H; pitch = RAMP_ANG; }
      } else {
        for (let i = 0; i < 4; i++) contacts[i] = 1;
        y = onRamp ? (x - p.x0) / RAMP_LEN * RAMP_H : 0;
        pitch = onRamp ? RAMP_ANG : pitch * Math.exp(-DT / 0.05);
      }
    }
    if (air) {
      for (let i = 0; i < 4; i++) contacts[i] = 0;
      y += vy * DT; vy -= G * DT; pitch *= Math.exp(-DT / 0.4);
      yaw += spinRate * DT; spinAng += spinRate * DT;
      if (y <= 0 && surfaceY(track, x) === 0) {
        y = 0; vy = 0; air = false; landTime = t;
        const j = plan[jumpIdx] || {};
        S.events.push({ type: 'land', t, jump: jumpIdx });
        slip = yaw - phi;
        afterTarget = j.after ? j.after.slip : slip; afterTau = j.after ? j.after.tau : 0.5;
        jumpIdx++;
        for (let i = 0; i < 4; i++) contacts[i] = 1;
      }
    }
    for (let i = 0; i < 4; i++) anyContact += contacts[i];
    // ---- yaw on the ground: slip eases toward its target, with a little wobble ----
    if (!air) {
      const j = plan[jumpIdx];
      const target = landTime >= 0 && (!j || t - landTime < 3.5) ? afterTarget : (j && j.approachSlip !== undefined ? j.approachSlip : afterTarget);
      const tau = landTime >= 0 && t - landTime < 3.5 ? afterTau : 0.6;
      slip += (target - slip) * (1 - Math.exp(-DT / tau));
      yaw = phi + slip + 0.05 * Math.sin(2.7 * t + 1.3);
    }
    // ---- 10 ms physics tick: steering, stored mode, tire force ----
    if (t >= nextTick - 1e-9) {
      nextTick += TICK;
      // raw input: countersteer command before takeoff, or after takeoff for a "switch on landing"
      const j = plan[jumpIdx];
      if (j && final) {
        const want = j.landSlipSign ?? Math.sign(j.landSlip || -slip);
        const dir = want < 0 ? 1 : -1;   // landing slip < 0 -> steer right
        if (j.cmd !== null && j.cmd !== undefined && t >= j.cmd) rawSteer = dir;
        if ((j.lead === null || j.lead === undefined) && air) rawSteer = dir;
      }
      if (steer < rawSteer) steer = Math.min(rawSteer, steer + 0.2);
      else if (steer > rawSteer) steer = Math.max(rawSteer, steer - 0.2);
      steer = Math.round(steer * 10) / 10;
      if (anyContact) {
        lastContactTick = Math.round(t * 1000) / 1000;
        const m = steer > 0.1 ? 2 : steer < -0.1 ? 1 : mode;
        if (m !== mode) {
          mode = m; modeTime = t; force = 1;
          S.events.push({ type: 'switch', t: Math.round(t * 1000) / 1000, jump: jumpIdx, air });
        }
      }
      const target = 1 + Math.pow(Math.abs(steer), 1.5);
      const age = (t - modeTime) * 1000;
      const fronts = contacts[0] + contacts[1];
      if (force >= target) force = target;
      else if (age >= 400 && age < 800) force = Math.min(target, force + 0.025 * fronts);
      else if (age >= 800 && fronts > 0) force = target;
    }
    // ---- speed ----
    if (!air) v += (-3.3 + 3.6 * (force - 1)) * DT * (anyContact ? 1 : 0);
    else v -= 0.2 * DT;
    v = Math.max(20, Math.min(62, v));
    x += v * Math.cos(phi) * DT; z -= v * Math.sin(phi) * DT;
    S.x[k] = x; S.y[k] = y; S.z[k] = z; S.yaw[k] = yaw; S.pitch[k] = pitch; S.steer[k] = steer;
    S.speed[k] = v; S.phi[k] = phi; S.air[k] = air ? 1 : 0; S.mode[k] = mode; S.modeTime[k] = modeTime;
    S.force[k] = force; S.spinAng[k] = spinAng;
    S.contact[k] = contacts[0] | contacts[1] << 1 | contacts[2] << 2 | contacts[3] << 3;
  }
  // derive grades per jump
  S.jumps = [];
  const nJ = S.events.filter(e => e.type === 'takeoff').length;
  for (let i = 0; i < nJ; i++) {
    const to = S.events.find(e => e.type === 'takeoff' && e.jump === i);
    const ld = S.events.find(e => e.type === 'land' && e.jump === i);
    const sw = S.events.filter(e => e.type === 'switch' && e.jump === i && !e.air && e.t <= to.tick + 1e-6).pop();
    const lead = sw ? Math.round((to.tick - sw.t) * 1000) : null;
    let label = 'MISSED';
    if (lead !== null) label = lead === 0 ? 'S+' : lead <= 10 ? 'S' : lead <= 30 ? 'A' : lead <= 60 ? 'B' : lead <= 110 ? 'C' : lead <= 250 ? 'D' : 'MISSED';
    S.jumps.push({ takeoff: to.t, takeoffTick: to.tick, land: ld ? ld.t : null, switchT: sw ? sw.t : null, lead, label });
  }
}

export function sample(S, s) {
  const f = Math.max(0, Math.min(S.n - 1.001, s / S.dt));
  const i = Math.floor(f), u = f - i;
  const L = (a) => a[i] + (a[i + 1] - a[i]) * u;
  return { s, x: L(S.x), y: L(S.y), z: L(S.z), yaw: L(S.yaw), pitch: L(S.pitch), steer: S.steer[i], speed: L(S.speed),
    phi: L(S.phi), contact: S.contact[i], air: S.air[i], mode: S.mode[i], modeTime: S.modeTime[i], force: S.force[i],
    spinAng: L(S.spinAng) };
}

// ---------------- textures ----------------
function canvasTex(w, h, draw, repeat) {
  const c = document.createElement('canvas'); c.width = w; c.height = h;
  draw(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  if (repeat) { t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(...repeat); }
  return t;
}
const hash = (i) => { const x = Math.sin(i * 127.1 + 311.7) * 43758.5453; return x - Math.floor(x); };
function iceTexture() {
  return canvasTex(1024, 1024, (g, w, h) => {
    const grd = g.createLinearGradient(0, 0, w, h);
    grd.addColorStop(0, '#bfe6f7'); grd.addColorStop(0.5, '#d9f2fc'); grd.addColorStop(1, '#b3def3');
    g.fillStyle = grd; g.fillRect(0, 0, w, h);
    // frosty blotches
    for (let i = 0; i < 260; i++) {
      const x = hash(i) * w, y = hash(i + 9) * h, r = 10 + hash(i + 3) * 70;
      const rg = g.createRadialGradient(x, y, 0, x, y, r);
      rg.addColorStop(0, `rgba(255,255,255,${0.12 + hash(i + 5) * 0.2})`); rg.addColorStop(1, 'rgba(255,255,255,0)');
      g.fillStyle = rg; g.fillRect(x - r, y - r, 2 * r, 2 * r);
    }
    // skate scratches
    g.lineCap = 'round';
    for (let i = 0; i < 420; i++) {
      const x = hash(i + 50) * w, y = hash(i + 70) * h, len = 30 + hash(i + 90) * 220, a = (hash(i + 110) - 0.5) * 0.5;
      g.strokeStyle = `rgba(255,255,255,${0.15 + hash(i + 130) * 0.35})`; g.lineWidth = 0.6 + hash(i + 150) * 1.6;
      g.beginPath(); g.moveTo(x, y); g.lineTo(x + Math.cos(a) * len, y + Math.sin(a) * len); g.stroke();
    }
    // cracks
    g.strokeStyle = 'rgba(120,180,210,0.35)'; g.lineWidth = 1.2;
    for (let i = 0; i < 18; i++) {
      let x = hash(i + 300) * w, y = hash(i + 320) * h; g.beginPath(); g.moveTo(x, y);
      for (let s = 0; s < 6; s++) { x += (hash(i * 7 + s) - 0.5) * 90; y += (hash(i * 13 + s) - 0.5) * 90; g.lineTo(x, y); }
      g.stroke();
    }
    // platform tile seams
    g.strokeStyle = 'rgba(90,150,190,0.35)'; g.lineWidth = 3;
    g.strokeRect(1.5, 1.5, w - 3, h - 3);
  }, [1, 1]);
}
function rampTexture() {
  return canvasTex(512, 512, (g, w, h) => {
    g.fillStyle = '#cdeefc'; g.fillRect(0, 0, w, h);
    for (let i = 0; i < 4; i++) {
      const y0 = i * 128 + 20;
      g.fillStyle = 'rgba(255,214,71,0.9)';
      g.beginPath(); g.moveTo(40, y0 + 90); g.lineTo(256, y0); g.lineTo(472, y0 + 90); g.lineTo(472, y0 + 120); g.lineTo(256, y0 + 30); g.lineTo(40, y0 + 120); g.closePath(); g.fill();
    }
  });
}
function boardTexture(text, bg, fg, sub) {
  return canvasTex(1024, 192, (g, w, h) => {
    g.fillStyle = bg; g.fillRect(0, 0, w, h);
    g.fillStyle = fg; g.font = 'italic 900 118px "Inter Tight"'; g.textAlign = 'center'; g.textBaseline = 'middle';
    g.fillText(text, w / 2, h / 2 + 6);
    if (sub) { g.font = '700 26px "Inter Tight"'; g.fillText(sub, w / 2, h - 22); }
  });
}
function crowdTexture() {
  // seat rows with scattered spectators, lit from the front
  return canvasTex(1024, 256, (g, w, h) => {
    for (let r = 0; r < 16; r++) {
      g.fillStyle = r % 2 ? '#2a3350' : '#2e3858'; g.fillRect(0, r * 16, w, 16);
      g.fillStyle = 'rgba(0,0,0,0.18)'; g.fillRect(0, r * 16 + 13, w, 3);
    }
    const cols = ['#ffd647', '#08e8de', '#ff63c2', '#f2f4f8', '#ff8c38', '#8aa0ff'];
    for (let i = 0; i < 380; i++) {
      const x = hash(i) * w, r = Math.floor(hash(i + 1) * 16);
      g.fillStyle = cols[Math.floor(hash(i + 2) * cols.length)]; g.globalAlpha = 0.35 + hash(i + 3) * 0.35;
      g.fillRect(x, r * 16 + 3, 5, 9);
      g.fillStyle = '#e8c9a8'; g.fillRect(x + 1, r * 16, 3, 3);
    }
    g.globalAlpha = 1;
  }, [3, 1]);
}
function skyTexture() {
  return canvasTex(64, 1024, (g, w, h) => {
    const grd = g.createLinearGradient(0, 0, 0, h);
    grd.addColorStop(0.0, '#0b1a45'); grd.addColorStop(0.32, '#2a4e9a'); grd.addColorStop(0.46, '#7a8fd0');
    grd.addColorStop(0.5, '#ffb07a'); grd.addColorStop(0.53, '#ff7a55'); grd.addColorStop(0.6, '#3a2a55'); grd.addColorStop(1, '#10101c');
    g.fillStyle = grd; g.fillRect(0, 0, w, h);
  });
}
function softDot() {
  return canvasTex(64, 64, (g) => {
    const rg = g.createRadialGradient(32, 32, 0, 32, 32, 32);
    rg.addColorStop(0, 'rgba(255,255,255,1)'); rg.addColorStop(0.4, 'rgba(235,248,255,0.7)'); rg.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = rg; g.fillRect(0, 0, 64, 64);
  });
}

// ---------------- car model ----------------
function buildCar(env) {
  const car = new THREE.Group();
  const paint = new THREE.MeshStandardMaterial({ color: 0xf4f7fb, roughness: 0.28, metalness: 0.15, envMapIntensity: 1.2 });
  const dark = new THREE.MeshStandardMaterial({ color: 0x151a22, roughness: 0.5, metalness: 0.2 });
  const carbon = new THREE.MeshStandardMaterial({ color: 0x23293a, roughness: 0.35, metalness: 0.4 });
  const cyan = new THREE.MeshStandardMaterial({ color: 0x08e8de, roughness: 0.3, metalness: 0.1, emissive: 0x046660, emissiveIntensity: 0.4 });
  const pink = new THREE.MeshStandardMaterial({ color: 0xff4fb8, roughness: 0.3, metalness: 0.1, emissive: 0x5a0a3a, emissiveIntensity: 0.4 });
  const glass = new THREE.MeshStandardMaterial({ color: 0x0c1422, roughness: 0.05, metalness: 0.6, envMapIntensity: 2 });
  const helmet = new THREE.MeshStandardMaterial({ color: 0xffd647, roughness: 0.25, metalness: 0.2 });
  const add = (geo, mat, x, y, z, rx = 0, ry = 0, rz = 0) => {
    const m = new THREE.Mesh(geo, mat); m.position.set(x, y, z); m.rotation.set(rx, ry, rz);
    m.castShadow = true; m.receiveShadow = true; car.add(m); return m;
  };
  // central tub from a side profile (x forward, y up), extruded across z
  const prof = new THREE.Shape();
  prof.moveTo(-2.05, 0.25); prof.lineTo(-2.1, 0.78); prof.lineTo(-1.2, 0.86); prof.lineTo(-0.35, 0.92);
  prof.quadraticCurveTo(0.15, 1.28, 0.75, 1.02); prof.lineTo(1.3, 0.72); prof.lineTo(2.45, 0.42);
  prof.quadraticCurveTo(2.62, 0.36, 2.55, 0.26); prof.lineTo(-2.05, 0.25);
  const tub = new THREE.ExtrudeGeometry(prof, { depth: 0.86, bevelEnabled: true, bevelThickness: 0.08, bevelSize: 0.06, bevelSegments: 3, curveSegments: 10 });
  tub.translate(0, 0, -0.43);
  add(tub, paint, 0, 0, 0);
  // sidepods
  const pod = new THREE.BoxGeometry(2.2, 0.42, 0.42);
  add(pod, cyan, -0.5, 0.48, -0.66); add(pod, cyan, -0.5, 0.48, 0.66);
  // livery
  const stripe = new THREE.BoxGeometry(4.3, 0.07, 0.02);
  add(stripe, cyan, 0.2, 0.55, -0.52); add(stripe, cyan, 0.2, 0.55, 0.52);
  const stripe2 = new THREE.BoxGeometry(3.0, 0.04, 0.02);
  add(stripe2, pink, -0.3, 0.66, -0.52); add(stripe2, pink, -0.3, 0.66, 0.52);
  add(new THREE.BoxGeometry(2.4, 0.03, 0.5), pink, 1.35, 0.62, 0, 0, 0, -0.26);
  // cockpit + driver
  add(new THREE.SphereGeometry(0.38, 20, 14, 0, Math.PI * 2, 0, Math.PI / 2), glass, 0.25, 0.98, 0, 0, 0, -0.35).scale.set(1.5, 0.8, 0.95);
  add(new THREE.SphereGeometry(0.2, 18, 14), helmet, 0.05, 1.12, 0);
  // air intake + engine cover fin
  add(new THREE.BoxGeometry(1.4, 0.3, 0.05), paint, -1.25, 1.05, 0, 0, 0, 0.08);
  // rear wing
  add(new THREE.BoxGeometry(0.55, 0.07, 2.1), carbon, -2.2, 1.28, 0, 0, 0, 0.12);
  add(new THREE.BoxGeometry(0.4, 0.05, 2.1), pink, -2.18, 1.4, 0, 0, 0, 0.18);
  const ep = new THREE.BoxGeometry(0.7, 0.55, 0.04);
  add(ep, carbon, -2.2, 1.18, -1.07); add(ep, carbon, -2.2, 1.18, 1.07);
  add(new THREE.BoxGeometry(0.12, 0.45, 0.08), carbon, -2.05, 0.98, -0.3); add(new THREE.BoxGeometry(0.12, 0.45, 0.08), carbon, -2.05, 0.98, 0.3);
  // front wing
  add(new THREE.BoxGeometry(0.5, 0.05, 2.0), carbon, 2.35, 0.24, 0);
  add(new THREE.BoxGeometry(0.35, 0.04, 2.0), cyan, 2.3, 0.3, 0, 0, 0, 0.15);
  // suspension arms
  const arm = new THREE.CylinderGeometry(0.025, 0.025, 1, 6);
  for (const w of WHEELS) {
    const a = add(arm, carbon, w.x, w.r * 0.95, w.z / 2, Math.PI / 2, 0, 0); a.scale.set(1, Math.abs(w.z) * 1.05, 1);
  }
  // wheels
  const wheels = [];
  const tireMat = new THREE.MeshStandardMaterial({ color: 0x14171d, roughness: 0.85 });
  const rimMat = new THREE.MeshStandardMaterial({ color: 0xc9d3de, roughness: 0.25, metalness: 0.8 });
  const iceRim = new THREE.MeshStandardMaterial({ color: 0xdff6ff, roughness: 0.2, transparent: true, opacity: 0.55 });
  const glowMat = new THREE.MeshBasicMaterial({ color: 0xffd95c, transparent: true, opacity: 0, depthWrite: false, depthTest: false, blending: THREE.AdditiveBlending, toneMapped: false });
  for (const w of WHEELS) {
    const steerG = new THREE.Group(); steerG.position.set(w.x, w.r, w.z); car.add(steerG);
    const spinG = new THREE.Group(); steerG.add(spinG);
    const tire = new THREE.Mesh(new THREE.CylinderGeometry(w.r, w.r, w.w, 28), tireMat); tire.rotation.x = Math.PI / 2; tire.castShadow = true;
    spinG.add(tire);
    const frost = new THREE.Mesh(new THREE.TorusGeometry(w.r - 0.02, 0.035, 8, 28), iceRim); spinG.add(frost);
    const rim = new THREE.Mesh(new THREE.CylinderGeometry(w.r * 0.62, w.r * 0.62, w.w + 0.02, 24), rimMat); rim.rotation.x = Math.PI / 2;
    spinG.add(rim);
    const hub = new THREE.Mesh(new THREE.CylinderGeometry(w.r * 0.2, w.r * 0.2, w.w + 0.05, 10), carbon); hub.rotation.x = Math.PI / 2; spinG.add(hub);
    const glow = new THREE.Mesh(new THREE.TorusGeometry(w.r + 0.14, 0.09, 8, 40), glowMat.clone());
    glow.position.set(w.x, w.r, w.z); car.add(glow);
    wheels.push({ steerG, spinG, glow, def: w });
  }
  car.userData.wheels = wheels;
  return car;
}

// ---------------- world ----------------
export function createWorld(renderer, track) {
  const scene = new THREE.Scene();
  const pmrem = new THREE.PMREMGenerator(renderer);
  const skyTex = skyTexture();
  const envScene = new THREE.Scene();
  envScene.add(new THREE.Mesh(new THREE.SphereGeometry(100, 32, 16), new THREE.MeshBasicMaterial({ map: skyTex, side: THREE.BackSide })));
  const envSun = new THREE.Mesh(new THREE.SphereGeometry(8, 16, 8), new THREE.MeshBasicMaterial({ color: 0xfff0d0 }));
  envSun.position.set(90, 8, -25); envScene.add(envSun);
  const env = pmrem.fromScene(envScene, 0.02).texture;
  scene.environment = env;
  // sky dome
  const sky = new THREE.Mesh(new THREE.SphereGeometry(1500, 32, 16), new THREE.MeshBasicMaterial({ map: skyTex, side: THREE.BackSide, fog: false }));
  scene.add(sky);
  const sun = new THREE.Mesh(new THREE.CircleGeometry(60, 40), new THREE.MeshBasicMaterial({ color: 0xffe2b0, fog: false }));
  scene.add(sun);
  scene.fog = new THREE.Fog(0xb88aa0, 220, 1100);
  scene.add(new THREE.HemisphereLight(0x9fc4ff, 0x2a2035, 1.1));
  const dir = new THREE.DirectionalLight(0xffe0c0, 2.6);
  dir.castShadow = true; dir.shadow.mapSize.set(2048, 2048);
  const sc = dir.shadow.camera; sc.left = -30; sc.right = 30; sc.top = 30; sc.bottom = -30; sc.near = 1; sc.far = 200;
  dir.shadow.bias = -0.0005;
  scene.add(dir); scene.add(dir.target);

  // track pieces
  const ice = iceTexture();
  const iceMat = (len) => {
    const m = new THREE.MeshPhysicalMaterial({ map: ice.clone(), color: 0x7fbfe6, roughness: 0.22, metalness: 0.0, clearcoat: 1, clearcoatRoughness: 0.06, envMapIntensity: 1.0 });
    m.map.needsUpdate = true; m.map.repeat.set(len / 24, 36 / 24); return m;
  };
  const W_TRACK = 36;
  const borderMat = new THREE.MeshStandardMaterial({ color: 0x2d6fd6, roughness: 0.4, metalness: 0.2 });
  const borderTop = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.3 });
  const pitMat = new THREE.MeshStandardMaterial({ color: 0x0b0f1a, roughness: 0.9 });
  const boards = [boardTexture('GORILLA GRIP', '#0b0f1a', '#ffd647', 'TRAINER'), boardTexture('OPENPLANET', '#ffd647', '#0b0f1a'),
    boardTexture('COUNTERSTEER LATE', '#08e8de', '#0b0f1a'), boardTexture('S+ OR NOTHING', '#ff4fb8', '#ffffff'), boardTexture('uwu', '#ffffff', '#ff4fb8', 'gorilla senpai approves')];
  const crowd = crowdTexture();
  for (const p of track.pieces) {
    const len = p.x1 - p.x0, cx = (p.x0 + p.x1) / 2;
    if (p.type === 'flat') {
      const m = new THREE.Mesh(new THREE.BoxGeometry(len, 10, W_TRACK), iceMat(len));
      m.position.set(cx, -5, 0); m.receiveShadow = true; scene.add(m);
    } else if (p.type === 'ramp') {
      const shape = new THREE.Shape(); shape.moveTo(0, 0); shape.lineTo(len, RAMP_H); shape.lineTo(len, -2); shape.lineTo(0, -2); shape.closePath();
      const g = new THREE.ExtrudeGeometry(shape, { depth: W_TRACK, bevelEnabled: false }); g.translate(p.x0, 0, -W_TRACK / 2);
      const m = new THREE.Mesh(g, [new THREE.MeshPhysicalMaterial({ map: rampTexture(), color: 0x9fd0ec, roughness: 0.2, clearcoat: 1, clearcoatRoughness: 0.08 }), new THREE.MeshStandardMaterial({ color: 0x9fd6ee, roughness: 0.2 })]);
      m.receiveShadow = true; m.castShadow = true; scene.add(m);
      // lip marker
      const lip = new THREE.Mesh(new THREE.BoxGeometry(0.4, 0.06, W_TRACK), new THREE.MeshBasicMaterial({ color: 0xffd647 }));
      lip.position.set(p.x1 - 0.2, RAMP_H + 0.02, 0); lip.rotation.z = RAMP_ANG; scene.add(lip);
    } else {
      const pit = new THREE.Mesh(new THREE.BoxGeometry(len, 1, W_TRACK + 30), pitMat); pit.position.set(cx, -40, 0); scene.add(pit);
    }
    if (p.type !== 'gap') {
      for (const side of [-1, 1]) {
        const b = new THREE.Mesh(new THREE.BoxGeometry(len, 0.8, 0.6), borderMat); b.position.set(cx, 0.4 + (p.type === 'ramp' ? RAMP_H / 2 : 0), side * (W_TRACK / 2 + 0.3));
        if (p.type === 'ramp') b.rotation.z = RAMP_ANG;
        b.castShadow = true; scene.add(b);
        const bt = new THREE.Mesh(new THREE.BoxGeometry(len, 0.08, 0.64), borderTop); bt.position.copy(b.position); bt.position.y += 0.42; bt.rotation.copy(b.rotation); scene.add(bt);
      }
    }
  }
  // ad boards and grandstands along the whole run
  let bi = 0;
  for (let x = -600; x < 3000; x += 16) {
    for (const side of [-1, 1]) {
      const tex = boards[(bi++) % boards.length];
      const board = new THREE.Mesh(new THREE.PlaneGeometry(15, 2.8), new THREE.MeshStandardMaterial({ map: tex, roughness: 0.6, emissive: 0xffffff, emissiveMap: tex, emissiveIntensity: 0.25 }));
      board.position.set(x, 1.4, side * 23); board.rotation.y = side > 0 ? Math.PI : 0; scene.add(board);
    }
  }
  for (const side of [-1, 1]) {
    for (let x = -600; x < 3000; x += 200) {
      const stand = new THREE.Mesh(new THREE.BoxGeometry(200, 16, 40), new THREE.MeshStandardMaterial({ color: 0xffffff, map: crowd, emissive: 0xffffff, emissiveMap: crowd, emissiveIntensity: 0.25, roughness: 0.9 }));
      stand.position.set(x + 100, 5, side * 78); stand.rotation.x = side * 0.55; scene.add(stand);
      const roof = new THREE.Mesh(new THREE.BoxGeometry(200, 1, 36), new THREE.MeshStandardMaterial({ color: 0xdfe6f0, roughness: 0.5 }));
      roof.position.set(x + 100, 22, side * 92); scene.add(roof);
      // light towers
      const tower = new THREE.Mesh(new THREE.BoxGeometry(1.2, 40, 1.2), new THREE.MeshStandardMaterial({ color: 0x8a93a6 }));
      tower.position.set(x + 20, 20, side * 60); scene.add(tower);
      const lamp = new THREE.Mesh(new THREE.BoxGeometry(6, 3, 0.6), new THREE.MeshBasicMaterial({ color: 0xfff4d6 }));
      lamp.position.set(x + 20, 40, side * 59); scene.add(lamp);
    }
  }
  // car
  const car = buildCar(env); scene.add(car);
  // spray particles and tire marks
  const NP = 480;
  const sprayGeo = new THREE.BufferGeometry();
  sprayGeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(NP * 3), 3));
  sprayGeo.setAttribute('alpha', new THREE.BufferAttribute(new Float32Array(NP), 1));
  sprayGeo.setAttribute('size', new THREE.BufferAttribute(new Float32Array(NP), 1));
  const sprayMat = new THREE.ShaderMaterial({
    uniforms: { map: { value: softDot() }, scale: { value: 900 } }, transparent: true, depthWrite: false,
    vertexShader: `attribute float alpha; attribute float size; varying float vA;
      uniform float scale; void main(){ vA = alpha; vec4 mv = modelViewMatrix * vec4(position,1.0);
      gl_PointSize = size * scale / -mv.z; gl_Position = projectionMatrix * mv; }`,
    fragmentShader: `uniform sampler2D map; varying float vA; void main(){ vec4 c = texture2D(map, gl_PointCoord);
      gl_FragColor = vec4(vec3(0.92,0.97,1.0), c.a * vA); }`,
  });
  const spray = new THREE.Points(sprayGeo, sprayMat); spray.frustumCulled = false; scene.add(spray);
  const NM = 4 * 160;
  const markGeo = new THREE.BufferGeometry();
  markGeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(NM * 6 * 3), 3));
  markGeo.setAttribute('color', new THREE.BufferAttribute(new Float32Array(NM * 6 * 4), 4));
  const marks = new THREE.Mesh(markGeo, new THREE.MeshBasicMaterial({ vertexColors: true, transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2 }));
  marks.frustumCulled = false; scene.add(marks);

  return { scene, car, dir, sun, sky, spray, marks, track };
}

const _q = new THREE.Quaternion(), _qy = new THREE.Quaternion(), _qz = new THREE.Quaternion();
export function wheelWorldAt(st, i) {
  const w = WHEELS[i], c = Math.cos(st.yaw), s = Math.sin(st.yaw);
  return [st.x + w.x * c + w.z * s, st.z - w.x * s + w.z * c];
}
// Pose the car and update effects for simulation time s.
export function poseWorld(W, S, s, opts = {}) {
  const st = sample(S, s);
  const { car } = W;
  car.position.set(st.x, st.y, st.z);
  _qy.setFromAxisAngle(new THREE.Vector3(0, 1, 0), st.yaw);
  _qz.setFromAxisAngle(new THREE.Vector3(0, 0, 1), st.pitch);
  car.quaternion.copy(_qz).multiply(_qy);
  const wheels = car.userData.wheels;
  wheels.forEach((wh, i) => {
    if (wh.def.front) wh.steerG.rotation.y = -st.steer * 0.42;
    wh.spinG.rotation.z = -(st.x * 1.0) / wh.def.r;
    const hl = opts.highlight && opts.highlight(i, st);
    wh.glow.material.opacity = hl ? hl : 0;
    wh.glow.material.color.set(wh.def.front ? 0xffd95c : 0x78d1ff);
    wh.glow.rotation.set(0, 0, 0);
  });
  // sun light follows the car so shadows stay sharp
  W.dir.position.set(st.x - 40, 60, st.z + 30); W.dir.target.position.set(st.x, 0, st.z);
  W.sun.position.set(st.x + 1200, 150, st.z - 300); W.sun.lookAt(st.x, 0, st.z);
  W.sky.position.set(st.x, 0, st.z);
  updateSpray(W, S, s, opts.sprayScale ?? 1);
  updateMarks(W, S, s);
  return st;
}
function updateSpray(W, S, s, scale) {
  const pos = W.spray.geometry.attributes.position.array, al = W.spray.geometry.attributes.alpha.array, sz = W.spray.geometry.attributes.size.array;
  const per = 120, dtE = 1 / 180; let n = 0;
  const kNow = Math.floor(s / dtE);
  for (let j = 0; j < per && n < pos.length / 3; j++) {
    const k = kNow - j, sb = k * dtE, age = s - sb;
    if (sb < 0) break;
    const st = sample(S, sb);
    for (let i = 0; i < 4; i++) {
      if (n >= pos.length / 3) break;
      const idx = n++;
      if (!(st.contact >> i & 1) || !WHEELS[i]) { al[idx] = 0; continue; }
      const h = hash(k * 4 + i);
      const [wx, wz] = wheelWorldAt(st, i);
      // spray flies out sideways from the sliding car, lags behind the travel
      const side = hash(k * 4 + i + 1000) - 0.5;
      const vx = st.speed * (0.55 + 0.3 * h), vz = side * 18, vy = 2.5 + 5 * hash(k * 4 + i + 2000);
      const x = wx + vx * age, y = surfaceYSafe(W.track, wx) + vy * age - 0.5 * G * age * age * 0.6, z = wz + vz * age;
      pos[idx * 3] = x; pos[idx * 3 + 1] = Math.max(surfaceYSafe(W.track, wx), y); pos[idx * 3 + 2] = z;
      const life = 0.5;
      al[idx] = age > life ? 0 : (1 - age / life) * 0.35 * scale;
      sz[idx] = 0.12 + age * 1.3;
    }
  }
  for (let i = n; i < pos.length / 3; i++) al[i] = 0;
  W.spray.geometry.attributes.position.needsUpdate = true; W.spray.geometry.attributes.alpha.needsUpdate = true; W.spray.geometry.attributes.size.needsUpdate = true;
}
function surfaceYSafe(track, x) { const y = surfaceY(track, x); return y === null ? -40 : y; }
function updateMarks(W, S, s) {
  const pos = W.marks.geometry.attributes.position.array, col = W.marks.geometry.attributes.color.array;
  const per = 160, dtM = 1 / 40; let q = 0;
  for (let i = 0; i < 4; i++) {
    let prev = null;
    for (let j = 0; j < per; j++) {
      const sb = s - j * dtM;
      const st = sb >= 0 ? sample(S, sb) : null;
      const cur = st && (st.contact >> i & 1) ? (() => { const [x, z] = wheelWorldAt(st, i); return { x, z, y: surfaceYSafe(W.track, x) + 0.015, a: Math.max(0, 1 - j / per) * 0.28 }; })() : null;
      const base = q * 18, cb = q * 24; q++;
      if (!cur || !prev) { for (let k = 0; k < 18; k++) pos[base + k] = 0; for (let k = 0; k < 24; k++) col[cb + k] = 0; prev = cur; continue; }
      const dx = cur.x - prev.x, dz = cur.z - prev.z, L = Math.hypot(dx, dz) || 1, wdt = WHEELS[i].w * 0.5;
      const nx = -dz / L * wdt, nz = dx / L * wdt;
      const v = [prev.x + nx, prev.y, prev.z + nz, prev.x - nx, prev.y, prev.z - nz, cur.x + nx, cur.y, cur.z + nz,
        cur.x + nx, cur.y, cur.z + nz, prev.x - nx, prev.y, prev.z - nz, cur.x - nx, cur.y, cur.z - nz];
      for (let k = 0; k < 18; k++) pos[base + k] = v[k];
      for (let k = 0; k < 6; k++) { col[cb + k * 4] = 1; col[cb + k * 4 + 1] = 1; col[cb + k * 4 + 2] = 1; col[cb + k * 4 + 3] = (k === 0 || k === 1 || k === 4 ? prev.a : cur.a); }
      prev = cur;
    }
  }
  W.marks.geometry.attributes.position.needsUpdate = true; W.marks.geometry.attributes.color.needsUpdate = true;
}
