// Generates pixel art for items ("it_<id>" in data/sprites.json) from base drawings per item kind, sized to
// the item's real footprint (32 px a cell) and coloured by element (looks slots A main / a dark / C accent).
// Hand-drawn items (HAND) and items no rule matches are left alone. L / T shapes are skipped (drawn by hand).
// Run from the project folder: node tools/dev/gen_item_art.js   (prints what it drew and what it skipped)
const fs = require("fs");
const d = require("../../data/game_data.json");
const HAND = new Set(["fire_gem", "ember_sword", "bellows", "ash_plate", "butcher_cleaver"]);
const C = 32;

// ---- element colours ----
const EL = {
  fire: { A: "#f08a3e", a: "#b8452a", C: "#ffd36b" },
  ice: { A: "#7cc8f5", a: "#2f6fa8", C: "#e3f6ff" },
  nature: { A: "#5bb35a", a: "#2f6e45", C: "#c9f27a" },
  shock: { A: "#f6d845", a: "#b98226", C: "#fff7b0" },
  arcane: { A: "#a070e8", a: "#5a3a9a", C: "#e6d4ff" },
  sea: { A: "#2fb3a8", a: "#1f6b6e", C: "#a8f0e8" },
  blood: { A: "#d9433a", a: "#8f2531", C: "#f29bb0" },
  holy: { A: "#f6c445", a: "#b98226", C: "#fff3c4" },
  shadow: { A: "#6b4fa0", a: "#2e2147", C: "#c9a7ff" },
  gold: { A: "#f6c445", a: "#b98226", C: "#fff3c4" },
  steel: { A: "#8f97a3", a: "#4c5361", C: "#f6c445" },
  medic: { A: "#f7f2e8", a: "#c9c2b5", C: "#d9433a" },
  wood: { A: "#a0703f", a: "#5b3a29", C: "#5bb35a" },
  stone: { A: "#8f97a3", a: "#4c5361", C: "#d3d6db" },
  leather: { A: "#8c5a3c", a: "#5b3a29", C: "#c08552" },
};
function element(id, it) {
  const n = id + " " + it.n.toLowerCase(), t = it.tags;
  if (/frost|ice|glacier|snow|winter/.test(n)) return "ice";
  if (/blood|leech|vampir|crimson|bleed|serrat|butcher/.test(n)) return "blood";
  if (/holy|bless|sacred|radiant|dawn|sun|judg|mercy|oath|sworn|penit|prayer|saint/.test(n)) return "holy";
  if (/shadow|night|twilight|wraith|reaper|void|curse|phantom|ghost|doom/.test(n)) return "shadow";
  if (/gold|midas|coin|fortune|lucky|treasure/.test(n)) return "gold";
  if (t.includes("Fire") || /fire|flame|ember|cinder|magma|scorch|blaze|forge|sear/.test(n)) return "fire";
  if (t.includes("Shock") || /storm|thunder|volt|spark|lightning|arc_|tesla/.test(n)) return "shock";
  if (t.includes("Sea") || /sea|harpoon|barnacle|tide|whal|leviathan|coral|reef/.test(n)) return "sea";
  if (t.includes("Water")) return "ice";
  if (t.includes("Nature") || /venom|poison|thorn|briar|plague|rot|spore|vine|moss/.test(n)) return "nature";
  if (t.includes("Arcane") || /rune|spell|arcane|mana|star/.test(n)) return "arcane";
  return "steel";
}

