# PackCraft v0.3.0 — QA & Balance Report

รอบนี้ **ไม่ได้แก้โค้ดเกมจริง**: ทุกการแก้เป็น patch แยกอยู่ใน `qa/patches/` และทดสอบบนสำเนา (git worktree) เท่านั้น
ตัวเลขทุกตัวมาจาก simulation จริง (Godot 4.4.1 headless) ด้วยบอทที่กำหนด seed ได้

---

## 1. Executive Summary

ทดสอบรวม **12,000 รัน** (3 บอท × 4 คลาส × 1,000 รัน, Normal) + 8,000 รันเทียบก่อน/หลัง + 5,000 รันทดลองนิสัย Warden + 240 รันตรวจ invariant + edge case 21 ข้อ

**Top 5**
1. **[Critical] Tinker เริ่มเกมด้วยไอเทมซ้อนกัน**: Battery วางทับ Spark Pistol ทุกรัน (invariant แตก 448 ครั้งใน 240 รัน, ทุกครั้งเป็น OVERLAP)
2. **[Critical] Cursed Altar ทำ Max HP ติดลบได้**: จ่าย 10 ครั้ง ได้ Max HP = −25
3. **[Critical] Merchant ปั่นทองได้**: ซื้อของลดราคา 50% แล้วขายคืนเต็มราคา ได้กำไร (50 → 55 ทอง) และ Gold Nugget ขายได้ 24 ทั้งที่เขียนว่า "worth 12"
4. **[Balance] Warden แรงเกิน**: ชนะ 73.6% ขณะที่คลาสอื่นอยู่ราว 42–45% (บอท smart) เสนอปรับแล้วลดเหลือ 63.6% แต่ยังเป็นอันดับ 1
5. **[Balance] บอสวัน 10 (Frost Wraith) เป็นกำแพง**: แพ้ 57.4% ต่อรันที่ไปถึง เพราะต้าน Physical 80% ส่วนบอสวัน 5 แพ้ 24.6%

Patch แก้บัคทั้ง 7 ตัว: edge case จาก FAIL 8/21 → **PASS 21/21**, invariant จาก 448 → **0** violation, error "Lambda capture freed" จาก 11 → **0**

---

## 2. Bug List

Severity: Critical = crash/softlock/เสียความคืบหน้า/exploit ทองหรือไอเทม · High = กลไกหลักผิดสเปก · Medium = ผิดแต่ไม่กระทบเกมเพลย์มาก · Low = เล็กน้อย

| ID | Severity | System | อาการ | Steps / Seed | สาเหตุ (ไฟล์/ฟังก์ชัน) | Fix |
|---|---|---|---|---|---|---|
| B01 | **Critical** | Start / Grid | Tinker เริ่มเกม Battery ทับ Spark Pistol ช่องเดียวกัน: แสดง "3/9 tiles used" แต่เห็นแค่ 2 ช่อง | เลือก Tinker → Start run (ทุก seed; invariant seed 100000+i·17+n ทุกตัวของ Tinker) · `--mode=edge` E16 | `data/game_data.json` classes.tinker.st: spark_pistol กว้าง 2 ช่องที่ (3,3), battery วางที่ (4,3) | ย้าย battery ไป (5,3) · `01_B01.patch` |
| B02 | **Critical** | Event: Cursed Altar | จ่ายด้วย Max HP ได้ไม่จำกัด จน Max HP และ HP ติดลบ (−25 หลังจ่าย 10 ครั้ง) | E9: day ≥ 3 เจอ Altar → กด "-10 Max HP" ซ้ำ (seed 4242) | `run_state.gd` `ev_altar()` ไม่มีพื้น, `event_ok("altar")` ยอมเสมอถ้ายังมีหัวใจ | พื้น Max HP 30 (`altar_hp_ok`), `max_hp()` ไม่ต่ำกว่า 10, ปุ่มถูก disable · `02_B02.patch` |
| B03 | High | Event: Cauldron | ใส่ของระดับ Legendary/Mythical แล้วได้ของ **ต่ำลง** (sunblade + sunforge_crown → war_horn Epic) | E10 (seed 4242) | `ev_brew()` ใช้ `roll_tiered(4, min(3, top+1))` ซึ่งเพดานคือ Epic | ถ้าของเข้า ≥ Epic สุ่มจาก rarity ถัดไปตรงๆ (`_brew_high`) · `03_B03.patch` |
| B04 | **Critical** | Event: Merchant | ซื้อของลด 50% ตอนเช้า แล้วขายให้ Merchant ราคาเต็ม = กำไรวนได้ (50 → 55 ทอง) | E11: ซื้อการ์ดราคาลด → เดินไป Merchant → "Sell at full price" | `ev_sell_full()` จ่าย `def().cost` เสมอ | เก็บราคาที่จ่ายจริง (`PItem.paid`, save/load ด้วย) แล้วจ่ายไม่เกินนั้น · `04_B04_B05.patch` |
| B05 | Medium | Event: Merchant | Gold Nugget เขียนว่า "Worth 12" แต่ Merchant จ่าย 24 (Big Ruby 20 → 40) | E11b | `ev_sell_full()` ไม่แยกของ Treasure | Treasure ขายตาม `sell_price` · patch เดียวกับ B04 |
| B06 | High | Shop / Sell | ลาก Path Relic ไปช่องขายได้ ได้ 0 ทอง และ relic หายถาวร (เสียความสามารถของ path) | E7: เลือก path → ลาก relic ไปช่องขาย | `sell()` และ `_drop()` เช็คแค่ `starter` | กัน relic เหมือน starter · `05_B06.patch` |
| B07 | Medium | UI | Console: "Lambda capture at index 0 was freed" ตอนข้ามหน้า Night/Victory เร็วๆ (ไม่ crash แต่เป็น script error) | `tests/qa_ui_timing.gd` (11 error) และพบใน browser console ตอนเล่นจริงหนึ่งครั้ง · **intermittent** ในการเล่นจริง (ขึ้นกับจังหวะกด) | `main.gd` `_reward_tile`, `_end_screen`, `_run_screen`, `_drop`: `create_tween()` ผูกกับ main แทน node ที่ถูกอ้าง | ผูก tween กับ node นั้น (`nl./pp./cc./g./gref.create_tween()`) · `06_B07.patch` |

