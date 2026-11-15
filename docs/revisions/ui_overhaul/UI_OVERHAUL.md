# UI overhaul (2026-11-15, branch `maanas/ui`)

Source: the owner's "UI Overhaul Prompt" (text in `UI_Overhaul_Prompt.txt`; the PDF, references, concept mock-ups
and sprite pack are in `E:\Prompt`). Goal: **a child can tell what is happening, what they need to do, and which
control to use**, with far less reading during play.

This file is the review the prompt asks for (how the UI is built, what is hardest to understand, the baseline), the
design direction, and the record of what changed. The mini-game rebuild has its own brief: `MINIGAME_BRIEF.md`.

## 1. Baseline: how the UI was built (before this branch)

Screenshots of the baseline: `baseline/01_main_menu.png`, `02_gameplay_hud.png`, `03_goals_panel.png`,
`04_settings.png`, `05_task_panel.png` (the owner's "Current UI" set). The ten repair mini-games before the rebuild
are the owner's "Medium UI" set.

### Layers

| Layer | Script | What it holds |
|---|---|---|
| CanvasLayer 10 | `scripts/game/game_hud.gd` (GameHud) | Corners (clock box, crew box), message line, crosshair, interaction prompt, death notice; `MissionHud`, voice, rover and drone widgets are its children |
| CanvasLayer 20 | `scripts/ui/ui_root.gd` (UiRoot) | A stack of `UiPanel`s (menus, station surfaces, mini-games), the backdrop, subtitles, the critical alert banner |
| CanvasLayer 60 | `scripts/ui/hud/survival_hud.gd` | The fatal-exposure banner and border |

Opening any UiRoot panel hides the whole HUD (`menu_mode_changed` -> `hud.set_visible_hud`).

### Shared building blocks

- **`UiTheme`** (`scripts/ui/ui_theme.gd`): one Theme built in code. Type variations (`PANEL`, `HUD_PANEL`, `CARD`,
  `TITLE`, `HEADING`, `MUTED`, `GOOD`, `WARN`, `URGENT`, `PRIMARY_BUTTON`, `KEYCAP`, `CHIP`, `TOAST`, bars), a
  palette with a high-contrast twin, base font 18 px scaled by the text-size setting, `key_cap()`.
- **`UiPanel`** (`scripts/ui/ui_panel.gd`): base of every panel UiRoot opens (`setup`, `refresh` four times a
  second, `first_focus`, `close_requested`, `max_width` / `max_height`, `interrupt_on_critical`).
- **`UiRoot`**: opens / closes / stacks panels, sizes them (`PANEL_SIZES`, "hug" heights), remembers focus and
  scroll, owns Esc, the backdrop and the mouse mode.
- **`AstraStyle`** (`scripts/ui/hud/astra_style.gd`): a second, separate style used by `MissionHud` and most
  `scripts/ui/hud/*` widgets: its own colours and smaller text (9-24 px against the theme's 18), applied once
  when a widget is built. It sits outside the theme: text-size changes do not reach it until a rebuild, only its
  glass reacts to high contrast, and its flat buttons draw no focus ring.
- **`TaskPanel`** (`scripts/ui/task_panel.gd`): the shared repair frame. The three base scripts
  (`board_ui.gd`, `electric_ui.gd`, `med_ui.gd`) add the host plumbing; `tNN_panel.gd` draws one mini-game and
  `tNN_rule.gd` is its host rule (`scripts/tasks/puzzle_registry.gd`).
- **`StationPanel`** (`scripts/ui/station_panel.gd`) + `scripts/ui/stations/*`: the surface behind E at a station.

### Screens and how much a player had to read

| Screen | Script | Opens with | Words on screen (about) |
|---|---|---|---|
| Main menu | `scripts/ui/main_menu.gd` | start | 45 (90 with Host / Join open) |
| Pause menu | `scripts/ui/pause_menu.gd` | Esc | 30-60 |
| Settings (Display / Controls / Graphics / Audio) | `scripts/ui/settings_panel.gd` | menus | 45 / 150+ / 30 / 35 |
| Crew select | `scripts/ui/crew_select_panel.gd` | C | 100-120 |
| Cargo | `scripts/ui/inventory_panel.gd` | I | 80-110 |
| Colony summary | `scripts/ui/colony_summary_panel.gd` | pause menu, computer | 250+ |
| Upgrade cards | `scripts/ui/upgrade_cards_panel.gd` | colony computer | many hundreds |
| Station surfaces | `scripts/ui/station_panel.gd` + subclasses | E at a station | 60-250+ |
| Big goals screen | `scripts/ui/hud/goals_big_panel.gd` | J | 150-200 |
| Power & life support drawer | `scripts/ui/hud/power_life_panel.gd` | P | 150-250 |
| Repair mini-games (ten) | `scripts/tasks/puzzles/tNN_panel.gd` | E at a broken part | 60-120 each, some taller than the screen |
| HUD in play | `game_hud.gd`, `mission_hud.gd`, `scripts/ui/hud/*` | always | about 150 across 12 boxes |

HUD widgets in the baseline screenshot: clock / storm / "Colony OK" box and a six-line goals list (top left); a
resource strip with units and trends (top centre) and an energy chip under it; a crew box with three labelled
bars and "Hands empty" (top right); up to four message toasts of one to three sentences each (right); a scout
report card with a paragraph and picture (bottom left); a mast camera card (bottom right); a six-button dock
(bottom centre); the interaction prompt under the crosshair.

## 2. What was hardest to understand

1. **The HUD says the same thing in several places and never says what to do next.** Battery state could show in
   six places at once; five separate text channels (message line, toasts, Mission Control card, subtitles, critical
   banner) compete; the goals list showed six goals with equal weight.
2. **The repair mini-games read like forms.** A title, a paragraph of instructions that also listed the keys, a row
   of labelled buttons ("Tube 3: Zentra on top (4/4)"), a status sentence written for developers ("Waiting for host
   validation...", "Progress is confirmed by the host."), a full-width "Cancel / close (Esc)". Three of them (T04,
   T11, T12) were taller than a 1280 x 720 window, so part of the game was below the fold.
3. **The wrong-specialist state.** A grid of scrambled symbols with the explanation in one line under it: a child
   saw noise first and the reason second.
4. **Numbers with units instead of states**: "562/800 kWh", "O2 60.0 kg", "▼ -4.2 kW · 9 h", kPa readings.
5. **The main menu's seven equal buttons**, one of them disabled with an explanation under it.
6. **Settings as sentences**: "High contrast (stronger colours and borders)", a drop-down for text size.
7. **Developer text shown to players**: "More controls arrive with the colony systems update.", "The room puzzles
   are previews until the T section...", "The host did not authorize this player."
8. **Repair names that describe the fault, not the action** ("Fix the wires (only Electrical engineer)") and a
   goals screen that repeats who can do it in a sentence on every row.

Already out of step before this branch (found during the review, not caused by it): the hint-strip assertion in
`tests/test_hud_panels.gd`, the M-key assertion in `tests/test_ui_framework.gd`, the tutorial tracker assertions
in `tests/test_tutorial.gd`, the scout goals assertions in `tests/test_scout.gd`, `tools/godot/capture_game.gd`
calling a method that no longer exists, and one timing check in `tests/test_broken_parts.gd`.

## 3. Direction

Among Us task screens are the benchmark ("Best UI"): brief text, colour and shape to signal what belongs together,
the next action obvious, the result shown directly on the puzzle. The owner's mock-ups add: the colony equipment
itself is the interface, and each apparatus has its own look while focus, prompts and success repeat everywhere.

Rules applied across the interface:

- **One thing to do, shown as a picture.** Each screen has one obvious primary action; secondary ones are smaller.
- **States, not numbers.** A bar and an icon while things are fine; a number only when something needs attention.
- **Words are short and live in one place.** Six words or fewer for a standing cue, with the key drawn as a key cap.
- **Colour always comes with a shape or mark.**
- **Conventions repeated everywhere** (drawn by `scripts/tasks/puzzles/kit.gd`): the focus ring (selected / the
  keyboard is here), the target ring (use this next), the green tick (done), the padlock (locked), turn arrows.
- **Nothing written for developers reaches a player.**
- Accessibility that existed is kept: keyboard for everything, visible focus, text size, UI scale, high contrast,
  reduce motion.

### The mini-game shell (`scripts/ui/task_panel.gd`)

| Before | After |
|---|---|
| Title, "Room | Role: ..." line, instructions paragraph | Action title; a chip with the specialist's symbol only when the repair needs one; the instructions behind a "?" button |
| Play area between text blocks, sometimes scrolling | The equipment fills the frame |
| Status sentence ("Waiting for host validation...", "Validated.", "Move rejected.") | One cue bar: the standing cue with key caps, or a short feedback line for 3.5 s |
| Full-width "Reset puzzle" and "Cancel / close (Esc)" buttons | Small pictogram buttons in the header (start again, close) |
| Progress bar with a percentage, "The colony keeps running while this panel is open." | A slim bar on the bottom edge; the note is gone |
| Solved: a sentence; the panel stays open over the world | The equipment shows its result, the shared green tick pops in, the panel closes itself, and the world's sparkle burst waits until the panel is closed so the player sees it |
| Wrong specialist: a grid of scrambled symbols, then a sentence | A padlock and the specialist's symbol and name, large; the sentence; the scrambled strip is a dim hint below |

### Repair names

| Task | Before | After |
|---|---|---|
| T01 | Fix the radio signal | Lock the Relay |
| T02 | Fix the wires | Patch the Relay |
| T03 | Fix the power dials | Sync the Turbine |
| T04 | Repair the power circuit | Light the Power Bench |
| T06 | Fix the broken pipe | Water the Kale |
| T08 | Repair the broken glass | Glaze the Dome |
| T09 | Fix the test-tube rack | Sort the Lab Samples |
| T10 | Fix the unplugged equipment | Revive the Med Bay |
| T11 | Clean the dusty hangar | Clear the Landing Lines |
| T12 | Repair the air leak | Seal the Airlock |

T05 Elements and T07 Pipes keep the maintenance interface (no broken-part mini-game).

## 4. Particle visibility (the prompt's bug fix)

| Effect | Before | After |
|---|---|---|
| Repair / pickup burst (`scripts/tasks/sparkle_burst.gd`) | 0.09 m stars at the part's bounds centre, 1.0 s | 0.22 m stars with a soft halo, 1.3 s, raised to chest height (1.25 m above the feet of the crew member by the part) when the part is lower than that |
| Gold guide lines to the tapes (`scripts/cassettes/tape_trail_presenter.gd`) | 0.06 m sparkles 6-14 cm above the floor | 0.15 m sparkles 1.05-1.35 m above the floor |
| Idle twinkle on a tape (`scripts/cassettes/cassette_presenter.gd`) | 20 sparkles in a flat cloud 12 cm over the tape | 28 sparkles in a column from the tape up to just over chest height |

## 5. What changed, by area

Commits on `maanas/ui`: `ec27d91` (checkpoint of the first session), `6f5b5c3` (T02, T04, T10), `be2fb6b` (T01, T03,
T06, T08, T09, T11, T12), `180b4fc` (HUD).

### Repair mini-games (all ten rebuilt on the shell)

Every game: action title, one cue line with key caps, the equipment fills the frame, no words on the equipment,
mouse and keyboard, a shape on every colour, the shared focus ring / target ring / tick / padlock, the shared
success mark, and the panel closes itself. All fit a 1280 x 720 window ("layout issues: none").

| Task | The equipment and what the child does | Suite |
|---|---|---|
| T01 Lock the Relay | Scope with a ghost wave and the live wave; turn one big knob (drag, wheel, arrows) or slide the frequency strip; hold pips and a padlock on the scope, data pulses run down a cable to the relay dish | 48/48 |
| T02 Patch the Relay | Four tinted plugs with shapes, a patch bay of shape-keyed sockets, the relay; a seated plug clicks in and its trace lights to the relay | 48/48 |
| T03 Sync the Turbine | One turbine face, three rings; only the active ring moves; press the big button in the green arc; locked rings show a padlock | 40/40 |
| T04 Light the Power Bench | Power jack, a board of cell plates, a real lamp; current lights the path to the first gap; a meter beside the lamp shows volts and a booster / reducer icon | 49/49 |
| T06 Water the Kale | Tank, 4 x 3 pipe board, kale tray; turn pipes, water runs to the first break, the kale perks up | 46/46 |
| T08 Glaze the Dome | Five coloured panes beside the dome frame; an outline previews the drop; sunlight passes through fitted panes, one shimmer at the end | 54/54 |
| T09 Sort the Lab Samples | The rack is the play area; fallen tubes on a mat with ghost slots; a picked tube lifts and leans to a valid tube, the dose pours, full one-kind tubes get a tick | 51/51 |
| T10 Revive the Med Bay | Heal station and CT scanner beside a power unit; shaped plugs; a heartbeat trace and a scanner sweep when powered; a self-test button | 48/48 |
| T11 Clear the Landing Lines | The hangar floor; brush clumps loose, vacuum the dust, the landing stripe shows through | 57/57 |
| T12 Seal the Airlock | The vapor leads to the seam; fit the shaped gasket, press three glowing points in order, the gauge needle rises into the green band. Rule: 3 press points (was 5); an old save past the new count is peeled back to 0 | 79/79 |

### Menus, settings, goals (first session, checked in screenshots)

Main menu: one large Play, Play with friends, small Settings / Credits / Quit chips. Pause: Resume plus a grid of
pictogram tiles. Settings: big "A" tiles for text size, toggles instead of sentences. Goals (J): one row per repair
with its picture, action title and the specialist's badge, a map beside the list.

### Sparkles

See §4. Stars are alpha blended with a darker amber rim (additive light vanished on the white walls); checked in
screenshots on light walls and on dark floor.

### Tests after the work

Green: task panel 29/29, all ten `test_puzzle_tNN`, hud_panels 89/89, upgrade_ui 60/60, survival_hud 65/65,
cassette_ui 76/76, tutorial_start 36/36, voice 84/84, p07_panels 54/54. Still failing, each traced to before this
branch: ui_framework 123/125 (M key / blueprint switched off in 301d499), station_panels 199/200 (same), tutorial
56/57 (tutorial widget off at 72070d4), scout 57/58 (scout goals off at 72070d4). game_scene 29/34 (player stuck
near the suit rack) was not run before the branch, so its cause is unconfirmed (see `AFTER_TOKENS_RESET.md`).

### HUD in play (finished after the checkpoint)

| Before | After |
|---|---|
| Resource strip "630/700 kWh ▲+7.1 kW", "59.9 kg ▼20 h" | A picture and a level bar per supply; a number, unit and mark only on a supply that is low. H still opens the numbers look. The choice is saved as `"numbers"` in `user://mission_hud.json`; the old `"compact"` key (false for everyone) is ignored |
| Battery chip "Battery 90 % · charging 8 kW" | Sun or moon, battery, arrow; words only while it drains ("~9 h"). The share is on the strip, not repeated |
| Low supply shown on the strip, the top-left chips and the battery chip | With the strip there, the top-left chips show only the room air; the suit tank stays a bar in the crew corner |
| Mission Control "…Find out why on the Power & life support drawer (P), then fix it at the station in the base." | "Down to 1.0 kg. Press P to see why." |
| Voice corner: a four-line radio-down paragraph over the mast camera | "✖ Radio down: Lock the Relay", placed above the mast camera card |
| "More controls arrive…", "previews until the T section", "Waiting for host validation...", "The host did not authorize this player." | Gone or replaced with short player words |

Drawing kits (`hud_kit.gd`, `goal_art.gd`, `menu_kit.gd`) fill polygons through a guard that drops doubled points and
shapes with no area (the moon pictogram's tips were doubled: "triangulation failed").
