// Second wave: 9 more monster families (3 per floor band) with unique Elites and ults.
// Run from the project folder after gen_monsters.js: node gen_monsters2.js
const fs = require("fs");
const C1 = [[0, 0]], V2 = [[0, 0], [0, 1]], V3 = [[0, 0], [0, 1], [0, 2]], H2 = [[0, 0], [1, 0]], SQ = [[0, 0], [1, 0], [0, 1], [1, 1]];
const it = (id, n, th, ic, t, c, cd, on) => ({ id, n, th, ic, t, c, cd, on });
const FAM = [
 ["Cave Spider", "แมงมุมถ้ำ", "🕷️", 1, { ic: "☠️", n: "Webspinner", th: "ชักใย", d: "poison bites and sticky webs", td: "กัดพิษและพ่นใยเหนียว" }, [
  it("m_spider_bite", "Spider Bite", "แมงมุมกัด", "🕷️", 0, C1, 1.4, { dmg: 1.5, st: { poison: 1 } }),
  it("m_web_shot", "Web Shot", "ยิงใย", "🕸️", 0, C1, 2.5, { dmg: 2, haste: [0.15, 2] }),
  it("m_silk_wrap", "Silk Wrap", "ห่อใย", "🧶", 1, H2, 4, { shield: 5 }),
  it("m_venom_sac", "Venom Sac", "ถุงพิษ", "🧪", 1, C1, 3, { st: { poison: 4 } }),
  it("m_spider_fang", "Spider Fang", "เขี้ยวแมงมุม", "🦷", 2, V2, 2, { dmg: 4, st: { poison: 2 } })]],
 ["Kobold", "โคโบลด์", "🦎", 1, { ic: "🔥", n: "Trapper", th: "นักวางกับดัก", d: "fire traps and quick stabs", td: "กับดักไฟและแทงเร็ว" }, [
  it("m_kobold_spear", "Kobold Spear", "หอกโคโบลด์", "🔱", 0, V2, 1.6, { dmg: 3 }),
  it("m_fire_trap", "Fire Trap", "กับดักไฟ", "🧨", 0, C1, 2.8, { dmg: 1, st: { burn: 3 } }),
  it("m_mining_pick", "Mining Pick", "อีเตอร์ขุดแร่", "⛏️", 1, V2, 2.6, { dmg: 6 }),
  it("m_lantern", "Kobold Lantern", "ตะเกียงโคโบลด์", "🏮", 1, C1, 4, { st: { burn: 4 } }),
  it("m_tin_shield", "Tin Shield", "โล่สังกะสี", "🛡️", 2, H2, 4, { shield: 7 })]],
 ["Wild Boar", "หมูป่า", "🐗", 1, { ic: "💥", n: "Charger", th: "พุ่งชน", d: "slow, heavy charges", td: "พุ่งชนช้าแต่หนัก" }, [
  it("m_tusk_gore", "Tusk Gore", "งาแทง", "🦴", 0, V2, 2.8, { dmg: 7 }),
  it("m_trample", "Trample", "เหยียบย่ำ", "🐾", 0, H2, 3.4, { dmg: 8 }),
  it("m_thick_hide", "Thick Hide", "หนังหนา", "🟫", 1, SQ, 4.5, { shield: 6 }),
  it("m_mud_wallow", "Mud Wallow", "แช่โคลน", "🟤", 1, C1, 6, { heal: 6 }),
  it("m_stampede", "Stampede", "วิ่งกระหน่ำ", "🐗", 2, SQ, 5, { dmg: 18 })]],
 ["Harpy", "ฮาร์ปี้", "🦅", 6, { ic: "🩸", n: "Shrieker", th: "กรีดร้อง", d: "swooping talons that make you Bleed", td: "โฉบกรงเล็บทำให้เลือดไหล" }, [
  it("m_talon_swipe", "Talon Swipe", "กรงเล็บโฉบ", "🪶", 0, C1, 1.2, { dmg: 2, st: { bleed: 1 } }),
  it("m_dive", "Dive", "โฉบดิ่ง", "🦅", 0, V2, 2.4, { dmg: 5 }),
  it("m_harpy_song", "Harpy Song", "เพลงฮาร์ปี้", "🎵", 1, C1, 5, { haste: [0.3, 2.5] }),
  it("m_feather_storm", "Feather Storm", "พายุขนนก", "🌪️", 1, H2, 2.2, { dmg: 3, st: { bleed: 2 } }),
  it("m_nest", "Nest", "รัง", "🪺", 2, SQ, 5, { heal: 8 }),
  it("m_razor_wing", "Razor Wing", "ปีกมีดโกน", "🪶", 2, V3, 1.8, { dmg: 6, st: { bleed: 2 } })]],
 ["Orc Raider", "ออร์คนักปล้น", "👹", 6, { ic: "😡", n: "Berserker", th: "คลั่งศึก", d: "heavy axes that hit harder over time", td: "ขวานหนักที่ตีแรงขึ้นเรื่อยๆ" }, [
  it("m_orc_axe", "Orc Axe", "ขวานออร์ค", "🪓", 0, V2, 2.4, { dmg: 7 }),
  it("m_war_cry", "War Cry", "โห่ศึก", "📢", 1, C1, 5, { haste: [0.35, 3] }),
  it("m_hide_shield", "Hide Shield", "โล่หนังสัตว์", "🛡️", 1, H2, 4, { shield: 7 }),
  it("m_spiked_mace", "Spiked Mace", "กระบองหนาม", "🏏", 1, V3, 3, { dmg: 9, st: { bleed: 1 } }),
  it("m_blood_rage", "Blood Rage", "โทสะเลือด", "💢", 2, C1, 6, { heal: 6, haste: [0.3, 2] }),
  it("m_great_cleaver", "Great Cleaver", "มีดพร้าใหญ่", "🔪", 2, SQ, 3.6, { dmg: 14 })]],
 ["Swamp Hag", "แม่มดหนองน้ำ", "🧙", 6, { ic: "☠️", n: "Hexer", th: "นักสาป", d: "curses of poison and Soaked", td: "คำสาปพิษและเปียกน้ำ" }, [
  it("m_hex_bolt", "Hex Bolt", "ลูกสาป", "🔮", 0, C1, 2, { dmg: 2, st: { poison: 2 } }),
  it("m_bog_water", "Bog Water", "น้ำหนอง", "💧", 0, C1, 2.6, { dmg: 1, st: { soaked: 3 } }),
  it("m_toad_brew", "Toad Brew", "ยาคางคก", "🐸", 1, C1, 5, { heal: 7 }),
  it("m_curse_doll", "Curse Doll", "ตุ๊กตาคำสาป", "🪆", 1, V2, 3.4, { dmg: 3, st: { poison: 4 } }),
  it("m_cauldron_bubble", "Cauldron Bubble", "หม้อเดือด", "🫕", 2, SQ, 4.5, { dmg: 5, st: { poison: 5 } }),
  it("m_mire", "Mire", "บึงดูด", "🌫️", 2, H2, 4, { shield: 8, st: { soaked: 2 } })]],
 ["Wyvern", "ไวเวิร์น", "🐉", 11, { ic: "☠️", n: "Venomtail", th: "หางพิษ", d: "bites and a deadly poison sting", td: "กัดและเหล็กในพิษร้ายแรง" }, [
  it("m_wyvern_bite", "Wyvern Bite", "ไวเวิร์นกัด", "🦷", 0, V2, 2, { dmg: 6 }),
  it("m_tail_sting", "Tail Sting", "เหล็กในหาง", "🦂", 1, V2, 3, { dmg: 4, st: { poison: 6 } }),
  it("m_wing_gust", "Wing Gust", "ลมปีก", "💨", 1, H2, 4, { haste: [0.3, 2.5] }),
  it("m_scale_armor", "Wyvern Scales", "เกล็ดไวเวิร์น", "🔰", 2, SQ, 5, { shield: 12 }),
  it("m_acid_breath", "Acid Breath", "ลมหายใจกรด", "🤢", 2, H2, 3.5, { dmg: 7, st: { poison: 5 } }),
  it("m_sky_dive", "Sky Dive", "ดิ่งฟ้า", "🐉", 3, SQ, 5, { dmg: 26 })]],
 ["Necromancer", "เนโครแมนเซอร์", "💀", 11, { ic: "🔥", n: "Death Magic", th: "เวทมรณะ", d: "dark fire and life drain", td: "ไฟมืดและดูดชีวิต" }, [
  it("m_shadow_bolt", "Shadow Bolt", "ลูกศรเงา", "🌑", 0, C1, 1.8, { dmg: 4, st: { burn: 1 } }),
  it("m_life_drain", "Life Drain", "ดูดชีวิต", "🩸", 1, C1, 2.6, { dmg: 4, heal: 3 }),
  it("m_bone_wall", "Bone Wall", "กำแพงกระดูก", "🦴", 1, SQ, 4.5, { shield: 10 }),
  it("m_grave_fire", "Grave Fire", "ไฟหลุมศพ", "🔥", 2, H2, 3, { dmg: 5, st: { burn: 5 } }),
  it("m_raise_dead", "Raise Dead", "ปลุกศพ", "🧟", 2, V2, 6, { heal: 10, haste: [0.25, 2] }),
  it("m_death_coil", "Death Coil", "ขดมรณะ", "🌀", 3, SQ, 4.5, { dmg: 18, st: { burn: 4 } })]],
 ["Werewolf", "มนุษย์หมาป่า", "🐺", 11, { ic: "💚", n: "Feral", th: "ดุร้าย", d: "frenzied claws and fast healing", td: "กรงเล็บคลั่งและฟื้นตัวเร็ว" }, [
  it("m_were_claw", "Were Claw", "กรงเล็บมนุษย์หมาป่า", "🐾", 0, C1, 1.1, { dmg: 3, st: { bleed: 1 } }),
  it("m_savage_bite", "Savage Bite", "กัดดุเดือด", "🦷", 1, V2, 2.2, { dmg: 6, st: { bleed: 2 } }),
  it("m_moon_rage", "Moon Rage", "โทสะจันทร์", "🌕", 1, C1, 5, { haste: [0.4, 3] }),
  it("m_regrowth", "Regrowth", "งอกใหม่", "💚", 2, C1, 4, { heal: 9 }),
  it("m_pounce", "Pounce", "ตะครุบ", "🐺", 2, SQ, 3.4, { dmg: 13 }),
  it("m_blood_howl", "Blood Howl", "หอนโลหิต", "🩸", 3, H2, 5, { dmg: 10, st: { bleed: 5 } })]],
];
const ELITES = [
 ["Cave Spider", "Venom Matron", "แม่แมงมุมพิษ", "🕷️", "regen", "a nest of poison that keeps coming", "รังพิษที่ไม่หมดสิ้น", it("m_sig_venom_matron", "Brood Sac", "ถุงไข่", "🥚", 3, SQ, 4, { st: { poison: 6 }, heal: 6 })],
 ["Kobold", "Kobold Chieftain", "หัวหน้าโคโบลด์", "🦎", "swift", "lights the whole tunnel on fire", "จุดไฟทั้งอุโมงค์", it("m_sig_kobold_chieftain", "Powder Keg", "ถังดินระเบิด", "🛢️", 3, SQ, 4.5, { dmg: 8, st: { burn: 6 } })],
 ["Wild Boar", "Iron Tusk", "งาเหล็ก", "🐗", "armored", "an armored boar with a crushing charge", "หมูป่าเกราะหนาพุ่งชนแรง", it("m_sig_iron_tusk", "Iron Charge", "พุ่งชนเหล็ก", "💥", 3, SQ, 4.5, { dmg: 20 })],
 ["Harpy", "Harpy Queen", "ราชินีฮาร์ปี้", "🦅", "swift", "a song that makes the whole flock faster", "เพลงที่เร่งทั้งฝูง", it("m_sig_harpy_queen", "Siren Song", "เพลงไซเรน", "🎶", 3, H2, 4, { haste: [0.45, 3], st: { bleed: 2 } })],
 ["Orc Raider", "Orc Warchief", "หัวหน้าศึกออร์ค", "👹", "berserk", "gets stronger every second of the fight", "แรงขึ้นทุกวินาทีที่สู้", it("m_sig_orc_warchief", "Skull Splitter", "ขวานผ่ากะโหลก", "🪓", 3, SQ, 3, { dmg: 16 })],
 ["Swamp Hag", "Bog Witch", "แม่มดบึง", "🧙", "warded", "brews a curse that heals her and poisons you", "ปรุงคำสาปที่ฟื้นนางและวางยาคุณ", it("m_sig_bog_witch", "Witch's Brew", "ยาแม่มด", "🫕", 3, SQ, 4, { heal: 10, st: { poison: 6 } })],
 ["Wyvern", "Elder Wyvern", "ไวเวิร์นโบราณ", "🐉", "armored", "a sting that poisons deep", "เหล็กในที่พิษซึมลึก", it("m_sig_elder_wyvern", "Death Sting", "เหล็กในมรณะ", "🦂", 3, V3, 3, { dmg: 8, st: { poison: 10 } })],
 ["Necromancer", "Lich", "ลิช", "💀", "purifier", "dark magic that burns and drains", "เวทมืดที่เผาและดูดชีวิต", it("m_sig_lich", "Phylactery", "ฟิแลคเทอรี", "🏺", 3, SQ, 4, { dmg: 10, heal: 6, st: { burn: 4 } })],
 ["Werewolf", "Blood Moon Beast", "อสูรจันทร์เลือด", "🐺", "regen", "heals as fast as you can hurt it", "ฟื้นเร็วพอๆ กับที่คุณตี", it("m_sig_blood_moon", "Blood Moon", "จันทร์เลือด", "🌕", 3, SQ, 4, { dmg: 12, heal: 5, st: { bleed: 3 } })],
];
const ULTS = {
 "Cave Spider": [{ ic: "🕸️", n: "Web Trap", d: "Poisons you 8 and heals 8% of its Max HP", need: 16, st: { poison: 8 }, heal_pct: 0.08 }, "กับดักใย", "วางยาพิษ 8 และฟื้น 8% ของ Max HP"],
 "Kobold": [{ ic: "🧨", n: "Big Bang", d: "hits for 3× its attack and Burns you 5", need: 16, nuke: 3, st: { burn: 5 } }, "ระเบิดใหญ่", "ตีแรง 3 เท่าและเผาคุณ 5"],
 "Wild Boar": [{ ic: "🐗", n: "Rampage", d: "a crushing blow for 5× its attack", need: 10, nuke: 5 }, "อาละวาด", "ตีหนัก 5 เท่า"],
 "Harpy": [{ ic: "🌪️", n: "Gale", d: "its items charge 60% faster for 4s", need: 20, haste: [0.6, 4] }, "พายุลม", "ไอเทมของมันชาร์จเร็วขึ้น 60% นาน 4 วิ"],
 "Orc Raider": [{ ic: "🪓", n: "Execute", d: "a crushing blow for 5× its attack", need: 10, nuke: 5 }, "ประหาร", "ตีหนัก 5 เท่า"],
 "Swamp Hag": [{ ic: "🫕", n: "Witch Curse", d: "Poisons you 6, Soaks you 4 and heals 8% of its Max HP", need: 16, st: { poison: 6, soaked: 4 }, heal_pct: 0.08 }, "คำสาปแม่มด", "วางยาพิษ 6 ทำให้เปียก 4 และฟื้น 8% ของ Max HP"],
 "Wyvern": [{ ic: "🦂", n: "Venom Strike", d: "hits for 3× its attack and Poisons you 8", need: 16, nuke: 3, st: { poison: 8 } }, "จู่โจมพิษ", "ตีแรง 3 เท่าและวางยาพิษ 8"],
 "Necromancer": [{ ic: "💀", n: "Soul Harvest", d: "hits for 3× its attack and heals 8% of its Max HP", need: 16, nuke: 3, heal_pct: 0.08 }, "เก็บเกี่ยววิญญาณ", "ตีแรง 3 เท่าและฟื้น 8% ของ Max HP"],
 "Werewolf": [{ ic: "🌕", n: "Full Moon", d: "its items charge 60% faster for 4s", need: 20, haste: [0.6, 4] }, "จันทร์เต็มดวง", "ไอเทมของมันชาร์จเร็วขึ้น 60% นาน 4 วิ"],
};