### ความไม่ตรงสเปก (Spec mismatch: ไม่นับเป็นบัค เพราะสเปกในโจทย์เก่ากว่าเกม)

| ID | สเปกบอก | เกมจริง | สมมติฐาน/ข้อเสนอ |
|---|---|---|---|
| S01 | การ์ดกระเป๋าหายไปหลังซื้อ | การ์ดยังอยู่ ซื้อซ้ำได้ในราคาเพิ่มขึ้น (E3) | ทำ patch optional ไว้ `07_S01.patch` (ใช้หรือไม่แล้วแต่ดีไซน์) |
| S02 | Poison cap 40 / Burn cap 30 | 50 / 60 (cap ทำงานถูกต้อง, E6) | ถือว่าค่าปัจจุบันคือดีไซน์ใหม่ |
| S03 | 5 คลาส + pet ประจำคลาส, chill/freeze, set synergy, inspector ด้านล่าง | 4 คลาส, pet เลือกเอง 8 ตัว, ไม่มี chill/freeze/set, inspector อยู่ด้านบน | เป็นการ redesign v2/v0.3 ตามที่ผู้ใช้สั่ง |
| S04 | (ไม่ได้ระบุ) ตายพร้อมกัน | ผู้เล่นชนะเมื่อ KO พร้อมกัน (เช็ค ehp ≤ 0 ก่อน, E5) | สมมติว่าตั้งใจ: เข้าข้างผู้เล่น |

ผ่านแล้ว (ไม่ใช่บัค): หมุนทุกรูปทุกตำแหน่ง 20,980 ครั้ง (E1), fusion ล้นไป storage (E2/E2b), แพ้แล้วฟื้น 50% / game over (E4), haste cap 1.5 / shield cap 40+4×วัน (E6b/c), bag piece 2→3 ช่องวัน 8 (E8), save/load กลาง event (E13), bump ใส่กระเป๋าเต็ม (E14), 3 ชิ้นติด = evolve 1 + เหลือ 1 (E15), เล่นผ่าน UI จริง title → day 2 ไม่มี error (qa_ui_flow)

---

## 3. Balance Report (โค้ดเดิม, Normal)

**บอท**: `random` = เลือกมั่ว, `greedy` = ซื้อ DPS สูงสุด + ไป Elite ตอนเลือดเยอะ, `smart` = ประเมินค่าไอเทม + เลือกเส้นทางตาม HP + ใช้ event
ใช้ smart เป็นตัวแทนผู้เล่นปกติ (n=1,000/คลาส, n=500/pet → ความคลาดเคลื่อน ±~4.4 แต้มที่ 95%)

