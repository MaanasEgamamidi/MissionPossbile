class_name CommsStage
extends RefCounted
## The colony radio's equipment stage (Prompt 11). Stage 0: no exterior link. Stages 1-4: the radio passes speech
## after 30 s, 15 s, 5 s, then near-immediately. The delay is the damaged equipment's buffering and processing; it is
## not network delay and not Earth-Mars light time. Stages are upgrade cards installed at the communications station.
##
## The four cards live in data/upgrades.json in the energy sector (the electrical systems sector, installed by the
## electrical and comms specialist): communications is not a sixth tier sector of ProgressionSystem. They are chained
## by prerequisites, so they install in order: comms_radio_1 needs no sector level, 2 needs Energy level 1, 3 Energy
## level 2, 4 Energy level 3. Messages from Earth are a separate system and are never made faster by these cards.
## 2026-11-15: crew voice no longer reads this stage. Who is heard by radio, and with what delay and garble, follows
## the Communication level (AreaLevels "command") in scripts/voice/suit_radio.gd. stage() stays for the tutorial's
## certification check and the old panels.

## Upgrade card ids, one per stage, installed in order.
const CARD_IDS: PackedStringArray = ["comms_radio_1", "comms_radio_2", "comms_radio_3", "comms_radio_4"]
## Intentional radio delay per stage in real seconds; stage 0 has no link (-1). Contract values (the brief).
const DELAY_S: PackedFloat32Array = [-1.0, 30.0, 15.0, 5.0, 0.0]
## Parts each card costs, stage 1..4 (contract: 1, 2, 3, 4).
const CARD_PARTS: PackedInt32Array = [1, 2, 3, 4]
## Station kind where the cards are installed (the existing communications station, cm_comms_console).
const INSTALL_KIND := "comms"
const INSTALL_STATION := "cm_comms_console"
## Specialist who installs them.
const SPECIALTY := &"electrical_comms"
const MAX_STAGE := 4


## Installed stage, 0..4.
static func stage(state: ColonyState) -> int:
	var n := 0
	for id: String in CARD_IDS:
		if state != null and state.has_upgrade(id):
			n += 1
		else:
			break
	return n


## Intentional delay in seconds for a stage; -1 when there is no exterior link.
static func delay_seconds(p_stage: int) -> float:
	return float(DELAY_S[clampi(p_stage, 0, DELAY_S.size() - 1)])


## True when the radio carries speech at all (stage 1 or more).
static func has_link(p_stage: int) -> bool:
	return delay_seconds(p_stage) >= 0.0


## The card that would raise the radio to the next stage, or "" at stage 4.
static func next_card(state: ColonyState) -> String:
	var s := stage(state)
	return CARD_IDS[s] if s < CARD_IDS.size() else ""


## How long the radio holds speech, in words: "after 30 s", "almost at once"; "" for no link.
static func delay_words(p_stage: int) -> String:
	var d := delay_seconds(p_stage)
	if d < 0.0:
		return ""
	if d <= 0.0:
		return "almost at once"
	return "after %d s" % roundi(d)


## One line for the HUD and the panels: "Radio stage 2 of 4: speech is heard after 15 s."
static func stage_text(p_stage: int) -> String:
	if not has_link(p_stage):
		return "Radio stage 0 of 4: no radio link outside. Repair the radio at the comms console."
	return "Radio stage %d of 4: speech is heard %s." % [p_stage, delay_words(p_stage)]


## Why the radio is slow, in plain words (shown in the voice settings and on the HUD help). Since 2026-11-15 the voice
## path follows the suit radio (scripts/voice/suit_radio.gd, the Communication level), so this returns its honest
## science note (read by path to keep the class_name scripts free of a preload cycle).
static func explanation() -> String:
	var script := load("res://scripts/voice/suit_radio.gd") as Script
	if script != null:
		var note: Variant = script.get_script_constant_map().get("SCIENCE_NOTE", "")
		if note is String and String(note) != "":
			return String(note)
	return ("Suit radio between spacesuits on Mars is almost instant in real life; the game's delay stands for a weak "
		+ "signal through a busy base relay. The real Earth-Mars delay is 4 to 24 minutes.")