let j = fs.readFileSync("data/game_data.json", "utf8");
const d = JSON.parse(j);
const th = {};
function setKey(key, value) {
  const at = j.indexOf("\n \"" + key + "\":");
  if (at < 0) throw new Error("no key " + key);
  const start = j.indexOf(":", at) + 1;
  let depth = 0, i = start;
  for (; i < j.length; i++) {
    const ch = j[i];
    if (ch === "\"") { i++; while (j[i] !== "\"") { if (j[i] === "\\") i++; i++; } continue; }
    if (ch === "{" || ch === "[") depth++;
    if (ch === "}" || ch === "]") { depth--; if (depth === 0) { i++; break; } }
  }
  j = j.slice(0, start) + " " + value + j.slice(i);
}
const one = (o) => "{\n" + Object.entries(o).map(([k, v]) => "  " + JSON.stringify(k) + ": " + JSON.stringify(v)).join(",\n") + "\n }";
const mi = d.monster_items, fams = d.families, styles = d.foe_styles, icons = d.foe_icons, bands = d.foe_bands, elites = d.elites, ults = d.foe_ults;
const add = (x) => { const { id, n, th: tn, ic, t, c, cd, on } = x; mi[id] = { n, ic, t, c, cd, on }; th[n] = tn; };
for (const [name, tn, ic, band, st, items] of FAM) {
  fams[name] = items.map((x) => x.id);
  items.forEach(add);
  styles[name] = { ic: st.ic, n: st.n, d: st.d };
  th[name] = tn; th[st.n] = st.th; th[st.d] = st.td;
  icons[name] = ic;
  if (!bands[String(band)].includes(name)) bands[String(band)].push(name);
  const [u, un, ud] = ULTS[name];
  ults[name] = u; th[u.n] = un; th[u.d] = ud;
}
for (const [fam, n, tn, ic, tr, desc, tdesc, sig] of ELITES) {
  add(sig);
  elites[fam] = { n, ic, tr, d: desc, item: sig.id };
  icons[n] = ic;
  th[n] = tn; th[desc] = tdesc;
}
setKey("monster_items", one(mi));
setKey("families", one(fams));
setKey("foe_styles", one(styles));
setKey("foe_icons", JSON.stringify(icons));
setKey("foe_bands", JSON.stringify(bands));
setKey("elites", one(elites));
setKey("foe_ults", one(ults));
JSON.parse(j);
fs.writeFileSync("data/game_data.json", j);
let t = fs.readFileSync("data/i18n.json", "utf8");
const have = JSON.parse(t).th;
const lines = Object.entries(th).filter(([k]) => !(k in have)).map(([k, v]) => "  " + JSON.stringify(k) + ": " + JSON.stringify(v) + ",");
const anchor = "  \"Auto-arrange the pack\": \"จัดกระเป๋าอัตโนมัติ\",";
t = t.replace(anchor, anchor + "\n" + lines.join("\n"));
JSON.parse(t);
fs.writeFileSync("data/i18n.json", t);
console.log("families", Object.keys(fams).length, "bands", JSON.stringify(Object.fromEntries(Object.entries(bands).map(([k, v]) => [k, v.length]))), "elites", Object.keys(elites).length, "thai added", lines.length);