### Win rate ตามคลาส

| คลาส | random | greedy | **smart** | วันเฉลี่ยที่ไปถึง (smart) |
|---|---|---|---|---|
| Ember | 19.5% | 44.0% | **41.7%** | 14.2 |
| Tinker | 6.7% | 22.8% | **43.7%** | 13.3 |
| Venom | 3.4% | 25.8% | **44.8%** | 14.5 |
| Warden | 13.8% | 39.8% | **73.6%** | 14.8 |
| รวม | 10.8% | 33.1% | **51.0%** | |

Path (smart): ember/forgeblade 43.1 · ember/inferno 40.2 · **tinker/arsenal 37.1** · tinker/overclock 49.6 · venom/plague 45.6 · venom/transmuter 44.0 · warden/colossus 73.5 · warden/thorns 73.7

### Win rate ตาม pet (smart) และ class × pet

| | bee | cat | fox | frog | mouse | owl | pup | turtle |
|---|---|---|---|---|---|---|---|---|
| **รวม** | 52.2 | **44.0** | 45.8 | 51.4 | 49.4 | 52.4 | 55.0 | **57.4** |
| ember | 45 | 34 | **27** | 50 | 38 | 38 | 44 | 57 |
| tinker | 46 | 28 | 38 | 48 | 46 | 43 | 50 | 49 |
| venom | 48 | 41 | 45 | 36 | 44 | 51 | 49 | 45 |
| warden | 70 | 73 | 73 | 72 | 69 | 77 | 77 | 79 |

ช่วงห่าง pet: 13.4 แต้ม (cat 44.0 ↔ turtle 57.4) · pet ที่เป็นสายป้องกัน (turtle, pup) ดีกว่าสายดาเมจ/เศรษฐกิจ

### Top 10 ไอเทมที่ "ยกอัตราชนะ" (อยู่ในกระเป๋าตอนจบ, smart, baseline 50.9%)

| ไอเทม | อยู่ในกระเป๋า | win% เมื่อมี | lift |
|---|---|---|---|
| Greater Potion | 10% | 100% | +54.1 ⚠️ |
| Health Potion | 6% | 100% | +52.3 ⚠️ |
| Wraith Lantern | 7% | 97% | +49.6 |
| Living Shield | 16% | 80% | +34.7 |
| Iron Shield | 44% | 70% | +34.1 |
| Soul Gem | 6% | 83% | +33.6 |
| Stone Shield | 14% | 79% | +32.7 |
| Root Ring | 23% | 75% | +32.0 |
| Granite Shield | 8% | 80% | +31.8 |
| Moss Charm | 20% | 76% | +31.0 |

⚠️ Potion 100% เป็น **survivor bias**: ยาถูกใช้แล้วหายไป ยาที่ยังเหลือในกระเป๋าตอนจบจึงพบแต่ในรันที่ชนะ ไม่ได้แปลว่า OP
Wraith Lantern / Soul Gem เป็นของดรอปบอส (ได้หลังชนะบอสเท่านั้น จึงสูงตามธรรมชาติ)
**ที่มีความหมายจริง**: ของสาย Shield ติด 6 จาก 10 อันดับ (ตรงกับที่ Warden แรง)

### Bottom 10

| ไอเทม | อยู่ในกระเป๋า | win% เมื่อมี | lift |
|---|---|---|---|
| Magma Hammer | 11% | 30% | **−24.2** |
| Turret Plans (relic Arsenal) | 12% | 37% | −15.7 |
| Fire Gem | 21% | 41% | −12.8 |
| Cinder Heart | 12% | 40% | −12.2 |
| Plague Censer | 5% | 40% | −11.6 |
| Blaze Gem | 20% | 42% | −10.7 |
| Mortar & Pestle | 14% | 42% | −10.1 |
| Gear Box | 18% | 43% | −9.1 |
| Anvil Sigil | 13% | 43% | −9.0 |
| Overclock Chip | 19% | 44% | −8.6 |

(lift คือ correlation ไม่ใช่ causation) · ข้อสังเกต: Magma Hammer เป็นของ Fire + Physical ที่โดนบอสวัน 10 (ต้าน Physical) และบอสวัน 15 กดอยู่

### Difficulty curve (smart): จำนวนครั้งที่แพ้ / รันที่ยังอยู่ในวันนั้น