// ---- base drawings. v(w, h): drawn upright in a w x h box; h(w, h): drawn lying in a w x h box ----
const r1 = (x) => Math.round(x * 2) / 2;
function blade(w, h, o = {}) {
  const cx = w / 2, bw = o.bw || Math.max(5, Math.min(9, w * 0.27)), tip = 2;
  const gy = Math.round(h * (o.guard || 0.7)), gw = Math.min(w - 6, bw * 3.2);
  const ops = [];
  if (o.flat) ops.push(["rect", cx - bw / 2, tip, bw, gy - tip, "l"], ["rect", cx, tip, bw / 2, gy - tip, "g"]);
  else ops.push(["poly", [[cx, tip], [cx + bw / 2, tip + bw], [cx + bw / 2, gy], [cx - bw / 2, gy], [cx - bw / 2, tip + bw]], "l"],
    ["poly", [[cx, tip], [cx + bw / 2, tip + bw], [cx + bw / 2, gy], [cx, gy]], "g"]);
  if (gy - tip > 14) ops.push(["rect", cx - 1, tip + bw + 2, 2, gy - tip - bw - 5, "A"]);
  ops.push(["rect", r1(cx - gw / 2), gy, r1(gw), 3, "C"], ["ell", cx - gw / 2, gy + 1.5, 2, 2, "C"], ["ell", cx + gw / 2, gy + 1.5, 2, 2, "C"]);
  const gh = h - gy - 9;
  ops.push(["rect", cx - 2, gy + 3, 4, gh, "n"]);
  for (let y = gy + 5; y < gy + 3 + gh - 1; y += 3) ops.push(["rect", cx - 2, y, 4, 1, "b"]);
  ops.push(["ell", cx, h - 4, 3, 2.6, "A"]);
  return ops;
}
const dagger = (w, h) => blade(w, h, { guard: h <= C ? 0.58 : 0.62, bw: 5 });
function cleaver(w, h) {
  const cx = w / 2, bh = Math.round(h * 0.58);
  return [["rect", cx - 9, 3, 18, bh, "l"], ["rect", cx - 9, 3, 3, bh, "g"], ["rect", cx + 7, 3, 2, bh, "e"], ["ell", cx + 3, 8, 2, 2, "x"],
    ["rect", cx - 4, bh - 2, 3, 2, "A"], ["rect", cx - 3, bh + 3, 6, 3, "d"], ["rect", cx - 2, bh + 6, 4, h - bh - 11, "n"], ["ell", cx, h - 4, 3, 2.5, "A"]];
}
function hammer(w, h, o = {}) {
  const cx = w / 2, hw = Math.min(w - 4, 26), hh = Math.max(12, Math.min(20, h * 0.28));
  const ops = [["rect", cx - 2, 3 + hh, 4, h - hh - 8, "n"]];
  for (let y = h - 14; y < h - 6; y += 3) ops.push(["rect", cx - 2, y, 4, 1, "b"]);
  ops.push(["rect", cx - hw / 2, 3, hw, hh, "d"], ["rect", cx - hw / 2, 3, hw, 3, "g"], ["rect", cx - 3, 3, 6, hh, "A"], ["rect", cx - 3, h - 6, 6, 4, "d"]);
  return ops;
}
function mace(w, h) {
  const cx = w / 2, r = Math.min(w * 0.3, 10);
  const ops = [["rect", cx - 2, 2 + r * 2, 4, h - r * 2 - 7, "n"], ["rect", cx - 3, h - 6, 6, 4, "C"]];
  for (const [dx, dy] of [[0, -1], [1, 0], [-1, 0], [0.7, 0.7], [-0.7, 0.7], [0.7, -0.7], [-0.7, -0.7]])
    ops.push(["poly", [[cx + dx * (r + 4), 3 + r + dy * (r + 4)], [cx + dx * r - dy * 3, 3 + r + dy * r + dx * 3], [cx + dx * r + dy * 3, 3 + r + dy * r - dx * 3]], "l"]);
  ops.push(["ell", cx, 3 + r, r, r, "g"], ["ell", cx, 3 + r, r * 0.45, r * 0.45, "A"]);
  return ops;
}
function club(w, h, o = {}) {
  const cx = w / 2, ops = [];
  if (o.stone) ops.push(["rect", cx - 2, 14, 4, h - 18, "n"], ["ell", cx, 11, Math.min(12, w / 2 - 2), 9, "g"], ["ell", cx - 3, 9, 4, 3, "l"], ["rect", cx + 1, 8, 1, 6, "d"], ["rect", cx - 6, 13, 5, 1, "d"]);
  else {
    ops.push(["poly", [[cx - 3, h - 3], [cx + 3, h - 3], [cx + 8, 7], [cx, 2], [cx - 8, 7]], "m"], ["rect", cx - 1, h * 0.35, 1, h * 0.4, "b"], ["px", cx + 3, h * 0.3, "n"], ["px", cx - 3, h * 0.5, "n"]);
    if (o.spiked) for (let y = 6; y < h * 0.55; y += 6) ops.push(["poly", [[cx - 9, y], [cx - 5, y - 2], [cx - 5, y + 2]], "l"], ["poly", [[cx + 9, y + 3], [cx + 5, y + 1], [cx + 5, y + 5]], "l"]);
  }
  ops.push(["rect", cx - 3, h - 6, 6, 3, "A"]);
  return ops;
}
function scythe(w, h) {
  const cx = w / 2 + 3;
  return [["rect", cx - 1.5, 4, 3, h - 6, "n"], ["rect", cx - 2, h * 0.55, 4, 2, "A"], ["poly", [[cx + 2, 3], [cx - 16, 4], [cx - 20, 12], [cx - 12, 8], [cx + 2, 9]], "l"], ["poly", [[cx - 16, 4], [cx - 20, 12], [cx - 17, 9]], "A"]];
}
function axe(w, h) {
  const cx = w / 2;
  return [["rect", cx - 2, 3, 4, h - 6, "n"], ["poly", [[cx + 2, 6], [w - 2, 2], [w - 2, 30], [cx + 2, 24]], "l"], ["poly", [[cx - 2, 6], [2, 2], [2, 30], [cx - 2, 24]], "l"],
    ["rect", w - 4, 3, 2, 26, "e"], ["rect", 2, 3, 2, 26, "e"], ["rect", cx - 4, 8, 8, 14, "d"], ["rect", cx - 1, 10, 2, 10, "A"], ["rect", cx - 3, h - 7, 6, 4, "d"]];
}
function spear(w, h, o = {}) {
  const cx = w / 2, ops = [["rect", cx - 1.5, 12, 3, h - 14, o.rod ? "g" : "n"], ["rect", cx - 2, h * 0.6, 4, 3, "A"]];
  if (o.rod) ops.push(["ell", cx, 7, 4, 4, "A"], ["ell", cx, 7, 2, 2, "C"], ["poly", [[cx + 6, 3], [cx + 3, 8], [cx + 6, 8], [cx + 3, 13]], "C"]);
  else {
    ops.push(["poly", [[cx, 2], [cx + 4, 10], [cx + 1, 14], [cx - 1, 14], [cx - 4, 10]], "l"], ["rect", cx - 0.5, 5, 1, 7, "A"]);
    if (o.barbs) ops.push(["poly", [[cx - 4, 10], [cx - 7, 16], [cx - 2, 13]], "g"], ["poly", [[cx + 4, 10], [cx + 7, 16], [cx + 2, 13]], "g"]);
  }
  return ops;
}
function knives(w, h, n) {   // a knife upright in each of n cells side by side
  const ops = [];
  for (let i = 0; i < n; i++) for (const op of dagger(C, C)) ops.push(shift(op, i * C, 0));
  return ops;
}
function whip(W, H, o = {}) {
  const cy = H / 2, ops = [["rect", 2, cy - 3, 11, 6, "n"], ["rect", 4, cy - 3, 1, 6, "b"], ["rect", 8, cy - 3, 1, 6, "b"], ["rect", 13, cy - 3, 2, 6, "C"]];
  if (o.flail) {
    for (let x = 16; x < W - 16; x += 4) ops.push(["ell", x, cy + Math.sin(x / 7) * 2, 1.5, 1.5, "g"]);
    ops.push(["ell", W - 9, cy, 7, 7, "d"], ["ell", W - 9, cy, 3, 3, "A"]);
    for (const [dx, dy] of [[0, -1], [1, 0], [0, 1], [-1, 0]]) ops.push(["poly", [[W - 9 + dx * 11, cy + dy * 11], [W - 9 + dx * 6 - dy * 2.5, cy + dy * 6 + dx * 2.5], [W - 9 + dx * 6 + dy * 2.5, cy + dy * 6 - dx * 2.5]], "l"]);
    return ops;
  }
  for (let x = 15; x < W - 4; x += 2) ops.push(["rect", x, r1(cy + Math.sin((x - 15) / 6) * H * 0.22) - 1, 2, 2.5, o.col || "A"]);
  if (o.thorns) for (let x = 20; x < W - 6; x += 7) ops.push(["px", x, r1(cy + Math.sin((x - 15) / 6) * H * 0.22) - 3, "L"]);
  ops.push(["px", W - 4, r1(cy + Math.sin((W - 19) / 6) * H * 0.22), "C"]);
  return ops;
}
function chain(W, H, o = {}) {
  const cy = H / 2, ops = [];
  for (let x = 6; x < W - 6; x += 7) ops.push(["ell", x, cy, 4, x % 2 ? 2.5 : 3.5, "g"], ["ell", x, cy, 2, 1, "x"]);
  if (o.hook) ops.push(["rect", W - 10, cy - 10, 3, 14, "l"], ["ell", W - 13, cy + 4, 6, 5, "l"], ["ell", W - 13, cy + 2, 3.5, 3, "x"], ["poly", [[W - 19, cy - 2], [W - 21, cy + 3], [W - 17, cy + 2]], "l"]);
  if (o.spikes) for (let x = 9; x < W - 6; x += 7) ops.push(["px", x, cy - 4, "l"], ["px", x + 3, cy + 4, "l"]);
  if (o.handles) ops.push(["rect", 1, cy - 4, 5, 8, "n"], ["rect", W - 6, cy - 4, 5, 8, "n"]);
  ops.push(["rect", W / 2 - 2, cy - 1, 4, 2, "A"]);
  return ops;
}
function gun(W, H, o = {}) {
  const cy = H / 2, ops = [], body = o.wood ? "m" : "g";
  if (o.long) {
    ops.push(["poly", [[2, cy - 2], [22, cy - 4], [24, cy + 4], [4, cy + 8]], "m"], ["rect", 22, cy - 5, 26, 9, body], ["rect", 48, cy - 3, W - 52, 4, "d"], ["rect", 48, cy - 3, W - 52, 1, "g"],
      ["rect", W - 6, cy - 4, 4, 6, "d"], ["rect", 26, cy - 2, 18, 2, "A"], ["rect", 34, cy + 4, 4, 5, "n"], ["ell", 56, cy - 6, 3, 1.5, "A"]);
  } else {
    ops.push(["rect", 22, cy - 6, W - 26, 6, "d"], ["rect", 22, cy - 6, W - 26, 2, body === "m" ? "Y" : "g"], ["rect", W - 6, cy - 7, 4, 8, "d"], ["rect", 14, cy - 7, 18, 10, body],
      ["rect", 22, cy - 3, W - 32, 2, "A"], ["poly", [[14, cy + 3], [24, cy + 3], [20, H - 2], [10, H - 2]], "n"], ["rect", 24, cy + 3, 5, 1, "d"], ["rect", 28, cy + 3, 1, 4, "d"]);
  }
  if (o.harpoon) ops.push(["poly", [[W - 2, cy - 3], [W - 10, cy - 8], [W - 10, cy + 2]], "l"]);
  return ops;
}
function cannon(W, H) {
  return [["poly", [[6, H * 0.4], [W - 6, H * 0.18], [W - 3, H * 0.42], [9, H * 0.62]], "d"], ["poly", [[6, H * 0.4], [W - 6, H * 0.18], [W - 6, H * 0.26], [7, H * 0.47]], "g"],
    ["rect", W * 0.45, H * 0.3, 4, H * 0.2, "A"], ["ell", W - 5, H * 0.3, 3, 6, "x"], ["rect", 8, H * 0.6, W - 22, 6, "n"],
    ["ell", W * 0.3, H * 0.74, H * 0.18, H * 0.18, "n"], ["ell", W * 0.3, H * 0.74, H * 0.07, H * 0.07, "Y"], ["ell", W * 0.7, H * 0.74, H * 0.18, H * 0.18, "n"], ["ell", W * 0.7, H * 0.74, H * 0.07, H * 0.07, "Y"]];
}
function sling(w, h) {
  const cx = w / 2, fy = h * 0.45;
  return [["rect", cx - 2, fy, 4, h - fy - 3, "n"], ["poly", [[cx - 2, fy + 2], [cx - 10, 6], [cx - 7, 4], [cx, fy - 2]], "n"], ["poly", [[cx + 2, fy + 2], [cx + 10, 6], [cx + 7, 4], [cx, fy - 2]], "n"],
    ["rect", cx - 9, 6, 18, 2, "A"], ["ell", cx, 9, 3.5, 3.5, "C"], ["rect", cx - 2, h - 8, 4, 1, "b"], ["rect", cx - 2, h - 12, 4, 1, "b"]];
}
function fist(W, H, o = {}) {
  const cy = H / 2, m = o.stone ? "g" : "l", dk = o.stone ? "d" : "g";
  const ops = [["rect", 3, cy - 8, 20, 16, "A"], ["rect", 3, cy - 8, 20, 3, "a"], ["rect", 20, cy - 9, 6, 18, "d"],
    ["ell", W - 20, cy, 15, 12, m], ["rect", W - 14, cy - 10, 1, 20, dk], ["rect", W - 21, cy - 11, 1, 22, dk], ["rect", W - 28, cy - 10, 1, 20, dk], ["ell", W - 24, cy + 9, 7, 3.5, m]];
  if (o.thorns) for (const y of [-8, -2, 4]) ops.push(["poly", [[W - 6, cy + y], [W - 1, cy + y + 2], [W - 6, cy + y + 4]], "G"]);
  return ops;
}
function claw(w, h) {
  const ops = [["ell", w / 2, h - 7, w * 0.36, 5, "b"], ["ell", w / 2, h - 8, w * 0.28, 3, "m"]];
  for (const x of [-8, 0, 8]) ops.push(["poly", [[w / 2 + x - 3, h - 9], [w / 2 + x + 3, h - 9], [w / 2 + x + 4, 6], [w / 2 + x + 1, 2], [w / 2 + x, 8]], "w"], ["poly", [[w / 2 + x + 3, h - 9], [w / 2 + x + 4, 6], [w / 2 + x + 1, 2]], "l"]);
  return ops;
}
function tusk(W, H) {
  return [["rect", 2, H / 2 - 3, 14, 6, "n"], ["rect", 14, H / 2 - 4, 3, 8, "A"], ["poly", [[17, H / 2 - 4], [W * 0.6, H / 2 - 7], [W - 3, 3], [W * 0.62, H / 2 + 1], [17, H / 2 + 4]], "w"], ["poly", [[17, H / 2 + 1], [W * 0.62, H / 2 + 1], [W - 3, 3], [W * 0.6, H / 2 - 2]], "l"]];
}
function golem(w, h) {
  const cx = w / 2;
  return [["rect", cx - 6, 4, 12, 10, "g"], ["rect", cx - 4, 7, 3, 3, "A"], ["rect", cx + 1, 7, 3, 3, "A"], ["rect", cx - 1, 1, 2, 4, "d"], ["ell", cx, 1.5, 1.5, 1.5, "A"],
    ["rect", cx - 9, 16, 18, 22, "d"], ["rect", cx - 7, 18, 14, 18, "g"], ["ell", cx, 26, 3.5, 3.5, "A"], ["rect", cx - 14, 17, 5, 18, "g"], ["rect", cx + 9, 17, 5, 18, "g"],
    ["rect", cx - 15, 34, 6, 5, "d"], ["rect", cx + 9, 34, 6, 5, "d"], ["rect", cx - 7, 39, 5, h - 44, "d"], ["rect", cx + 2, 39, 5, h - 44, "d"], ["rect", cx - 9, h - 6, 8, 4, "g"], ["rect", cx + 1, h - 6, 8, 4, "g"]];
}
function drum(W, H) {
  const cx = W / 2;
  return [["rect", 8, H * 0.3, W - 16, H * 0.55, "A"], ["ell", cx, H * 0.85, W / 2 - 8, H * 0.1, "a"], ["rect", 8, H * 0.3, W - 16, 4, "d"], ["rect", 8, H * 0.8, W - 16, 4, "d"],
    ...[0, 1, 2, 3, 4].map((i) => ["poly", [[12 + i * (W - 24) / 5, H * 0.36], [12 + (i + 0.5) * (W - 24) / 5, H * 0.74], [12 + (i + 1) * (W - 24) / 5, H * 0.36]], "C"]),
    ["ell", cx, H * 0.3, W / 2 - 8, H * 0.12, "w"], ["ell", cx, H * 0.3, W / 2 - 14, H * 0.07, "l"],
    ["poly", [[cx - 20, 4], [cx - 17, 3], [cx - 6, H * 0.26], [cx - 9, H * 0.27]], "m"], ["ell", cx - 18.5, 4, 3, 3, "w"], ["poly", [[cx + 20, 4], [cx + 17, 3], [cx + 6, H * 0.26], [cx + 9, H * 0.27]], "m"], ["ell", cx + 18.5, 4, 3, 3, "w"]];
}
function ship(W, H) {
  return [["poly", [[4, H * 0.62], [W - 4, H * 0.58], [W - 14, H - 4], [14, H - 4]], "n"], ["rect", 8, H * 0.62, W - 16, 3, "b"], ["rect", W * 0.35, 6, 3, H * 0.56, "n"], ["rect", W * 0.65, 10, 3, H * 0.5, "n"],
    ["poly", [[W * 0.35 - 16, 10], [W * 0.35 + 18, 10], [W * 0.35 + 16, H * 0.5], [W * 0.35 - 14, H * 0.5]], "c"], ["poly", [[W * 0.65 - 14, 14], [W * 0.65 + 16, 14], [W * 0.65 + 14, H * 0.5], [W * 0.65 - 12, H * 0.5]], "c"],
    ["rect", W * 0.35 - 2, 3, 12, 5, "A"], ...[0, 1, 2, 3].map((i) => ["ell", 22 + i * (W - 44) / 3, H * 0.74, 2.5, 2.5, "x"])];
}
function shield(w, h) {
  const cx = w / 2;
  return [["poly", [[cx, 2], [w - 3, 6], [w - 4, h * 0.55], [cx, h - 2], [4, h * 0.55], [3, 6]], "g"], ["poly", [[cx, 5], [w - 6, 8], [w - 7, h * 0.54], [cx, h - 6], [7, h * 0.54], [6, 8]], "A"],
    ["rect", cx - 1.5, 7, 3, h - 16, "C"], ["rect", 8, h * 0.32, w - 16, 3, "C"], ["px", 6, 8, "e"], ["px", 7, 9, "e"]];
}
function volley(W, H) {   // arrows / bolts flying right
  const ops = [];
  for (const [y, x0] of [[H * 0.3, 4], [H * 0.55, 12], [H * 0.78, 2]]) ops.push(["rect", x0, y - 1, W - x0 - 12, 2, "A"], ["poly", [[W - 4, y], [W - 12, y - 4], [W - 12, y + 4]], "C"], ["poly", [[x0, y - 4], [x0 + 6, y], [x0, y + 4]], "a"]);
  return ops;
}
function flames(W, H) {   // a flame in each cell
  const ops = [];
  for (let i = 0; i < W / C; i++) {
    const x = i * C + 16;
    ops.push(["poly", [[x, 2], [x + 6, 10], [x + 10, 16], [x + 9, 24], [x + 5, 30], [x - 5, 30], [x - 9, 24], [x - 9, 16], [x - 5, 19], [x - 3, 10]], "a"], ["ell", x, 23, 6, 6.5, "A"], ["poly", [[x, 9], [x + 5, 20], [x - 5, 20]], "A"], ["ell", x, 25, 3.5, 4, "C"]);
  }
  return ops;
}
function tornado(W, H) {
  const ops = [];
  for (let i = 0; i < 6; i++) ops.push(["ell", W / 2 + Math.sin(i) * 3, 4 + i * (H - 8) / 6, (W / 2 - 6) * (1 - i / 7), 2.5, i % 2 ? "l" : "c"]);
  for (const [x, y] of [[10, 8], [W - 10, 14], [16, 22], [W - 16, 26]]) ops.push(["poly", [[x, y - 3], [x + 2, y], [x, y + 3], [x - 2, y]], "l"]);
  return ops;
}

