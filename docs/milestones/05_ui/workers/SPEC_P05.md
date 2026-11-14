# Mars Colony (Godot 4.7.2) — Prompt 05 build spec for parallel workers: native game UI, controls and sources

You are one of four workers building separate parts of the game's user interface at the same time. Each worker has
its **own copy** of the project and a **fixed list of files it may create or replace**. The parts are merged
afterwards, so the class names, public methods and data formats below are a contract.

The game: a cooperative Mars colony game for children aged 9 to 12, Godot 4.7.2, typed GDScript. Players walk a
colony base in first or third person, use stations, carry cargo, and keep power, oxygen, water and food going.

## Ground rules

- Typed GDScript 4.7, tabs, one `class_name` per file, `##` doc comments on public members, plain wording.
- Build every screen **in code from Control nodes and containers** (VBoxContainer, HBoxContainer, GridContainer,
  MarginContainer, ScrollContainer, TabContainer, PanelContainer). No hand-written `.tscn`, no fixed pixel positions
  for content, no images or icon files, no third-party art, no image generation. Symbols are Unicode glyphs or shapes
  drawn with `draw_*` in a Control. No web views, no network access, nothing that needs the internet.
- Every panel extends **`UiPanel`** (`scripts/ui/ui_panel.gd`, read it) and uses the shared theme by type variation
  names from **`UiTheme`** (`scripts/ui/ui_theme.gd`). Never set colours or font sizes locally except in `UiTheme`.
- A panel only **reads** state for display and asks for changes with `services.request(action, target, params)`.
  It never edits `ColonyState`, `CharacterState` or the clock. On a networked client that call returns a "pending"
  answer (`result.pending == true`) and the real answer comes later as `services.events.action_resolved`; panels
  just re-read state in `refresh()`.
- Reading age 9 to 12: short sentences, everyday words, the number with its unit, and a "?" button for the longer
  explanation. Colour is never the only cue: pair it with a word or a symbol (✓ ok, ! attention, ✖ urgent).
- Run Godot through the wrapper from your copy: `..\godot.cmd --headless --path . --import` after adding a
  `class_name`; `..\godot.cmd --headless --path . --script res://tests/<your_test>.gd` to run a test.
- Tests: `extends SceneTree`, work in `_initialize()`, print `PASS <name>` / `FAIL <name>: <detail>`, then
  `RESULT <passed>/<total>`, `quit(0)` if all passed else `quit(1)`. Never print PASS for something not measured.
  UI tests run headless; build the panel, add it to `root`, `await process_frame` twice, then check.
- Every test must check its panels with **`UiLayoutCheck`** (`scripts/ui/ui_layout_check.gd`, read it) at three
  sizes — 1280×720, 1920×1080, and 1280×720 with text scale 1.5 — by setting `root.size` (and `UiTheme.apply_text_scale`)
  and laying the panel out full-rect, then requiring `UiLayoutCheck.problems(panel, size).is_empty()` and
  `UiLayoutCheck.focus_problems(panel).is_empty()`. Report the problems found, never hide them.
  (Until worker A's real theme is merged, focus styles come from the default theme; your test may report focus
  problems from the stub theme as a known stub limitation, but layout problems must be zero.)
- Make a test game state with `GameServices.new()`, add it to `root`, `start_new_game(1)`. The saves it writes go
  to `user://`; point them inside your copy first: `services.saves = SaveService.new(ProjectSettings.globalize_path("res://").path_join("_test_saves/<you>"), "colony", 2)`.
- GDScript traps seen in this project: a variable may not share a name with a global `class_name`;
  `var x := <Variant>` fails to infer — write the type; JSON numbers come back as `float`; `Node3D` already has
  `set_identity()`; a node's global transform is valid only inside the tree; `Control.size` set before the node is in
  a sized parent is overwritten by containers.
- Keep running and fixing until your test passes with zero script errors.
- Final message: (1) files created or replaced, (2) the exact test command and its full last output, (3) anything
  unfinished, uncertain or deviating from this spec. Nothing else.

## What already exists (read before you start)

