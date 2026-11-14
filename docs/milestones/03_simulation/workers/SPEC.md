# Mars Colony (Godot 4.7.2) — shared build spec for parallel workers

You are one of several workers building separate parts of the same Godot 4.7.2 game at the same time.
Each worker has its **own copy** of the project and a **fixed list of files it may create**. The parts are merged
afterwards, so the public names and signatures below are a contract: implement them exactly, and do not edit any
file that is not on your list (read anything you like).

## Ground rules

- Language: typed GDScript 4.7 (`var x: int`, `-> void`), tabs for indentation, one `class_name` per file.
  Short `##` doc comments on every public member. Plain, direct wording.
- No new autoloads, no edits to `project.godot`, no plugins, no C#. No baked textures.
- Use the Godot wrapper to run things from your project copy (the folder you start in):
  - `..\godot.cmd --headless --path . --import` — run once after you add or rename a `class_name` script, otherwise
    the new global class is not known to `--script` runs.
  - `..\godot.cmd --headless --path . --script res://tests/<your_test>.gd` — run a test.
- Tests are headless scripts: `extends SceneTree`, do the work in `func _initialize() -> void:` (use `await process_frame`
  / `await physics_frame` when you need frames), print one line per check — `PASS <name>` or `FAIL <name>: <detail>` —
  then `RESULT <passed>/<total>` and call `quit(0)` if all passed else `quit(1)`.
  Never print PASS for something the test did not actually measure.
- Keep running and fixing until your tests pass with **zero** script errors or warnings-as-errors in the output.
  If something cannot be made to work, say so plainly in your final message; do not hide it.
- GDScript traps seen in this project: a `const` or variable may not have the same name as a global `class_name`;
  `var x := <Variant expression>` fails to infer — write the type; JSON numbers always come back as `float`;
  `for item in untyped_array` needs `for item: Type in ...` if you use typed members; a node's `global_transform`
  is only valid once it is inside the tree.
- Final message: (1) files created, (2) the exact test command and its full last output, (3) anything unfinished,
  uncertain or deviating from this spec. Nothing else.

## What already exists (read these first)

| File | Global class | What it is |
|---|---|---|
| `scripts/core/game_config.gd` | `GameConfig` (Resource) | Engineering settings; `SOL_HOURS`, `MARS_GRAVITY` = 3.73 |
| `scripts/core/game_balance.gd` | `GameBalance` (Resource) | Designer tuning: stores, rates, cargo slots, recovery |
| `scripts/core/game_events.gd` | `GameEvents` (Node) | All gameplay signals |
| `scripts/core/action_request.gd` | `ActionRequest` | What a player asks for |
| `scripts/core/action_result.gd` | `ActionResult` | The host's answer; `MESSAGES` has the failure reasons |
| `scripts/core/layers.gd` | `Layers` | Physics and render layer numbers |
| `scripts/state/character_state.gd` | `CharacterState` | One crew member |
| `scripts/state/colony_state.gd` | `ColonyState` | All authoritative state, `to_dict()` / `from_dict()` |
| `scripts/sim/sol_clock.gd` | `SolClock` | Game time; `advance(real_dt) -> game hours` |
| `scripts/sim/colony_sim.gd` | `ColonySim` | `step(state, balance, phase, dt_hours) -> Array[StringName]` (crew at zero health) |
| `scripts/world/colony_zones.gd` | `ColonyZones` | Zone names and lookups from `data/colony_manifest.json` |
| `data/colony_manifest.json` | — | Every map object: `name`, `gc_asset`, `area`, `cls`, `matrix_world` (Blender, 4 rows), optional `door_id`, `door_slide`, `inter` |
| `data/colliders.json` | — | Per-asset collision boxes, already Y-up: `assets[gc_asset].cols[] = {c: centre, h: half extents, q: quaternion xyzw}` |

Coordinates: Blender is Z-up; Godot position = `(x, z, -y)` of the Blender position. A Blender world matrix `M`
(rows as in the manifest) becomes the Godot transform `C * M * C^-1` with `C` mapping `(x, y, z) -> (x, z, -y)`.

Game rules that matter to every part:

- The host owns the truth. A player never changes state directly; they send an `ActionRequest` and get an `ActionResult`.
- Four crew characters always exist. A player controls one; a character nobody controls is parked at the hub,
  uses no supplies, and its condition is frozen. Equipment, cargo, health, stamina and suit charge stay with the character.
- One sol = `GameConfig.SOL_HOURS` game hours, played in `sol_minutes` real minutes (default 20, host may set 5–120).
  Changing it keeps the time of day. Input, movement, animation and the one-second suit check run in **real** seconds.
- Mars gravity 3.73 m/s² everywhere.

---

## Part A — actions and session (`worker A`)

Files: `scripts/session/action_service.gd`, `scripts/session/builtin_actions.gd`, `scripts/session/session_service.gd`,
`scripts/session/legacy_stations.gd`, `scripts/world/station_catalog.gd`, `tests/test_session.gd`.

