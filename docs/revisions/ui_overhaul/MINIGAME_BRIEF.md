# Mini-game rebuild: shared brief (UI overhaul, 2026-11-15)

Every engineer rebuilding a repair mini-game reads this first. Owner's brief: `UI_Overhaul_Prompt.txt` in this folder
(lines 100-205 are about the mini-games). The older contract for rules and panels is the "Contracts" section of
`docs/revisions/BROKEN_PARTS_BRIEF.md` and the header of `scripts/tasks/puzzle_registry.gd`; it still holds.

## The goal

Among Us task screens are the benchmark: a child sees a piece of equipment, knows what to do without reading, does it
with one obvious control, and sees the result on the equipment itself. Today's panels ("Medium UI") are a form: a
title, a paragraph of instructions, labelled buttons, a status sentence. Rebuild the PRESENTATION of your mini-game so
that the colony equipment is the interface. Keep the puzzle rule (what counts as solved) unless your task section
says otherwise.

## What already exists (do not rebuild it, do not edit it)

- `scripts/ui/task_panel.gd` (class TaskPanel): the shell. Read its header comment. It gives you
  - a header (title, who-can-do-it chip, "?" help that reveals `instructions`, start again, close),
  - `play_area` (a VBoxContainer that fills the frame): put your equipment here,
  - the cue bar: `set_cue("Turn the pipes [Enter]")` is the ONE standing line (six words or fewer; a key in square
    brackets becomes a key cap); `flash("Nearly! One more turn.", &"warn")` or writing `status_label.text` shows a
    feedback line for a few seconds (eight words or fewer, friendly),
  - the slim progress bar, the shared success mark (a green tick that pops in 0.8 s after the host confirms the
    repair) and closing itself afterwards. Do not draw your own "solved" banner and do not close the panel.
  - `wants_less_motion()`: when true, show end states at once instead of animating.
- `scripts/tasks/puzzles/kit.gd` (preload it as `Kit`): sprites (`Kit.tex("irrigation/pipe_elbow")`,
  `draw_fit`, `draw_fill`, `draw_turned`, `smooth`), plates (`bay`, `housing`, `box`, `hazard_stripes`) and the shared
  marks every mini-game must use so children learn them once: `focus_ring` (selected / keyboard is here),
  `target_ring` (use this next / valid place), `tick` (done), `cross`, `lock`, `turn_arrows`, `arrow`, `key_cap`,
  `shape` (a shape on every colour), `pips`, `text`, `pulse`.
- Your base script (`board_ui.gd`, `electric_ui.gd` or `med_ui.gd`): claims the task, sends moves, redraws from the
  host's state. Read it; do not edit it.
- Sprites: `assets/ui/minigames/<set>/*.png` (see its README; preview: `E:\Prompt\Godot Assets\Sprite Preview.png`;
  assembly notes: `E:\Prompt\Godot Assets\README.md`).

## Design rules

1. One piece of equipment fills the play area: build it as one (or a few) custom-drawn Controls with
   `size_flags_horizontal/vertical = Control.SIZE_EXPAND_FILL` and a `custom_minimum_size` of about 900 x 420, drawn
   relative to its own `size` so it scales. It must fit without scrolling in a 1280 x 720 window (the panel is then
   1100 x 640, the play area about 1050 x 470) and look good at 1920 x 1080 (panel up to 1100 x 820).
2. No words on the equipment (a number on a meter is fine). No rows of text buttons. Words go in `task_title`
   (the action title given in your task), `set_cue`, feedback lines and `instructions` (two or three short
   sentences, only seen behind "?"). Vocabulary for a 9-12 year old. No scary failure, no red "wrong" screens: a
   wrong move gets a gentle shake / amber mark and a short friendly line.
3. Mouse first, directly on the equipment (click, and drag where the concept says so). Keyboard must still play the
   whole game: Tab / arrow keys move between the parts, Enter / Space acts. The usual way: one focusable flat Button
   (drawn by you, `focus_mode = FOCUS_ALL`) per interactive part, laid over the art; draw `Kit.focus_ring` on the
   focused part. Every focusable control needs a `tooltip_text` naming it (that is its accessible name).
4. Show what to do next with `Kit.target_ring` on the part to use and a short cue; show the result on the equipment
   (water runs, a lamp lights, a needle rises) the moment the host confirms the move.
5. Colour is never the only cue: pair every colour with a shape (`Kit.shape`).
6. Animate with `_process` + `queue_redraw()`; skip to the end state when `wants_less_motion()`.
7. The panel never decides anything: it sends moves and draws `puzzle_state` from the host, as today. Keep public
   members that tests, `tools/godot/capture_puzzles.gd` or other scripts read, or update those readers.

