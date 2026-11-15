// Patch notes for the Codex: each CHANGELOG.md section, plus every number that changed in that version,
// worked out by comparing data/game_data.json at its deploy tag (posted/vX) with the deploy before it.
// The newest section, if not deployed yet, is compared with the working copy.
// require("./patches.js")(projectDir, thaiMap) -> [{v, notes: [text], changes: [{k: "up"|"down"|"new"|"chg", g, t}]}]
const fs = require("fs");
const { execFileSync } = require("child_process");

const MAX_VERSIONS = 8;

module.exports = function patches(P, T) {
  const th = (s) => (s && T[s]) || s || "";
  const md = fs.readFileSync(P + "/CHANGELOG.md", "utf8");
  const secs = [];
  for (const part of md.split(/^## /m).slice(1)) {
    const lines = part.split("\n");
    const v = lines[0].trim();
    if (!/^v\d/.test(v)) continue;
    secs.push({ v, notes: lines.slice(1).filter((l) => l.startsWith("- ")).map((l) => l.slice(2).replace(/\*\*/g, "")) });
  }
  const git = (args) => { try { return execFileSync("git", args, { cwd: P, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], maxBuffer: 64 << 20 }); } catch (e) { return null; } };
  const tags = (git(["tag", "-l", "posted/v*"]) || "").split("\n").filter(Boolean).map((t) => t.slice(7));
  const ver = (s) => s.slice(1).split(".").map(Number);
  const cmp = (a, b) => { const x = ver(a), y = ver(b); for (let i = 0; i < 3; i++) if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) - (y[i] || 0); return 0; };
  tags.sort(cmp);
  const dataAt = (v) => { const s = v ? git(["show", "posted/" + v + ":data/game_data.json"]) : fs.readFileSync(P + "/data/game_data.json", "utf8"); try { return s ? JSON.parse(s) : null; } catch (e) { return null; } };
  const out = [];
  for (const s of secs.slice(0, MAX_VERSIONS)) {
    const deployed = tags.includes(s.v);
    const prev = tags.filter((t) => cmp(t, s.v) < 0).pop();
    const a = prev ? dataAt(prev) : null;
    const b = deployed ? dataAt(s.v) : dataAt(null);
    out.push({ v: s.v, live: deployed, notes: s.notes, changes: a && b ? diff(a, b, th) : [] });
  }
  return out;
};