### `StationCatalog` (RefCounted)
`static func from_manifest(manifest_path: String, zones: ColonyZones) -> Dictionary`
Returns `station id -> {"kind": String, "zone": String, "position": [x, y, z], "specialty": ""}` for every manifest
object that has `inter`. Station id = the object's `name` (stable). `kind` = its `inter` value
(`suits, computer, comms, food, board, lifesupport, heal, survivor, power`). Position in Godot coordinates.
`zone` = `zones.zone_of(area, position)`. `specialty` stays `""` (no specialist gating has been decided yet).

### `ActionService` (RefCounted)
Holds the action definitions and the per-peer request log.

```gdscript
class Definition extends RefCounted:
	var id: StringName
	var needs_actor := true            # request.actor must be a character owned by request.peer_id
	var host_only := false             # only SessionService.HOST_PEER may ask
	var allowed_while_paused := false
	var target_kind: StringName = &""  # "", &"station", &"item", &"cache", &"character"
	var station_kinds := PackedStringArray()   # if target is a station: allowed kinds (empty = any)
	var specialty: StringName = &""    # required CharacterState.specialty ("" = anyone)
	var check_distance := true         # actor must be within config.interact_distance_m of a positioned target
	var params := {}                   # name -> {"type": TYPE_BOOL/TYPE_INT/TYPE_FLOAT/TYPE_STRING, "min": x, "max": y, "optional": bool}
	var important := false             # the game saves right after it succeeds
	var check := Callable()            # func(ctx: Context) -> ActionResult (a failure) or null
	var apply := Callable()            # func(ctx: Context) -> Dictionary (ActionResult.changes)

class Context extends RefCounted:
	var session: SessionService
	var state: ColonyState
	var clock: SolClock
	var config: GameConfig
	var balance: GameBalance
	var request: ActionRequest
	var definition: Definition
	var actor: CharacterState          # null if the action needs no actor
	var target := {}                   # station / item / cache record, else {}
	var target_character: CharacterState
	var target_position := Vector3.ZERO
	var has_target_position := false

func register(definition: Definition) -> void
func definition(id: StringName) -> Definition          # null if unknown
func resolve(session: SessionService, request: ActionRequest) -> ActionResult
func forget_peer(peer_id: int) -> void                 # drop that peer's request log
```

`resolve` checks, in this order, and returns the first failure (reason names are keys of `ActionResult.MESSAGES`):
1. `request.shape_problem()` not empty → `bad_request`.
2. Same `(peer_id, request_id)` seen before → return the stored result `.as_duplicate()`; **change nothing**.
3. Unknown action → `unknown_action`.
4. Parameters: unknown name, missing non-optional name, wrong type, or number outside `min..max` → `bad_request`.
   (`TYPE_FLOAT` accepts an int. Strings are at most 64 characters.)
5. `host_only` and peer is not the host → `host_only`.
6. Session paused and not `allowed_while_paused` → `paused`.
7. `needs_actor`: `actor` empty → `no_actor`; unknown character or not owned by this peer → `not_owner`.
8. Target: missing or of the wrong kind → `unknown_target`; station of a kind not in `station_kinds` → `wrong_target`.
9. Distance (if `check_distance`, there is an actor and the target has a position): farther than
   `config.interact_distance_m` → `too_far`. An item carried by someone has no position.
10. Specialty: `definition.specialty` or the station's `specialty`, if set and different from the actor's → `wrong_specialty`.
11. `check` callable (prerequisites, quantities) → whatever failure it returns.
12. `apply` → `ActionResult.success(request_id, changes)`.

Every result from step 3 onwards (success or failure) is stored in the request log for that peer; the log keeps the
last `config.remembered_requests` ids per peer. After resolving, emit `events.action_resolved(result)` and, on
success, `events.state_changed(action id)`.

### `SessionService` (RefCounted)

```gdscript
const HOST_PEER := 1
var config: GameConfig
var balance: GameBalance
var events: GameEvents
var state: ColonyState            # null until begin()
var clock: SolClock
var sim: ColonySim
var actions: ActionService        # created in _init with BuiltinActions.register(actions)
var rng: RandomNumberGenerator
var peers: Array[int]             # connected peers, host first
var paused := false               # true only while every connected peer has voted to pause

func _init(p_config: GameConfig, p_balance: GameBalance, p_events: GameEvents) -> void
func begin(p_state: ColonyState, p_clock: SolClock) -> void   # attach a new or loaded game; peers = [HOST_PEER]; rng from state.rng_seed / rng_state; clears votes, accumulator and pending suit checks
func advance(real_delta: float) -> int                        # returns simulation ticks run
func submit(request: ActionRequest) -> ActionResult           # = actions.resolve(self, request)
func request(action: StringName, target: StringName = &"", params := {}, peer := HOST_PEER) -> ActionResult
func peer_joined(peer: int) -> void
func peer_left(peer: int) -> void
func set_pause_vote(peer: int, wants_pause: bool) -> void
func report_position(peer: int, character_id: StringName, position: Vector3, yaw: float) -> bool
func recover_character(id: StringName) -> Dictionary
func is_at_hub(position: Vector3) -> bool
func sync_rng_to_state() -> void                              # state.rng_state = rng.state (call before saving)
func suit_check_progress(character_id: StringName) -> float   # 0..1, or -1.0 if none is running
```

