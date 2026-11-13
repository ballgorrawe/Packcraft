# PackCraft v0.14 — Class Mastery

Why: a finished run gives nothing to keep, so there is no pull to start the next one (play logs:
13 of 25 runs were abandoned, 6 within 3 floors). Mastery gives every run, won or lost, progress on
the class you played, a little say over which path the shop leans toward, and cosmetics to show.

Decisions (user, 2026-11-13):
- Power stays small: the tree only leans the shop toward a path and adds conveniences.
- Free respec, any time.
- Works in every mode; from Ascension 5 the tree's bonuses are off (cosmetics stay).
- 10 levels per class, about 15-20 runs to max.
- Every level gives a cosmetic: hero skins, pack themes, fight effects, titles and portrait frames.

## Mastery XP (per class, settings key `mst_<cls>`)

At the end of a story run (win, loss or Endless death; not quits, trials or puzzles):
- 10 per floor reached (Endless floors count up to 30)
- 25 per boss beaten (mini-bosses 10)
- 50 for a win
A typical loss around floor 10 gives ~130, a win ~300.

Level n costs 150 + 25 n XP (level 1: 175 … level 10: 400; 2875 in all, ~17 runs).

## Skill tree (per class, settings key `mst_tree_<cls>`: node id -> rank)

One skill point per level (10 in all). Three branches, one per path of the class, plus one shared
node. 13 points of nodes for 10 points: you choose.

Each path branch:
- Favoured path (3 ranks): shop rolls lean to this path's items, +8% chance per rank
  (path items = the items the class trial buys to build the path's Masterwork).
- Head start (1 rank): the run starts with one tier-1 item of this path in storage.

Shared:
- Free reroll (1 rank): the first reroll each day is free.

Respec: free, from the Mastery screen, any time outside a run.
Off from Ascension 5 (the run shows "Mastery bonuses off").

## Cosmetics (per class; equipped per class, settings key `cos_<cls>`)

| Level | Reward |
|---|---|
| 1 | Title I |
| 2 | Pack theme I |
| 3 | Hero skin I |
| 4 | Hit sparks (class colour) |
| 5 | Bronze portrait frame |
| 6 | Title II |
| 7 | Pack theme II |
| 8 | Hero skin II |
| 9 | Fusion burst (class colour) |
| 10 | Gold frame + Title III "Master" |

- Hero skin: another emoji for the hero on the HUD and hero select.
- Pack theme: the pack's background, cell and border colours.
- Fight effects: hit sparks / fusion burst in the class colour.
- Title: shown under the hero name (hero select, end screen).
- Frame: ring around the HUD portrait.

## Screens
- Menu: 🏅 Mastery → class list with level bars → one class: XP bar, tree (tap a node to add a
  point, ↺ Reset), cosmetics (tap to equip).
- End screen: "+130 Mastery XP" with the bar filling, and "Level up! New: …" when it levels.
- Hero select: level badge and title under each class.

## Balance
- Bots measure with mastery off (as now) and with a full tree (`--mastery=1`) to see the gap.
