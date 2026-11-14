# Perf overhaul: scene inventory (headless, 2026-11-14)

From `tools/perf/probe_inventory.gd`, `probe_glass.gd`, `probe_env.gd`, `probe_rocks.gd` on commit d5c8df6.

## How the map is built (why the brief's Static/Dynamic split was adapted)

The colony is one imported map (`colony.glb`, 2147 meshes) whose meshes are **merged across rooms**. Each mesh already
carries the render layers of every lighting zone it touches (`ColonyZones.mask_for_aabb`, layers 1..18; layer 20 =
"can shadow the sun"), and each fixture light is limited to its zone's layer. A room is therefore not a node
subtree: reparenting into `Static` / `Dynamic` roots is impossible without rebuilding the map (and would touch art).
So a `Zone` here is a runtime node that switches its **render layer bit in the gameplay camera's cull mask** (drawing)
and its **fixture lights** (lighting). There is no per-room scripted content: crew and carried items move between
rooms (they are "Persistent" in the brief's terms) and stations are Area3D collision only.

## Zones (17)

| Zone | Layer | Fixture lights (shadowed) | Probe | Notes |
|---|---|---|---|---|
| Hangar bay | 1 | 33 (3) | yes | ceiling 4.7 m |
| Crew corridor | 2 | 17 (2) | yes | |
| Mess hall | 3 | 23 (3) | yes | glass door to plaza |
| Rec kitchen | 4 | 14 (3) | yes | glass wall to mess hall |
| Med Bay | 5 | 18 (3) | yes | window to plaza |
| Command Room | 6 | 17 (3) | yes | glass door to plaza |
| Blast-door passage | 7 | 4 (1) | yes | 4 x 2 m, window to command |
| West bunk room | 8 | 19 (3) | yes | |
| East quarters | 9 | 16 (3) | yes | |
| Service corridor | 10 | 15 (3) | yes | window to life support |
| Greenhouse | 11 | 76 (3), 35 of them AreaLight3D | yes | glass door to plaza |
| Airlock | 12 | 22 (3) | yes | tunnel door 901 to the outside |
| Power Room | 13 | 25 (3) | yes | window + glass door to plaza |
| Life Support | 14 | 18 (3) | yes | |
| Pipe gallery | 15 | 7 (3) | yes | window to hangar |
| Dome plaza | 16 | 25 (3) | - | under the glass hall dome: sees Mars |
| Garden dome | 17 | 14 (3) | - | separate glass dome outside; airlock 911/912 |
| (Exterior) | 18 | 47 (3) | - | Mars; handled by ExteriorController, not a Zone |

No room has AnimationPlayers, particles, rigid bodies or looping audio of its own; nothing to put in `Dynamic`.

## Doors (28) and windows (7)

24 manifest doors (`Collision/Doors/Door_1..24`), the exit tunnel pair (901 inner Airlock-plaza, 902 outer
plaza-Mars) and the garden dome pair (911 inner, 912 outer to Mars). Zones on each side are sampled 1.2 m either
side of the door (3.5 m for an airlock door inside a vestibule). **26 of 28 door leaves have a glass vision panel**
(`*_door_leaf` meshes with `colony_glass.gdshader`), so a closed door does not block sight. The two garden doors have
none. All doors open by proximity (DoorController sense sphere, 2.2 m); airlock pairs cycle.

Windows (glazed non-door meshes touching two zones): Command-Blast, Hangar-Pipe gallery, Service-Life Support,
Med Bay-plaza, Mess-Rec kitchen, Power-plaza, plus plaza-garden (the hall's dome glass).

Graph (door or window links):

```
Hangar bay: Pipe gallery, Blast-door passage, Crew corridor, Service corridor, Airlock
Crew corridor: Hangar bay, Mess hall, West bunk room, Greenhouse
Mess hall: Crew corridor, Dome plaza, Med Bay, Rec kitchen
Rec kitchen: Mess hall, Pipe gallery, Command Room
Med Bay: Mess hall, Dome plaza
Command Room: Dome plaza, Rec kitchen, East quarters, Blast-door passage
Blast-door passage: Hangar bay, Command Room
West bunk room: Crew corridor, Greenhouse
East quarters: Command Room, Life Support
Service corridor: Hangar bay, Life Support, Power Room
Greenhouse: West bunk room, Crew corridor, Dome plaza, Airlock
Airlock: Greenhouse, Hangar bay, Power Room, Dome plaza
Power Room: Service corridor, Airlock, Dome plaza
Life Support: East quarters, Service corridor
Pipe gallery: Hangar bay, Rec kitchen
Dome plaza: Mess hall, Command Room, Greenhouse, Power Room, Airlock, Med Bay, Garden dome
Garden dome: Dome plaza
```

No long straight corridor of rooms exists (brief 4.1 design note): the colony is a ring of rooms round the plaza.

## Mars ("MarsRoot")

`world/Terrain` (25 chunks, 2.77 M tris) and `world/Environment` (996 rocks, 39 scenery meshes 0.79 M tris incl. the
glass hall `SFX_hall_glass` and exit tunnel). `ScoutWorld` (rovers, deposits: gameplay objects) is left alone.
Collision for all of it is built separately at load (RockCollision, EnvironmentCollision, PropCollision).

## Expensive dynamic entities

The other crew (up to 3): rigged astronaut models with an AnimationPlayer. Their body node carries the door-sensing
`Presence` AnimatableBody3D, so only the model child is view-gated, never the body.
