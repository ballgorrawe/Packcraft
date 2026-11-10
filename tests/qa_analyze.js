// QA analysis of Monte Carlo output from tests/qa_harness.gd (--mode=mc).
// Usage: node tests/qa_analyze.js <folder with *.out files> [data/game_data.json]
// Prints win rates by class / pet / style, item win-rate deltas, difficulty and gold curves,
// node choices, and a static value-per-tile table.
const fs = require("fs");
const path = require("path");
const dir = process.argv[2];
const dataPath = process.argv[3] || path.join(__dirname, "..", "data", "game_data.json");
const data = JSON.parse(fs.readFileSync(dataPath, "utf8"));

const runs = [];
for (const f of fs.readdirSync(dir).filter((f) => f.endsWith(".out"))) {
  for (const line of fs.readFileSync(path.join(dir, f), "utf8").split("\n")) {
    if (!line.startsWith("RUN|")) continue;
    const p = line.trim().split("|");
    if (p.length !== 20) continue; // half-written line (job still running)
    runs.push({
      style: p[1], diff: p[2], cls: p[3], pet: p[4], seed: +p[5], win: p[6] === "1", day: +p[7], path: p[8],
      gold: p[9] ? p[9].split(",").map(Number) : [], deaths: p[10] ? p[10].split(",").map(Number) : [],
      items: p[11] ? p[11].split(",") : [], fights: +p[12], losses: +p[13], ew: +p[14], el: +p[15], maxGold: +p[16],
      kinds: JSON.parse(p[17] || "{}"), campHp: p[18] ? p[18].split(",").map(Number) : [], cap: p[19] === "1",
    });
  }
}
const pct = (a, b) => (b ? ((100 * a) / b).toFixed(1) + "%" : "-");
const by = (arr, key) => arr.reduce((m, r) => ((m[key(r)] = m[key(r)] || []).push(r), m), {});
const line = (s) => console.log(s);

line(`# Runs: ${runs.length}`);
line("\n## Win rate by style x class (avg day reached)");
for (const [st, rs] of Object.entries(by(runs, (r) => r.style))) {
  const parts = Object.entries(by(rs, (r) => r.cls)).map(([c, x]) => `${c} ${pct(x.filter((r) => r.win).length, x.length)} (d${(x.reduce((s, r) => s + r.day, 0) / x.length).toFixed(1)})`);
  line(`- ${st} [n=${rs.length}] overall ${pct(rs.filter((r) => r.win).length, rs.length)} :: ${parts.join(" | ")}`);
}

const smart = runs.filter((r) => r.style === "smart");
line("\n## Win rate by pet (smart bot, all classes)");
for (const [p, x] of Object.entries(by(smart, (r) => r.pet)).sort()) line(`- ${p}: ${pct(x.filter((r) => r.win).length, x.length)} (n=${x.length})`);

line("\n## Win rate by class x path (smart)");
for (const [k, x] of Object.entries(by(smart, (r) => r.cls + "/" + (r.path || "-"))).sort()) line(`- ${k}: ${pct(x.filter((r) => r.win).length, x.length)} (n=${x.length})`);

line("\n## Class x pet matrix (smart, win %)");
const pets = [...new Set(smart.map((r) => r.pet))].sort();
line("| class | " + pets.join(" | ") + " |");
line("|---|" + pets.map(() => "---").join("|") + "|");
for (const [c, x] of Object.entries(by(smart, (r) => r.cls))) {
  const bp = by(x, (r) => r.pet);
  line(`| ${c} | ` + pets.map((p) => (bp[p] ? (100 * bp[p].filter((r) => r.win).length / bp[p].length).toFixed(0) : "-")).join(" | ") + " |");
}

line("\n## Difficulty curve (smart): fights lost per day / runs alive that day");
const alive = {}, lost = {};
for (const r of smart) {
  for (let d = 1; d <= Math.min(15, r.day); d++) alive[d] = (alive[d] || 0) + 1;
  for (const d of r.deaths) lost[d] = (lost[d] || 0) + 1;
}
line("| day | alive | fights lost | loss rate |");
line("|---|---|---|---|");
for (let d = 1; d <= 15; d++) line(`| ${d} | ${alive[d] || 0} | ${lost[d] || 0} | ${pct(lost[d] || 0, alive[d] || 0)} |`);
line("\nRun-ending day (smart, losses only):");
const endDay = by(smart.filter((r) => !r.win), (r) => r.day);
line(Object.keys(endDay).sort((a, b) => a - b).map((d) => `d${d}:${endDay[d].length}`).join("  "));