| วัน | 1 | 2 | 3 | 4 | **5 บอส** | 6 | 7 | 8 | 9 | **10 บอส** | 11 | 12 | 13 | 14 | **15 บอส** |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| แพ้ | 0.8% | 1.7% | 3.8% | 7.4% | **24.6%** | 9.2% | 7.5% | 6.3% | 7.6% | **57.4%** | 13.0% | 12.8% | 13.9% | 15.4% | **90.2%*** |

\* วัน 15 นับการแพ้ซ้ำ (มีหัวใจฟื้นแล้วสู้ใหม่) จึงสูงได้ · วันที่จบรัน (แพ้): d10 = 200 รัน, d15 = 1,172 รัน ที่เหลือกระจาย d4–d14
**กราฟไม่เรียบ**: วัน 6–9 ง่ายกว่าวัน 4 แล้วกระโดดที่วัน 10 (ความต่าง 7.6% → 57.4%)

### Gold curve (smart: ทองในมือตอนเช้า)

| วัน | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| mean | 0.8 | 1.0 | 1.1 | 1.3 | 1.5 | **8.3** | 4.2 | 3.0 | 2.8 | 3.1 | **6.0** | 4.1 | 3.8 | 4.2 | 4.5 |
| p90 | 2 | 3 | 3 | 3 | 3 | 20 | 13 | 7 | 6 | 7 | 16 | 9 | 9 | 9 | 10 |

บอทใช้ทองหมดทุกวัน จึงเห็นแค่ "เงินเหลือ" ไม่ใช่รายได้: พุ่งหลังบอสวัน 5 และ 10 (ดรอป Treasure) · ไม่พบเงินติดลบ (invariant gold ≥ 0 ผ่านทุกรัน)

อื่นๆ: Elite/Ambush ชนะ 44.7% (7,770 ไฟต์) → บอท greedy ที่ชอบไป Elite ชนะแค่ 33.1% vs smart 51.0% (ความเสี่ยง Elite ไม่คุ้ม) · Campfire ถูกเลือกตอน HP เฉลี่ย 29% · สร้าง Capstone ได้แค่ 10.6% ของรัน smart

---

## 4. Balance Proposals (before → after, smart, seed เดียวกัน)

ทดสอบบน worktree ที่ **แก้บัคแล้ว** (fixes-only) เทียบกับ fixes + ค่าที่เสนอ 4,000 รันต่อฝั่ง

| # | ค่า | เก่า → ใหม่ | เหตุผล | ผลที่คาด | ผลจริง (sim) |
|---|---|---|---|---|---|
| P1 | Warden Guard: ได้ 1 Guard ต่อโล่ | 10 → **20** | Warden 73.6% สูงกว่าค่าเฉลี่ยคลาสอื่น ~30 แต้ม | ลด reflect | เดี่ยว: 72.6 → 66.8% (n=500) |
| P1 | Warden Guard reflect ต่อ Guard | 0.5 → **0.25** | เหมือนกัน | ลด reflect | เดี่ยว: 72.6 → 67.0% (n=500) |
| P1 | Stone Shield (ของเริ่ม Warden) โล่ | 5 → **4** | ของสาย Shield ติด Top 10 หลายชิ้น | ลดโล่ช่วงต้น | เดี่ยว: 72.6 → 67.8% (n=500) |
| | **รวม P1 ทั้ง 3** | | | ~60% | **73.6 → 63.6%** (n=1,000) |
| P2 | Earthshatter (ult Warden) ×โล่ | 2.0 → 1.5 | สมมติว่า ult เป็นตัวแรง | ลด Warden | **ไม่มีผล** (73.6 → 73.6%) → ult ไม่ใช่ต้นเหตุ, **ไม่แนะนำ** ใส่ไว้เพื่อบันทึก |
| P3 | Frost Wraith HP (บอสวัน 10) | 400 → **360** | กำแพงวัน 10 แพ้ 57.9% | ลดการแพ้วัน 10 | 57.9 → **55.9%** (ลดนิดเดียว) |
| P4 | Turret Plans (relic Arsenal) +ดาเมจ/turret | +1 → **+2** | arsenal 36.2% ต่ำสุด | buff arsenal | 36.2 → **40.0%**, Tinker รวม 44.8 → 46.8% |
| P5 | Lucky Cat crit | 8% → 12% | cat ต่ำสุด | +3 แต้ม | 46.2 → 46.0% **ไม่มีผล** → ต้องเปลี่ยนแนว (เช่น +crit damage) |
| P6 | Sly Fox reroll ฟรี/วัน | 1 → **2** | fox ต่ำ (ember/fox 27%) | +2 แต้ม | 46.0 → 46.8% (ในช่วง noise) |
| P7 | Shell Turtle โล่เริ่มไฟต์ | 10 → **8** | turtle สูงสุด | −2 แต้ม | 58.2 → **56.4%** |