- `request(...)` builds an `ActionRequest` with a fresh id `"p<peer>-<counter>"`, `actor` = the id of the character
  that peer controls (or `&""`), then calls `submit`.
- `advance(real_delta)`: does nothing and returns 0 if `state == null`. Otherwise:
  1. Suit checks (below) advance by `real_delta` — real seconds, unaffected by sol length; they do not advance while paused.
  2. If not paused: add `real_delta` to an accumulator; `tick = 1.0 / config.sim_tick_hz`; while the accumulator is
     at least `tick - 1e-9` and fewer than `config.max_ticks_per_frame` ticks ran this call: subtract `tick`,
     `phase_before = clock.phase`, `dt_hours = clock.advance(tick)`, `down = sim.step(state, balance, phase_before, dt_hours)`,
     call `recover_character` for each id in `down`, emit `events.sol_started(clock.sol_index)` once per `clock.rolled_over`.
     Left-over time stays in the accumulator (never dropped). If any tick ran, emit `events.state_changed(&"tick")`.
- Pause: `set_pause_vote` records the vote; `paused` = every peer in `peers` has voted true (so a solo player pauses
  at once, co-op needs everyone). Emit `events.pause_changed` when it flips. A peer that leaves loses its vote.
- `report_position`: only if `character_id` is controlled by `peer` — store position and yaw, return true; else false.
- `peer_joined`: add to `peers` (max 4; ignore duplicates). `peer_left`: the peer's character keeps everything it
  carries, is moved to its `hub_spot`, `owner_peer = 0` (emit `events.crew_ownership_changed(id, 0)`); cancel its suit
  check; remove the peer, its vote and its request log; recompute pause. No penalty of any kind.
- `is_at_hub(p)`: `p.distance_to(config.hub_position) <= config.hub_radius_m`.
- `recover_character(id)` (a character reached zero condition):
  - If it carries cargo: create one cache `{"id": "cache_<n>", "position": [x, y, z], "items": [ids]}` at the
    character's current position (`n` from `state.counters["cache"]`, then increment); each of those items gets
    `holder = "cache:<cache id>"` and the cache position; the character's cargo is emptied. No cargo → no cache.
  - Charge the colony `config.recovery_cost_sols` of one astronaut's daily food and water:
    meals = `recovery_cost_sols * balance.meals_per_sol`, water = `recovery_cost_sols * balance.water_l_per_hour * GameConfig.SOL_HOURS`,
    taken with `state.add_to_store` (so it can never go negative and never blocks the recovery); add what was actually
    taken to `state.ledger["recovery_meals"]` / `["recovery_water_l"]`.
  - `position = hub_spot`, `health = balance.recovery_health`. **Do not touch** `suit_on`, `suit_charge`, `equipment`, `owner_peer`.
  - Returns and emits via `events.character_recovered(id, info)`:
    `info = {"meals": float, "water_l": float, "cache_id": String ("" if none), "cache_position": [x, y, z] or []}`.
- Suit check: takes `config.suit_check_seconds` real seconds. Started by the `begin_suit_check` action. While it runs,
  every `advance` verifies the condition still holds: the character is still controlled by the same peer and still within
  `config.interact_distance_m` of the suit station it started at. If not → cancel: emit
  `events.suit_check_finished(id, suit_on_unchanged, false)`, nothing changes. When the time is up: set
  `suit_on` to the requested value and emit `events.suit_check_finished(id, suit_on, true)`.
  A suit check **never** changes `suit_charge` (no refilling by taking the suit off and on).

### `BuiltinActions` (RefCounted) — `static func register(service: ActionService) -> void`

| id | actor | target | params | rules beyond the standard checks | effect |
|---|---|---|---|---|---|
| `claim_character` | no (`needs_actor = false`) | character | — | `already_yours` if the peer already controls it; `character_taken` if another peer does. If the peer already controls a different character (a switch): `switch_disabled` when `session.peers.size() >= 4`, `not_at_hub` unless the current character `is_at_hub`. | The old character (if any) gets `owner_peer = 0`; the target gets `owner_peer = peer`. Emit `crew_ownership_changed` for each. `important`. |
| `release_character` | yes | — | — | — | Actor: `owner_peer = 0`, `position = hub_spot`; cancel its suit check. `important`. |
| `vote_pause` | no | — | `paused: bool` | `allowed_while_paused` | `session.set_pause_vote(peer, paused)` |
| `set_sol_minutes` | no, `host_only` | — | `minutes: float` 5..120 | `allowed_while_paused` | `clock.set_sol_minutes`; emit `events.sol_settings_changed`. `important`. |
| `set_zone_power` | yes | station of kind `power` | `zone: String`, `on: bool` | `unknown_target` if the zone is not in `state.zones` | `state.zones[zone]["powered"] = on`; emit `events.zone_power_changed(zone, on)` only if it changed |
| `pick_up` | yes | item | — | `already_held` if `holder != ""`; `cargo_full` if the actor already carries `balance.cargo_slots` items | item `holder` = actor id; append to actor cargo |
| `drop` | yes | item | — | `not_held` unless the actor carries it; no distance check | remove from cargo; item `holder = ""`, `position` = actor position |
| `collect_cache` | yes | cache | — | `cargo_full` if no free slot | move items into the actor's cargo while slots are free (`holder` = actor id); delete the cache when it is empty. `important`. |
| `begin_suit_check` | yes | station of kind `suits` | `on: bool` | `missing_prerequisite` if `suit_on` already equals `on` or a check is already running for this actor | start the timed check; emit `events.suit_check_started(id, seconds)` |