// ---- batch 2: armour and shields ----
// fit: ops drawn for a bw x bh design, scaled evenly into w x h and centred (keeps proportions)
function fit(ops, bw, bh, w, h) {
  const k = Math.min(w / bw, h / bh), ox = (w - bw * k) / 2, oy = (h - bh * k) / 2;
  return ops.map((op) => {
    const o = op.slice();
    if (o[0] === "poly") o[1] = o[1].map(([x, y]) => [ox + x * k, oy + y * k]);
    else if (o[0] === "ell" || o[0] === "rect") { o[1] = ox + o[1] * k; o[2] = oy + o[2] * k; o[3] *= k; o[4] *= k; }
    else if (o[0] === "px") return ["rect", ox + o[1] * k, oy + o[2] * k, k, k, o[3]];
    return o;
  });
}
function roundShield(w, h) {
  const r = Math.min(w, h) / 2 - 2, cx = w / 2, cy = h / 2, ops = [["ell", cx, cy, r, r, "g"], ["ell", cx, cy, r - 3, r - 3, "A"]];
  for (let i = 0; i < 8; i++) ops.push(["px", Math.floor(cx + Math.cos(i * Math.PI / 4) * (r - 1.5)), Math.floor(cy + Math.sin(i * Math.PI / 4) * (r - 1.5)), "l"]);
  ops.push(["ell", cx, cy, r * 0.3, r * 0.3, "l"], ["ell", cx - 1, cy - 1, r * 0.12, r * 0.12, "e"], ["ell", cx - r * 0.5, cy - r * 0.5, 2, 1.5, "C"]);
  return ops;
}
function tower(w, h, o = {}) {
  const ops = [["rect", 3, 2, w - 6, h - 4, o.wood ? "n" : "g"], ["rect", 5, 4, w - 10, h - 8, "A"]];
  if (o.wood) for (let x = 11; x < w - 6; x += 6) ops.push(["rect", x, 4, 1, h - 8, "a"]);
  if (o.brick) for (let y = 4, i = 0; y < h - 6; y += 6, i++) {
    ops.push(["rect", 5, y, w - 10, 1, "a"]);
    for (let x = 13 + (i % 2) * 4; x < w - 6; x += 8) ops.push(["rect", x, y, 1, 6, "a"]);
  }
  ops.push(["rect", 3, h * 0.28, w - 6, 3, o.wood ? "d" : "l"], ["rect", 3, h * 0.7, w - 6, 3, o.wood ? "d" : "l"]);
  for (const [x, y] of [[5, 4], [w - 7, 4], [5, h - 7], [w - 7, h - 7]]) ops.push(["rect", x, y, 2, 2, "y"]);
  if (o.leaves) ops.push(["ell", 8, 8, 4, 2.5, "G"], ["ell", w - 9, h * 0.5, 4, 2.5, "G"], ["ell", 10, h - 12, 3.5, 2, "L"]);
  if (o.emblem) ops.push(["rect", w / 2 - 1.5, h * 0.36, 3, h * 0.3, "C"], ["rect", w / 2 - 6, h * 0.44, 12, 3, "C"]);
  return ops;
}
function chest(w, h, o = {}) {
  const body = o.leather ? "m" : "g", dk = o.leather ? "n" : "d";
  const ops = [["ell", 14, 15, 10, 7, dk], ["ell", 50, 15, 10, 7, dk], ["poly", [[12, 13], [52, 13], [50, 52], [40, 58], [24, 58], [14, 52]], body], ["poly", [[24, 11], [40, 11], [36, 21], [28, 21]], "x"]];
  if (o.mail) for (let y = 24; y < 52; y += 4) for (let x = 18 + (y % 8 ? 2 : 0); x < 46; x += 4) ops.push(["px", x, y, "d"]);
  else if (o.studs) for (let y = 26; y < 50; y += 7) for (let x = 20; x < 46; x += 7) ops.push(["px", x, y, "y"], ["px", x + 1, y, "Y"]);
  else ops.push(["rect", 18, 27, 28, 3, dk], ["rect", 18, 37, 28, 3, dk], ["rect", 20, 46, 24, 3, dk]);
  if (o.pipes) ops.push(["rect", 16, 20, 3, 30, "Y"], ["rect", 45, 20, 3, 30, "Y"], ["ell", 17.5, 19, 3, 3, "l"], ["ell", 46.5, 19, 3, 3, "l"]);
  ops.push(["rect", 31, 21, 2, 32, o.leather ? "b" : "l"], ["rect", 16, 53, 32, 4, "n"], ["rect", 30, 53, 4, 4, "A"], ["rect", 14, 13, 36, 2, "A"]);
  return fit(ops, 64, 64, w, h);
}
function cloak(w, h, o = {}) {
  const ops = o.wings
    ? [["poly", [[32, 10], [62, 6], [56, 30], [60, 54], [44, 46], [32, 60], [20, 46], [4, 54], [8, 30], [2, 6]], "A"], ["poly", [[32, 14], [52, 12], [48, 42], [32, 54], [16, 42], [12, 12]], "a"]]
    : [["poly", [[32, 14], [52, 30], [56, 62], [8, 62], [12, 30]], "A"], ["poly", [[32, 18], [46, 34], [44, 62], [20, 62], [18, 34]], "a"], ["rect", 31, 30, 2, 32, "A"]];
  ops.push(["ell", 32, 13, 11, 11, "A"], ["ell", 32, 15, 7, 7, "x"], ["px", 29, 15, "C"], ["px", 35, 15, "C"], ["ell", 32, 25, 2.5, 2.5, "Y"]);
  return fit(ops, 64, 64, w, h);
}
function mountain(w, h) {
  return fit([["poly", [[2, 60], [24, 10], [44, 60]], "g"], ["poly", [[22, 60], [44, 18], [62, 60]], "d"], ["poly", [[24, 10], [30, 22], [26, 20], [22, 24], [18, 22]], "w"],
    ["poly", [[44, 18], [49, 28], [44, 26], [40, 29]], "w"], ["rect", 2, 58, 60, 4, "A"]], 64, 64, w, h);
}
function wall(w, h, o = {}) {
  const ops = [["rect", 2, 3, w - 4, h - 5, o.wood ? "n" : "d"]];
  for (let y = 3, i = 0; y < h - 4; y += 8, i++) for (let x = 2 - (i % 2) * 7; x < w - 2; x += 14) {
    const x0 = Math.max(2, x + 1), x1 = Math.min(w - 2, x + 13);
    if (x1 > x0) ops.push(["rect", x0, y + 1, x1 - x0, 6, o.wood ? "m" : (i + x) % 3 ? "g" : "l"]);
  }
  ops.push(["rect", 2, 3, w - 4, 2, "A"]);
  if (o.leaves) for (let x = 6; x < w - 4; x += 11) ops.push(["ell", x, 5, 5, 3.5, "G"], ["ell", x + 3, 4, 2, 1.5, "L"]);
  if (o.cross) ops.push(["rect", w / 2 - 2, h * 0.3, 4, h * 0.45, "C"], ["rect", w / 2 - 7, h * 0.4, 14, 4, "C"]);
  return ops;
}
function smoke(w, h) {
  const m = Math.min(w, h), ops = [], puffs = [[0.3, 0.6, 0.26], [0.55, 0.45, 0.3], [0.75, 0.62, 0.22], [0.45, 0.72, 0.24], [0.2, 0.42, 0.16]];
  for (const [x, y, r] of puffs) ops.push(["ell", x * w, y * h, r * m * 1.2, r * m, "g"]);
  for (const [x, y, r] of puffs) ops.push(["ell", x * w - 2, y * h - 2, r * m * 0.8, r * m * 0.6, "l"]);
  ops.push(["ell", 0.55 * w, 0.5 * h, 3, 2, "A"]);
  return ops;
}
function shell(w, h, o = {}) {
  const ops = [["poly", [[32, 58], [6, 30], [8, 16], [20, 6], [44, 6], [56, 16], [58, 30]], "A"]];
  for (const x of [14, 23, 32, 41, 50]) ops.push(["poly", [[32, 56], [x - 1.5, 8], [x + 1.5, 8]], "a"]);
  ops.push(["rect", 26, 54, 12, 6, "a"]);
  if (o.pearl) ops.push(["ell", 32, 40, 7, 7, "w"], ["ell", 30, 38, 2, 2, "e"]);
  return fit(ops, 64, 64, w, h);
}
function heart(w, h, o = {}) {
  const ops = [["ell", 10, 12, 7.5, 7.5, "A"], ["ell", 22, 12, 7.5, 7.5, "A"], ["poly", [[3, 14], [29, 14], [16, 29]], "A"], ["ell", 9, 10, 2, 2, "C"]];
  if (o.stone) ops.push(["rect", 12, 8, 1, 10, "a"], ["rect", 18, 14, 6, 1, "a"], ["rect", 9, 18, 5, 1, "a"]);
  if (o.thorns) ops.push(["rect", 2, 16, 28, 2, "D"], ["px", 6, 15, "L"], ["px", 14, 18, "L"], ["px", 24, 15, "L"]);
  return fit(ops, 32, 32, w, h);
}
function brazier(w, h) {
  return fit([["poly", [[8, 30], [56, 30], [48, 50], [16, 50]], "d"], ["rect", 8, 28, 48, 4, "g"], ["rect", 22, 50, 4, 10, "d"], ["rect", 38, 50, 4, 10, "d"],
    ["ell", 20, 28, 6, 4, "x"], ["ell", 32, 27, 7, 5, "x"], ["ell", 44, 28, 6, 4, "x"], ["ell", 26, 27, 2, 1.5, "o"], ["ell", 39, 27, 2, 1.5, "o"],
    ["poly", [[32, 4], [40, 16], [42, 26], [22, 26], [24, 16]], "A"], ["poly", [[32, 12], [36, 22], [28, 22]], "C"], ["poly", [[20, 12], [24, 24], [16, 24]], "A"], ["poly", [[44, 10], [48, 24], [40, 24]], "A"]], 64, 64, w, h);
}
function bark(w, h) {
  return fit([["poly", [[6, 4], [26, 3], [28, 28], [4, 29]], "n"], ["rect", 9, 5, 2, 22, "b"], ["rect", 15, 4, 2, 24, "b"], ["rect", 21, 5, 2, 22, "b"], ["ell", 12, 16, 2, 3, "x"], ["ell", 24, 8, 5, 3, "G"], ["ell", 25, 7, 2, 1.5, "L"]], 32, 32, w, h);
}
function mask(w, h) {
  const cx = w / 2;
  return [["ell", cx, 16, 12, 13, "n"], ["poly", [[cx - 7, 20], [cx + 7, 20], [cx, h - 3]], "n"], ["poly", [[cx - 2, 22], [cx + 4, 22], [cx, h - 6]], "b"], ["ell", cx - 5, 14, 3.5, 3.5, "A"], ["ell", cx + 5, 14, 3.5, 3.5, "A"],
    ["px", cx - 6, 13, "e"], ["px", cx + 4, 13, "e"], ["rect", cx - 12, 6, 24, 3, "d"], ["rect", cx - 4, 2, 8, 5, "d"]];
}

