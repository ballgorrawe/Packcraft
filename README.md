# PackCraft (Godot 4.4)

Tactical backpack auto-battler, ported from the HTML prototype (v3) and the GDD.

## Run
Open this folder in Godot 4.4 (Import → `project.godot`) and press F5.

## Controls
- **Drag** items from the shop, storage or pack onto the backpack grid. Works with mouse and touch.
- **Rotate while dragging:** `R` / `Q`, right-click, or tap with a second finger.
- **Tap** an item to inspect it; tap a placed item again (or use *Rotate ↻*) to rotate it in place.
- Drop on the **Storage Box** to store, or on the **Merchant’s Stall** to sell. Storage has no limit; **Clear pack** moves everything from the pack into storage at once.
- Tap glowing `+` tiles to unlock bag expansions.

## Saving
- The run autosaves after every action and when the app is closed, minimised or sent to the background.
- The title screen shows **▶ CONTINUE** when a save exists. A run saved mid-fight restarts that fight.
- Finishing a run (win or loss) deletes the save. One save slot.
- Files: `user://run_save.json` and `user://settings.cfg` (Windows: `%APPDATA%\Godot\app_userdata\PackCraft\`).
- **Text size** (S / M / L) is on the title screen; phones default to M.

## Exporting
Presets are in `export_presets.cfg`: **Android** (APK, arm64 + armv7, landscape, immersive), **Web** (PWA, works in phone browsers) and **Windows Desktop**.

One-time setup:
1. Godot → *Editor → Manage Export Templates → Download and Install* (needed for every platform).
2. Android only: install a **JDK 17** and the **Android SDK** (Android Studio is the easiest way), then set both paths in *Editor Settings → Export → Android*. Godot creates a debug keystore for you.

Then *Project → Export…*, pick a preset, and *Export Project*. Builds go to `build/`. From the command line:
```
godot --headless --path . --export-debug "Android"
godot --headless --path . --export-release "Web"
```
The Web build has to be served over HTTP (for example `python -m http.server` in `build/web`), not opened as a file.

## Layout
| Path | What |
|---|---|
| `data/game_data.json` | All content: items, recipes, heroes, companions, bosses, modifiers, sets. Edit to rebalance. |
| `scripts/core/game_data.gd` | Loads the JSON, shape rotation, text helpers |
| `scripts/core/run_state.gd` | Run rules: day loop, shop, grid, stars, sets, Golden Link fusion, nodes, night, save/load |
| `scripts/core/combat_sim.gd` | Real-time 0.1 s tick combat (burn, poison, chill, freeze, haste, fatigue) |
| `scripts/core/save_game.gd` | Save slot + settings file |
| `scripts/main.gd` | Screens + drag-and-drop controller |
| `scripts/ui/*` | Theme, backpack grid, shape drawing, combat arena |
| `tests/` | Headless tests (see below) |

## Tests
```
godot --headless --path . --script res://tests/sim_test.gd      # bot plays 20 full runs
godot --headless --path . --script res://tests/save_test.gd     # save/load round-trip
godot --headless --path . --script res://tests/ui_save_test.gd  # autosave + Continue through the real UI
godot --headless --path . --script res://tests/loot_test.gd     # loot tier odds by day and node
godot --headless --path . --script res://tests/sim_test.gd -- --greedy  # bot always takes Elite/Ambush (snowball check)
```

## Screenshots of every screen (dev, never touches your save)
```
godot --path . -- --autoshot=C:/temp/shots
```