Items live in `state.items[id] = {"kind": String, "position": [x, y, z], "holder": String}`; caches in `state.caches`.
The distance target of an item is its position (only while `holder == ""`), of a cache its position, of a station its position.

### `LegacyStations` (RefCounted)
Compatibility layer for the old browser game, where a player simply "used" a station.
`const KIND_ACTION := {"power": &"set_zone_power", "suits": &"begin_suit_check"}`
`static func interact(session: SessionService, peer: int, station_id: StringName, params := {}) -> ActionResult` —
unknown station → `unknown_target`; a kind with no entry in `KIND_ACTION` → `not_available_yet`; otherwise
`session.request(action, station_id, params, peer)`.
`static func stations_of_kind(state: ColonyState, kind: String) -> Array[StringName]`.

### `tests/test_session.gd` must prove (with real assertions on state)
- Station catalog from the real manifest: 9 stations, kinds as listed, the power panel is in zone `Power Room`.
- Every failure reason in the table and in steps 1–10 is produced by a request built to trigger exactly it.
  Register one extra test-only definition to prove `wrong_specialty`, `missing_prerequisite` and `insufficient`.
- A duplicate request id returns the first result with `duplicate == true` and changes nothing (e.g. `pick_up` twice
  does not add the item twice; a failed request repeated after the cause is fixed still returns the stored failure).
- Carrying: pick up, drop, cargo limit, an item can never be held by two characters; `state.invariants_ok()` is empty
  after every step.
- Claiming and switching: first claim; switch at hub with 1–3 peers; `not_at_hub`; `switch_disabled` with 4 peers;
  everything the old character carried and its health/suit charge are unchanged after a switch; parked characters do
  not lose health and are not counted as consumers over a simulated sol.
- Pause: solo vote pauses at once and `advance` runs 0 ticks while paused; with 2 peers one vote does not pause, two do;
  a peer leaving while it was the only one not voting pauses the rest; un-voting resumes. The suit check does not
  progress while paused.
- Suit check: completes after 1.0 real second (at 20-minute and at 5-minute sols alike), is cancelled by walking away,
  `suit_charge` is identical before and after ten on/off cycles.
- Recovery: with cargo → one cache at the incident position holding exactly those items, cost charged once, health =
  `recovery_health`, suit and equipment untouched; with empty food/water stores recovery still succeeds and stores stay
  at 0; `collect_cache` returns the items; nothing is duplicated or lost.
- Peer loss: character parked at hub with its cargo, no stores charged.
- Sol length: after `set_sol_minutes`, `clock.phase` and `clock.sol_index` are exactly unchanged and
  `battery_kwh` is exactly unchanged at that instant; the ledger identity
  `battery_now == battery_start + solar_used_kwh - load_served_kwh` holds (within 1e-6) after a run that changes sol
  length several times; a full sol at 5, 20 and 120 minutes ends with the same stores within 1.0 %.
- Frame-rate independence: the same scripted run (60 real seconds, actions at fixed real times) driven at 30, 60, 144
  frames per second and with irregular frame times ends with the same tick count ±1 and the same stores within one
  tick's worth of flow. Report the measured differences in the output.
- Only the host may `set_sol_minutes`.

---

## Part B — saving (`worker B`)

Files: `scripts/save/save_service.gd`, `scripts/save/save_migrations.gd`, `scripts/save/save_load_result.gd`, `tests/test_saves.gd`.

### `SaveLoadResult` (RefCounted)
`status: StringName` — one of `&"ok"`, `&"recovered_from_backup"`, `&"no_save"`, `&"unsupported_schema"`, `&"corrupt"`;
`payload: Dictionary` (empty unless ok / recovered); `source_path: String`; `schema: int` (schema found in the file used or
rejected); `migrated_from: int` (−1 if no migration ran); `problems: PackedStringArray` (one line per file that was
tried and rejected, and why); `func is_usable() -> bool` (ok or recovered).

### `SaveMigrations` (RefCounted)
`var current_version := 1`; `var steps := {}` (`from_version: int -> Callable(payload: Dictionary) -> Dictionary`, each
step lifts a payload exactly one version); `func register(from_version: int, step: Callable) -> void`;
`func can_migrate(from_version: int) -> bool` (true if every step from there to current exists; a version above current is never
migratable); `func migrate(payload: Dictionary, from_version: int) -> Dictionary` (works on a deep copy).
Policy: a save from a **newer** game is refused and left untouched; an older save is migrated in memory and only
rewritten at the next normal save, so the original file stays as a backup.

