# Mission Possible

**NASA Space Apps Challenge 2026 · Seattle**  
*Build a Junior Astronaut Mission Trainer*

A cooperative Mars colony game for ages 9–12. Repair a damaged outpost, share limited power, and keep your crew supplied with air, water, and food. Every upgrade has a cost.

**[▶ Play or download](https://udaykamboj.github.io/mission-possible-live/)** · 1–4 players · Godot 4.7.2 · GDScript · Blender

## Inside the game

- **Repair and explore:** four crew roles, room-specific repairs, six collectible learning tapes, and rover exploration.
- **Run the colony:** connected power, life-support, food, weather, and radiation systems. State lives in [`scripts/state`](scripts/state); simulation runs in [`scripts/sim`](scripts/sim).
- **Work together:** host-authoritative ENet LAN multiplayer, shared actions, and Windows voice chat. See [`scripts/net`](scripts/net) and [`scripts/session`](scripts/session).
- **Learn from evidence:** archived Perseverance MEDA weather, Curiosity RAD-informed radiation, MOXIE/ECLSS-inspired life support, and credited NASA photographs. Scientific inputs and gameplay assumptions are separated in the [source register](docs/source_register.md).

**Controls:** WASD + mouse · Shift sprint · Space jump · E interact · Tab camera · J goals · Esc menu.

Desktop is recommended. Browser play is experimental and solo; LAN multiplayer and voice are unavailable there. Mac downloads are not notarized and have no voice chat.

## Run from source

Install **Godot 4.7.2** and **Git LFS**, then:

```sh
git lfs pull
godot --path . --editor
```

Open `project.godot` and run `scenes/game.tscn`. Build commands and architecture are in the [developer guide](docs/DEVELOPER_GUIDE.md); browser export configuration is in [`live/`](live).

## Team & credits

**Jose Gerald · Maanas Egamamidi · Harshil Sharma · Uday Kamboj · Vivaan Pillai · Pratik Parida**

Built with Godot and Blender, with coding assistance from Claude and Codex. NASA image credits and third-party attributions are documented in the [source register](docs/source_register.md), [credits data](data/credits.json), and [notices](docs/release/THIRD_PARTY_NOTICES.md).