// ---- batch 3: gems, potions, bombs, mechs, tools, spells, charms, relics ----
const SP = JSON.parse(fs.readFileSync("data/sprites.json", "utf8")).sprites;
const copy = (sid) => () => SP[sid];                                     // same footprint as an existing sprite
const D = (ops, bw = 32, bh = 32) => (w, h) => fit(ops, bw, bh, w, h);   // a fixed design, fitted evenly
const gem = D([["poly", [[10, 4], [22, 4], [29, 12], [16, 29], [3, 12]], "a"], ["poly", [[11, 5], [21, 5], [27, 12], [16, 27], [5, 12]], "A"], ["poly", [[11, 5], [21, 5], [24, 12], [8, 12]], "C"], ["poly", [[16, 12], [24, 12], [16, 27]], "a"], ["px", 13, 7, "w"], ["px", 14, 7, "w"]]);
const crystal = D([["poly", [[16, 1], [23, 8], [23, 24], [16, 31], [9, 24], [9, 8]], "a"], ["poly", [[16, 2], [22, 8], [22, 24], [16, 30]], "A"], ["poly", [[16, 2], [10, 8], [10, 24], [16, 30]], "C"], ["rect", 12, 8, 1, 14, "w"]]);
const orb = D([["ell", 16, 16, 12, 12, "a"], ["ell", 16, 16, 10, 10, "A"], ["ell", 12, 12, 4, 3, "C"], ["px", 11, 11, "w"], ["px", 25, 6, "C"], ["px", 5, 25, "C"]]);
const potion = D([["rect", 13, 2, 6, 4, "m"], ["rect", 12, 6, 8, 7, "l"], ["ell", 16, 21, 11, 10, "l"], ["ell", 16, 22, 9, 8, "A"], ["rect", 8, 17, 16, 2, "C"], ["ell", 12, 20, 2, 3, "w"], ["rect", 14, 7, 4, 5, "c"]]);
const vial = D([["rect", 12, 2, 8, 6, "m"], ["rect", 11, 8, 10, 4, "l"], ["rect", 12, 12, 8, 10, "l"], ["poly", [[12, 22], [20, 22], [27, 36], [27, 60], [5, 60], [5, 36]], "l"], ["poly", [[7, 38], [25, 38], [25, 58], [7, 58]], "A"], ["rect", 7, 38, 18, 2, "C"], ["rect", 9, 41, 2, 13, "w"]], 32, 64);
const lantern = D([["rect", 13, 2, 6, 4, "d"], ["rect", 8, 6, 16, 4, "d"], ["rect", 9, 10, 14, 40, "A"], ["ell", 16, 30, 4, 8, "C"], ["rect", 9, 10, 2, 40, "d"], ["rect", 15, 10, 2, 40, "d"], ["rect", 21, 10, 2, 40, "d"], ["rect", 8, 50, 16, 4, "d"], ["rect", 11, 54, 10, 6, "d"]], 32, 64);
const pouch = D([["ell", 16, 21, 11, 9, "m"], ["rect", 12, 8, 8, 5, "m"], ["poly", [[9, 3], [23, 3], [20, 9], [12, 9]], "m"], ["rect", 11, 10, 10, 2, "A"], ["ell", 12, 18, 2, 2, "b"], ["ell", 21, 22, 3, 3, "C"]]);
const belt = D([["rect", 2, 18, 92, 8, "n"], ["rect", 2, 20, 92, 1, "b"], ["rect", 44, 16, 8, 12, "Y"], ...[14, 66].map((x) => [["rect", x - 4, 2, 8, 4, "m"], ["rect", x - 3, 6, 6, 4, "l"], ["ell", x, 20, 9, 9, "l"], ["ell", x, 21, 7, 7, "A"], ["ell", x - 3, 18, 1.5, 2.5, "w"]]).flat(), ["rect", 26, 6, 8, 18, "l"], ["rect", 27, 12, 6, 12, "C"], ["rect", 78, 6, 8, 18, "l"], ["rect", 79, 12, 6, 12, "a"]], 96, 32);
const urn = D([["poly", [[10, 4], [22, 4], [20, 8], [26, 16], [24, 26], [20, 30], [12, 30], [8, 26], [6, 16], [12, 8]], "A"], ["rect", 10, 3, 12, 3, "a"], ["rect", 7, 15, 18, 3, "C"], ["ell", 11, 13, 1.5, 3, "w"], ["rect", 8, 23, 16, 1, "a"]]);
const cauldron = D([["ell", 32, 38, 26, 20, "d"], ["rect", 6, 22, 52, 6, "g"], ["ell", 32, 24, 24, 5, "A"], ["ell", 26, 23, 4, 2, "C"], ["ell", 40, 22, 3, 2, "C"], ["rect", 12, 54, 6, 8, "d"], ["rect", 46, 54, 6, 8, "d"], ["ell", 30, 12, 3, 3, "A"], ["ell", 38, 6, 2, 2, "A"]], 64, 64);
const bowl = D([["poly", [[4, 14], [60, 14], [50, 30], [14, 30]], "m"], ["ell", 32, 14, 28, 4, "A"], ["rect", 4, 13, 56, 2, "b"], ["ell", 26, 13, 4, 1.5, "C"], ["rect", 22, 22, 20, 2, "b"]], 64, 32);
const mortar = D([["poly", [[4, 14], [60, 14], [50, 30], [14, 30]], "g"], ["ell", 32, 14, 28, 4, "A"], ["poly", [[40, 12], [56, 0], [60, 3], [44, 15]], "l"], ["rect", 4, 13, 56, 2, "d"]], 64, 32);
const vat = D([["rect", 6, 6, 52, 24, "m"], ["rect", 6, 9, 52, 3, "d"], ["rect", 6, 24, 52, 3, "d"], ["ell", 32, 6, 26, 4, "A"], ["ell", 26, 5, 4, 1.5, "C"], ["rect", 52, 16, 8, 4, "g"]], 64, 32);
const feather = D([["poly", [[27, 2], [30, 7], [20, 20], [9, 29], [7, 27], [14, 17]], "A"], ["poly", [[27, 2], [14, 17], [7, 27], [10, 21], [19, 9]], "C"], ["poly", [[28, 3], [29, 4], [7, 30], [6, 29]], "w"]]);
const mushroom = D([["rect", 12, 17, 8, 12, "w"], ["rect", 12, 26, 8, 3, "l"], ["ell", 16, 14, 14, 9, "A"], ["rect", 2, 14, 28, 4, "A"], ["ell", 10, 10, 2.5, 2, "w"], ["ell", 20, 8, 3, 2, "w"], ["ell", 23, 14, 2, 1.5, "w"]]);
const seed = D([["ell", 16, 20, 8, 9, "m"], ["ell", 16, 12, 10, 5, "n"], ["rect", 15, 3, 2, 6, "n"], ["ell", 13, 19, 2, 3, "b"], ["ell", 21, 5, 4, 2, "G"]]);
const syringe = D([["poly", [[6, 24], [22, 8], [26, 12], [10, 28]], "l"], ["poly", [[8, 24], [20, 12], [24, 14], [12, 26]], "A"], ["poly", [[22, 8], [28, 2], [31, 5], [26, 12]], "d"], ["poly", [[6, 26], [1, 31], [2, 31], [7, 27]], "g"]]);
const sprig = D([["rect", 15, 6, 2, 24, "D"], ["ell", 10, 12, 6, 3, "A"], ["ell", 22, 10, 6, 3, "A"], ["ell", 9, 20, 6, 3, "A"], ["ell", 23, 19, 6, 3, "A"], ["ell", 16, 5, 3, 4, "C"]]);
const clover = D([["rect", 15, 16, 2, 14, "D"], ["ell", 11, 11, 6, 6, "A"], ["ell", 21, 11, 6, 6, "A"], ["ell", 11, 20, 6, 5, "A"], ["ell", 21, 20, 6, 5, "A"], ["ell", 16, 15, 2, 2, "C"]]);
const wreath = (w, h) => { const m = Math.min(w, h), cx = w / 2, cy = h / 2, r = m / 2 - 6, ops = [];
  for (let i = 0; i < 12; i++) ops.push(["ell", cx + Math.cos(i * Math.PI / 6) * r * (w > h ? 1.6 : 1), cy + Math.sin(i * Math.PI / 6) * r, 5, 3.5, i % 2 ? "G" : "D"]);
  for (let i = 0; i < 6; i++) ops.push(["ell", cx + Math.cos(i * Math.PI / 3 + 0.3) * r * (w > h ? 1.6 : 1), cy + Math.sin(i * Math.PI / 3 + 0.3) * r, 1.8, 1.8, "A"]);
  return ops; };