### `SaveService` (RefCounted)

```gdscript
const FORMAT := "mars_colony_save"
var directory := "user://saves"
var save_name := "colony"
var backup_count := 2
var migrations: SaveMigrations
var game_version := "0.3.0"
var fail_after_bytes := -1     # TEST HOOK: if >= 0, write() stops after writing this many bytes to the temp file and returns ERR_FILE_CANT_WRITE, as if the game had been killed mid-write

func _init(p_directory := "user://saves", p_save_name := "colony", p_backup_count := 2, p_migrations: SaveMigrations = null) -> void
func main_path() -> String        # <directory>/<save_name>.json
func temp_path() -> String        # <directory>/<save_name>.json.tmp
func backup_path(index: int) -> String   # <directory>/<save_name>.bak<index>.json, index from 1 (1 = newest backup)
func write(payload: Dictionary, reason: StringName = &"manual") -> Error
func read() -> SaveLoadResult
func has_save() -> bool
func delete_all() -> void
static func canonical_text(payload: Dictionary) -> String
static func checksum(payload: Dictionary) -> String
func validate_text(text: String) -> SaveLoadResult     # parse + checks on one file's text, no fallback
```

File contents (JSON, UTF-8, tab-indented):
`{"format": "mars_colony_save", "schema": <int>, "game_version": "...", "saved_at_unix": <int>, "reason": "...", "checksum": "<sha256 hex>", "payload": {...}}`

- `canonical_text(payload)` = `JSON.stringify(JSON.parse_string(JSON.stringify(payload, "", true, true)), "", true, true)`
  — sorted keys, full precision, after one round trip so that ints and floats print the same way before saving and
  after loading. `checksum` = SHA-256 hex of that text's UTF-8 bytes.
- `write`: make the directory; write the whole file to `temp_path()`; close it; read it back and `validate_text` it
  (if that fails, delete the temp file and return an error — the existing save is untouched). Then rotate: delete the
  oldest backup, shift `bak(i)` → `bak(i+1)`, **copy** the current main file to `bak1`, then rename the temp file over the
  main file. Returns `OK` only when the new main file is in place.
  `saved_at_unix` is for display only; **nothing may ever compute elapsed real time from it** (no offline deterioration).
- `read`: try, in order, the main file, then the temp file, then `bak1`, `bak2`, … The first file that passes
  `validate_text` wins. Status `ok` if it was the main file, otherwise `recovered_from_backup`. Each rejected file adds a
  line to `problems`. If no file exists at all → `no_save`. If files exist but none is usable → `unsupported_schema`
  when at least one was rejected only for its schema, else `corrupt`.
- `validate_text` rejects: unparsable JSON, not a dictionary, wrong `format`, missing fields, `payload` not a dictionary,
  checksum mismatch, schema newer than `migrations.current_version` (status `unsupported_schema`), older schema with no
  migration path (`unsupported_schema`). An older schema with a path is migrated and returned `ok` with `migrated_from` set.
  The checksum is always verified against the payload **as stored**, before migrating.
- `read` never modifies or deletes any file.
- Windows note: Godot's `DirAccess.rename` removes an existing destination first, so there is a short moment with no
  main file. That is why `read` falls back to the temp file and the backups. Say this in a comment.

### `tests/test_saves.gd` must prove
Use a real payload: `{"clock": SolClock.new().to_dict(), "colony": ColonyState.new_game(GameBalance.new(), 12345, PackedStringArray(["Power Room", "Life Support"])).to_dict(), "session": {"host_character": "crew_1"}}`
with a few items, a cache, and non-trivial numbers. Save into a folder inside the project copy
(`ProjectSettings.globalize_path("res://").path_join("_test_saves")`), cleaned at the start of each case.
- Fresh start: `read()` on an empty folder → `no_save`, `has_save()` false.
- Round trip: write, read → `ok`; `ColonyState.from_dict(payload.colony).to_dict()` deep-equals the original
  `to_dict()` after the same JSON round trip; the 64-bit `rng_state` string survives exactly;
  a `RandomNumberGenerator` restored from the saved seed/state produces the same next 20 numbers as the original.
- Repeated save: 5 writes with changing payloads → main holds the 5th, `bak1` the 4th, `bak2` the 3rd, no other files
  (no temp file left).
- Interrupted write: with a good save in place, `fail_after_bytes = 100` → `write` returns an error, `read()` still
  returns the old save with status `ok`; a later normal write succeeds and leaves no temp file.
- Truncated main file (cut the main file in half on disk) → `recovered_from_backup` from `bak1`, payload = previous save,
  `problems` names the main file.
- Main file missing but a complete temp file present → the temp file is used (`recovered_from_backup`).
- Bit rot: change one digit inside the payload of the main file (valid JSON, wrong checksum) → falls back to `bak1`.
- All files damaged → `corrupt`, empty payload, and no file was changed or deleted by `read`.
- Unsupported schema: a file with `schema` 99 and a correct checksum, no backups → `unsupported_schema`, file untouched (same bytes).
- Migration: with a `SaveMigrations` whose `current_version` is 2 and one step 1→2 (adds a field), a schema-1 file loads
  as `ok` with `migrated_from == 1` and the new field present; the file on disk is unchanged until the next write, and
  after that write it says `schema: 2`.