## Making a missing sprite (only if your task section says your game has no sprite set)

The owner's Codex CLI can generate images (it is how the existing pack was made). One sprite per call, about 90 s:

```
mkdir -p "$SCRATCH/gen" && cd "$SCRATCH/gen" && timeout 420 codex exec --skip-git-repo-check --sandbox workspace-write -C "$SCRATCH/gen" "Use your built-in image generation tool to create ONE image and save it in the current directory as NAME.png. Subject: <one object, straight-on view>. Style: game UI sprite, muted industrial Mars-colony equipment, gunmetal grey and warm off-white housings with small amber/yellow accents, soft even studio lighting, clean readable silhouette, centered, fully transparent background, no text, no letters, no numbers, no ground shadow. After saving, print the saved file's absolute path and pixel size. Do nothing else." 2>&1 | tail -5
```

Then with Python + Pillow: check it really has transparency, trim the transparent border, resize so the longest
side is at most 512 px, look at it with the Read tool, and save it as
`assets/ui/minigames/<your set>/<name>.png`. Generate at most 8 images. If Codex reports a usage or rate limit,
stop, draw that part with Kit shapes instead and say so in your report (the owner will swap accounts).
New PNGs must be imported before Godot can load them. Take the import lock, import, switch mipmaps on, import again:

```
until mkdir _locks/import 2>/dev/null; do sleep 10; done
"$G" --headless --path . --import >/dev/null 2>&1
sed -i 's/^mipmaps\/generate=false/mipmaps\/generate=true/' assets/ui/minigames/<your set>/*.png.import
"$G" --headless --path . --import >/dev/null 2>&1
rmdir _locks/import
```

(`mkdir -p _locks` first if the folder is missing. Never leave the lock behind.)

## Working rules (about ten engineers are editing this working tree at the same time)

- You own only: `scripts/tasks/puzzles/tNN_panel.gd`, `scripts/tasks/puzzles/tNN_rule.gd` (change it only if your
  task section allows), `tests/test_puzzle_tNN.gd`, your own `_solve_tNN` function in
  `tools/godot/capture_puzzles.gd` (Edit tool only, never rewrite that file), and new sprites in your own
  `assets/ui/minigames/<set>/` folder. Nothing else. If something outside must change (kit, shell, base script,
  another test), do not change it: describe it in your report.
- Never use git stash / checkout / restore / reset / clean / commit / branch / add. No new class_name scripts
  (preload by path).
- Godot (Git Bash): `G="/c/Users/megam/Downloads/Godot Installs/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"`.
  Never open the editor. Import only as described above.
  - Your test suite: `timeout 600 "$G" --headless --path . --script res://tests/test_puzzle_tNN.gd 2>&1 | grep -E "^FAIL|^RESULT|SCRIPT ERROR|Parse Error"`
    (prints `RESULT n/m`). Run only your own suite. It must end green. Update assertions that are about the old
    presentation (strings, node names); never weaken a rule / host / save check. The shell closes itself about 3 s
    after a repair: a test that keeps using the panel long after solving can set `TaskPanel.auto_close_seconds = 0.0`.
  - Screenshots (needs a window, so no --headless): `timeout 300 "$G" --path . --resolution 1280x720 --script res://tools/godot/capture_puzzles.gd -- --out "$SCRATCH/tNN" --only TNN 2>&1 | grep -E "SHOT|ERROR|layout issues|solved="`
    writes `TNN_start.png`, `TNN_solved.png` (right after the last move) and `TNN_stamp.png` (a second later, with
    the shell's success mark). It plays your game through `_solve_tNN` with the keyboard: keep that function
    working. LOOK at the PNGs with the Read tool, compare them with the old panel
    (`$SCRATCH/base/TNN_start.png`, `TNN_solved.png`) and with your references, and iterate until it reads at a
    glance. Do not report that it looks right without having looked. "layout issues: none" must hold.
  - `$SCRATCH` = `C:/Users/megam/AppData/Local/Temp/claude/11cb5dac7f8c6657/7a943902-2697-4360-822b-b18a469253ca/scratchpad`
  - Another engineer's half-edited file can break a Godot run for a moment ("Parse Error" in a file that is not
    yours): wait a minute and run again.
- Stay inside the project folder, `E:\Prompt` and `$SCRATCH`.

## Report (plain text, concise)

Files changed; what the child now sees and does (start, each step, solved) and the cue / feedback lines you wrote;
sprites generated (names) if any; your suite's RESULT line; the screenshot paths you looked at; anything not
verified, left undone, or needed in a file you do not own.
