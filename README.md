```text
███╗   ███╗██╗███████╗███████╗██╗ ██████╗ ███╗   ██╗
████╗ ████║██║██╔════╝██╔════╝██║██╔═══██╗████╗  ██║
██╔████╔██║██║███████╗███████╗██║██║   ██║██╔██╗ ██║
██║╚██╔╝██║██║╚════██║╚════██║██║██║   ██║██║╚██╗██║
██║ ╚═╝ ██║██║███████║███████║██║╚██████╔╝██║ ╚████║
╚═╝     ╚═╝╚═╝╚══════╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝

██████╗  ██████╗ ███████╗███████╗██╗██████╗ ██╗     ███████╗
██╔══██╗██╔═══██╗██╔════╝██╔════╝██║██╔══██╗██║     ██╔════╝
██████╔╝██║   ██║███████╗███████╗██║██████╔╝██║     █████╗
██╔═══╝ ██║   ██║╚════██║╚════██║██║██╔══██╗██║     ██╔══╝
██║     ╚██████╔╝███████║███████║██║██████╔╝███████╗███████╗
╚═╝      ╚═════╝ ╚══════╝╚══════╝╚═╝╚═════╝ ╚══════╝╚══════╝

```

[**▶ Launch Game**](https://udaykamboj.github.io/mission-possible-live/) · Godot 4.7.2

---

A Godot 4.7.2 / GDScript cooperative Mars colony simulation, built for **NASA Space Apps Challenge 2026 · Seattle — Build a Junior Astronaut Mission Trainer**. One to four players repair and operate a shared outpost through linked power, life-support, agriculture, weather, radiation, and progression systems.

The runtime separates colony state, simulation, validated actions, and scene presentation. Gameplay systems operate on serializable data; the 3D world and UI present that state and submit requests through the session layer.

## Run

Use **Godot 4.7.2** and **Git LFS**. From the repository root:

```sh
git lfs pull
godot --path . --editor
```

Open `project.godot` and run the project. The entry scene is [`scenes/game.tscn`](scenes/game.tscn); [`scripts/game/game_main.gd`](scripts/game/game_main.gd) assembles the world, collision, services, player, HUD, and presenters. The map can be opened separately at `scenes/world/colony_world.tscn`.

## Runtime architecture

| Layer | Implementation |
| --- | --- |
| State | [`scripts/state/`](scripts/state) stores colony and character state, including resources, crew condition, and shared progress. |
| Simulation | [`scripts/sim/`](scripts/sim) advances the sol clock, colony systems, and progression. Rates and capacities are configured through [`GameBalance`](scripts/core/game_balance.gd) and `config/`. |
| Actions | [`scripts/session/`](scripts/session) handles gameplay requests, role checks, and action results. Presenters submit actions instead of directly modifying colony state. |
| Multiplayer | [`scripts/net/`](scripts/net) provides host-authoritative ENet sessions and UDP LAN discovery for one host and up to three clients. |
| Persistence | [`scripts/save/`](scripts/save) handles colony saves and migrations; local input and display preferences are kept separately. |
| Presentation | [`scripts/world/`](scripts/world), [`scripts/player/`](scripts/player), and [`scripts/ui/`](scripts/ui) manage world interaction, movement, cameras, menus, and the mission HUD. |
| Content | [`data/`](data) contains catalogues, scientific references, weather bundles, questions, and upgrade definitions; [`assets/`](assets) contains runtime models, textures, and audio. |

## Implemented systems

**Colony operations.** Power allocation affects oxygen production, water processing, crop growth, and equipment availability. The model distinguishes power in kW from stored energy in kWh and applies resource rates against colony time. Equipment maintenance and immediate exposure hazards use their own real-time rules.

**Repairs and learning.** Role-specific stations connect repair tasks to electrical engineering, agriculture, medicine, and field work. Six shared cassettes are collected in the world and played at the Command Room deck. [`ProgressionSystem`](scripts/sim/progression_system.gd) records practical evidence, question results, installed upgrades, and sector tiers in colony state.

**Weather and survival.** [`scripts/weather/`](scripts/weather) loads archived weather bundles and presents atmospheric changes. [`scripts/survival/`](scripts/survival) handles exposure, pressure hazards, radiation, and colony failure conditions. Airlock pressure is localized to the affected vestibule.

**Shared play.** The host owns colony simulation and saves. Clients send requests and receive state updates; player movement and voice use separate ENet channels. [`scripts/voice/`](scripts/voice) handles the Windows TwoVoIP/Opus integration and radio behavior. Multiplayer currently targets the same local network.

## Scientific inputs

| Input | Use in the codebase |
| --- | --- |
| Perseverance MEDA / NASA PDS | Archived pressure, temperature, and wind samples feed the weather bundle. |
| LMD Mars dust maps | Dust-opacity inputs inform seasonal weather and solar-output effects. |
| Curiosity RAD | Radiation measurements inform the surface-dose model. |
| NASA ECLSS / BVAD and JPL MOXIE | Reference mechanisms and crew-consumption figures inform life-support configuration. Colony-scale equipment and gameplay rates include explicit scaling and tuning. |
| Mars constants and NASA photography | Gravity and sol duration inform movement and timing; credited photographs accompany cassette briefings. |

[`docs/source_register.md`](docs/source_register.md) records provenance. The `data/model_sources*.json` files distinguish reference values, physical relationships, engineering choices, and gameplay assumptions. These categories matter: a tuned upgrade cost or simulated storm schedule is not a measured NASA value.

## Browser and desktop builds

[Launch Game](https://udaykamboj.github.io/mission-possible-live/) opens the browser/download selector. Desktop is recommended for the full game.

| Build | Notes |
| --- | --- |
| Windows | LAN multiplayer and bundled voice support. Extract the complete ZIP before running the EXE. |
| macOS | Universal app; not notarized. The current package has no voice library. |
| Browser | Experimental solo export using Compatibility/WebGL. Graphics presets trade resolution, shadows, and material detail for performance. LAN discovery, ENet multiplayer, and voice are unavailable. |

[`live/build.py`](live/build.py) exports temporary project copies. [`live/web_profile.py`](live/web_profile.py) applies browser-specific settings and staging changes; the desktop source remains separate from those transformations. The launch page and exported packages are deployed through a dedicated hosting repository.

## Controls

| Input | Action |
| --- | --- |
| WASD / mouse | Move / look |
| Shift / Space | Sprint / jump |
| E | Interact with stations, equipment, and world objects |
| G / left mouse | Handle carried objects |
| Tab | Switch first-person / third-person camera |
| J / Esc | Goals / close panel or pause |
| Shift + Backspace | Open the source register |

Input bindings and accessibility options are available in Settings. Browser menus release the cursor; gameplay captures it for mouse look.

## Development

Build commands, collision generation, import details, and historical implementation notes are preserved in the [developer guide](docs/DEVELOPER_GUIDE.md). The [player guide](docs/release/PLAYER_GUIDE.md) contains longer gameplay instructions; some packaging details there predate the browser and Mac exports.

The automated suites live in [`tests/`](tests). Run them on Windows with `tools/run_tests.ps1 -Import`; historical results and limitations are documented under `docs/`. No new test results are claimed by this README update.

**Team:** Jose Gerald · Maanas Egamamidi · Harshil Sharma · Uday Kamboj · Vivaan Pillai · Pratik Parida. Built with Godot and Blender, with coding assistance from Claude and Codex. See [credits](data/credits.json) and [third-party notices](docs/release/THIRD_PARTY_NOTICES.md) for tools and asset attribution.