- Older schema without a path (`schema` 0) → `unsupported_schema`.
- No offline effect: write, then rewrite the file's `saved_at_unix` to ten days ago with a recomputed envelope — the
  loaded payload is byte-for-byte the same canonical text.

---

## Part C — world collision and doors (`worker C`)

Files: `scripts/world/world_collision.gd`, `scripts/world/door_controller.gd`, `scripts/world/terrain_height.gd`,
`tools/godot/build_heightmap.gd`, `tests/test_collision.gd`.

The map's visual scene (not in your copy; it is ~300 MB) is an imported glTF whose mesh nodes are named after the
manifest object `name` and carry the same metadata (`gc_asset`, `area`, `cls`, `door_id`, `door_slide`, `inter`).
Your code builds collision **from the two JSON files only**, and finds visual nodes by name when a scene is given.

### `WorldCollision` (RefCounted)
`static func build(manifest_path: String, colliders_path: String) -> Node3D`
Returns a node named `Collision` containing:
- `Static` — one `StaticBody3D` per manifest `area` (named after the area, spaces → `_`), `collision_layer = Layers.WORLD`,
  `collision_mask = 0`, holding a `CollisionShape3D` (`BoxShape3D`) for every collider box of every object of class
  `floor`, `static`, `deco`, `dynamic` and `ladder` that has boxes. World transform of a box = object transform
  (converted from `matrix_world`) × box local transform (`c`, `q`); box size = `2 * h` scaled by the object's scale.
  (`dynamic` map props stay fixed for now; turning them into physics props is a later milestone.)
- `Doors` — one `DoorController` per `door_id`, see below.
- `Stations` — one `Area3D` per object with `inter` (`collision_layer = Layers.STATION`, mask 0, a 1.2 m sphere at the
  object position), node name = object name, metadata `station_id` (= name) and `kind` (= `inter`).
Also `static func stats(collision: Node3D) -> Dictionary` → counts of bodies, boxes, doors, leaves, stations.

### `DoorController` (Node3D)
One sliding door = all manifest objects sharing a `door_id` (its leaves, class `door`).
Each leaf slides `door_slide` metres along its own local +X axis when open (signed; pairs slide apart).
- Builds an `AnimatableBody3D` per leaf (`collision_layer = Layers.DOOR`, mask 0, `sync_to_physics = true`) with the leaf's boxes.
- `var door_id: int`, `var open_amount := 0.0` (0 closed .. 1 open), `var locked := false`, `var open_seconds := 0.6`,
  `var sense_radius := 2.2` (metres from the door centre), `signal opened_changed(door_id: int, open: bool)`.
- `func attach_visuals(scene_root: Node) -> int` — finds nodes named like each leaf under `scene_root`
  (`find_child(name, true, false)`), remembers their closed transforms and from then on moves them with the leaf. Returns how many it found.
- Opens automatically while any body on `Layers.PLAYER` is within `sense_radius` (use an `Area3D` with mask
  `Layers.PLAYER`) and it is not `locked`; closes otherwise. Movement is eased over `open_seconds` **real** seconds in `_physics_process`.
- `func set_locked(value: bool) -> void`, `func is_open() -> bool` (open_amount > 0.95).

### `TerrainHeight` (Resource) and `tools/godot/build_heightmap.gd`
The outdoor terrain is far too dense for triangle collision, so it is sampled to a height grid.
`TerrainHeight`: `@export var origin: Vector2` (world x, z of sample 0,0), `@export var cell := 1.0`,
`@export var width: int`, `@export var depth: int`, `@export var heights: PackedFloat32Array` (row-major, z rows),
`func height_at(x: float, z: float) -> float` (bilinear, clamped at the edges),
`func make_body() -> StaticBody3D` (a `HeightMapShape3D` correctly positioned and scaled for `cell`, layer `Layers.WORLD`),
`static func from_meshes(root: Node3D, cell: float, bounds: Rect2) -> TerrainHeight` (for every `MeshInstance3D` under
`root`, bins world-space vertices into the grid keeping the highest y per cell, then fills empty cells from their
neighbours). `tools/godot/build_heightmap.gd` is a headless `SceneTree` script:
`--script res://tools/godot/build_heightmap.gd -- --scene <res path of a scene with terrain meshes> --cell 1.0 --out res://data/terrain_height.res [--bounds x0,z0,x1,z1]`.

### `tests/test_collision.gd` must prove
- Build from the real `data/` files: report `stats`; every manifest object with at least one collider box in
  `colliders.json` (of the classes listed) produced exactly that many shapes; 24 doors and 52 leaves; 9 stations.
- Transform check: for 20 objects spread over the map (include rotated and scaled ones if any exist), the world-space
  centre of the first box equals an independent calculation from the JSON within 1 mm.
- Physics check (add the collision to the tree, `await physics_frame`): a ray cast straight down inside three
  different rooms hits a floor near y = 0 (print the y); a ray across a wall line is blocked.
