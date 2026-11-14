// Lists every player-visible English string that has no Thai translation.
// node th_scan.js <project dir> [out.json]
const fs = require('fs');
const path = require('path');
const P = process.argv[2];
const th = JSON.parse(fs.readFileSync(path.join(P, 'data/i18n.json'), 'utf8')).th;
const data = JSON.parse(fs.readFileSync(path.join(P, 'data/game_data.json'), 'utf8'));
const DISPLAY = new Set(['n', 'd', 'comp', 'warn', 'txt', 'line', 'desc', 'msg', 'title', 'lines', 'tip', 'short', 'say', 'name']);
const miss = {};
const add = (s, where) => {
  if (typeof s !== 'string') return;
  if (!s.trim() || !/[A-Za-z]{2,}/.test(s) || s in th) return;
  (miss[s] = miss[s] || new Set()).add(where);
};
function walk(o, where, key) {
  if (Array.isArray(o)) { o.forEach((x) => (typeof x === 'string' ? DISPLAY.has(key) && add(x, where) : walk(x, where, key))); return; }
  if (o && typeof o === 'object') { for (const k in o) { const v = o[k]; if (typeof v === 'string') { if (DISPLAY.has(k)) add(v, where + '.' + k); } else walk(v, where + (/^\d+$/.test(k) ? '' : '.' + k), k); } }
}
for (const top in data) walk(data[top], top, top);
// code: tr("...") / I18n.t("...")
const files = [];
(function rec(d) { for (const f of fs.readdirSync(d)) { const p = path.join(d, f); if (fs.statSync(p).isDirectory()) rec(p); else if (p.endsWith('.gd')) files.push(p); } })(path.join(P, 'scripts'));
for (const f of files) {
  const src = fs.readFileSync(f, 'utf8');
  const re = /\b(?:tr|I18n\.t)\(\s*"((?:[^"\\]|\\.)*)"/g;
  let m;
  while ((m = re.exec(src))) add(JSON.parse('"' + m[1] + '"'), 'code:' + path.basename(f));
}
const groups = {};
for (const [s, w] of Object.entries(miss)) { const g = [...w][0].split('.').slice(0, 2).join('.'); (groups[g] = groups[g] || []).push(s); }
for (const g of Object.keys(groups).sort()) console.log(String(groups[g].length).padStart(4), g, '|', groups[g].slice(0, 3).join(' / ').slice(0, 110));
console.log('TOTAL', Object.keys(miss).length);
if (process.argv[3]) fs.writeFileSync(process.argv[3], JSON.stringify(Object.fromEntries(Object.entries(miss).map(([k, v]) => [k, [...v]])), null, 1));