| File | Class | Use |
|---|---|---|
| `scripts/core/game_services.gd` | `GameServices` | `state()`, `clock()`, `config`, `balance`, `events`, `zones`, `local_peer()`, `local_character()`, `is_authority()`, `request(action, target, params) -> ActionResult`, `session` (host side: `session.paused`, `session.peers`, `session.suit_check_progress(id)`), `net` (null when solo) |
| `scripts/core/game_events.gd` | `GameEvents` | signals: `state_changed(reason)`, `zone_power_changed`, `pause_changed`, `sol_settings_changed`, `crew_ownership_changed`, `action_resolved(result)`, `character_recovered`, `suit_check_started/finished`, `game_saved`, `game_loaded` |
| `scripts/core/action_result.gd` | `ActionResult` | `ok`, `reason`, `message` (plain language), `pending` |
| `scripts/state/colony_state.gd` | `ColonyState` | `store(&"battery_kwh" / &"water_l" / &"oxygen_kg" / &"food_meals")`, `capacities`, `parts`, `solar_kw`, `load_kw`, `power_deficit`, `unmet`, `zones[zone] = {powered, condition, tier}`, `stations[id] = {kind, zone, position, specialty}`, `characters`, `items[id] = {kind, position, holder}`, `caches`, `ledger` |
| `scripts/state/character_state.gd` | `CharacterState` | `id`, `specialty` (one of `CharacterState.SPECIALTIES`), `display_name`, `owner_peer` (0 = parked), `position`, `hub_spot`, `health`, `stamina`, `suit_on`, `suit_charge`, `cargo` |
| `scripts/sim/sol_clock.gd` | `SolClock` | `sol_index`, `phase`, `hour_of_sol()`, `sol_minutes` |
| `scripts/core/game_balance.gd` | `GameBalance` | `cargo_slots`, `load_of_zone(zone)`, rates |
| `scripts/player/player_input.gd` | `PlayerInput` | `ACTIONS`, `ACTION_NAMES`, `ensure_actions()`, `rebind(action, event)`, `reset(action)`, `save(path)`, `load(path)`, `describe(action)` |
| `scripts/world/colony_zones.gd` | `ColonyZones` | room rectangles (`rooms`: name, x0, y0, x1, y1 in Blender x,y; Godot x = x, z = −y), `dome`, `zone_at_world(pos)` |
| `scripts/ui/*` stubs | see below | each stub names its owner |
| `scripts/game/game_hud.gd` | `GameHud` | the interim HUD being replaced (read it for what it shows today) |
| `data/colony_manifest.json` | — | rooms, dome, `pads_y_up`, stations (objects with `inter`) |

Actions a panel may request today (host validates): `claim_character` (target = crew id), `release_character`,
`vote_pause` (`paused: bool`), `set_sol_minutes` (`minutes` 5–120, host only), `set_zone_power` (target = power
station id `pw_panel`, `zone`, `on`), `pick_up` / `drop` (target = item id), `collect_cache` (target = cache id),
`begin_suit_check` (target = suit station, `on`). Failure reasons and messages: `ActionResult.MESSAGES`.

Controls (fixed by the brief; remappable): WASD + mouse; Shift sprint; Space jump; **E interact — the one key for
every interaction (use a station, pick up, put down)**; G and left mouse also grab/drop; Tab first/third person;
M blueprint; I cargo; C crew; V push to talk; Esc close the top panel, otherwise pause; Shift+Backspace source
register; F5 unbound.

## Rules that span all parts (UiRoot implements them; your panels must not fight them)

- Tab (view) and M (blueprint) act only when gameplay has focus; never while a panel is open or text is being typed.
- E must not open and close a panel in the same handled event.
- Opening the first panel frees the mouse and stops the player body steering; closing the last restores capture.
- After rapid panel switches, lists keep their scroll position and keyboard focus lands on a sensible control
  (regression lesson from the old browser game: action lists lost scroll and focus).
- Esc closes the top panel first; with nothing open it opens the pause menu.

---

## Part A — UI framework, theme, menus, settings (`worker A`)