- Doors: a ray through a closed door is blocked; after placing a `CharacterBody3D` on `Layers.PLAYER` next to the door
  and waiting 1.0 s of physics frames the door `is_open()` and the same ray passes; after removing the body it closes
  again; a `locked` door stays shut. With a synthetic visual scene (plain `Node3D`s named like the leaves),
  `attach_visuals` finds all of them and they move by `door_slide` when open.
- Heightmap: `from_meshes` on a synthetic sloped/bumpy `ArrayMesh` reproduces known heights within the cell tolerance;
  a body dropped on `make_body()` (or a downward ray) lands at `height_at` within 5 cm at 10 points; the tool script
  runs on a small scene you save for the test and writes a loadable `.res`.

---

## Part D — player, cameras and input (`worker D`)

Files: `scripts/player/player_controller.gd`, `scripts/player/player_camera_rig.gd`, `scripts/player/player_input.gd`,
`scripts/player/player_tuning.gd`, `scripts/player/player_visual.gd`, `scripts/player/carry_item.gd`,
`tests/test_player.gd`. Build node trees in code (no hand-written `.tscn`).

### `PlayerTuning` (Resource) — every movement number in one place, each with a comment saying what it is and why
`walk_speed` (m/s without suit), `sprint_multiplier`, `ground_acceleration`, `ground_deceleration`, `air_control`,
`jump_height_m`, `floor_snap_m`, `max_slope_degrees`, `step_height_m`, `mouse_sensitivity`, `pitch_limit_degrees`,
`body_height_m` (1.8), `body_radius_m` (0.32), `eye_height_m`, `reach_m`, `sprint_stamina_per_second`,
`stamina_recover_per_second`, `throw_speed`.
Gravity is always `GameConfig.MARS_GRAVITY` (3.73 m/s²); jump velocity = `sqrt(2 * g * jump_height_m)`.
Retune for Mars: on Earth a 0.45 m hop takes 0.6 s; choose values that feel controllable under 3.73 m/s² (a hop should
not hang for seconds) and state your reasoning in the comments. Wearing the suit multiplies ground speed by
`config.suit_speed_factor` (0.8). These are designer tuning values, not science.

### `PlayerInput` (RefCounted)
`const ACTIONS` — the defaults: `move_forward` W, `move_back` S, `move_left` A, `move_right` D, `sprint` Shift,
`jump` Space (the same action brakes a rover later), `interact` E, `grab` G **and** left mouse button,
`toggle_view` Tab, `map` M, `push_to_talk` V, `back` Escape, `source_register` Shift+Backspace. **F5 must stay unbound.**
`static func ensure_actions() -> void` (adds missing actions and default events to `InputMap`; never removes a remap),
`static func rebind(action: StringName, event: InputEvent) -> void`, `static func reset(action: StringName) -> void`,
`static func save(path: String) -> Error` / `static func load(path: String) -> Error` (JSON of the remapped events),
`static func describe(action: StringName) -> String` (e.g. `"Tab"`, `"G / Left mouse"`).

