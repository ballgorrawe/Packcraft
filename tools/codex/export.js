// The Codex data (items, monsters, bosses, classes, pets, events, rules, sprites) from the game files.
// node export.js <project dir> <out data.json>  (tools/codex/build.js runs it)
const fs = require("fs");
const P = process.argv[2];
const d = JSON.parse(fs.readFileSync(P + "/data/game_data.json", "utf8"));
const T = JSON.parse(fs.readFileSync(P + "/data/i18n.json", "utf8")).th;
const SP = JSON.parse(fs.readFileSync(P + "/data/sprites.json", "utf8"));
const main = fs.readFileSync(P + "/scripts/main.gd", "utf8");
const th = (s) => (s && T[s]) || s || "";
const two = (s) => ({ th: th(s), en: s || "" });
const snake = (n) => n.toLowerCase().replace(/ /g, "_").replace(/'/g, "");

// ---- items (player items, as before)
const made = {}; for (const r of d.recipes) (made[r.r] = made[r.r] || []).push(r);
const evoFrom = {}; for (const [k, v] of Object.entries(d.items)) if (v.evo) evoFrom[v.evo] = k;
const relicOf = {}; for (const [k, p] of Object.entries(d.paths)) relicOf[p.relic] = k;
const items = [];
for (const [k, v] of Object.entries(d.items)) {
  const src = []; if (v.shop) src.push("shop"); if (evoFrom[k]) src.push("evo"); if (made[k]) src.push(made[k].some((r) => r.c) ? "mw" : "recipe"); if (relicOf[k]) src.push("relic"); if (v.sig) src.push("sig"); if (!src.length) src.push("other");
  const how = []; if (evoFrom[k]) how.push(["evo", [evoFrom[k], evoFrom[k]]]); for (const r of made[k] || []) how.push([r.c ? "mw" : "recipe", [r.a, r.b].concat(r.c ? [r.c] : [])]);
  const on = v.on || {};
  items.push({ id: k, ic: v.ic, bd: v.bd || "", n: v.n, th: th(v.n), cl: v.cl || "", t: v.t, cost: v.cost, cells: v.c.length, tags: v.tags.map(th), cd: v.cd || 0, dmg: on.dmg || 0, sh: on.shield || 0, hl: on.heal || 0, el: on.el ? th(on.el) : "", d: v.d ? th(v.d) : "", src, how, evo: v.evo || "", path: relicOf[k] ? th(d.paths[relicOf[k]].n) : "", sig: v.sig || 0 });
}
// ---- monsters
const effect = (on) => {
  const out = [];
  if (on.dmg) out.push("⚔️ " + on.dmg);
  if (on.shield) out.push("🛡️ " + on.shield);
  if (on.heal) out.push("💚 " + on.heal);
  for (const [k, n] of Object.entries(on.st || {})) out.push(d.statuses[k].ic + " " + th(d.statuses[k].n) + " " + n);
  if (on.haste) out.push("💨 เร็วขึ้น " + Math.round(on.haste[0] * 100) + "% " + on.haste[1] + " วิ");
  if (on.crit) out.push("🎯 " + Math.round(on.crit * 100) + "%");
  return out.join(" · ");
};
const mitem = (id) => { const m = d.monster_items[id]; return { ic: m.ic, ...two(m.n), t: m.t, cd: m.cd, fx: effect(m.on || {}) }; };
const bandOf = {}; for (const [b, fams] of Object.entries(d.foe_bands)) for (const f of fams) bandOf[f] = +b;
const monsters = Object.entries(d.families).map(([fam, ids]) => {
  const el = d.elites[fam], st = d.foe_styles[fam], u = d.foe_ults[fam];
  return {
    id: fam, ...two(fam), ic: d.foe_icons[fam], sprite: "foe_" + snake(fam), band: bandOf[fam] || 1,
    style: { ic: st.ic, ...two(st.n), d: th(st.d) },
    items: ids.map(mitem),
    ult: u ? { ic: u.ic, ...two(u.n), d: th(u.d) } : null,
    elite: el ? { ...two(el.n), ic: el.ic, sprite: "elite_" + snake(el.n), d: th(el.d), traits: el.tr.split(",").map((k) => ({ ic: d.traits[k].ic, ...two(d.traits[k].n), d: th(d.traits[k].d || "") })), item: mitem(el.item) } : null,
  };
});
const bosses = d.bosses.map((b) => ({
  ...two(b.n), ic: d.foe_icons[b.n], sprite: "boss_" + snake(b.n), floor: b.d, hp: b.hp, atk: b.atk, cd: b.cd,
  imm: b.imm ? th(b.imm) : "", weak: b.weak ? th(b.weak) : "",
  mech: b.mech ? { ic: b.mech.ic, ...two(b.mech.n), d: th(b.mech.d) } : null,
  pack: (d.boss_packs[b.n] ? d.boss_packs[b.n].items : []).map((p) => mitem(p[0])),
  drops: (d.boss_drops[b.n] || []).map(([id, w]) => ({ id, ic: d.items[id] ? d.items[id].ic : "", th: d.items[id] ? th(d.items[id].n) : id, w })),
}));
const traits = Object.entries(d.traits).map(([k, v]) => ({ ic: v.ic, ...two(v.n), d: th(v.d || "") }));
// ---- classes and paths
const classes = Object.entries(d.classes).map(([k, c]) => ({
  id: k, ...two(c.n), ic: c.ic, col: c.col, sprite: "hero_" + k, d: th(c.d), stats: Object.entries(c.stats || {}).map(([s, v]) => [th(s), v]),
  comp: (c.comp || []).map(th), start: (c.st || []).map((s) => s[0]),
  ult: c.ult ? { ic: c.ult.ic, ...two(c.ult.n), d: th(c.ult.d) } : null,
  paths: c.paths.map((p) => { const pd = d.paths[p]; const mw = d.recipes.find((r) => r.path === p && r.c); return { ...two(pd.n), ic: pd.ic, d: th(pd.d), relic: pd.relic, mw: mw ? { parts: [mw.a, mw.b, mw.c], r: mw.r } : null }; }),
}));
const pets = Object.entries(d.pets).map(([k, p]) => ({ id: k, ...two(p.n), ic: p.ic, sprite: "pet_" + k, d: th(p.d) }));
// ---- events, world rules, hazards, difficulties
const evs = [];
const evRe = /"(\w+)": \["([^"]+)", "([^"]+)", "([^"]+)"\]/g;
for (const block of [main.slice(main.indexOf("const EV := {"), main.indexOf("}", main.indexOf("const EV := {"))), main.slice(main.indexOf("const GAMES := {"), main.indexOf("}", main.indexOf("const GAMES := {")))])
  for (const m of block.matchAll(evRe)) evs.push({ id: m[1], ic: m[2], ...two(m[3]), d: th(m[4]), sprite: "ev_" + m[1] });