// Every number a player would notice, as lines: ⬆️ good for the player, ⬇️ bad for the player.
function diff(a, b, th) {
  const out = [];
  const num = (x) => (Math.round(x * 100) / 100).toString();
  const add = (k, g, t) => out.push({ k, g, t });
  // [field, Thai label, +1 if more is better for the player, -1 if less is better]
  const ON = [["dmg", "ดาเมจ", 1], ["heal", "ฮีล", 1], ["shield", "โล่", 1], ["crit", "โอกาสคริ", 1], ["charge", "ชาร์จของข้างๆ", 1], ["ramp", "ดาเมจเพิ่มต่อครั้ง", 1], ["dmg_per_res", "ดาเมจต่อทรัพยากร", 1]];
  const onDiff = (oa, ob, push) => {
    oa = oa || {}; ob = ob || {};
    for (const [f, lab, s] of ON) if ((oa[f] || 0) !== (ob[f] || 0)) push((ob[f] || 0) * s > (oa[f] || 0) * s ? "up" : "down", `${lab} ${num(oa[f] || 0)} → ${num(ob[f] || 0)}`);
    const sa = oa.st || {}, sb = ob.st || {};
    for (const k of new Set([...Object.keys(sa), ...Object.keys(sb)])) if ((sa[k] || 0) !== (sb[k] || 0)) push((sb[k] || 0) > (sa[k] || 0) ? "up" : "down", `${th(k.charAt(0).toUpperCase() + k.slice(1))} ${num(sa[k] || 0)} → ${num(sb[k] || 0)}`);
    const ha = oa.haste || [], hb = ob.haste || [];
    if (String(ha) !== String(hb)) push((hb[0] || 0) * (hb[1] || 0) >= (ha[0] || 0) * (ha[1] || 0) ? "up" : "down", `เร่งความเร็ว ${ha.length ? Math.round(ha[0] * 100) + "%/" + ha[1] + "วิ" : "-"} → ${hb.length ? Math.round(hb[0] * 100) + "%/" + hb[1] + "วิ" : "-"}`);
  };
  // items
  const newItems = [];
  for (const [id, ib] of Object.entries(b.items || {})) {
    const ia = (a.items || {})[id];
    const nm = `${ib.ic} ${th(ib.n)}`;
    if (!ia) { newItems.push(nm); continue; }
    const parts = [];
    onDiff(ia.on, ib.on, (k, t) => parts.push([k, t]));
    if ((ia.cd || 0) !== (ib.cd || 0) && ia.cd && ib.cd) parts.push([ib.cd < ia.cd ? "up" : "down", `ทำงานทุก ${num(ia.cd)} → ${num(ib.cd)} วิ`]);
    if ((ia.cost || 0) !== (ib.cost || 0)) parts.push([ib.cost < ia.cost ? "up" : "down", `ราคา ${ia.cost} → ${ib.cost}`]);
    for (const [k, t] of parts) add(k, "ไอเทม", `${nm}: ${t}`);
  }
  if (newItems.length) add("new", "ไอเทม", `ไอเทมใหม่ ${newItems.length} ชิ้น: ${newItems.slice(0, 12).join(", ")}${newItems.length > 12 ? " ..." : ""}`);
  // path Ultimates and Masterwork recipes
  for (const [p, pb] of Object.entries(b.paths || {})) {
    const pa = (a.paths || {})[p] || {};
    const ua = pa.ult, ub = pb.ult;
    const pn = `${pb.ic} ${th(pb.n)}`;
    if (ub && !ua) add("new", "ท่าไม้ตาย", `${pn}: ท่าไม้ตายใหม่ ${ub.ic} ${th(ub.n)}`);
    else if (ub && ua) {
      onDiff(ua.on, ub.on, (k, t) => add(k, "ท่าไม้ตาย", `${pn} ${ub.ic} ${th(ub.n)}: ${t}`));
      if (ua.need !== ub.need) add(ub.need < ua.need ? "up" : "down", "ท่าไม้ตาย", `${pn} ${ub.ic} ${th(ub.n)}: ชาร์จ ${ua.need} → ${ub.need} ครั้ง`);
    }
    const ra = (a.recipes || []).find((r) => r.path === p && r.c), rb = (b.recipes || []).find((r) => r.path === p && r.c);
    if (ra && rb && [ra.a, ra.b, ra.c].join() !== [rb.a, rb.b, rb.c].join()) {
      const n = (id) => (b.items[id] ? th(b.items[id].n) : id);
      add("chg", "สุดยอดฝีมือ", `${pn}: ${n(rb.r)} = ${n(rb.a)} + ${n(rb.b)} + ${n(rb.c)}`);
    }
  }
  // class resources (value per stack and cap)
  for (const [c, cb] of Object.entries(b.classes || {})) {
    const ra = ((a.classes || {})[c] || {}).res, rb = cb.res;
    if (!ra || !rb) continue;
    for (const [f, lab] of [["v", "ต่อหน่วย"], ["cap", "สูงสุด"]]) if (ra[f] !== rb[f]) add(rb[f] > ra[f] ? "up" : "down", "คลาส", `${cb.ic} ${th(cb.n)} ${rb.ic} ${th(rb.n)} ${lab}: ${ra[f]} → ${rb[f]}`);
  }
  // bosses and difficulties (more for the monster is bad for the player)
  for (const bb of b.bosses || []) {
    const ba = (a.bosses || []).find((x) => x.n === bb.n);
    if (!ba) continue;
    if (ba.hp !== bb.hp) add(bb.hp < ba.hp ? "up" : "down", "บอส", `${th(bb.n)}: HP ${ba.hp} → ${bb.hp}`);
    if (ba.atk !== bb.atk) add(bb.atk < ba.atk ? "up" : "down", "บอส", `${th(bb.n)}: พลังโจมตี ${ba.atk} → ${bb.atk}`);
  }
  for (const db of b.difficulties || []) {
    const da = (a.difficulties || []).find((x) => x.id === db.id);
    if (!da) continue;
    if (da.hp !== db.hp) add(db.hp < da.hp ? "up" : "down", "ความยาก", `${th(db.n)}: HP มอน ×${da.hp} → ×${db.hp}`);
    if (da.dps !== db.dps) add(db.dps < da.dps ? "up" : "down", "ความยาก", `${th(db.n)}: ดาเมจมอน ×${da.dps} → ×${db.dps}`);
  }
  return out;
}