const root = D([["rect", 14, 2, 4, 16, "n"], ["poly", [[14, 16], [6, 28], [9, 29], [16, 20]], "n"], ["poly", [[18, 16], [26, 28], [23, 29], [16, 20]], "n"], ["rect", 15, 18, 2, 12, "b"], ["ell", 20, 5, 5, 3, "G"], ["ell", 11, 8, 4, 2.5, "G"], ["px", 15, 6, "b"]]);
const bomb = D([["ell", 15, 19, 11, 11, "x"], ["ell", 11, 15, 3, 3, "d"], ["rect", 12, 6, 7, 4, "d"], ["poly", [[17, 6], [21, 2], [23, 3], [19, 7]], "b"], ["ell", 23, 2.5, 2.5, 2.5, "C"], ["px", 25, 1, "y"], ["rect", 7, 21, 16, 2, "A"]]);
const cluster = D([...[[16, 18], [32, 22], [48, 18]].map(([x, y]) => [["ell", x, y, 9, 9, "x"], ["ell", x - 3, y - 3, 2, 2, "d"], ["rect", x - 1, y - 12, 2, 4, "b"], ["ell", x, y - 13, 2, 2, "C"], ["rect", x - 6, y + 1, 12, 2, "A"]]).flat()], 64, 32);
const payload = D([["poly", [[8, 32], [18, 16], [46, 16], [56, 32], [46, 48], [18, 48]], "g"], ["poly", [[46, 16], [58, 6], [60, 20], [52, 24]], "d"], ["poly", [[46, 48], [58, 58], [60, 44], [52, 40]], "d"],
  ...[0, 1, 2, 3].map((i) => ["poly", [[20 + i * 7, 18], [24 + i * 7, 18], [20 + i * 7, 46], [16 + i * 7, 46]], "A"]), ["ell", 10, 32, 4, 6, "d"]], 64, 64);
const keg = D([["ell", 16, 16, 11, 13, "m"], ["rect", 5, 8, 22, 2, "d"], ["rect", 5, 22, 22, 2, "d"], ["rect", 15, 3, 2, 26, "n"], ["ell", 16, 16, 3, 3, "A"], ["rect", 14, 0, 4, 4, "C"]]);
const oilcan = D([["rect", 7, 12, 16, 17, "g"], ["poly", [[23, 14], [31, 7], [31, 10], [23, 19]], "g"], ["rect", 11, 7, 6, 5, "d"], ["rect", 7, 19, 16, 3, "A"], ["ell", 9, 15, 1, 2, "l"]]);
const rocket = D([["poly", [[10, 10], [48, 10], [60, 16], [48, 22], [10, 22]], "l"], ["rect", 22, 10, 6, 12, "A"], ["poly", [[10, 10], [3, 3], [16, 10]], "r"], ["poly", [[10, 22], [3, 29], [16, 22]], "r"], ["poly", [[10, 13], [1, 16], [10, 19]], "o"], ["ell", 40, 16, 3, 3, "c"]], 64, 32);
const battery = D([["rect", 9, 6, 14, 24, "d"], ["rect", 13, 3, 6, 3, "g"], ["rect", 10, 8, 12, 20, "A"], ["rect", 10, 8, 12, 6, "a"], ["poly", [[17, 12], [12, 20], [16, 20], [14, 27], [20, 17], [16, 17]], "C"]]);
const magnet = D([["rect", 5, 4, 7, 16, "r"], ["rect", 20, 4, 7, 16, "r"], ["rect", 5, 18, 22, 8, "r"], ["rect", 5, 4, 7, 4, "l"], ["rect", 20, 4, 7, 4, "l"], ["px", 14, 4, "A"], ["px", 17, 2, "A"], ["px", 15, 8, "C"]]);
const coil = D([["rect", 14, 2, 4, 28, "d"], ...[5, 9, 13, 17, 21, 25].map((y) => ["ell", 16, y, 9, 2, "Y"]), ["px", 4, 6, "A"], ["px", 27, 14, "A"], ["px", 5, 22, "C"]]);
const core = D([["rect", 5, 5, 22, 22, "g"], ["rect", 7, 7, 18, 18, "d"], ["ell", 16, 16, 7, 7, "A"], ["ell", 14, 14, 2.5, 2.5, "C"], ["rect", 3, 14, 4, 4, "Y"], ["rect", 25, 14, 4, 4, "Y"], ["rect", 14, 3, 4, 4, "Y"], ["rect", 14, 25, 4, 4, "Y"]]);
const gear = (() => { const ops = []; for (let i = 0; i < 8; i++) { const a = i * Math.PI / 4; ops.push(["rect", 16 + Math.cos(a) * 11 - 2.5, 16 + Math.sin(a) * 11 - 2.5, 5, 5, "g"]); }
  ops.push(["ell", 16, 16, 10, 10, "g"], ["ell", 16, 16, 5, 5, "d"], ["ell", 16, 16, 2, 2, "A"]); return D(ops); })();
const chip = D([["rect", 7, 7, 18, 18, "x"], ["rect", 9, 9, 14, 14, "d"], ["rect", 12, 12, 8, 8, "A"], ...[10, 14, 18, 22].flatMap((v) => [["rect", v - 1, 3, 2, 4, "Y"], ["rect", v - 1, 25, 2, 4, "Y"], ["rect", 3, v - 1, 4, 2, "Y"], ["rect", 25, v - 1, 4, 2, "Y"]])]);
const drone = D([["rect", 2, 8, 10, 2, "d"], ["rect", 20, 8, 10, 2, "d"], ["ell", 7, 7, 6, 1.5, "l"], ["ell", 25, 7, 6, 1.5, "l"], ["rect", 6, 9, 2, 5, "d"], ["rect", 24, 9, 2, 5, "d"], ["ell", 16, 18, 10, 7, "g"], ["ell", 16, 19, 4, 3, "A"], ["ell", 15, 18, 1.5, 1.5, "C"], ["rect", 10, 25, 2, 4, "d"], ["rect", 20, 25, 2, 4, "d"]]);
const turret = D([["poly", [[4, 62], [28, 62], [24, 50], [8, 50]], "d"], ["rect", 10, 22, 12, 28, "g"], ["rect", 10, 22, 3, 28, "l"], ["ell", 16, 18, 10, 8, "g"], ["rect", 16, 14, 16, 5, "d"], ["ell", 13, 17, 3, 3, "A"], ["rect", 8, 34, 16, 3, "A"], ["rect", 12, 8, 8, 4, "d"]], 32, 64);
const castle = D([["rect", 6, 20, 52, 40, "g"], ...[6, 18, 30, 42, 52].map((x) => ["rect", x, 12, 6, 8, "g"]), ["rect", 24, 40, 16, 20, "x"], ["ell", 32, 40, 8, 6, "x"], ["rect", 12, 28, 6, 8, "x"], ["rect", 46, 28, 6, 8, "x"], ["rect", 26, 22, 30, 5, "d"], ["rect", 52, 18, 10, 12, "d"], ["ell", 20, 24, 3, 3, "A"]], 64, 64);
const scales = D([["rect", 15, 6, 2, 22, "Y"], ["rect", 8, 28, 16, 3, "Y"], ["rect", 3, 7, 26, 2, "Y"], ["poly", [[4, 9], [1, 18], [7, 18]], "d"], ["poly", [[28, 9], [25, 18], [31, 18]], "d"], ["ell", 4, 18, 4, 2, "y"], ["ell", 28, 18, 4, 2, "y"], ["ell", 16, 5, 2, 2, "A"]]);
const stone = D([["ell", 16, 18, 13, 9, "g"], ["ell", 13, 15, 6, 3, "l"], ["rect", 14, 18, 8, 1, "d"], ["rect", 9, 21, 5, 1, "d"], ["px", 20, 14, "A"]]);
const hourglass = D([["rect", 7, 2, 18, 3, "n"], ["rect", 7, 27, 18, 3, "n"], ["poly", [[9, 5], [23, 5], [17, 16], [23, 27], [9, 27], [15, 16]], "c"], ["poly", [[11, 8], [21, 8], [16, 15]], "y"], ["poly", [[16, 18], [21, 26], [11, 26]], "y"], ["rect", 7, 5, 2, 22, "n"], ["rect", 23, 5, 2, 22, "n"], ["px", 16, 20, "A"]]);
const clock = D([["ell", 16, 16, 13, 13, "A"], ["ell", 16, 16, 10, 10, "w"], ["rect", 15, 8, 2, 9, "x"], ["rect", 15, 15, 7, 2, "x"], ["px", 16, 7, "a"], ["px", 25, 16, "a"], ["px", 16, 25, "a"], ["px", 7, 16, "a"], ["rect", 14, 1, 4, 3, "Y"]]);
const bell = D([["poly", [[16, 4], [24, 10], [26, 24], [6, 24], [8, 10]], "Y"], ["rect", 4, 24, 24, 3, "Y"], ["ell", 16, 28, 3, 2.5, "n"], ["rect", 15, 1, 2, 4, "n"], ["rect", 11, 10, 2, 12, "y"], ["rect", 6, 20, 20, 1, "A"]]);
const horn = D([["poly", [[4, 26], [8, 22], [20, 14], [26, 4], [30, 6], [28, 16], [22, 22], [8, 28]], "w"], ["poly", [[26, 4], [30, 6], [28, 12], [24, 8]], "A"], ["rect", 10, 21, 3, 6, "Y"], ["rect", 17, 15, 3, 6, "Y"], ["ell", 4, 27, 2, 2, "n"]]);
const book = D([["rect", 6, 4, 20, 24, "A"], ["rect", 6, 4, 3, 24, "a"], ["rect", 9, 25, 17, 3, "w"], ["rect", 13, 9, 10, 2, "C"], ["rect", 13, 13, 8, 1, "C"], ["ell", 18, 19, 3, 3, "C"]]);
const scroll = D([["rect", 8, 6, 16, 20, "w"], ["ell", 16, 6, 9, 2.5, "m"], ["ell", 16, 26, 9, 2.5, "m"], ["rect", 11, 10, 10, 1, "n"], ["rect", 11, 14, 8, 1, "n"], ["rect", 11, 18, 10, 1, "n"], ["ell", 20, 22, 2, 2, "A"]]);
const mirror = D([["rect", 14, 22, 4, 9, "n"], ["ell", 16, 12, 10, 11, "Y"], ["ell", 16, 12, 7.5, 8.5, "c"], ["poly", [[11, 9], [14, 6], [15, 7], [12, 10]], "w"], ["ell", 18, 15, 3, 3, "A"]]);
const cloud = (W, H) => { const ops = [["ell", W * 0.3, 12, 11, 8, "l"], ["ell", W * 0.5, 9, 13, 9, "w"], ["ell", W * 0.7, 12, 11, 8, "l"], ["rect", W * 0.2, 12, W * 0.6, 8, "l"]];
  for (let x = W * 0.25; x < W * 0.8; x += 8) ops.push(["rect", x, 23, 2, 5, "A"]);
  ops.push(["poly", [[W * 0.55, 16], [W * 0.48, 26], [W * 0.53, 26], [W * 0.5, 31], [W * 0.6, 22], [W * 0.55, 22]], "C"]); return ops; };