### `PlayerCameraRig` (Node3D)
First person: `Camera3D` at eye height. Third person: close behind the character on a `SpringArm3D`
(`spring_length = config.third_person_distance_m`, a `SphereShape3D` of radius 0.2, `collision_mask = Layers.WORLD | Layers.DOOR`,
the player's own body excluded with `add_excluded_object`), so the camera never passes through walls.
`fov = config.fov_degrees` (72) in both views. One `Camera3D` is `current` at a time.
`func setup(config: GameConfig, body: CollisionObject3D, eye_height: float) -> void`, `func set_first_person(on: bool) -> void`,
`func is_first_person() -> bool`, `func camera() -> Camera3D`, `func add_look(yaw_delta: float, pitch_delta: float) -> void`,
`func yaw() -> float`, `func pitch() -> float`. In first person the camera's `cull_mask` has the bit of
`Layers.RENDER_FIRST_PERSON_HIDDEN` cleared; in third person it is set.

### `PlayerVisual` (Node3D)
The body the player sees. Until the rigged astronaut arrives it is a jointed stand-in made of capsules and boxes
(head, helmet, torso, two arms with hands, two legs with boots), proportions of a 1.8 m person.
`func set_model(scene: PackedScene) -> void` (replaces the stand-in with a rigged model later; looks for nodes named
`Head`, `Helmet`, `HandAnchorR`, `HandAnchorL` and an `AnimationPlayer`), `func set_first_person(on: bool) -> void`
(head and helmet meshes move to render layer `Layers.RENDER_FIRST_PERSON_HIDDEN` only, so the local camera skips
them while arms, hands, torso, legs and boots stay visible — one body, no duplicate limbs),
`func set_zone_layers(mask: int) -> void` (render layers of all visible parts, so room lights reach the character),
`func set_suit(on: bool) -> void` (shows/hides helmet, pack and suit parts), `func set_identity(index: int) -> void`
(0..3: a small coloured shoulder patch and chest stripe; restrained, not a full recolour),
`func hand_anchor(right := true) -> Node3D`, `func play(state: StringName, speed := 1.0) -> void` — states `idle, walk,
sprint, jump, land, carry, use, suit, seated`; the stand-in animates them procedurally (limb swing etc.).

### `CarryItem` (RigidBody3D)
A prop that can be carried. `var item_id: StringName`, `collision_layer = Layers.ITEM`, mask `Layers.WORLD | Layers.ITEM | Layers.DOOR`,
metadata `item_id`. `func attach_to(anchor: Node3D) -> void` (freezes, disables collision, follows the anchor),
`func release(world_position: Vector3, velocity := Vector3.ZERO) -> void`, `func is_held() -> bool`.
`static func make_crate(id: StringName, size := 0.4) -> CarryItem`.

### `PlayerController` (CharacterBody3D)
`collision_layer = Layers.PLAYER`, `collision_mask = Layers.WORLD | Layers.DOOR | Layers.ITEM`. Capsule collider.

```gdscript
signal perspective_changed(first_person: bool)
signal action_answered(result: ActionResult)
var config: GameConfig
var tuning: PlayerTuning
var character: CharacterState          # the authoritative record this body represents (read-only here, except through callables)
var submit := Callable()               # func(action: StringName, target: StringName, params: Dictionary) -> ActionResult
var report_position := Callable()      # func(position: Vector3, yaw: float) -> void
var input_enabled := true
func setup(p_config: GameConfig, p_tuning: PlayerTuning, p_character: CharacterState, p_submit: Callable, p_report_position: Callable) -> void
func set_first_person(on: bool) -> void
func is_first_person() -> bool
func camera_rig() -> PlayerCameraRig
func visual() -> PlayerVisual
func teleport(position: Vector3, yaw: float) -> void
func held_item() -> CarryItem          # the CarryItem node currently in the hand, or null
func aimed_target() -> Dictionary      # {"kind": "station"/"item"/"", "id": StringName, "node": Node} under the crosshair within reach
```

- Starts in **first person**. `toggle_view` (Tab) switches view; `map` (M) is never consumed by this class.
- Movement in `_physics_process`: camera-relative WASD, acceleration/deceleration, sprint (drains `character.stamina`
  locally for feel only — the authoritative stamina model is a later milestone, say so in a comment), jump from the
  floor only, Mars gravity, `floor_snap_length`, `floor_max_angle`, small steps climbed. Suit on → speed × 0.8.
  Calls `report_position` every physics frame.
- `interact` (E): if `aimed_target()` is a station → `submit(&"begin_suit_check", id, {"on": not character.suit_on})`
  for kind `suits`; for other kinds emit `action_answered` with the result of
  `submit(&"use_station", id, {})` (the host answers; unknown actions come back as a clear failure).
- `grab` (G / LMB): nothing held and a `CarryItem` is aimed at → `submit(&"pick_up", item_id, {})`; on `ok` attach the
  item to the right hand anchor. Something held → `submit(&"drop", item_id, {})`; on `ok` release it in front of the
  player, thrown at `tuning.throw_speed` if `sprint` is held. The controller never edits `character.cargo` itself.
- Mouse look only while `Input.mouse_mode == MOUSE_MODE_CAPTURED`; `back` (Esc) releases the mouse.
- Changing view, suit state or held item never changes `character.owner_peer` or `character.cargo`.

### `tests/test_player.gd` must prove (headless physics on a synthetic test room built in the test: floor, a wall,
a 20° ramp, a 50° ramp, a 0.2 m step; drive input with `Input.action_press` / `action_release`)
- Input map: every action exists with the listed default; F5 is bound to nothing; Tab is not on `map`, M is not on
  `toggle_view`; rebinding one action survives `save` + `reset` + `load`.
- Gravity: a free fall from 3 m takes `sqrt(2*3/3.73)` s within 5 %. Jump apex = `jump_height_m` within 5 %; print
  the measured apex and air time.
- Speed: steady walk speed = `walk_speed` within 3 %; with `suit_on` it is 0.8 × that within 3 %; sprint ratio as tuned.
- Slopes and steps: climbs the 20° ramp and the 0.2 m step, does not climb the 50° ramp.
- Walls: walking into the wall for 2 s never moves the body through it.
- Cameras: starts in first person; FOV is 72 in both views; in third person in open space the camera is
  `third_person_distance_m` behind (±0.1 m); with the player's back 0.6 m from a wall the camera stays on the player's
  side of the wall; the first-person camera's `cull_mask` excludes the hidden layer and the head and helmet meshes are
  on that layer only, while arm/hand/torso/leg/boot meshes are still visible to it; exactly one camera is current.
- Authority: with a fake `submit` that records calls and answers like the host, 20 view toggles and a suit flag change
  leave `character.owner_peer` and `character.cargo` identical; grab sends exactly one `pick_up`, the item follows the
  hand anchor (its global position tracks the anchor within 1 cm while walking), drop sends one `drop` and the item is a
  free body again; a refused `pick_up` attaches nothing.
- `PlayerVisual`: all nine states play without error; `set_identity(0..3)` gives four different patch colours;
  `hand_anchor()` is not null.