**สรุปหลังปรับ** (fixes + P1, P3–P7): Ember 41.9 · Tinker 46.8 · Venom 43.8 · Warden **63.6** · ช่วงห่างคลาสลดจาก 31.9 → 21.7 แต้ม
**ยังไม่จบ**: Warden ยังนำ ~17 แต้ม และวัน 10 ยังเป็นกำแพง ข้อเสนอต่อไป (ยังไม่ได้ sim):
- ปรับระบบโล่ทั้งเกม (shield cap หรือการ decay)
- ลดการต้าน Physical ของ Frost Wraith จาก 80% → 50% แทนการลด HP

หมายเหตุ: Fix B01 (Tinker overlap) ทำให้ Tinker 43.7 → 44.8% เอง

---

## 5. Proposed Patches

ทั้งหมดอยู่ใน `qa/patches/` (apply ด้วย `git apply qa/patches/<file>`):

| ไฟล์ | เนื้อหา |
|---|---|
| `01_B01.patch` | Tinker battery (4,3) → (5,3) |
| `02_B02.patch` | Altar: `MIN_MAX_HP = 30`, `altar_hp_ok()`, `max_hp()` ≥ 10, ปุ่ม disable |
| `03_B03.patch` | Cauldron: `_brew_high()` สำหรับของ ≥ Epic |
| `04_B04_B05.patch` | `PItem.paid` (+ save/load), `merchant_price()`, Treasure = sell_price |
| `05_B06.patch` | ห้ามขาย relic (`sell()`, `_drop()`, ป้าย inspector) |
| `06_B07.patch` | tween ผูกกับ node ที่ถูกอ้าง 5 จุดใน `main.gd` |
| `07_S01.patch` | (optional, สเปก) การ์ดกระเป๋าหายหลังซื้อ |
| `all_fixes.diff` | B01–B07 + S01 รวมไฟล์เดียว |
| `balance_proposals.diff` | P1–P7 (ต่อจาก all_fixes) **รวม P2 ที่ไม่มีผล: ตัดออกได้** |

ข้อควรระวังตอน apply: ข้อความใหม่ใน `game_data.json` (Guard, Cat, Fox, Turtle, Turret Plans) ต้องเพิ่มคำแปลไทยใน `data/i18n.json` ด้วย ไม่งั้นจะแสดงเป็นภาษาอังกฤษ

---

## 6. Test Harness

| ไฟล์ | ใช้ทำอะไร | คำสั่ง |
|---|---|---|
| `tests/qa_harness.gd` | edge case E1–E16 | `godot --headless --path . --script res://tests/qa_harness.gd -- --mode=edge` |
| | invariant (gold ≥ 0, hearts, HP, ไม่ทับ/ไม่หลุดกริด, uid ไม่ซ้ำ, status/shield cap, NaN, stalemate, ของไม่หาย) | `... -- --mode=inv --runs=60` |
| | Monte Carlo (style random/greedy/smart) | `... -- --mode=mc --style=smart --cls=warden --start=0 --count=250 [--diff=hard]` |
| | เล่นซ้ำ seed เดียวแบบละเอียด | `... -- --mode=repro --seed=100169` |
| `tests/qa_analyze.js` | สรุปผล MC เป็นตาราง | `node tests/qa_analyze.js <โฟลเดอร์ .out>` |
| `tests/qa_ui_timing.gd` | จับ error freed lambda (B07) | `godot --headless --path . --script res://tests/qa_ui_timing.gd` |
| `tests/qa_ui_flow.gd` | กดปุ่มจริงจาก title → day 2 | `godot --headless --path . --script res://tests/qa_ui_flow.gd` |

Seed: invariant = `100000 + i·17 + n` · MC = `i·1009 + class_index·7 + style_code·1000003` · edge = 4242 (คงที่)
`godot` = `C:\Users\ChiNoMyA\Downloads\Godot_v4.4.1-stable_win64.exe\Godot_v4.4.1-stable_win64_console.exe`
เทสต์เดิม (save_test, ui_save_test, swap_test, loot_test) ผ่านทั้งหมดบนโค้ดที่ apply patch แล้ว