const pickaxe = D([["poly", [[6, 28], [24, 8], [26, 10], [8, 30]], "n"], ["poly", [[10, 4], [24, 2], [30, 14], [26, 12], [22, 6], [12, 7]], "g"], ["rect", 21, 6, 4, 4, "A"]]);
const toolbox = D([["rect", 4, 12, 56, 18, "A"], ["rect", 4, 12, 56, 4, "a"], ["rect", 24, 4, 16, 3, "d"], ["rect", 24, 4, 3, 9, "d"], ["rect", 37, 4, 3, 9, "d"], ["rect", 28, 18, 8, 4, "Y"], ["poly", [[8, 12], [14, 0], [16, 1], [12, 12]], "l"], ["rect", 46, 4, 6, 8, "n"]], 64, 32);
const runestone = D([["ell", 16, 17, 11, 13, "g"], ["ell", 13, 12, 5, 4, "l"], ["poly", [[16, 8], [20, 16], [16, 26], [12, 16]], "A"], ["poly", [[16, 11], [18, 16], [16, 22], [14, 16]], "C"], ["rect", 9, 16, 14, 1, "A"]]);
const star = D([["poly", [[16, 2], [19.5, 12.1], [29.3, 12.7], [21.7, 18.9], [24.2, 29], [16, 23], [7.8, 29], [10.3, 18.9], [2.7, 12.7], [12.5, 12.1]], "A"], ["ell", 16, 16, 3.5, 3.5, "C"]]);
const twinstars = D([["poly", [[10, 2], [12, 9], [18, 10], [12, 12], [10, 19], [8, 12], [2, 10], [8, 9]], "A"], ["poly", [[22, 12], [24.5, 19], [31, 21], [24.5, 23], [22, 30], [19.5, 23], [13, 21], [19.5, 19]], "C"]]);
const comet = D([["poly", [[16, 62], [6, 22], [26, 22]], "a"], ["poly", [[16, 56], [10, 24], [22, 24]], "A"], ["ell", 16, 16, 10, 10, "A"], ["ell", 16, 16, 6, 6, "C"], ["ell", 14, 14, 2, 2, "w"]], 32, 64);
const shard = D([["poly", [[16, 1], [24, 12], [20, 31], [12, 31], [8, 12]], "a"], ["poly", [[16, 2], [22, 12], [18, 30], [16, 30]], "A"], ["poly", [[16, 2], [10, 12], [14, 30], [16, 30]], "C"], ["rect", 13, 10, 1, 10, "w"]]);
const wand = D([["poly", [[15, 22], [17, 22], [18, 62], [14, 62]], "n"], ["rect", 14, 54, 4, 3, "Y"], ["poly", [[16, 2], [19.5, 10], [28, 11], [21.5, 16], [23.5, 25], [16, 20], [8.5, 25], [10.5, 16], [4, 11], [12.5, 10]], "A"], ["ell", 16, 14, 2.5, 2.5, "C"]], 32, 64);
const portal = (w, h) => { const cx = w / 2, cy = h / 2, rx = w / 2 - 3, ry = h / 2 - 3, ops = [];
  for (let i = 0; i < 4; i++) ops.push(["ell", cx, cy, rx * (1 - i * 0.22), ry * (1 - i * 0.22), ["a", "A", "x", "C"][i]]);
  for (let i = 0; i < 10; i++) { const a = i * 0.9; ops.push(["px", Math.floor(cx + Math.cos(a) * rx * (0.3 + i * 0.06)), Math.floor(cy + Math.sin(a) * ry * (0.3 + i * 0.06)), "w"]); }
  return ops; };
const orrery = D([["rect", 30, 40, 4, 18, "Y"], ["rect", 20, 56, 24, 5, "Y"], ["ell", 32, 28, 26, 8, "C"], ["ell", 32, 28, 23, 6, "x"], ["ell", 32, 28, 13, 13, "A"], ["ell", 28, 24, 4, 3, "C"], ["ell", 8, 24, 3, 3, "c"], ["ell", 56, 32, 3, 3, "r"]], 64, 64);
const ring = D([["ell", 16, 19, 10, 10, "Y"], ["ell", 16, 19, 6.5, 6.5, "x"], ["ell", 16, 9, 5, 5, "A"], ["ell", 15, 8, 1.5, 1.5, "w"], ["px", 10, 14, "y"]]);
const beads = D([...Array.from({ length: 12 }, (_, i) => ["ell", 16 + Math.cos(i * Math.PI / 6) * 10, 14 + Math.sin(i * Math.PI / 6) * 10, 2.5, 2.5, i % 3 ? "n" : "A"]), ["rect", 15, 24, 2, 5, "Y"], ["poly", [[16, 28], [19, 31], [13, 31]], "Y"]]);
const idol = D([["ell", 16, 9, 7, 7, "A"], ["poly", [[9, 14], [23, 14], [25, 30], [7, 30]], "A"], ["rect", 7, 28, 18, 3, "a"], ["px", 13, 8, "C"], ["px", 18, 8, "C"], ["rect", 13, 11, 6, 1, "a"], ["rect", 11, 19, 10, 2, "a"]]);
const anvil = D([["poly", [[2, 8], [28, 8], [28, 14], [20, 16], [12, 16], [6, 12]], "d"], ["rect", 12, 16, 8, 8, "d"], ["rect", 8, 24, 16, 5, "d"], ["rect", 2, 8, 26, 2, "g"], ["ell", 16, 5, 3, 2, "A"]]);
const sigil = D([["ell", 16, 16, 13, 13, "Y"], ["ell", 16, 16, 10.5, 10.5, "A"], ["poly", [[16, 7], [19, 16], [16, 25], [13, 16]], "C"], ["rect", 8, 15, 16, 2, "C"], ["px", 9, 9, "w"]]);
const fang = D([["poly", [[8, 4], [24, 4], [22, 14], [16, 30], [10, 14]], "w"], ["poly", [[16, 4], [24, 4], [22, 14], [16, 30]], "l"], ["rect", 7, 3, 18, 3, "n"], ["ell", 16, 3, 2, 2, "A"]]);
const bucket = D([["poly", [[5, 10], [27, 10], [24, 29], [8, 29]], "g"], ["ell", 16, 10, 11, 3, "A"], ["rect", 5, 15, 22, 2, "d"], ["rect", 7, 24, 18, 2, "d"], ["ell", 16, 6, 11, 6, "d"], ["ell", 16, 6, 9, 4.5, "x"]]);
const target = D([["ell", 16, 16, 13, 13, "w"], ["ell", 16, 16, 10, 10, "A"], ["ell", 16, 16, 6.5, 6.5, "w"], ["ell", 16, 16, 3, 3, "A"], ["poly", [[17, 15], [29, 3], [30, 4], [18, 16]], "n"], ["poly", [[27, 2], [31, 2], [31, 6]], "C"]]);
const quiver = D([["poly", [[10, 6], [20, 6], [22, 30], [8, 30]], "n"], ["rect", 9, 12, 12, 2, "b"], ["rect", 12, 2, 1, 8, "l"], ["rect", 16, 1, 1, 9, "l"], ["poly", [[11, 0], [14, 0], [12.5, 4]], "A"], ["poly", [[15, 0], [18, 0], [16.5, 4]], "C"], ["rect", 9, 22, 12, 2, "A"]]);
const meat = D([["rect", 4, 20, 10, 4, "w"], ["ell", 4, 19, 3, 3, "w"], ["ell", 4, 25, 3, 3, "w"], ["ell", 19, 14, 11, 10, "A"], ["ell", 17, 12, 7, 5, "C"], ["ell", 22, 17, 2, 1.5, "w"]]);
const nugget = D([["ell", 16, 18, 12, 9, "a"], ["ell", 15, 17, 10, 8, "A"], ["ell", 21, 14, 5, 4, "A"], ["ell", 12, 14, 3, 2, "C"], ["px", 20, 12, "w"]]);
const totem = D([["rect", 8, 8, 16, 54, "m"], ["poly", [[2, 10], [8, 8], [8, 14]], "A"], ["poly", [[30, 10], [24, 8], [24, 14]], "A"], ...[14, 32, 50].flatMap((y) => [["rect", 11, y - 3, 3, 3, "x"], ["rect", 18, y - 3, 3, 3, "x"], ["rect", 12, y + 3, 8, 2, "n"], ["rect", 8, y + 7, 16, 2, "a"]]), ["ell", 16, 6, 8, 4, "A"]], 32, 64);
const crownArt = D(SP.ic_crown || []);