Files: `scripts/ui/ui_theme.gd` (replace the stub, keep its constants and functions), `scripts/ui/ui_root.gd`,
`scripts/ui/game_settings.gd`, `scripts/ui/main_menu.gd`, `scripts/ui/pause_menu.gd`, `scripts/ui/settings_panel.gd`,
`scripts/ui/subtitle_line.gd`, `tests/test_ui_framework.gd`.

### `UiTheme` (replace stub)
One `Theme` built in code: dark translucent panels over the 3D view with a warm Mars accent (orange) and a cool
accent (teal) for interactive focus; high contrast text (WCAG AA 4.5:1 for body text against its panel — compute
and assert it in your test for every label variation); a clearly visible focus style on every focusable control type
(Button, CheckBox, CheckButton, OptionButton, LineEdit, Slider, SpinBox, ItemList, TabBar, ScrollBar); hover/pressed/
disabled states; rounded corners kept small. Define all type variations named in the stub. Font: the engine default
font (no files). `apply_text_scale(s)` sets every font size from `BASE_FONT_SIZE * s` (titles larger) on the same
Theme object so open panels update.

### `GameSettings` (Resource)
`ui_scale` 0.75–2.0 (default 1.0), `text_scale` 1.0 / 1.25 / 1.5, `subtitles` (true), `fov_degrees` 60–100 (72),
`mouse_sensitivity` 0.0005–0.006 (0.002), `invert_y` (false), `toggle_sprint` (false: hold Shift), `reduce_motion`
(false), `high_contrast` (false). `static func load_or_default(path := "user://settings.json") -> GameSettings`,
`func save(path := "user://settings.json") -> Error` (JSON), `signal changed`, `func apply(tree: SceneTree) -> void`
(sets `tree.root.content_scale_factor = ui_scale`, calls `UiTheme.apply_text_scale(text_scale)`; high contrast swaps
theme colours). Gameplay code reads FOV, sensitivity, invert and toggle sprint from it (the integrator wires that).

### `UiRoot` (CanvasLayer, layer 20)
```gdscript
signal menu_mode_changed(open: bool)        # first panel opened / last panel closed
signal quit_to_menu_requested
var services: GameServices
var settings: GameSettings
func setup(p_services: GameServices, p_settings: GameSettings) -> void
func open(panel: UiPanel) -> void            # calls panel.setup(services) if not set up, pushes, shows, focuses panel.first_focus()
func close_top() -> void                     # honours panel.can_close()
func close_all() -> void
func is_open() -> bool
func top() -> UiPanel
func gameplay_has_focus() -> bool            # no panel open and no LineEdit/TextEdit/SpinBox has focus
func open_pause_menu() -> void
func show_subtitle(text: String, seconds := 4.0, speaker := "") -> void   # authored messages, via SubtitleLine
```
- Panels are centred in a full-rect container with a margin; a panel with `keeps_world_visible == false` gets a
  dimmed full-screen backdrop. Only the top panel takes input; panels underneath are hidden.
- Connects each panel's `close_requested` and `open_requested(panel)`.
- `_unhandled_input`: `back` → close top, or open the pause menu if nothing is open; `source_register` →
  `open(SourceRegisterPanel.new())` (works from anywhere, also from the pause menu); `map` → toggle
  `BlueprintPanel` only if `gameplay_has_focus()` or the blueprint is the top panel; `inventory` → `InventoryPanel`
  and `crew` → `CrewSelectPanel` under the same rule; `interact` while a panel opened in an earlier frame is on top
  and that panel is a station surface (meta `station_surface`) → close it. Record `Engine.get_process_frames()` at
  open and never close in the same frame it opened.
- Mouse: `Input.mouse_mode` VISIBLE while any panel with `captures_mouse` is open, CAPTURED when the last closes
  (only if the game is running, i.e. `services.has_game()` and the pause menu is closed).
- Refreshes the top panel 4 times a second (`panel.refresh()`).
- Keeps a dictionary of scroll positions per panel class so reopening restores them.

