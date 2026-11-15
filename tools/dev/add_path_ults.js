// Writes each path's Ultimate into data/game_data.json (paths[id].ult) and its Thai text into data/i18n.json.
// Re-runnable. node tools/dev/add_path_ults.js
const fs = require("fs");
const U = [
  // [path, name, thai name, icon, need, on, sp, d, thai d]
  ["inferno", "Solar Flare", "เปลวสุริยะ", "☀️", 22, {el: "Fire", st: {burn: 12}}, "solar_flare", "Detonates all Burn on the enemy for three times its stacks as Fire damage, then adds 12 Burn.", "ระเบิด Burn ทั้งหมดบนศัตรูเป็นดาเมจไฟ 3 เท่าของจำนวน Burn แล้วติด Burn 12"],
  ["forgeblade", "World Cleave", "ผ่าโลก", "🪓", 22, {dmg: 60, dmg_per_res: 5, el: "Physical", shield: 15}, "pierce_all", "Deals 60 + 5 per Heat Physical damage that ignores Armor, and gives 15 Shield.", "ดาเมจกายภาพ 60 + 5 ต่อ Heat ทะลุเกราะทั้งหมด และได้ Shield 15"],
  ["phoenix", "Rebirth Flame", "เปลวเกิดใหม่", "🪶", 22, {st: {burn: 6}}, "heal_pct", "Heals 25% of your Max HP and adds 6 Burn.", "ฮีล 25% ของ Max HP และติด Burn 6"],
  ["plague", "Pandemic", "โรคระบาด", "🦠", 24, {heal: 12}, "double_poison", "Doubles the Poison on the enemy and heals you for 12.", "Poison บนศัตรูเพิ่มเป็น 2 เท่า และฮีล 12"],
  ["transmuter", "Midas Touch", "สัมผัสไมดาส", "💰", 24, {el: "Physical", st: {bleed: 6}, heal: 10}, "midas", "Deals 1.5 damage per gold you hold (max 120), adds 6 Bleed and heals you for 10.", "ดาเมจ 1.5 ต่อทองที่ถือ (สูงสุด 120) ติด Bleed 6 และฮีล 10"],
  ["bombardier", "Carpet Bomb", "ทิ้งระเบิดปูพรม", "💣", 24, {st: {burn: 8}, heal: 8}, "fire_bomb", "Every Bomb goes off at once, then adds 8 Burn and heals you for 8.", "ระเบิดทุกชิ้นทำงานทันที แล้วติด Burn 8 และฮีล 8"],
  ["overclock", "Overdrive", "โอเวอร์ไดรฟ์", "⚡", 24, {haste: [0.6, 5], shield: 15}, "full_charge", "Every item charges fully, then +60% Haste for 5 seconds and 15 Shield.", "ไอเทมทุกชิ้นชาร์จเต็ม แล้ว Haste +60% นาน 5 วินาที และได้ Shield 15"],
  ["arsenal", "Full Barrage", "ระดมยิง", "🎯", 24, {dmg: 25, el: "Physical"}, "fire_turret", "Every Turret fires three times at once, then a 25 damage shell.", "Turret ทุกชิ้นยิงทันที 3 รอบ แล้วยิงกระสุน 25 ดาเมจ"],
  ["voltmaster", "Thunderstorm", "พายุฟ้าคะนอง", "🌩️", 24, {dmg: 18, el: "Shock"}, "volley6", "Six lightning bolts, 18 Shock damage each.", "สายฟ้า 6 ครั้ง ครั้งละ 18 ดาเมจ Shock"],
  ["thorns", "Iron Thicket", "พงหนามเหล็ก", "🌵", 16, {shield: 40, st: {thorns: 16}}, "", "Gain 16 Thorns and 40 Shield.", "ได้ Thorns 16 และ Shield 40"],
  ["colossus", "Titan Slam", "ทุบไททัน", "🗿", 16, {el: "Physical"}, "titan_slam", "Deals damage equal to 30% of your Max HP.", "ดาเมจเท่ากับ 30% ของ Max HP"],
  ["earthshaker", "Earthquake", "แผ่นดินไหว", "🌋", 16, {dmg: 20, el: "Physical"}, "stun25", "Deals 20 Physical damage and stuns the enemy's items for 2.5 seconds.", "ดาเมจกายภาพ 20 และสตันไอเทมศัตรู 2.5 วินาที"],
  ["crimson", "Hemorrhage", "เลือดทะลัก", "🩸", 30, {}, "hemorrhage", "Doubles the Bleed on the enemy and heals you for half of it.", "Bleed บนศัตรูเพิ่มเป็น 2 เท่า และฮีลครึ่งหนึ่งของ Bleed"],
  ["phantom", "Shadow Volley", "ห่าธนูเงา", "🏹", 30, {}, "fire_ranged", "Every Ranged weapon fires at once and you evade the next 2 attacks.", "อาวุธ Ranged ทุกชิ้นยิงทันที และหลบการโจมตี 2 ครั้งถัดไป"],
  ["assassin", "Shadowstep", "ก้าวเงา", "👤", 30, {}, "shadowstep", "Evade the next attack; your next weapon hit is a 250% critical hit that applies 6 Bleed.", "หลบการโจมตีครั้งถัดไป อาวุธครั้งถัดไปคริ 250% และติด Bleed 6"],
  ["frostbinder", "Absolute Freeze", "เยือกแข็งสัมบูรณ์", "❄️", 40, {st: {soaked: 6}}, "freeze30", "Freezes the enemy's items for 3 seconds and Soaks it 6.", "แช่แข็งไอเทมศัตรู 3 วินาที และติด Soaked 6"],
  ["voidcaller", "Event Collapse", "หลุมดำถล่ม", "🕳️", 40, {dmg: 60, dmg_per_res: 3, el: "Arcane"}, "void_cost", "Lose 10% of your HP: deal 60 + 3 per Mana Magic damage.", "เสีย 10% ของ HP แลกดาเมจเวท 60 + 3 ต่อ Mana"],
  ["starcaller", "Supernova", "ซูเปอร์โนวา", "🌟", 40, {dmg: 20, dmg_per_res: 3, el: "Arcane"}, "supernova", "Spend all Mana: deal 20 + 3 per Mana Magic damage and freeze the enemy's items for 2 seconds.", "ใช้ Mana ทั้งหมด: ดาเมจเวท 20 + 3 ต่อ Mana และแช่แข็งไอเทมศัตรู 2 วินาที"],
  ["tempest", "Storm Verdict", "คำพิพากษาพายุ", "⛈️", 44, {dmg: 20, el: "Shock"}, "charge_rune", "Deals 20 Shock damage and every Rune charges fully.", "ดาเมจ Shock 20 และ Rune ทุกชิ้นชาร์จเต็ม"],
  ["dusk", "Blood Moon", "จันทร์เลือด", "🌘", 44, {dmg: 25, el: "Physical", st: {bleed: 15}}, "drain_half", "Deals 25 Physical damage and 15 Bleed; heals you for half the damage.", "ดาเมจกายภาพ 25 และติด Bleed 15 ฮีลครึ่งหนึ่งของดาเมจ"],
  ["templar", "Aegis Smite", "ทุบโล่ศักดิ์สิทธิ์", "🛡️", 44, {shield: 25, el: "Physical"}, "shield_smite", "Gain 25 Shield, then deal damage equal to all your Shield.", "ได้ Shield 25 แล้วฟาดดาเมจเท่ากับ Shield ทั้งหมด"],
  ["apex", "Feeding Frenzy", "คลั่งล่า", "🐺", 60, {heal: 10}, "fire_beast", "Every Beast attacks at once and adds 3 Bleed each; heals you for 10.", "Beast ทุกตัวโจมตีทันที ติด Bleed 3 ต่อตัว และฮีล 10"],
  ["shaman", "Spirit Bloom", "วิญญาณผลิบาน", "🌿", 60, {dmg: 15, el: "Nature"}, "spirit_bloom", "Heals 5 per Beast and Totem and deals 15 Nature damage.", "ฮีล 5 ต่อ Beast และ Totem และดาเมจธรรมชาติ 15"],
  ["packlord", "Alpha Roar", "คำรามจ่าฝูง", "🦁", 60, {heal: 10, haste: [0.6, 4]}, "alpha_roar", "Heal 10, gain 2 Shield per Beast and +60% Haste for 4 seconds.", "ฮีล 10 ได้ Shield 2 ต่อ Beast และ Haste +60% นาน 4 วินาที"],
  ["bloodwater", "Blood Tide", "กระแสเลือด", "🦈", 52, {st: {bleed: 10}}, "charge_sea", "Adds 10 Bleed and every Sea creature charges fully.", "ติด Bleed 10 และสัตว์ทะเลทุกตัวชาร์จเต็ม"],
  ["siren", "Maelstrom Call", "เรียกน้ำวน", "🌀", 52, {dmg: 15, el: "Physical", heal: 12}, "maelstrom", "Deal 15 Physical + 2 Water damage per Tide (counts up to 15 Tide), freeze the enemy's items for 1.5 seconds and heal 12.", "ดาเมจกายภาพ 15 + น้ำ 2 ต่อ Tide (นับสูงสุด 15) แช่แข็งไอเทมศัตรู 1.5 วินาที และฮีล 12"],
  ["cannoneer", "Broadside", "ยิงกราด", "💥", 52, {dmg: 20, el: "Physical"}, "volley5", "Five cannon shots, 20 Physical damage each.", "ยิง 5 นัด นัดละ 20 ดาเมจกายภาพ"],
];
const gp = "data/game_data.json";
let g = fs.readFileSync(gp, "utf8");
const data = JSON.parse(g);
const ps = g.indexOf('\n "paths": {');   // only inside the paths block (a status shares a path's id)
let head = g.slice(0, ps);
g = g.slice(ps);
for (const [p, n, , ic, need, on, sp, d] of U) {
  if (!data.paths[p]) throw new Error("no path " + p);
  const re = new RegExp('^(  "' + p + '":\\s*\\{.*?)(, ?"ult":\\{.*\\})?\\}(,?)$', "m");
  if (!re.test(g)) throw new Error("line not found " + p);
  const ult = JSON.stringify({n, ic, need, on, sp, d});
  g = g.replace(re, (m, a, _u, comma) => a + ',"ult":' + ult + "}" + comma);
}
g = head + g;
JSON.parse(g);
fs.writeFileSync(gp, g);
const ip = "data/i18n.json";
let t = fs.readFileSync(ip, "utf8");
const tj = JSON.parse(t);
const map = tj.th || tj;
let add = "";
for (const [, n, nth, , , , , d, dth] of U) {
  for (const [k, v] of [[n, nth], [d, dth]]) if (!(k in map) && !add.includes(JSON.stringify(k) + ":")) add += "  " + JSON.stringify(k) + ": " + JSON.stringify(v) + ",\n";
}
if (add) t = t.replace('  "Continue": "ไปต่อ",\n', '  "Continue": "ไปต่อ",\n' + add);
JSON.parse(t);
fs.writeFileSync(ip, t);
console.log("ults written", U.length);
