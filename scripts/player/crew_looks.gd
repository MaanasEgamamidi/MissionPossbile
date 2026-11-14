class_name CrewLooks
extends RefCounted
## How each of the four crew members looks: the one table PlayerVisual (body), CrewPortrait (badge and portrait),
## BlueprintView (map markers) and the name tags read. Index 0..3 follows CharacterState.SPECIALTIES.
##   feminine     value of the "Feminine" blend shape on the body and suit meshes (0 or 1)
##   hair         Hair_* meshes shown unsuited
##   hair_suited  meshes shown while the helmet is on: HairIn_* (hair that fits inside the helmet) and Hair_Beard
##   hair_color / skin_color   albedo of the per-body copies of Mat_Hair / Mat_Skin
##   accent       Mat_Ident (patches, stripes, bands, cuffs, symbol), lit a little by its own emission;
##                Mat_IdentDark (trim) gets it darkened by IDENT_DARK_AMOUNT
##   symbol       suit symbol mesh Ident_Symbol_<symbol>; `glyph` is the same shape as text (name tag, HUD badge)
##   glyph_scale  font size of the glyph relative to the word, so every symbol is as tall as the capitals
##   band         helmet and backpack band pattern mesh Ident_Band_<band>
##   colour_word  the accent in words (map legend)
##   tag          short word for the name tag when the display name is too long for one
##   height       uniform scale of the model (feet stay on the floor: the model's origin is between the feet). Visual
##                only: the collision capsule, eye height and reach are the same for everyone (PlayerTuning).
## Accents, symbols and bands: fable_crew_verdict_1.md (yellow / blue / green / magenta stay apart for deuteranopes).
## Green is 178a3e, not 1e9e48: under a deuteranopia simulation 1e9e48 turned the same olive as the orange suit.
## Medical is 1.03, not 1.05: overhead parts in the map leave 1.86-2.0 m of headroom (doors are 2.15 m or more).

const LOOKS: Array[Dictionary] = [
	{"specialty": &"electrical_comms", "feminine": 1.0, "hair": [&"Hair_Ponytail"], "hair_suited": [&"HairIn_Ponytail"],
		"hair_color": Color("3b2417"), "skin_color": Color("a8714f"), "accent": Color("ffc400"), "height": 0.93,
		"symbol": &"Triangle", "glyph": "▲", "glyph_scale": 1.0, "band": &"Solid", "colour_word": "yellow", "tag": "Electrical"},
	{"specialty": &"medical_life_support", "feminine": 0.0, "hair": [&"Hair_Curly"], "hair_suited": [&"HairIn_Curly"],
		"hair_color": Color("151210"), "skin_color": Color("6e452e"), "accent": Color("2a7bff"), "height": 1.03,
		"symbol": &"Plus", "glyph": "✚", "glyph_scale": 1.0, "band": &"Double", "colour_word": "blue", "tag": "Medical"},
	{"specialty": &"biology_food", "feminine": 1.0, "hair": [&"Hair_Bob"], "hair_suited": [&"HairIn_Bob"],
		"hair_color": Color("a4502a"), "skin_color": Color("f1c9a5"), "accent": Color("178a3e"), "height": 0.90,
		"symbol": &"Circle", "glyph": "●", "glyph_scale": 1.7, "band": &"Dots", "colour_word": "green", "tag": "Biology"},
	{"specialty": &"field_engineering_geology", "feminine": 0.0, "hair": [&"Hair_Buzz", &"Hair_Beard"],
		"hair_suited": [&"HairIn_Buzz", &"Hair_Beard"],
		"hair_color": Color("6b4a2b"), "skin_color": Color("c39a6e"), "accent": Color("d2379b"), "height": 1.0,
		"symbol": &"Diamond", "glyph": "◆", "glyph_scale": 1.15, "band": &"Chevron", "colour_word": "magenta", "tag": "Geology"},
]
## How much darker Mat_IdentDark is than the accent.
const IDENT_DARK_AMOUNT := 0.35
## Emission energy of the accent surfaces (their own colour), so they read in shade.
const IDENT_EMISSION := 0.4
## Longest display name the name tag shows as it is.
const NAME_TAG_MAX_CHARS := 14


static func look(index: int) -> Dictionary:
	return LOOKS[clampi(index, 0, LOOKS.size() - 1)]


static func accent(index: int) -> Color:
	return look(index).accent as Color


static func accent_dark(index: int) -> Color:
	return accent(index).darkened(IDENT_DARK_AMOUNT)


static func glyph(index: int) -> String:
	return String(look(index).glyph)


static func glyph_scale(index: int) -> float:
	return float(look(index).get("glyph_scale", 1.0))


## Look index of a specialty (CharacterState.specialty), or -1 if it is not one of the four.
static func index_of(specialty: StringName) -> int:
	for i: int in LOOKS.size():
		if LOOKS[i].specialty == specialty:
			return i
	return -1


## Text of the name tag over a crew member: the display name when it is short, else the look's one-word tag (the
## default display names are whole specialty phrases, too wide to float over a head).
static func tag_text(display_name: String, index: int) -> String:
	return display_name if display_name != "" and display_name.length() <= NAME_TAG_MAX_CHARS else String(look(index).tag)
