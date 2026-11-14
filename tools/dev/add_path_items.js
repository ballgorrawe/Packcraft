// Adds 54 path items (2 per path: a mid-game piece and a late payoff) to data/game_data.json, with Thai text
// in data/i18n.json. "pth" ties an item to its path: the shop leans to it once that path is chosen.
// Re-running replaces the items it added before. Run from the project folder: node tools/dev/add_path_items.js
const fs = require("fs");
const S = { "1": [[0, 0]], "1x2": [[0, 0], [0, 1]], "2x1": [[0, 0], [1, 0]], "2x2": [[0, 0], [1, 0], [0, 1], [1, 1]], "1x3": [[0, 0], [0, 1], [0, 2]] };
// [id, path, class, name, thai name, icon, tier, cost, shape, cd, tags, extra fields, description (en), description (th)]
const A = [
  // ember
  ["cinder_quill", "phoenix", "ember", "Cinder Quill", "ขนนกถ่านไฟ", "🪶", 1, 5, "1", 3, ["Tool", "Fire"], { on: { heal: 2, st: { burn: 1 } } }],
  ["phoenix_mantle", "phoenix", "ember", "Phoenix Mantle", "ผ้าคลุมฟีนิกซ์", "🧥", 2, 10, "2x2", 4.5, ["Armor", "Fire"], { on: { shield: 7 }, sp: "heal_burn" },
    "Every time you heal 1 or more, the enemy gains 1 Burn.", "ทุกครั้งที่ฟื้นเลือด 1 ขึ้นไป ศัตรูติด Burn 1"],
  ["kindling_gem", "inferno", "ember", "Kindling Gem", "อัญมณีเชื้อไฟ", "🔸", 1, 5, "1", 0, ["Gem", "Fire"], { adj: [{ tag: "Weapon", k: "to_fire", v: 1 }, { tag: "Fire", k: "burn", v: 1 }] }],
  ["pyre_brand", "inferno", "ember", "Pyre Brand", "ดาบกองไฟ", "🗡️", 2, 10, "1x2", 2, ["Weapon", "Melee", "Fire"], { on: { dmg: 6, el: "Fire" }, sp: "burn_feed" },
    "+0.4 damage for every Burn on the enemy (up to +12).", "ดาเมจ +0.4 ต่อ Burn ที่ศัตรูติด (สูงสุด +12)"],
  ["tempering_anvil", "forgeblade", "ember", "Tempering Anvil", "ทั่งชุบเหล็ก", "⚒️", 1, 6, "2x1", 0, ["Tool"], { adj: [{ tag: "Weapon", k: "dmg", v: 2 }, { tag: "Weapon", k: "pierce", v: 0.1 }] }],
  ["forgefather_maul", "forgeblade", "ember", "Forgefather's Maul", "ค้อนบิดาแห่งเตาหลอม", "🔨", 2, 10, "1x3", 2.8, ["Weapon", "Melee"], { on: { dmg: 13, el: "Physical", ramp: 1.5 } }],
  // venom
  ["fuse_pouch", "bombardier", "venom", "Fuse Pouch", "ถุงชนวน", "🧨", 1, 5, "1", 0, ["Tool", "Fire"], { adj: [{ tag: "Bomb", k: "cdr", v: 0.12 }, { tag: "Bomb", k: "burn", v: 1 }] }],
  ["chain_grenade", "bombardier", "venom", "Chain Grenade", "ระเบิดลูกโซ่", "💣", 2, 9, "2x1", 3, ["Bomb", "Fire"], { on: { dmg: 10, el: "Fire", st: { burn: 2 } }, sp: "bomb_chain" },
    "When it goes off, your other Bombs charge 0.5s.", "เมื่อระเบิด ระเบิดลูกอื่นของคุณชาร์จเร็วขึ้น 0.5 วิ"],
  ["blight_vial", "plague", "venom", "Blight Vial", "ขวดโรคเน่า", "🧪", 1, 5, "1", 2.5, ["Potion", "Nature"], { on: { st: { poison: 3 } } }],
  ["rot_harvester", "plague", "venom", "Rot Harvester", "เคียวเก็บเกี่ยวความเน่า", "🌾", 2, 10, "1x3", 2.4, ["Weapon", "Melee", "Nature"], { on: { dmg: 5, el: "Nature" }, sp: "poison_harvest" },
    "Each hit also deals 25% of the enemy's Poison as Nature damage.", "ทุกครั้งที่ตี สร้างดาเมจ Nature เพิ่ม 25% ของ Poison ที่ศัตรูติด"],
  ["gilded_shiv", "transmuter", "venom", "Gilded Shiv", "มีดทองคำ", "🔪", 1, 5, "1", 1.5, ["Weapon", "Melee"], { on: { dmg: 3, el: "Physical", st: { bleed: 1 } }, sp: "gold_shot" },
    "+1 damage for every 6 gold you hold.", "ดาเมจ +1 ต่อทองที่ถือทุก 6 เหรียญ"],
  ["alchemy_crucible", "transmuter", "venom", "Alchemy Crucible", "เบ้าหลอมแปรธาตุ", "🏺", 2, 10, "2x2", 0, ["Tool"], { pass: { income: 2 }, adj: [{ tag: "Weapon", k: "dmg", v: 2 }] }],
  // tinker
  ["spark_plug", "voltmaster", "tinker", "Spark Plug", "หัวเทียน", "🔌", 1, 5, "1", 1.2, ["Mech", "Shock"], { on: { dmg: 2, el: "Shock" } }],
  ["arc_relay", "voltmaster", "tinker", "Arc Relay", "รีเลย์สายฟ้า", "📡", 2, 10, "2x1", 0, ["Mech", "Shock"], { sp: "shock_relay" },
    "Every 4th Shock hit from your pack zaps the enemy for 8 more Shock.", "ทุกการโจมตี Shock ครั้งที่ 4 ในกระเป๋า ช็อตศัตรูเพิ่ม 8 Shock"],
  ["capacitor_bank", "overclock", "tinker", "Capacitor Bank", "แบงก์ตัวเก็บประจุ", "🔋", 1, 6, "2x1", 2.5, ["Mech", "Tool"], { on: { charge: 0.5 } }],
  ["overdrive_coil", "overclock", "tinker", "Overdrive Coil", "ขดลวดโอเวอร์ไดรฟ์", "🌀", 2, 10, "1x2", 2, ["Mech", "Shock"], { on: { dmg: 6, el: "Shock", haste: [0.15, 2] } }],
  ["ammo_crate", "arsenal", "tinker", "Ammo Crate", "ลังกระสุน", "📦", 1, 5, "2x1", 0, ["Tool"], { adj: [{ tag: "Turret", k: "dmg", v: 2 }] }],
  ["twin_turret", "arsenal", "tinker", "Twin Turret", "ป้อมปืนแฝด", "🗼", 2, 10, "1x2", 2, ["Turret", "Weapon", "Ranged", "Mech"], { on: { dmg: 6, el: "Physical" }, sp: "turret_volley" },
    "Fires a second shot for half damage.", "ยิงซ้ำอีกนัด ดาเมจครึ่งหนึ่ง"],
  // warden
  ["tremor_boots", "earthshaker", "warden", "Tremor Boots", "รองเท้าสะเทือนพื้น", "🥾", 1, 5, "2x1", 3, ["Armor"], { on: { shield: 4 }, adj: [{ tag: "Melee", k: "dmg", v: 1 }] }],
  ["fault_maul", "earthshaker", "warden", "Fault Maul", "ค้อนรอยเลื่อน", "🔨", 2, 10, "1x3", 3, ["Weapon", "Melee"], { on: { dmg: 15, el: "Physical" }, sp: "aftershock" },
    "Each hit is followed by an aftershock for 30% of its damage.", "ทุกครั้งที่ตี มีแรงสั่นตามมาอีก 30% ของดาเมจ"],
  ["briar_coat", "thorns", "warden", "Briar Coat", "เสื้อเถาหนาม", "🧥", 1, 5, "2x1", 3, ["Armor", "Plant"], { on: { shield: 3, st: { thorns: 2 } } }],
  ["bramble_heart", "thorns", "warden", "Bramble Heart", "หัวใจพุ่มหนาม", "💚", 2, 10, "1", 0, ["Plant", "Nature"], { sp: "thorn_shield" },
    "Every time your Thorns hit back, gain 1 Shield.", "ทุกครั้งที่หนามสะท้อนดาเมจ ได้โล่ 1"],
  ["titan_belt", "colossus", "warden", "Titan Belt", "เข็มขัดไททัน", "🎗️", 1, 6, "2x1", 0, ["Armor"], { pass: { hp_pct: 25 } }],
  ["colossus_fist", "colossus", "warden", "Colossus Fist", "กำปั้นยักษ์", "👊", 2, 10, "2x1", 3, ["Weapon", "Melee"], { on: { dmg: 4, el: "Physical" }, sp: "hp_strike_big" },
    "+10% of your Max HP as damage.", "ดาเมจเพิ่ม 10% ของเลือดสูงสุด"],
  // rogue
  ["whetted_edge", "assassin", "rogue", "Whetted Edge", "หินลับคม", "🪨", 1, 5, "1", 0, ["Tool"], { adj: [{ tag: "Weapon", k: "crit", v: 0.08 }] }],
  ["coup_dagger", "assassin", "rogue", "Coup Dagger", "กริชปลิดชีพ", "🗡️", 2, 10, "1x2", 2, ["Weapon", "Melee"], { on: { dmg: 7, el: "Physical", crit: 0.25, critx: 2.5 }, sp: "execute_low" },
    "Deals 50% more damage to an enemy below 30% HP.", "ดาเมจ +50% ใส่ศัตรูที่เลือดต่ำกว่า 30%"],
  ["hemo_hook", "crimson", "rogue", "Hemorrhage Hook", "ตะขอเลือดไหล", "🪝", 1, 5, "1x2", 1.8, ["Weapon", "Melee"], { on: { dmg: 3, el: "Physical", st: { bleed: 2 } } }],
  ["sanguine_chalice", "crimson", "rogue", "Sanguine Chalice", "ถ้วยโลหิต", "🍷", 2, 10, "1", 0, ["Charm"], { all: [{ tag: "Weapon", k: "bleed", v: 1 }] }],
  ["shadow_boots", "phantom", "rogue", "Shadow Boots", "รองเท้าเงา", "👢", 1, 5, "1", 0, ["Armor"], { sp: "phantom_dodge" },
    "+6% chance to dodge.", "โอกาสหลบ +6%"],
  ["phantom_knives", "phantom", "rogue", "Phantom Knives", "มีดบินเงา", "🔪", 2, 10, "1", 1.2, ["Weapon", "Ranged"], { on: { dmg: 3, el: "Physical" }, sp: "empty_dmg" },
    "+1 damage for every empty pack tile (up to +8).", "ดาเมจ +1 ต่อช่องว่างในกระเป๋า (สูงสุด +8)"],
  // weaver
  ["comet_fragment", "starcaller", "weaver", "Comet Fragment", "เศษดาวหาง", "☄️", 1, 5, "1", 2.2, ["Spell", "Arcane"], { on: { dmg: 4, el: "Arcane" } }],
  ["astral_loom", "starcaller", "weaver", "Astral Loom", "กี่ทอดวงดาว", "🧵", 2, 10, "2x1", 0, ["Tool", "Arcane"], { adj: [{ tag: "Spell", k: "cdr", v: 0.12 }, { tag: "Spell", k: "dmg", v: 2 }] }],
  ["frost_bead", "frostbinder", "weaver", "Frost Bead", "ลูกปัดน้ำแข็ง", "🧊", 1, 5, "1", 2, ["Spell", "Water"], { on: { dmg: 3, el: "Water", st: { soaked: 1 } } }],
  ["glacier_tome", "frostbinder", "weaver", "Glacier Tome", "ตำราธารน้ำแข็ง", "📘", 2, 10, "1x2", 3, ["Spell", "Water"], { on: { dmg: 8, el: "Water" }, sp: "shatter" },
    "+2 damage for every Soaked on the enemy (up to +16).", "ดาเมจ +2 ต่อ Soaked ที่ศัตรูติด (สูงสุด +16)"],
  ["hollow_candle", "voidcaller", "weaver", "Hollow Candle", "เทียนกลวง", "🕯️", 1, 5, "1", 2.4, ["Spell", "Arcane"], { on: { dmg: 6, el: "Arcane" } }],
  ["abyss_pact", "voidcaller", "weaver", "Abyss Pact", "สัญญาห้วงเหว", "📜", 2, 10, "1", 0, ["Charm"], { sp: "spell_leech" },
    "Your Spells heal you for 10% of their damage.", "เวทของคุณฟื้นเลือด 10% ของดาเมจ"],
  // inquisitor
  ["oath_plate", "templar", "inquisitor", "Oath Plate", "เกราะคำสาบาน", "🛡️", 1, 6, "2x2", 3.5, ["Armor"], { on: { shield: 7 } }],
  ["bulwark_blade", "templar", "inquisitor", "Bulwark Blade", "ดาบปราการ", "⚔️", 2, 10, "1x3", 2.4, ["Weapon", "Melee"], { on: { dmg: 8, el: "Physical" }, sp: "shield_dmg" },
    "+25% of your Shield as damage.", "ดาเมจเพิ่ม 25% ของโล่ที่มี"],
  ["gale_rune", "tempest", "inquisitor", "Gale Rune", "รูนลมกรรโชก", "🌬️", 1, 5, "1", 2, ["Rune", "Shock"], { on: { dmg: 3, el: "Shock", haste: [0.1, 1.5] } }],
  ["squall_blade", "tempest", "inquisitor", "Squall Blade", "ดาบพายุฝน", "🗡️", 2, 10, "1x2", 1.2, ["Weapon", "Melee", "Shock"], { on: { dmg: 4, el: "Shock", charge: 0.3 } }],
  ["crimson_rune", "dusk", "inquisitor", "Crimson Rune", "รูนสีเลือด", "🩸", 1, 5, "1", 2.6, ["Rune"], { on: { dmg: 4, el: "Physical", heal: 1, st: { bleed: 1 } } }],
  ["duskreaver", "dusk", "inquisitor", "Duskreaver", "ดาบล่าอัสดง", "⚔️", 2, 10, "1x3", 2.6, ["Weapon", "Melee"], { on: { dmg: 12, el: "Physical" }, sp: "leech" },
    "Heals you for 15% of its damage.", "ฟื้นเลือด 15% ของดาเมจที่ทำ"],
  // beast
  ["jackal", "packlord", "beast", "Jackal", "หมาจิ้งจอก", "🐕", 1, 5, "1", 1.4, ["Beast", "Melee"], { on: { dmg: 3, el: "Physical" } }],
  ["den_banner", "packlord", "beast", "Den Banner", "ธงรังฝูง", "🚩", 2, 10, "1x2", 0, ["Totem"], { all: [{ tag: "Beast", k: "dmg", v: 2 }] }],
  ["bone_talisman", "apex", "beast", "Bone Talisman", "เครื่องรางกระดูก", "🦴", 1, 5, "1", 0, ["Charm"], { adj: [{ tag: "Beast", k: "pierce", v: 0.1 }, { tag: "Beast", k: "bleed", v: 1 }] }],
  ["dire_lynx", "apex", "beast", "Dire Lynx", "แมวป่าดุร้าย", "🐆", 2, 10, "2x1", 1.8, ["Beast", "Melee"], { on: { dmg: 6, el: "Physical", crit: 0.15, st: { bleed: 2 } } }],
  ["moss_totem", "shaman", "beast", "Moss Totem", "โทเท็มตะไคร่", "🎋", 1, 5, "1x2", 3, ["Totem", "Nature"], { on: { heal: 3 } }],
  ["elder_stag", "shaman", "beast", "Elder Stag", "กวางผู้เฒ่า", "🦌", 2, 10, "2x2", 2.5, ["Beast", "Nature"], { on: { dmg: 5, el: "Nature", heal: 3 }, sp: "heal_shield" },
    "When it heals, also gain half as much Shield.", "เมื่อฟื้นเลือด ได้โล่ครึ่งหนึ่งของที่ฟื้น"],
  // corsair
  ["powder_horn", "cannoneer", "corsair", "Powder Horn", "เขาดินปืน", "📯", 1, 5, "1", 0, ["Tool"], { adj: [{ tag: "Ranged", k: "dmg", v: 2 }] }],
  ["swivel_gun", "cannoneer", "corsair", "Swivel Gun", "ปืนหมุน", "🔫", 2, 10, "2x1", 1.6, ["Weapon", "Ranged"], { on: { dmg: 7, el: "Physical", crit: 0.1 } }],
  ["serrated_gaff", "bloodwater", "corsair", "Serrated Gaff", "ตะขอฟันเลื่อย", "🪝", 1, 5, "1x2", 1.8, ["Weapon", "Melee", "Sea"], { on: { dmg: 3, el: "Physical", st: { bleed: 2 } } }],
  ["tiger_shark", "bloodwater", "corsair", "Tiger Shark", "ฉลามเสือ", "🦈", 2, 10, "2x1", 1.6, ["Beast", "Sea"], { on: { dmg: 6, el: "Physical", st: { bleed: 1 } }, sp: "blood_scent" },
    "Deals 40% more damage to a Bleeding enemy.", "ดาเมจ +40% ใส่ศัตรูที่เลือดออก"],
  ["tide_pearl", "siren", "corsair", "Tide Pearl", "ไข่มุกกระแสน้ำ", "🦪", 1, 5, "1", 0, ["Charm", "Water"], { adj: [{ tag: "Water", k: "soaked", v: 1 }, { tag: "Shock", k: "dmg", v: 2 }] }],
  ["siren_conch", "siren", "corsair", "Siren Conch", "หอยสังข์ไซเรน", "🐚", 2, 10, "1", 2.5, ["Tool", "Water", "Shock"], { on: { dmg: 4, el: "Shock", st: { soaked: 2 } } }],
];