### `MainMenu` (UiPanel, full screen, `keeps_world_visible = false`)
Title "Mars Colony", buttons: **Continue** (enabled only if `services.saves.has_save()`; shows "Sol N, saved <date>"
from the save file's `saved_at_unix` and payload clock), **New colony**, **Host on this network**, **Join a colony**
(address field, port field defaulting to `NetSession.DEFAULT_PORT`, a line explaining "Ask the host for the address
shown on their screen. You must be on the same network."), **Settings**, **Sources and credits**, **Quit**.
Signals: `continue_pressed`, `new_game_pressed`, `host_pressed(port: int, continue_save: bool)`,
`join_pressed(address: String, port: int)`, `quit_pressed`. Host and Join show a plain note that co-op arrives in a
later update when `NetSession.host()` returns `ERR_UNAVAILABLE` (the integrator handles that; the menu shows
`func show_notice(text)`).

### `PauseMenu` (UiPanel)
Shows "Paused" (solo) or the vote state in co-op ("2 of 3 players want to pause"; who has voted is not stored
client-side yet — show the counts the host sends when available, otherwise just "Waiting for everyone to agree").
Buttons: Resume, Colony summary (`ColonySummaryPanel`), Crew (`CrewSelectPanel`), Settings, Sources
(`SourceRegisterPanel`), Credits (`CreditsPanel`), Save now (host only; calls `services.save_now(&"manual")`),
Quit to menu (emits UiRoot's `quit_to_menu_requested`), Quit game (`services.quit_game()`). **Host only**: the sol
length setting — a slider 5–120 minutes with a label "One sol (Mars day) lasts N real minutes" and an explanation
that the time of day stays where it is when changed; it sends `set_sol_minutes` on release. Opening the pause menu
sends `vote_pause {paused: true}`, closing it sends `{paused: false}`.

### `SettingsPanel` (UiPanel)
Tabs: **Display** (UI scale, text size, high contrast, subtitles, reduce motion), **Controls** (mouse sensitivity,
invert Y, FOV, toggle sprint; and the remapping list: every action in `PlayerInput.ACTION_NAMES` order with its
current binding from `PlayerInput.describe` and a "Change" button that waits for the next key or mouse button —
Esc cancels — then `PlayerInput.rebind`; a "Reset" per action; "Reset all"; saves to `user://input.json`).
Changes apply live and save on close. While capturing a key, `can_close()` returns false and the captured key is
consumed so it does not reach gameplay.

### `SubtitleLine` (Control)
Bottom-centre, readable on any background, wraps, queues messages, shows the speaker name if given, respects
`settings.subtitles` (when off, only messages marked essential are shown). `func show_line(text, seconds, speaker := "", essential := false)`.

### `tests/test_ui_framework.gd` must prove
Theme contrast for every label variation; focus style present on every focusable type; MainMenu, PauseMenu,
SettingsPanel pass `UiLayoutCheck` at the three sizes with zero problems; Tab-key focus cycles through every
interactive control of each panel; UiRoot: open/close stack, mouse mode transitions, Esc closes top then opens pause,
`gameplay_has_focus()` false while a LineEdit is focused (simulate typing "tab m" into the join address — the view
and map actions must not fire: assert `map` toggles nothing and no blueprint panel opens), `interact` does not close
a station surface in the frame it opened but does in a later frame, scroll position restored after
open→other→close→reopen; remapping: capture a key, Esc cancels, reset restores defaults, saved file reloads;
GameSettings save/load round trip; sol-length slider sends exactly one `set_sol_minutes` per change on the host and is
absent for a non-host (simulate `services.mode = &"client"`).

---

## Part B — Source register, explanations, credits (`worker B`)

Files: `scripts/ui/explanations.gd`, `scripts/ui/explain_button.gd`, `scripts/ui/source_register_panel.gd`,
`scripts/ui/credits_panel.gd`, `scripts/ui/source_library.gd`, `tools/build_source_data.py`,
`data/sources.json`, `data/claims.json`, `data/explanations.json`, `data/credits.json`, `tests/test_sources.gd`.

### Data (built by `tools/build_source_data.py` from the development register, then hand-edited where needed)
- Input: `docs/source_register.md` (copy in your folder; read it fully — its "How to read it" section defines the
  status and evidence category words). Output `data/sources.json`:
  `{"schema":1, "built_from":"docs/source_register.md", "sources":[{"id":"S01","title":..., "publisher":..., "url":..., "status":"VERIFIED|PARTIAL|SEARCH-ONLY|FAILED", "checked_on":"2026-11-11", "kind":..., "category":"measured|modelled|analog|technology|fiction|tuning|engine", "values_read":..., "supports":..., "mission_site":..., "observation_dates":..., "units":...}]}`.
  Keep every S, T, M and L entry. Do not invent values the register does not contain; leave a field empty if unknown.
  The script is Python 3 standard library only; run it with `py -I tools\build_source_data.py`.
- `data/claims.json`: every factual statement the game shows, each `{"id", "text", "source_ids": [...], "category", "note"}`.
  Category is one of: `archive` (value from a NASA/PDS document), `game_time` (time compression, e.g. the 20-minute
  sol), `fiction` (2080 hardware scaling, the fictional colony), `balance` (game tuning, no source). Required claims
  at least: `gravity` (3.73 m/s², S01), `sol_length` (24 h 39 min 35 s, S02), `sol_compression` (20 real minutes per
  sol, game_time), `oxygen_from_water` (electrolysis on ISS, S08), `oxygen_from_co2` (MOXIE made oxygen from Mars air,
  S09), `water_recycling` (ISS recycles water, S08), `plants_in_space` (S11), `solar_dust` (dust lowers solar output —
  use S18 only if its status allows; otherwise mark the claim as unsourced so it shows "source not yet checked"),
  `crew_rates` (balance), `battery_numbers` (balance), `colony_premise` (fiction). Status SEARCH-ONLY or FAILED must
  be shown as "not yet checked" in the UI, never as a citation.
- `data/explanations.json`: plain-language entries `{"id": {"title", "short" (one sentence), "long" (2–5 short
  sentences), "source_ids": [...], "claim_ids": [...]}}`. Required ids (other workers use them):
  `battery`, `solar_power`, `load`, `power_deficit`, `stamina_vs_electricity` (your body's energy vs the colony's
  electricity), `stock_vs_flow` (an amount in store, kWh/L/kg, vs a rate, kW or per hour), `oxygen`, `water`,
  `food`, `parts`, `suit_tank`, `health`, `stamina`, `sol_clock`, `sol_length`, `cargo`, `pause_vote`,
  `specialists`, `crew_switching`, `upgrades`, `recovery`, `zones_power`, `blueprint`, `sources`.
- `data/credits.json`: Godot Engine 4.7.2 (MIT licence, godotengine.org), Blender 5.3 (GPL, used as a tool),
  Human Base Meshes 1.4.1 (Blender Studio; record both licence statements found, see L01 in the register and
  `docs/milestones/04_player/rig/PROVENANCE.md` if present), the owner's `PlayerCharacter.fbx` low-poly base and
  `Walking.fbx` (Mixamo) as named in `docs/milestones/04_player/HANDOFF.md` "Change after handoff" sections, NASA
  sources (public information; link to the register). Read those docs from `G:\nasa app\mars_colony_godot\docs\`
  (read only). State unknown licences as unknown.

### `SourceLibrary` (RefCounted, static)
`static func sources() -> Array[Dictionary]`, `source(id) -> Dictionary`, `claims() -> Array[Dictionary]`,
`claim(id) -> Dictionary`, `credits() -> Array[Dictionary]`, `is_citable(source) -> bool` (VERIFIED or PARTIAL),
`status_text(source) -> String` (plain: "Checked on 11 Nov 2026", "Partly checked", "Not yet checked", "Could not be opened").
Loads from `res://data/*.json` once; works fully offline.

### `Explanations` (replace stub; keep `get_entry`, `ids`)
Reads `data/explanations.json` through `SourceLibrary`.

### `ExplainButton` (replace stub; keep `explanation_id` and `make`)
A small "?" button (tooltip = the short text). Pressing it opens a small popup (PopupPanel inside the same window)
with title, long text, the category of each linked claim in words ("measured on Mars", "ISS or Earth test",
"game time", "made up for the game", "game balance"), and a "Sources" button that opens the source register at the
right entry: emit a signal `sources_requested(id: String)` and, if the button's owning UiPanel is known
(walk up `get_parent()` to the first UiPanel), call `panel.open_requested.emit(panel_for_sources)` with a
`SourceRegisterPanel` whose `show_entry(id)` was called. Keyboard reachable; Esc closes the popup first.

### `SourceRegisterPanel` (replace stub; keep `show_entry`)
Two panes: a searchable list (filter field + category filter: All, Measured on Mars, Models, ISS and Earth tests,
Technology, Fiction, Game balance, Engine and tools) of claims and sources, and a detail pane: title, publisher,
mission and site, observation dates, units, status in words, what was read, what it supports, which game claims use
it, and the URL as text with an "Open in browser" button that calls `OS.shell_open(url)` **only when pressed** and
only for `https://` URLs; a note "Opens your web browser. The game works without it." No network access otherwise.
Explains at the top in two sentences what the register is. Shift+Backspace opens it (UiRoot does that).

### `CreditsPanel` (replace stub)
Lists `data/credits.json` grouped by kind (engine, tools, assets, science sources) with licence text in words.

### `tests/test_sources.gd` must prove
Every claim's source ids exist; no claim of category `archive` cites only SEARCH-ONLY/FAILED sources (such claims
must be shown as unsourced); every explanation id required above exists with non-empty short and long text and
valid source/claim ids; every `https://` URL is well-formed and every displayed link equals the register's URL for
that id (verify against `docs/source_register.md` by re-parsing); the register opens offline (no HTTPRequest nodes
anywhere in your panels; assert by scanning the tree) and `OS.shell_open` is not called during the test (wrap it
behind a `static var open_url_hook: Callable` that the test replaces); ExplainButton opens its popup and the
sources link opens the register at the right entry; SourceRegisterPanel filter and category work; all panels pass
`UiLayoutCheck` at the three sizes; long entries wrap without clipping.

---

## Part C — HUD, colony summary, cargo, crew selection (`worker C`)

Files: `scripts/game/game_hud.gd` (replace; keep class `GameHud` and the methods listed), `scripts/ui/colony_summary_panel.gd`,
`scripts/ui/inventory_panel.gd`, `scripts/ui/crew_select_panel.gd`, `scripts/ui/crew_portrait.gd`,
`scripts/ui/reading_row.gd`, `tests/test_hud_panels.gd`.

### `GameHud` (CanvasLayer, layer 10) — replace
Public API (the game calls these): `setup(services: GameServices) -> void`, `set_target(target: Dictionary) -> void`
(as returned by `PlayerController.aimed_target()`: `kind` "station"/"item"/"", `id`, `node`), `show_message(text: String, seconds := 3.0) -> void`,
`set_visible_hud(on: bool) -> void`, `set_held(item_id: StringName) -> void` (what is in the hands, or &""),
`set_status(text: String) -> void` (one line for network/session status; empty hides it).
Content — small and readable, corners only, never a dashboard:
- top-left: sol and time ("Sol 3 · 14:20"), with a sun/moon symbol; under it **at most three urgent readings** chosen
  by need — battery %, oxygen, water, food, suit tank — showing only those below a warning level, each with symbol,
  value with unit, and word ("Low"); when nothing is low show one quiet line "Colony OK ✓".
- top-right: your crew member (name, specialty symbol and colour), health and stamina as small bars **labelled with
  words** ("Body energy" for stamina, never "energy" alone), suit on/off and tank %.
- centre: crosshair; interaction cue under it: "[E] Use power panel", "[E] Pick up supply crate", "[E] Put down"
  when holding something and not aiming at a station; key names from `PlayerInput.describe(&"interact")`.
- bottom-centre: message line (queued, wraps), used by `show_message`; suit check progress bar when
  `services.session.suit_check_progress(id) >= 0` (host only; hide on clients).
- small key hint strip that fades after 30 s of play: "M map · I cargo · C crew · Esc pause · Shift+Backspace sources".
- "PAUSED" banner when `services.session.paused` (host) — the pause menu itself is worker A's.
Refreshes 4 times a second, not every frame. Uses `UiTheme` variations.

### `ReadingRow` (HBoxContainer)
`static func make(symbol: String, label: String, explanation_id: String) -> ReadingRow`; `func set_value(text: String, level: StringName)`
where level is `&"ok"`, `&"warn"`, `&"urgent"` (symbol ✓/!/✖ and theme variation), with an `ExplainButton` at the end.
Used by the colony summary and by worker D's station panels.

### `ColonySummaryPanel` (UiPanel)
Explains the colony at a glance and in depth:
- **Stocks** (amounts in store) with units and capacity bars: battery kWh, oxygen kg, water L, food meals, parts.
- **Flows** (rates right now): solar kW, load kW, net kW (charging/draining), and for oxygen, water and food the use
  per sol for the active crew; a one-line cause for each change ("Battery draining: the colony uses 53 kW and the
  sun gives 19 kW").
- **Time left** for each stock at the current flow ("Oxygen lasts about 6 sols at this rate"); "—" when it is not
  going down.
- A short boxed explanation of **stock vs flow** and of **body energy (stamina) vs colony electricity**, with
  ExplainButtons (`stock_vs_flow`, `stamina_vs_electricity`).
- Rooms: which zones are powered (list with ✓/✖ and their kW), read only (switching is at the power panel).
Values computed from `state()` only; flows use `state.solar_kw`, `state.load_kw`, `balance` rates and the number of
active crew. Units always shown. ExplainButton ids from Part B's list.

### `InventoryPanel` (UiPanel) — I key
Your crew member's cargo: slots used / `balance.cargo_slots`, each item with a name made from its `kind`
("Supply crate"), and a "Put down" button that sends `drop`. Shows caches you know of (from `state.caches`) with
their zone and distance from you, and explains in one line what a cache is (ExplainButton `recovery`).

### `CrewSelectPanel` (UiPanel) — C key, also opened by the menus
Four cards, one per character in `state().characters` (sorted by id): `CrewPortrait`, name, specialty in words with a
symbol, status in words — "You", "Free — waiting at the hub", "Played by player 2", plus health and suit tank, and where
they are (zone name). A "Play as …" button sends `claim_character`; it is disabled with the reason in words when the
host would refuse: not at the hub ("Walk to the hub to change crew member"), four players ("With four players
everyone keeps their own crew member"), taken. A line explains the rule (ExplainButton `crew_switching`). After a
request, show its answer (or "Asked the host…" when pending) in the panel.

### `CrewPortrait` (Control)
A portrait of a crew member. Preferred: a small `SubViewport` (160×200) rendering a `PlayerVisual` (head and
shoulders, `use_rig_if_available()`, `set_crew_identity(index)`, `set_first_person(false)`, its own Camera3D and light,
`render_target_update_mode = UPDATE_ONCE`) inside a `SubViewportContainer`. If the rig is not available (your copy has
no character asset) fall back to a drawn badge: a circle in the specialist colour with the specialist symbol
(⚡ electrical and comms, ✚ medical and life support, ❀ biology and food, ⛏ field engineering and geology).
`func setup(character: CharacterState, index: int) -> void`.

### `tests/test_hud_panels.gd` must prove
HUD shows at most three urgent readings and "Colony OK" when none are low (set store values to force each case);
stamina is labelled as body energy and battery as colony electricity; interaction cue text for station, item, holding;
messages queue; ColonySummary computes time-left correctly for a known flow (set stores and rates, compare with a
hand calculation) and shows "—" when not falling; units present on every number; InventoryPanel "Put down" sends exactly
one `drop` for the right item and the list updates after the state changes; CrewSelect disables with the right reason
for each refusal case (far from hub, four peers — set `services.session.peers = [1,2,3,4]`, taken) and sends one
`claim_character` when allowed; all panels and the HUD pass `UiLayoutCheck` at the three sizes.

---

## Part D — Station surfaces, upgrade cards, blueprint map (`worker D`)

Files: `scripts/ui/station_panels.gd` (replace stub; keep `for_station`), `scripts/ui/station_panel.gd`,
`scripts/ui/power_station_panel.gd`, `scripts/ui/upgrade_cards_panel.gd`, `scripts/ui/blueprint_panel.gd`,
`scripts/ui/blueprint_view.gd`, `data/upgrades.json`, `tests/test_station_panels.gd`.

### Station surfaces
`StationPanels.for_station(station_id, services) -> UiPanel` returns the panel for the station's `kind`, with meta
`station_surface = true` and `station_id`. Return null for `suits` (the suit rack is used directly with E: it starts
the suit check).
- `StationPanel` (UiPanel, generic): header with the station name in words ("Life support console"), the zone,
  whether that zone has power (✓/✖ in words), a "What you can do here" list, its readings as `ReadingRow`s with
  ExplainButtons, and a plain line "More controls arrive with the colony systems update" for things not built yet.
  Station kinds and what they show today:
  `computer` (colony computer): buttons to open Colony summary (`ColonySummaryPanel`), Upgrades
  (`UpgradeCardsPanel`), Blueprint (`BlueprintPanel`) via `open_requested`; `comms`: Earth messages placeholder
  list with an explanation that Earth is minutes away by radio (no numbers unless from a source: use the
  explanation id `sources`); `food` (greenhouse console): food stock and use per sol; `lifesupport`: oxygen and water
  stocks, oxygen made and used per sol from `ColonyState.ledger` deltas, whether Life Support has power;
  `heal` (med station): crew health list; `board` (transceiver board), `survivor` (patient): short descriptions.
- `PowerStationPanel` (`power`): every zone with a switch (CheckButton) and its kW from `balance.load_of_zone`; total
  load, solar, net; the battery with time left; a sentence of cause and effect when a switch changes ("Greenhouse off:
  the colony now uses 44 kW"). Each switch sends `set_zone_power` (target = the station id) and reflects the state on
  `refresh()`; a refused switch flips back and shows the reason.

### `UpgradeCardsPanel` and `data/upgrades.json`
Upgrades are built in a later milestone; this milestone shows the cards. `data/upgrades.json`:
`{"schema":1, "note":"PLACEHOLDER CARDS for the UI; the real catalogue comes with the upgrade milestone.", "cards":[...]}`
with 6 to 8 cards across the five sectors (health and life support; food production; resources and manufacturing;
energy; science and research), each `{id, title, sector, zone, tier, cost_parts, prerequisites, specialty, effect, question}`
— all marked placeholder, numbers are game balance. Load into `UpgradeDefinition` resources (read
`scripts/core/upgrade_definition.gd`; you may not edit it — keep extra fields in a side dictionary). Cards show title,
sector symbol, facility, tier, cost in parts vs parts available, installer specialty with symbol, what it changes, and
why it is locked, in words ("Needs 4 parts — the colony has 10", "Upgrades are installed in a later update"). The
install button is present and disabled with that reason. Keyboard: cards in a grid, focus moves between cards.

### `BlueprintPanel` (UiPanel; M key, `keeps_world_visible = true`) and `BlueprintView` (Control)
A top-down plan drawn with `draw_*` from `data/colony_manifest.json` rooms (rectangles, Blender x,y → screen), the
dome outline (superellipse: `rx, ry, n`), the pads, the stations (symbol + short name), and live markers: you, the
other crew (specialist colour and initial), items on the ground, caches (orange with "!"), and unpowered rooms drawn
dim with ✖. A legend explains every symbol in words. Zoom with + / − buttons and the mouse wheel, pan by dragging;
"Centre on me" button. Clicking a room shows its name, power state and load. North arrow. Scales to the panel size.

### `tests/test_station_panels.gd` must prove
`for_station` gives the right panel type for each of the 9 stations of a real new game and null for the suit rack;
power switches send exactly one `set_zone_power` each with the right zone and value, reflect a host refusal (simulate
by requesting from too far: move the local character away so the host answers `too_far`) and update load text after
the state changes; computer buttons emit `open_requested` with the right panel classes; upgrade cards load, show
cost vs available parts and the locked reason, and the install button is disabled; blueprint draws (call
`queue_redraw`, await a frame, no errors), converts coordinates correctly (a room's centre maps to the drawn rect's
centre within 1 px for two rooms), shows unpowered rooms dimmed after `set_zone_power` off, and the legend lists every
symbol used; all panels pass `UiLayoutCheck` at the three sizes.
