# UI overhaul: what to do after the tokens reset (written 2026-11-15)

Branch `maanas/ui`, committed locally, **not pushed**. Full record: `UI_OVERHAUL.md` in this folder.

## Done

- Sparkles: bigger, alpha-blended with a dark rim, at chest height (repair burst, tape guide lines, tape twinkle).
- Mini-game shell + all ten repair mini-games rebuilt (T01-T04, T06, T08-T12), every suite green.
- HUD: icons and bars while calm, numbers only when something is low; short messages.
- Menus, pause, settings, goals screen reworked; new action titles everywhere (incl. radio message, Blender data
  generator).

## Next, in priority order

1. **Station panels** (skipped on purpose). The surfaces behind E at a station: `scripts/ui/station_panel.gd` +
   `scripts/ui/stations/*` (bed, cargo, cassette player, colony computer, repair stations...). Same rules as the
   rest: one obvious action, states not numbers, six words or fewer, pictures. Baseline shots of them (before) are in
   the old session's scratchpad `stations/` folder, which may be wiped; re-capture with
   `tools/godot/capture_stations.gd`. Tests: `tests/test_station_panels.gd`.
2. **Other screens not touched**: crew select (C), cargo (I), colony summary, upgrade cards, power & life support
   drawer (P). Upgrade cards had "many hundreds" of words (see `UI_OVERHAUL.md` §1).
3. **Check `test_game_scene` (29/34)**: five suit-rack checks fail (player stuck ~2.3 m up near the rack). Probably
   not UI. Run it on `72070d4` to confirm it was already failing; a suspect is the ~100 uncommitted `.glb.import`
   changes from Godot reimporting (they are left uncommitted on purpose: decide whether to keep or `git restore` them).
4. **Small leftovers**
   - Goals screen (J): the list opens scrolled so the top row is cut in half.
   - T09: owner's idea "open with the tubes already standing" for a shorter first puzzle is not done
     (`t09_rule.gd` still has `FALLEN_TUBES = 3`). The fourth liquid (purple diamond) is drawn in code, no sprite.
   - T02 wrong specialist: the concept wants the electrical badge where the first plug would be; needs a hook in
     `puzzle_registry.gd` / `task_panel.gd` (the shell's generic padlock view is shown now and reads fine).
   - `tools/godot/capture_puzzles.gd` forces 1280x720 (`--resolution` is ignored) and its stamp shot waits frames,
     not seconds (solvers add a short wait as a workaround). Make both proper options.
   - Mission Control card and the bottom dock still use the old `AstraStyle`, which ignores the text-size setting.
   - Mid-game states not yet looked at in screenshots: a held plug (T02/T10), a wrong-socket shake, T04 meter with a
     joined path at the wrong voltage.
5. **Pre-existing failures (not caused by this branch)**: M key / blueprint (ui_framework 2, station_panels 1, off
   since `301d499`), tutorial widget (tutorial 1) and scout goals (scout 1), off since `72070d4`. Update or delete
   those assertions when those features are decided.
6. **Ship it**: push `maanas/ui` and open a PR to `main` when happy (`git push -u origin maanas/ui`).

## How to run things (this machine)

```
G="/c/Users/megam/Downloads/Godot Installs/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
timeout 900 "$G" --headless --path . --script res://tests/<suite>.gd 2>&1 | grep -E "^FAIL|^RESULT|SCRIPT ERROR"
timeout 300 "$G" --path . --script res://tools/godot/capture_game.gd -- --hud --size 1280x720 --out <folder>
```

`tools/run_suites_locked.sh` has a teammate's Godot path hard-coded; copy it and change `GODOT=` to the line above.
