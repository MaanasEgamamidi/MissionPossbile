# UI overhaul: what to do after the tokens reset (written 2026-11-15)

Branch `maanas/ui`, **not pushed**. The first session's work is committed; check `git status` for the second session's. Full record: `UI_OVERHAUL.md` in this folder.

## Done

- Sparkles: bigger, alpha-blended with a dark rim, at chest height (repair burst, tape guide lines, tape twinkle).
- Mini-game shell + all ten repair mini-games rebuilt (T01-T04, T06, T08-T12), every suite green.
- HUD: icons and bars while calm, numbers only when something is low; short messages.
- Menus, pause, settings, goals screen reworked; new action titles everywhere (incl. radio message, Blender data
  generator).

## Done in the second session (2026-11-15, after the reset)

- Station surfaces (shared frame + every station), cassette player, tape briefings.
- Mission Control card, bottom dock, crew (C), cargo (I), Power & life support drawer (P).
- Upgrade cards, colony summary, quiz, journal.
- T09 opens with one fallen tube; `capture_puzzles.gd --size`; leftover developer phrases.
- `test_game_scene` and `test_repair_anchors` checked against `72070d4`: both fail there too (see `UI_OVERHAUL.md`).

## Next, in priority order

1. **Aiming bug (older than this branch)**: aiming at the Command Room tape picks the T02 repair station
   (`tests/test_repair_anchors.gd`, 108/114). The broken rack's whole-model aim target covers the tape.
2. **`test_game_scene` is timing dependent** (passes and fails on the same commit): make its suit-rack approach wait
   until the player is standing still on the floor.
3. **Small leftovers**
   - T02 wrong specialist: the concept wants the electrical badge where the first plug would be; the shell's generic
     padlock view is shown now and reads fine.
   - Lab and weather station panels got the new frame only; their long text is untouched. The Upgrades strip on a
     station still has five sentences per card (pinned by `test_upgrade_ui`).
   - `PowerModel.LABELS` ("Electrolyser", "CO2-oxygen unit") is where the jargon on switches and alerts comes from.
   - Pictogram sizes on the information panels are fixed when a panel opens (text and bars follow the setting live).
   - Not yet looked at in screenshots: a held plug (T02 / T10), a wrong-socket shake, T04's meter with a joined path
     at the wrong voltage, the drawer's Messages list with messages in it, the "B Build here" chip.
   - Nothing was played end to end in the running game with a second player.
4. **Pre-existing failures (not caused by this branch)**: M key / blueprint (ui_framework 2, station_panels 1, off
   since `301d499`), tutorial widget (tutorial 1) and scout goals (scout 1), off since `72070d4`. Update or delete
   those assertions when those features are decided.
5. **Ship it**: push `maanas/ui` and open a PR to `main` when happy (`git push -u origin maanas/ui`).

## How to run things (this machine)

```
G="/c/Users/megam/Downloads/Godot Installs/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
timeout 900 "$G" --headless --path . --script res://tests/<suite>.gd 2>&1 | grep -E "^FAIL|^RESULT|SCRIPT ERROR"
timeout 300 "$G" --path . --script res://tools/godot/capture_game.gd -- --hud --size 1280x720 --out <folder>
```

`tools/run_suites_locked.sh` has a teammate's Godot path hard-coded; copy it and change `GODOT=` to the line above.