// ---- batch 4: creatures (existing pet / monster sprites fitted to the footprint, plus a few new ones) ----
const SPL = JSON.parse(fs.readFileSync("data/sprites.json", "utf8")).looks;
// a sprite's ops with some colour letters swapped, plus extra ops, fitted evenly
const from = (sid, map = {}, extra = []) => D(SP[sid].map((o) => { const c = o.slice(); if (map[c[c.length - 1]]) c[c.length - 1] = map[c[c.length - 1]]; return c; }).concat(extra));
const shark = D([["poly", [[4, 16], [0, 5], [6, 14]], "g"], ["poly", [[4, 16], [0, 27], [6, 18]], "g"], ["poly", [[4, 16], [14, 10], [40, 8], [56, 12], [62, 17], [56, 22], [40, 24], [14, 22]], "g"],
  ["poly", [[14, 19], [40, 21], [56, 20], [60, 18], [56, 23], [40, 25], [14, 22]], "w"], ["poly", [[28, 9], [38, 0], [41, 9]], "g"], ["poly", [[30, 21], [35, 30], [39, 22]], "d"],
  ["px", 52, 14, "k"], ["rect", 45, 13, 1, 5, "d"], ["rect", 47, 13, 1, 5, "d"], ["px", 57, 19, "w"], ["px", 59, 18, "w"], ["rect", 20, 15, 18, 1, "A"]], 64, 32);
const puffer = D([...Array.from({ length: 12 }, (_, i) => ["poly", [[16 + Math.cos(i * 0.52) * 14, 16 + Math.sin(i * 0.52) * 13], [16 + Math.cos(i * 0.52 + 0.15) * 9, 16 + Math.sin(i * 0.52 + 0.15) * 9], [16 + Math.cos(i * 0.52 - 0.15) * 9, 16 + Math.sin(i * 0.52 - 0.15) * 9]], "Y"]),
  ["ell", 16, 16, 11, 10, "y"], ["ell", 15, 20, 7, 5, "w"], ["ell", 20, 12, 2.5, 2.5, "w"], ["px", 21, 12, "k"], ["poly", [[4, 16], [0, 11], [0, 21]], "o"], ["ell", 26, 17, 1.5, 1, "R"]]);
const bear = (armored) => D([["rect", 18, 48, 8, 14, "n"], ["rect", 44, 48, 8, 14, "n"], ["ell", 36, 40, 24, 17, "n"], ["ell", 18, 24, 13, 12, "n"], ["ell", 9, 13, 4.5, 4.5, "n"], ["ell", 27, 12, 4.5, 4.5, "n"],
  ["ell", 9, 13, 2, 2, "m"], ["ell", 27, 12, 2, 2, "m"], ["ell", 11, 29, 6, 4.5, "m"], ["ell", 7, 27, 2, 1.5, "k"], ["px", 17, 21, "k"], ["px", 24, 21, "k"],
  ...(armored ? [["rect", 24, 26, 30, 7, "g"], ["rect", 24, 26, 30, 2, "l"], ["rect", 30, 35, 22, 6, "d"], ["ell", 18, 15, 10, 4, "g"], ["px", 28, 29, "y"], ["px", 44, 29, "y"]] : [["ell", 40, 34, 12, 6, "b"]])], 64, 64);
const deer = D([["rect", 26, 44, 4, 16, "n"], ["rect", 46, 44, 4, 16, "n"], ["ell", 38, 38, 18, 10, "m"], ["poly", [[18, 24], [26, 22], [30, 36], [22, 38]], "m"], ["ell", 17, 21, 7, 6, "m"], ["ell", 11, 23, 3, 2.5, "b"], ["px", 9, 22, "k"], ["px", 16, 19, "k"],
  ["poly", [[20, 15], [24, 2], [26, 3], [23, 14]], "C"], ["poly", [[23, 8], [30, 4], [30, 6], [24, 10]], "C"], ["poly", [[14, 15], [8, 4], [10, 3], [16, 14]], "C"], ["poly", [[10, 9], [3, 7], [3, 9], [10, 11]], "C"],
  ["px", 34, 34, "w"], ["px", 40, 32, "w"], ["px", 46, 35, "w"], ["ell", 56, 34, 3, 2, "w"], ["ell", 38, 30, 12, 2, "A"]], 64, 64);