evs.push({ id: "camp", ic: "🔥", ...two("Campfire"), d: th("Recover 50% HP"), sprite: "ev_camp" });
const mods = d.mods.map((m) => ({ ...two(m.n), d: th(m.d) }));
const hazards = d.hazards.map((h) => ({ ic: h.ic, ...two(h.n), d: th(h.d) }));
const statuses = Object.entries(d.statuses).map(([k, s]) => ({ ic: s.ic, ...two(s.n), d: th(s.d || ""), col: s.col }));
const diffs = d.difficulties.map((x) => ({ ic: x.ic, ...two(x.n), d: th(x.d), hp: x.hp, dps: x.dps }));
const picks = (d.leveling.picks || []).map((p) => ({ ic: p.ic, ...two(p.n), d: th(p.d) }));
const out = { items, cls: Object.fromEntries(Object.entries(d.classes).map(([k, c]) => [k, { n: th(c.n), ic: c.ic, col: c.col }])), tiers: d.tier_names.map(th), tcol: d.tier_colors,
  monsters, bosses, traits, classes, pets, events: evs, mods, hazards, statuses, diffs, picks, sprites: SP };
fs.writeFileSync(process.argv[3], JSON.stringify(out));
console.log("items", items.length, "monsters", monsters.length, "bosses", bosses.length, "events", evs.length, "bytes", fs.statSync(process.argv[3]).size);