const gd = JSON.parse(fs.readFileSync("data/game_data.json", "utf8"));
let j = fs.readFileSync("data/game_data.json", "utf8");
const ids = new Set(A.map((a) => a[0]));
// drop lines this tool added before, then check the ids are free
j = j.split("\n").filter((l) => { const m = l.match(/^  "([a-z_]+)": \{.*"pth":/); return !(m && ids.has(m[1])); }).join("\n");
const now = JSON.parse(j);
for (const a of A) {
  if (now.items[a[0]]) throw new Error("id taken: " + a[0]);
  if (!gd.paths[a[1]] || gd.paths[a[1]].cl !== a[2]) throw new Error("bad path: " + a[1]);
}
// corner badge: the path's icon (tests want no two items to look the same), else the first free fallback
const looks = new Set(Object.values(now.items).map((it) => it.ic + "|" + (it.bd || "")));
const badge = (ic, pth) => {
  for (const b of [gd.paths[pth].ic, "⭐", "✨", "🔹", "🔸", "💠", "👑", "🔥", "⚡", "🩸"]) {
    if (!looks.has(ic + "|" + b)) { looks.add(ic + "|" + b); return b; }
  }
  throw new Error("no free badge for " + ic);
};
const lines = A.map(([id, pth, cl, n, , ic, t, cost, shape, cd, tags, x, dd]) => {
  const it = { bd: badge(ic, pth), n, ic, t, lv: t >= 2 ? 2 : 1, cost, cl, shop: 1, pth, c: S[shape], tags, cd, ...x };
  if (dd) it.d = dd;
  return "  " + JSON.stringify(id) + ": " + JSON.stringify(it) + ",";
});
j = j.replace('\n "items": {\n', '\n "items": {\n' + lines.join("\n") + "\n");
JSON.parse(j);
fs.writeFileSync("data/game_data.json", j);

let t = fs.readFileSync("data/i18n.json", "utf8");
const have = JSON.parse(t).th;
const th = {};
for (const a of A) { th[a[3]] = a[4]; if (a[12]) th[a[12]] = a[13]; }
const add = Object.entries(th).filter(([k]) => !(k in have)).map(([k, v]) => "  " + JSON.stringify(k) + ": " + JSON.stringify(v) + ",");
const anchor = '  "Auto-arrange the pack": "จัดกระเป๋าอัตโนมัติ",';
t = t.replace(anchor, anchor + (add.length ? "\n" + add.join("\n") : ""));
JSON.parse(t);
fs.writeFileSync("data/i18n.json", t);
console.log("added", A.length, "items,", add.length, "Thai strings");
