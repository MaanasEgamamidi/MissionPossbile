class_name Layers
extends RefCounted
## Physics and render layer numbers used across the game, in one place.

# ---- physics layers (bit values for collision_layer / collision_mask)
const WORLD := 1          # floors, walls, furniture, terrain
const PLAYER := 2         # crew bodies
const ITEM := 4           # things that can be carried
const DOOR := 8           # sliding door leaves
const STATION := 16       # interaction volumes (Area3D), never solid
const CREW_SOLID := 32    # other crew, including parked crew; separate from door sensing
const LADDER := 64        # climb interaction volumes, never solid

# ---- render layers (1-based layer numbers, as in the editor)
## Layers 1..18 are lighting zones (see ColonyZones.layer_of); layer 20 is "can shadow the sun".
## A mesh on this layer only is skipped by the local first-person camera: the local head and helmet go here.
const RENDER_FIRST_PERSON_HIDDEN := 19


static func render_bit(layer_number: int) -> int:
	return 1 << (layer_number - 1)