// ---- which drawing each item gets: [regex on id, drawing, orientation "v" upright / "h" lying] ----
const RULES = [
  // batch 4: creatures ("@sprite" takes that sprite's own colours)
  [/^wolf_pup$/, from("pet_pup"), "v", true],
  [/^dire_wolf$/, from("fpet_wolf"), "v", true, "@fpet_wolf"],
  [/^pack_alpha$/, from("elite_alpha_wolf"), "v", true, "@elite_alpha_wolf"],
  [/^hawk$/, from("fpet_hawk"), "v", true],
  [/storm_hawk/, from("pet_owl", {}, [["poly", [[26, 4], [22, 11], [25, 11], [22, 17], [29, 9], [26, 9]], "y"]]), "v", true],
  [/tiger_cub/, from("pet_cat", { G: "y" }, [["rect", 11, 21, 1, 5, "x"], ["rect", 15, 20, 1, 6, "x"], ["rect", 19, 21, 1, 5, "x"], ["rect", 15, 8, 2, 2, "x"], ["rect", 9, 13, 2, 1, "x"], ["rect", 21, 13, 2, 1, "x"]]), "v", true],
  [/sabertooth/, from("pet_cat", { G: "y" }, [["rect", 11, 21, 1, 5, "x"], ["rect", 15, 20, 1, 6, "x"], ["rect", 19, 21, 1, 5, "x"], ["rect", 15, 8, 2, 2, "x"], ["rect", 9, 13, 2, 1, "x"], ["rect", 21, 13, 2, 1, "x"]].concat([["poly", [[13.5, 18], [15.5, 18], [14.5, 23]], "w"], ["poly", [[17.5, 18], [19.5, 18], [18.5, 23]], "w"]])), "v", true],
  [/stray_kitten/, from("pet_cat"), "v", true],
  [/nurse_cat/, from("pet_cat", {}, [["rect", 3, 3, 7, 2, "r"], ["rect", 5, 1, 2, 6, "r"]]), "v", true],
  [/fox_kit|lucky_fox/, from("pet_fox"), "v", true],
  [/odd_couple|den_mother/, from("pet_mouse", { p: "g" }), "v", true],
  [/armored_grizzly/, bear(true), "v", true],
  [/grizzly/, bear(false), "v", true],
  [/world_spirit/, deer, "v", true, "ice"],
  [/boar_tusk/, from("foe_wild_boar"), "v", true, "@foe_wild_boar"],
  [/shark|great_white|megalodon/, shark, "h", true, "sea"],
  [/puffer/, puffer, "v", true],
  [/octopus|kraken/, from("boss_abyss_kraken"), "v", true],
  [/electric_eel|thunder_eel/, (w, h) => {   // a long wavy eel down the footprint
    const cx = w / 2, ops = [];
    for (let y = h - 4; y > 8; y -= 2) { const r = Math.min(4.5, 1.5 + (h - y) * 0.15); ops.push(["ell", cx + Math.sin(y / 9) * 6, y, r, 2.5, "A"]); }
    for (let y = 14; y < h - 6; y += 9) ops.push(["px", Math.floor(cx + Math.sin(y / 9) * 6), y, "C"]);
    ops.push(["ell", cx, 6, 5.5, 4.5, "A"], ["px", cx - 3, 5, "k"], ["px", cx + 2, 5, "k"], ["rect", cx - 2, 9, 4, 1, "a"], ["poly", [[cx + 6, 2], [cx + 3, 7], [cx + 6, 7], [cx + 3, 12]], "C"]);
    return ops;
  }, "v", false, "shock"],
  // batch 3 (fixed designs, fitted evenly into the footprint)
  [/forge_bellows|stoke_bellows/, copy("it_bellows"), "v", true],
  [/phoenix_crown/, crownArt, "v", true],
  [/gold_scale|gilded_scale/, scales, "v", true],
  [/whetstone|quake_stone/, stone, "v", true, "stone"],
  [/hourglass|chrono/, hourglass, "v", true],
  [/tide_clock|verdict_bell|tide_bell/, bell, "v", true],
  [/clock/, clock, "v", true],
  [/horn|whistle/, horn, "v", true],
  [/ledger|_log$|tome|codex/, book, "v", true],
  [/plans|chart/, scroll, "v", true],
  [/mirror/, mirror, "v", true],
  [/lantern|censer|pyre/, lantern, "v", true],
  [/rain_cloud|thunderhead|toxic_rain|hailstorm/, cloud, "h", true],
  [/armor_breaker/, pickaxe, "v", true],
  [/oil_can/, oilcan, "v", true],
  [/powder_keg|fuse_kit/, keg, "v", true],
  [/upgrade_bench/, toolbox, "v", true],
  [/cluster_bomb|timed_barrage/, cluster, "v", true],
  [/doomsday_payload/, payload, "v", true],
  [/rocket|bunker_buster/, rocket, "v", true],
  [/bomb|blast|napalm/, bomb, "v", true],
  [/spore/, mushroom, "v", true],
  [/seed/, seed, "v", true],
  [/feather|plume|time_ember|phoenix_ember/, feather, "v", true],
  [/antidote|crimson_brand/, syringe, "v", true],
  [/potion_belt/, belt, "v", true],
  [/herb_pouch|coin_purse/, pouch, "v", true],
  [/cauldron/, cauldron, "v", true],
  [/mortar/, mortar, "v", true],
  [/feeding_bowl/, bowl, "v", true],
  [/brewing_vat/, vat, "v", true],
  [/urn|holy_relic|panacea_pot|warm_elixir/, urn, "v", true],
  [/vial|flask|draught|acid|catalyst|elixir|ambrosia|healing_brew/, (w, h) => (h > w ? vial(w, h) : potion(w, h)), "v", true],
  [/potion/, potion, "v", true],
  [/battery/, battery, "v", true],
  [/capacitor|static_coil/, magnet, "v", true],
  [/flux_coil/, coil, "v", true],
  [/core|tesla_engine/, core, "v", true],
  [/gear_box/, gear, "v", true],
  [/chip/, chip, "v", true],
  [/drone/, drone, "v", true],
  [/siege_walker/, golem, "v"],
  [/doom_turret|citadel/, castle, "v", true],
  [/turret|flechette/, turret, "v", true],
  [/rune/, runestone, "v", true],
  [/wand/, wand, "v", true],
  [/comet|shooting_star/, comet, "v", true],
  [/twin_stars/, twinstars, "v", true],
  [/star_orb|arcane_bolt|lucky_spark|soul_gem/, orb, "v", true],
  [/barrage|starstorm|arcane_storm|event_horizon|void_sigil|rift/, portal, "v", true],
  [/orrery/, orrery, "v", true],
  [/frost_shard|ice_lance|absolute_zero|eternal_ice/, shard, "v", true, "ice"],
  [/frost_barrier|mana_shield|aegis_ward/, roundShield, "v", true],
  [/ring$|band$/, ring, "v", true],
  [/beads/, beads, "v", true],
  [/idol/, idol, "v", true],
  [/anvil/, anvil, "v", true],
  [/sigil/, sigil, "v", true],
  [/alpha_fang/, fang, "v", true],
  [/chum/, bucket, "v", true, "blood"],
  [/siren_pearl/, (w, h) => shell(w, h, { pearl: true }), "v", true, "sea"],
  [/death_mark/, target, "v", true, "blood"],
  [/quiver/, quiver, "v", true],
  [/raw_meat|prime_steak/, meat, "v", true, "blood"],
  [/nugget/, nugget, "v", true, "gold"],
  [/big_ruby/, gem, "v", true, "blood"],
  [/totem/, totem, "v", true],
  [/clover|moss/, clover, "v", true, "nature"],
  [/herbal|thorn_vine/, sprig, "v", true, "nature"],
  [/wreath|briar_crown|crown_of_thorns/, wreath, "v", true, "nature"],
  [/root/, root, "v", true, "nature"],
  [/heart/, heart, "v", true],
  [/crystal|prism/, crystal, "v", true],
  [/gem|magma_core/, gem, "v", true],
  // batch 2: armour and shields
  [/mountain_aegis|world_wall/, mountain, "v", true],
  [/medic_shield/, shield, "v", false, "medic"],
  [/wooden_shield/, (w, h) => tower(w, h, { wood: true }), "v", false, "wood"],
  [/living_shield/, (w, h) => tower(w, h, { wood: true, leaves: true }), "v", false, "wood"],
  [/stone_shield|granite_shield/, (w, h) => tower(w, h, { brick: true }), "v", false, "stone"],
  [/tower_shield|bastion$|templar_shield/, (w, h) => tower(w, h, { emblem: true }), "v", true],
  [/tidal_shield|monsoon_shield|buckler/, roundShield, "v", true],
  [/shield|aegis|ward$|bulwark/, (w, h) => (w > h ? roundShield(w, h) : shield(w, h)), "v", true],
  [/living_wall/, (w, h) => wall(w, h, { wood: true, leaves: true }), "v", true, "wood"],
  [/crusader_wall/, (w, h) => wall(w, h, { cross: true }), "v", true, "holy"],
  [/wall/, wall, "v", true, "stone"],
  [/nightweave_cloak/, (w, h) => cloak(w, h, { wings: true }), "v", true],
  [/cloak/, cloak, "v", true],
  [/smoke|veil/, smoke, "v", true],
  [/pearl_remedy/, (w, h) => shell(w, h, { pearl: true }), "v", true, "sea"],
  [/shell_guard/, shell, "v", true, "sea"],
  [/golem_heart/, (w, h) => heart(w, h, { stone: true }), "v", true, "stone"],
  [/thornheart/, (w, h) => heart(w, h, { thorns: true }), "v", true, "blood"],
  [/rebirth_coal|hearth/, brazier, "v", true],
  [/bark/, bark, "v", true],
  [/plague_mask/, mask, "v", false, "nature"],
  [/leather_vest/, (w, h) => chest(w, h, { leather: true }), "v", true, "leather"],
  [/brigandine/, (w, h) => chest(w, h, { leather: true, studs: true }), "v", true, "leather"],
  [/mail/, (w, h) => chest(w, h, { mail: true }), "v", true],
  [/steam_plate|steam_bulwark/, (w, h) => chest(w, h, { pipes: true }), "v", true],
  [/plate|vest/, chest, "v", true],
  [/twin_daggers|fan_of_knives/, (w, h) => knives(w, h, w / C), "h", true],
  [/blade_storm/, tornado, "h"],
  [/twin_flames/, flames, "h", true],
  [/phantom_volley/, volley, "h"],
  [/scorching_flail/, (w, h) => whip(w, h, { flail: true }), "h"],
  [/thorn_whip|briar_lash/, (w, h) => whip(w, h, { col: "G", thorns: true }), "h"],
  [/whip/, whip, "h"],
  [/boarding_hook/, (w, h) => chain(w, h, { hook: true }), "h"],
  [/razor_wire/, (w, h) => chain(w, h, { spikes: true }), "h"],
  [/garrote/, (w, h) => chain(w, h, { handles: true }), "h"],
  [/chain/, chain, "h"],
  [/harpoon_gun/, (w, h) => gun(w, h, { harpoon: true }), "h"],
  [/rifle|repeater/, (w, h) => gun(w, h, { long: w >= 3 * C }), "h"],
  [/flintlock|lucky_pistol/, (w, h) => gun(w, h, { wood: true }), "h"],
  [/pistol/, gun, "h"],
  [/deck_cannon|broadside/, cannon, "h"],
  [/scrap_cannon/, (w, h) => gun(w, h, {}), "h"],
  [/ghost_galleon/, ship, "h"],
  [/tusk_blade/, tusk, "h"],
  [/granite_knuckle|stone_fist/, (w, h) => fist(w, h, { stone: true }), "h"],
  [/thorned_fist/, (w, h) => fist(w, h, { thorns: true }), "h"],
  [/bear_claw|razor_claw|feral_charge/, claw, "v"],
  [/drum/, drum, "h"],
  [/golem|scrap_knight/, golem, "v"],
  [/aegis/, shield, "v"],
  [/sling/, sling, "v"],
  [/lightning_rod/, (w, h) => spear(w, h, { rod: true }), "v"],
  [/harpoon/, (w, h) => spear(w, h, { barbs: true }), "v"],
  [/lance|spear|pike|trident/, spear, "v"],
  [/scythe|reaper/, scythe, "v"],
  [/worldsplitter|_axe|^axe/, axe, "v"],
  [/cleaver/, cleaver, "v"],
  [/mace/, mace, "v"],
  [/rock_club|boulder_maul/, (w, h) => club(w, h, { stone: true }), "v"],
  [/spiked_club/, (w, h) => club(w, h, { spiked: true }), "v"],
  [/club/, club, "v"],
  [/hammer|maul/, hammer, "v"],
  [/dagger|knife|kris|shiv|needle|bloodletter/, dagger, "v"],
  [/executioner|headsman|verdict|judgement/, (w, h) => blade(w, h, { flat: true, bw: 9 }), "v"],
  [/greatsword|zweihander|sundering|dawnbreaker/, (w, h) => blade(w, h, { bw: 9 }), "v"],
  [/sword|blade|edge|saber|cutlass|fang|oath|sunblade/, blade, "v"],
];

// ---- geometry helpers ----
function shift(op, dx, dy) {
  const o = op.slice();
  if (o[0] === "poly") o[1] = o[1].map(([x, y]) => [x + dx, y + dy]); else { o[1] += dx; o[2] += dy; }
  return o;
}
// upright art (box w x h) laid down in a box h x w, tip to the right; lying art stood up the other way
function turn(op, boxH, toRight) {
  const f = toRight ? ([x, y]) => [boxH - y, x] : ([x, y]) => [y, boxH - x];
  const o = op.slice();
  if (o[0] === "poly") o[1] = o[1].map(f);
  else if (o[0] === "ell") { [o[1], o[2]] = f([o[1], o[2]]); [o[3], o[4]] = [o[4], o[3]]; }
  else if (o[0] === "rect") { const a = f([o[1], o[2]]), b = f([o[1] + o[3], o[2] + o[4]]); o[1] = Math.min(a[0], b[0]); o[2] = Math.min(a[1], b[1]); o[3] = Math.abs(a[0] - b[0]); o[4] = Math.abs(a[1] - b[1]); }
  else if (o[0] === "px") { const a = f([o[1] + 0.5, o[2] + 0.5]); o[1] = Math.floor(a[0]); o[2] = Math.floor(a[1]); }
  return o;
}
const round = (op) => JSON.parse(JSON.stringify(op, (k, v) => (typeof v === "number" ? Math.round(v * 2) / 2 : v)));

// ---- generate ----
const only = process.argv[2] ? new RegExp(process.argv[2]) : null;   // optional: tag or id filter
const art = {}, looks = {}, skipped = [];
for (const [id, it] of Object.entries(d.items)) {
  if (HAND.has(id) || (only && !only.test(id) && !it.tags.some((t) => only.test(t)))) continue;
  const w = Math.max(...it.c.map((p) => p[0])) + 1, h = Math.max(...it.c.map((p) => p[1])) + 1;
  if (it.c.length < w * h) { skipped.push(id + " (L/T shape)"); continue; }
  const rule = RULES.find((r) => r[0].test(id));
  if (!rule) { skipped.push(id); continue; }
  const [, draw, orient, fixed, elx] = rule;
  const W = w * C, H = h * C;
  let ops;
  if (fixed || (orient === "v" && h >= w) || (orient === "h" && w >= h)) ops = draw(W, H);
  else if (orient === "v") ops = draw(H, W).map((op) => turn(op, W, true));   // upright art in a wide footprint: lies down
  else ops = draw(H, W).map((op) => turn(op, H, false));                       // lying art in a tall footprint: stands up
  art["it_" + id] = ops.map(round);
  looks["it_" + id] = [elx && elx[0] === "@" ? (SPL[elx.slice(1)] || [EL.steel])[0] : EL[elx || element(id, it)]];
}

// ---- write: drop old generated entries, insert the new ones ----
let j = fs.readFileSync("data/sprites.json", "utf8");
const gen = new Set(Object.keys(art));
j = j.split("\n").filter((l) => { const m = l.match(/^  "(it_[a-z0-9_]+)":/); return !(m && gen.has(m[1])); }).join("\n");
const put = (sect, obj) => {
  const a = '\n "' + sect + '": {\n', i = j.indexOf(a);
  j = j.slice(0, i + a.length) + Object.entries(obj).map(([k, v]) => '  "' + k + '": ' + JSON.stringify(v) + ",\n").join("") + j.slice(i + a.length);
};
put("looks", looks);
put("sprites", art);
JSON.parse(j);
fs.writeFileSync("data/sprites.json", j);
console.log("drew", gen.size, "items; skipped", skipped.length + ":", skipped.join(" "));