line("\n## Gold in hand each morning (smart, mean / p90)");
const gd = {};
for (const r of smart) r.gold.forEach((g, i) => (gd[i + 1] = gd[i + 1] || []).push(g));
line("| day | mean | p90 |");
line("|---|---|---|");
for (const d of Object.keys(gd).map(Number).sort((a, b) => a - b).slice(0, 15)) {
  const a = gd[d].slice().sort((x, y) => x - y);
  line(`| ${d} | ${(a.reduce((s, v) => s + v, 0) / a.length).toFixed(1)} | ${a[Math.floor(a.length * 0.9)]} |`);
}

line("\n## Nodes chosen (all styles)");
for (const [st, rs] of Object.entries(by(runs, (r) => r.style))) {
  const tot = {};
  rs.forEach((r) => Object.entries(r.kinds).forEach(([k, v]) => (tot[k] = (tot[k] || 0) + v)));
  line(`- ${st}: ` + Object.entries(tot).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k} ${v}`).join(", "));
}
const ew = runs.reduce((s, r) => s + r.ew, 0), el = runs.reduce((s, r) => s + r.el, 0);
line(`- Elite/Ambush fights won: ${pct(ew, ew + el)} of ${ew + el}`);
const greedy = runs.filter((r) => r.style === "greedy");
line(`- Greedy (takes Elites when healthy) wins ${pct(greedy.filter((r) => r.win).length, greedy.length)} vs smart ${pct(smart.filter((r) => r.win).length, smart.length)}`);
const camp = runs.flatMap((r) => r.campHp);
line(`- Campfire picks: ${camp.length}, avg HP when picked ${(100 * camp.reduce((s, v) => s + v, 0) / Math.max(1, camp.length)).toFixed(0)}%`);
line(`- Runs that built a Capstone: ${pct(runs.filter((r) => r.cap).length, runs.length)} (smart ${pct(smart.filter((r) => r.cap).length, smart.length)})`);

line("\n## Items in the final pack (smart): win rate with vs without (min 150 runs with it)");
const base = smart.filter((r) => r.win).length / smart.length;
const stats = {};
for (const r of smart) for (const id of new Set(r.items)) { const s = (stats[id] = stats[id] || { n: 0, w: 0 }); s.n++; if (r.win) s.w++; }
const rows = Object.entries(stats).filter(([, s]) => s.n >= 150).map(([id, s]) => {
  const without = smart.filter((r) => !r.items.includes(id));
  const wo = without.filter((r) => r.win).length / Math.max(1, without.length);
  return { id, n: s.n, pick: s.n / smart.length, wr: s.w / s.n, delta: s.w / s.n - wo };
});
rows.sort((a, b) => b.delta - a.delta);
const fmt = (x) => `| ${x.id} | ${data.items[x.id] ? data.items[x.id].n : x.id} | ${(100 * x.pick).toFixed(0)}% | ${(100 * x.wr).toFixed(0)}% | ${(100 * x.delta >= 0 ? "+" : "") + (100 * x.delta).toFixed(1)} |`;
line(`Baseline smart win rate ${(100 * base).toFixed(1)}%`);
line("\nTop 10 (biggest win-rate lift):\n| id | item | in packs | win% with | lift pts |\n|---|---|---|---|---|");
rows.slice(0, 10).forEach((x) => line(fmt(x)));
line("\nBottom 10:\n| id | item | in packs | win% with | lift pts |\n|---|---|---|---|---|");
rows.slice(-10).reverse().forEach((x) => line(fmt(x)));
line("\n(Lift is correlation, not cause: items that appear late or in strong runs look better.)");

line("\n## Static value: per tile and per gold (active items, before buffs)");
const val = [];
for (const [id, d] of Object.entries(data.items)) {
  if (!d.cd || d.cd <= 0 || !d.c) continue;
  const on = d.on || {};
  const st = on.st || {};
  const dps = ((on.dmg || 0) * (1 + (on.crit || 0) * ((on.critx || 2) - 1)) + (st.burn || 0) * 3 + (st.poison || 0) * 3) / d.cd;
  const sup = ((on.shield || 0) + (on.heal || 0)) / d.cd;
  const cells = d.c.length;
  val.push({ id, n: d.n, t: d.t, cells, cost: d.cost, dps, sup, perTile: (dps + sup) / cells, perGold: d.cost ? (dps + sup) / d.cost : null, shop: d.shop });
}
const tierN = data.tier_names;
val.sort((a, b) => b.perTile - a.perTile);
line("| item | rarity | tiles | dmg/s | shield+heal/s | value/tile | value/gold |\n|---|---|---|---|---|---|---|");
for (const x of val.filter((v) => v.shop)) line(`| ${x.n} | ${tierN[x.t]} | ${x.cells} | ${x.dps.toFixed(2)} | ${x.sup.toFixed(2)} | ${x.perTile.toFixed(2)} | ${x.perGold === null ? "-" : x.perGold.toFixed(2)} |`);
