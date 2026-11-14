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

// ---- which drawing each item gets: [regex on id, drawing, orientation "v" upright / "h" lying] ----
const RULES = [
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
  const [, draw, orient, fixed] = rule;
  const W = w * C, H = h * C;
  let ops;
  if (fixed || (orient === "v" && h >= w) || (orient === "h" && w >= h)) ops = draw(W, H);
  else if (orient === "v") ops = draw(H, W).map((op) => turn(op, W, true));   // upright art in a wide footprint: lies down
  else ops = draw(H, W).map((op) => turn(op, H, false));                       // lying art in a tall footprint: stands up
  art["it_" + id] = ops.map(round);
  looks["it_" + id] = [EL[element(id, it)]];
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
