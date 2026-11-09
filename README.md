# PackCraft (Godot 4.4)

Tactical backpack auto-battler for phones (portrait). Design notes: [docs/design_v2.md](docs/design_v2.md).

## Run
Open this folder in Godot 4.4 (Import → `project.godot`) and press F5. On PC the window opens phone-shaped (portrait).

## How it plays
- **4 classes**, each with its own resource, an **Ultimate** that fires when your items have triggered enough, and **two paths** picked on day 4.
- **Evolve:** two copies of the same item that touch become a new item at night (new name, new effect). The level is hidden.
- **Recipes:** two different items that touch fuse at night. **Capstones** need an evolved item + a recipe item + the right path.
- **Touching items buff each other** (`adj`), some items buff the whole pack (`all`).
- Fights are real time: every item charges up and fires. Burn, Poison and Thorns are data-driven statuses.

## Controls
- **Drag** items from the shop, storage or pack onto the backpack grid. Mouse and touch.
- **Tap** an item to inspect it (one popup, bottom of the screen). **Tap a placed item again** to rotate it.
- **Drag to the shop** to sell, **drag to storage** to store. There are no Sell / Store / Rotate buttons.
- While dragging: **second finger**, right-click, `R` / `Q` rotate.
- **Empty pack** moves everything into storage (storage has no limit).
- Tap glowing `+` tiles to unlock bag space.

## Language
English is the base. Thai is in `data/i18n.json` (`"th": {"English text": "คำแปล"}`); anything missing falls back to English. Switch on the title screen. Thai uses the bundled **Noto Sans Thai** (`assets/fonts`, SIL OFL).

## Saving
- Autosaves after every action and when the app is closed or sent to the background. One slot; finishing a run deletes it.
- Files: `user://run_save.json`, `user://settings.cfg` (Windows: `%APPDATA%\Godot\app_userdata\PackCraft\`). v0.1 saves are not loaded.

## Exporting
Presets are in `export_presets.cfg`: **Android** (APK, portrait), **Web** (PWA, portrait) and **Windows Desktop**.
1. Godot → *Editor → Manage Export Templates → Download and Install*.
2. Android only: install **JDK 17** and the **Android SDK**, set both in *Editor Settings → Export → Android*.

```
godot --headless --path . --export-debug "Android"
godot --headless --path . --export-release "Web"
```
The Web build must be served over HTTP (for example `python -m http.server` in `build/web`).

## Layout
| Path | What |
|---|---|
| `data/game_data.json` | All content: statuses, classes, paths, items, recipes, bosses, modifiers, difficulty (`foe_hp_mult`, `foe_atk_mult`). Edit to rebalance. |
| `data/i18n.json` | Translations |
| `scripts/core/game_data.gd` | Loads the JSON, shapes, item descriptions |
| `scripts/core/run_state.gd` | Run rules: day loop, shop, grid buffs, evolutions/recipes, paths, loot, night, save/load |
| `scripts/core/combat_sim.gd` | Real-time 0.1 s combat: statuses, crits, Charge, Haste, resources, Ultimates, item specials (`sp`) |
| `scripts/core/i18n.gd` | Loads translations at runtime |
| `scripts/main.gd` | Portrait screens + drag-and-drop |
| `scripts/ui/*` | Theme, backpack grid, shapes, combat screen |
| `tests/` | Headless tests |

### Adding a status
Add it to `statuses` in `game_data.json`. A status with `tick` deals `stacks × dmg` every `tick` seconds and loses `decay` stacks; a hero status with `reflect` hits back when you are struck. Items apply it with `"on": {"st": {"bleed": 2}}`. Only statuses with a brand-new behaviour need code (in `combat_sim.gd`).

## Tests
```
godot --headless --path . --script res://tests/sim_test.gd -- --runs=10 --quiet   # bot plays full runs per class
godot --headless --path . --script res://tests/sim_test.gd -- --greedy           # bot always takes Elite/Ambush
godot --headless --path . --script res://tests/sim_test.gd -- --losses           # print every lost fight
godot --headless --path . --script res://tests/save_test.gd                       # save/load round-trip
godot --headless --path . --script res://tests/ui_save_test.gd                    # autosave + Continue through the real UI
godot --headless --path . --script res://tests/loot_test.gd                       # loot tier odds by day
```
After adding a new script with `class_name`, run `godot --headless --path . --import` once so the class is registered.

## Screenshots of every screen (dev, never touches your save)
```
godot --path . --resolution 720x1280 -- --autoshot=C:/temp/shots
godot --path . --resolution 720x1280 -- --autoshot=C:/temp/shots_th --lang=th
```
